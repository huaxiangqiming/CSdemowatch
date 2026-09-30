package demo

import (
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"

	"csdemowatch/parser/internal/replay"
	"github.com/golang/geo/r3"
	dem "github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/common"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/events"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/msg"
)

type liveFire struct {
	entity  *common.Inferno
	event   *replay.Event
	patches map[int]int
}
type combatRecorder struct {
	bombPending []*replay.Event
	bombDropped *replay.Event
	r           *recorder
	p           dem.Parser
	events      []*replay.Event
	projectiles []*replay.Projectile
	byEntity    map[int]*replay.Projectile
	live        map[*common.GrenadeProjectile]*replay.Projectile
	observed    map[*common.GrenadeProjectile]*replay.Projectile
	smokes      map[int]*replay.Event
	fires       map[*common.Inferno]*liveFire
	linked      map[string]bool
	flashes     map[int]*replay.Event
}

func newCombatRecorder(r *recorder, p dem.Parser) *combatRecorder {
	return &combatRecorder{r: r, p: p, byEntity: map[int]*replay.Projectile{}, live: map[*common.GrenadeProjectile]*replay.Projectile{}, smokes: map[int]*replay.Event{}, fires: map[*common.Inferno]*liveFire{}, linked: map[string]bool{}, flashes: map[int]*replay.Event{}}
}
func pos(p r3.Vector) replay.Position { return replay.Position{X: p.X, Y: p.Y, Z: p.Z} }
func (c *combatRecorder) now() float64 {
	return math.Max(0, float64(c.p.GameState().IngameTick()-c.r.r.Metadata.SourceStartTick)/c.r.r.Metadata.SourceTickRate)
}
func (c *combatRecorder) actor(p *common.Player) (string, string) {
	if p == nil {
		return "", "UNKNOWN"
	}
	team := teamName(p.Team)
	if team == "" {
		team = "UNKNOWN"
	}
	id := c.r.playerID(p)
	if _, exists := c.r.players[id]; !exists && team == "UNKNOWN" {
		return "", "UNKNOWN"
	}
	if _, exists := c.r.players[id]; !exists {
		// Event-only participants still get a padded unavailable movement track.
		name := strings.TrimSpace(p.Name)
		if name == "" {
			name = id
		}
		steam := ""
		if p.SteamID64 != 0 {
			steam = strconv.FormatUint(p.SteamID64, 10)
		}
		rosterTeam := team
		if rosterTeam == "UNKNOWN" {
			rosterTeam = "T"
		}
		c.r.players[id] = replay.Player{ID: id, SteamID: steam, Name: name, Team: rosterTeam}
	}
	return id, team
}
func (c *combatRecorder) event(kind string, player *common.Player) *replay.Event {
	id, team := c.actor(player)
	e := &replay.Event{ID: fmt.Sprintf("%s_%06d", kind, len(c.events)+1), Type: kind, Time: c.now(), Tick: c.p.GameState().IngameTick(), ActorPlayerID: id, ActorTeam: team}
	c.events = append(c.events, e)
	return e
}
func grenadeType(t common.EquipmentType) string {
	switch t {
	case common.EqSmoke:
		return "smoke"
	case common.EqMolotov:
		return "molotov"
	case common.EqIncendiary:
		return "incendiary"
	case common.EqHE:
		return "he"
	case common.EqFlash:
		return "flash"
	}
	return ""
}
func (c *combatRecorder) register() {
	c.registerBomb()
	c.registerDamage()
	c.observed = map[*common.GrenadeProjectile]*replay.Projectile{}
	c.p.RegisterEventHandler(func(e events.GrenadeProjectileThrow) {
		if !c.r.started || e.Projectile == nil || e.Projectile.WeaponInstance == nil {
			return
		}
		g := e.Projectile
		kind := grenadeType(g.WeaponInstance.Type)
		if kind == "" {
			return
		}
		id, team := c.actor(g.Thrower)
		projectile := &replay.Projectile{ID: fmt.Sprintf("projectile_%05d", len(c.projectiles)+1), Type: kind, ActorPlayerID: id, ActorTeam: team, ThrowTime: c.now()}
		c.projectiles = append(c.projectiles, projectile)
		c.byEntity[g.Entity.ID()] = projectile
		c.live[g] = projectile
		c.observed[g] = projectile
		c.addFrame(projectile, g.Position())
	})
	c.p.RegisterEventHandler(func(e events.GrenadeProjectileBounce) {
		if projectile := c.live[e.Projectile]; projectile != nil {
			c.addFrame(projectile, e.Projectile.Position())
		}
	})
	c.p.RegisterEventHandler(func(e events.GrenadeProjectileDestroy) {
		c.detectUtility(e.Projectile)
		if smoke := c.smokes[e.Projectile.Entity.ID()]; smoke != nil {
			smoke.ExpireTime = c.now()
			smoke.EndReason = "entity_destroyed"
			delete(c.smokes, e.Projectile.Entity.ID())
		}
		delete(c.observed, e.Projectile)
		if projectile := c.live[e.Projectile]; projectile != nil {
			c.addFrame(projectile, e.Projectile.Position())
			projectile.EndTime = c.now()
			projectile.EndReason = "entity_destroyed"
			delete(c.live, e.Projectile)
		}
	})
	c.p.RegisterEventHandler(func(e events.SmokeStart) {
		if c.r.started {
			c.utility("smoke", e.GrenadeEvent)
		}
	})
	c.p.RegisterEventHandler(func(e events.SmokeExpired) {
		if smoke := c.smokes[e.GrenadeEntityID]; smoke != nil {
			smoke.ExpireTime = c.now()
			smoke.EndReason = "smoke_expired"
			delete(c.smokes, e.GrenadeEntityID)
		}
	})
	c.p.RegisterEventHandler(func(e events.HeExplode) {
		if c.r.started {
			c.utility("he", e.GrenadeEvent)
		}
	})
	c.p.RegisterEventHandler(func(e events.FlashExplode) {
		if c.r.started {
			c.utility("flash", e.GrenadeEvent)
		}
	})
	// With legacy-event mode enabled, v5.2.0 doesn't dispatch FlashExplode.
	// Read its authoritative raw detonation event rather than infer from deletion.
	c.p.RegisterEventHandler(func(e events.GenericGameEvent) {
		if !c.r.started || e.Name != "flashbang_detonate" {
			return
		}
		user := int(e.Data["userid"].GetValShort())
		if user == 0 {
			user = int(e.Data["userid"].GetValLong())
		}
		var thrower *common.Player
		for _, p := range c.p.GameState().Participants().All() {
			if p.UserID == user {
				thrower = p
				break
			}
		}
		c.utility("flash", events.GrenadeEvent{Thrower: thrower, GrenadeEntityID: int(e.Data["entityid"].GetValLong()), Position: r3.Vector{X: float64(e.Data["x"].GetValFloat()), Y: float64(e.Data["y"].GetValFloat()), Z: float64(e.Data["z"].GetValFloat())}})
	})
	c.p.RegisterEventHandler(func(e events.PlayerFlashed) {
		if e.Player == nil || e.Projectile == nil {
			return
		}
		f := c.flashes[e.Projectile.Entity.ID()]
		if f == nil {
			return
		}
		id, _ := c.actor(e.Player)
		f.AffectedPlayers = append(f.AffectedPlayers, replay.FlashEffect{PlayerID: id, FlashDuration: e.FlashDuration().Seconds()})
	})
	c.p.RegisterEventHandler(func(e events.InfernoStart) {
		if !c.r.started {
			return
		}
		inf := e.Inferno
		fire := c.event("fire", inf.Thrower())
		point := pos(inf.Entity.Position())
		fire.Position = &point
		fire.ActivateTime = fire.Time
		fire.ThrowTime = fire.Time
		fire.GrenadeType = "unknown_fire"
		// Inferno uses a different entity ID. Link only a matching thrower's nearby
		// projectile in a tight temporal/spatial window, otherwise keep unknown.
		best := math.Inf(1)
		var match *replay.Projectile
		for i := len(c.projectiles) - 1; i >= 0; i-- {
			g := c.projectiles[i]
			if fire.Time-g.ThrowTime > 15 {
				break
			}
			if c.linked[g.ID] || g.ActorPlayerID == "" || g.ActorPlayerID != fire.ActorPlayerID || (g.Type != "molotov" && g.Type != "incendiary") || len(g.Frames) == 0 {
				continue
			}
			last := g.Frames[len(g.Frames)-1]
			d := math.Sqrt(math.Pow(last.Position.X-point.X, 2) + math.Pow(last.Position.Y-point.Y, 2) + math.Pow(last.Position.Z-point.Z, 2))
			if fire.Time-last.Time <= 0.5 && d < 128 && d < best {
				best = d
				match = g
			}
		}
		if match != nil {
			c.attach(fire, match)
			fire.GrenadeType = match.Type
		}
		live := &liveFire{entity: inf, event: fire, patches: map[int]int{}}
		c.fires[inf] = live
		c.captureFire(live)
	})
	c.p.RegisterEventHandler(func(e events.InfernoExpired) {
		if f := c.fires[e.Inferno]; f != nil {
			c.endFire(f, c.now(), "inferno_expired")
			delete(c.fires, e.Inferno)
		}
	})
	c.p.RegisterNetMessageHandler(func(m *msg.CMsgTEFireBullets) {
		if !c.r.started || m.Origin == nil || m.Angles == nil {
			return
		}
		shooter := c.p.GameState().Participants().FindByPawnHandle(uint64(m.GetPlayer()))
		shot := c.event("shot", shooter)
		point := replay.Position{X: float64(m.Origin.GetX()), Y: float64(m.Origin.GetY()), Z: float64(m.Origin.GetZ())}
		shot.Origin = &point
		yaw := float64(m.Angles.GetY()) * math.Pi / 180
		pitch := float64(m.Angles.GetX()) * math.Pi / 180
		direction := replay.Position{X: math.Cos(pitch) * math.Cos(yaw), Y: math.Cos(pitch) * math.Sin(yaw), Z: -math.Sin(pitch)}
		shot.Direction = &direction
		shot.DirectionSource = "fire_bullets_angles"
	})
	c.p.RegisterEventHandler(func(e events.Kill) {
		if !c.r.started || e.Victim == nil {
			return
		}
		kill := c.event("kill", e.Killer)
		kill.VictimPlayerID, kill.VictimTeam = c.actor(e.Victim)
		kill.AssisterPlayerID, _ = c.actor(e.Assister)
		kill.Headshot = e.IsHeadshot
		if e.Weapon != nil {
			kill.Weapon = e.Weapon.Type.String()
		}
		point := pos(e.Victim.Position())
		kill.Position = &point
	})
}
func (c *combatRecorder) addFrame(g *replay.Projectile, p r3.Vector) {
	t := c.now()
	f := replay.ProjectileFrame{Time: t, Tick: c.p.GameState().IngameTick(), Position: pos(p)}
	if len(g.Frames) > 0 {
		last := len(g.Frames) - 1
		if g.Frames[last].Time == t {
			g.Frames[last] = f
			return
		}
		if g.Frames[last].Time > t {
			return
		}
	}
	g.Frames = append(g.Frames, f)
}
func (c *combatRecorder) attach(e *replay.Event, g *replay.Projectile) {
	e.ProjectileID = g.ID
	e.ThrowTime = g.ThrowTime
	e.ActorPlayerID = g.ActorPlayerID
	e.ActorTeam = g.ActorTeam
	c.linked[g.ID] = true
	g.EndTime = e.Time
	g.EndReason = "activated"
	for key, value := range c.live {
		if value == g {
			c.addFrame(g, key.Position())
			delete(c.live, key)
		}
	}
}
func (c *combatRecorder) utility(kind string, source events.GrenadeEvent) {
	if g := c.byEntity[source.GrenadeEntityID]; g != nil && g.Type == kind && c.linked[g.ID] {
		return
	}
	// Some demos repeat identical detonation events. Entity IDs are reused, so
	// deduplicate only within the same tick, never across rounds.
	if kind == "flash" {
		if old := c.flashes[source.GrenadeEntityID]; old != nil && old.Tick == c.p.GameState().IngameTick() {
			return
		}
	}
	e := c.event(kind, source.Thrower)
	point := pos(source.Position)
	e.Position = &point
	e.ActivateTime = e.Time
	e.ThrowTime = e.Time
	e.GrenadeType = kind
	if g := c.byEntity[source.GrenadeEntityID]; g != nil && g.Type == kind && !c.linked[g.ID] && e.Time >= g.ThrowTime {
		c.attach(e, g)
	}
	switch kind {
	case "smoke":
		c.smokes[source.GrenadeEntityID] = e
	case "he":
		e.ExpireTime = e.Time + 0.35
		e.EndReason = "visual_pulse"
	case "flash":
		e.ExpireTime = e.Time + 0.25
		e.EndReason = "visual_pulse"
		c.flashes[source.GrenadeEntityID] = e
	}
}
func (c *combatRecorder) captureFire(f *liveFire) {
	for i, patch := range f.entity.Fires().List() {
		index, active := f.patches[i]
		if patch.IsBurning && !active {
			f.patches[i] = len(f.event.Patches)
			f.event.Patches = append(f.event.Patches, replay.FirePatch{Position: pos(patch.Vector), ActivateTime: c.now()})
		}
		if !patch.IsBurning && active {
			f.event.Patches[index].ExpireTime = c.now()
			delete(f.patches, i)
		}
	}
}
func (c *combatRecorder) endFire(f *liveFire, t float64, reason string) {
	f.event.ExpireTime = t
	f.event.EndReason = reason
	for _, i := range f.patches {
		f.event.Patches[i].ExpireTime = t
	}
	// Inferno entities linger after the last flame stops burning. The replay
	// interval describes fire, not the entity's later cleanup time.
	if len(f.event.Patches) > 0 {
		last := f.event.Time
		for _, patch := range f.event.Patches {
			last = math.Max(last, patch.ExpireTime)
		}
		if last < t {
			f.event.ExpireTime = last
			f.event.EndReason = "last_flame_extinguished"
		}
	}
	f.patches = map[int]int{}
}
func (c *combatRecorder) capture() {
	c.captureBomb()
	for entity, g := range c.live {
		c.addFrame(g, entity.Position())
	}
	for _, f := range c.fires {
		c.captureFire(f)
	}
}
func (c *combatRecorder) finish() {
	end := c.r.r.Metadata.Duration
	for _, e := range c.smokes {
		e.ExpireTime = end
		e.EndReason = "demo_end"
	}
	for _, f := range c.fires {
		c.endFire(f, end, "demo_end")
	}
	for _, g := range c.projectiles {
		if g.EndReason == "" {
			g.EndTime = end
			g.EndReason = "demo_end"
		}
		c.r.r.Projectiles = append(c.r.r.Projectiles, *g)
	}
	sort.SliceStable(c.events, func(i, j int) bool { return c.events[i].Time < c.events[j].Time })
	for _, e := range c.events {
		if e.ExpireTime > end {
			e.ExpireTime = end
		}
		c.r.r.Events = append(c.r.r.Events, *e)
	}
}

// Sample activation flags after all updates in a network frame, so position
// and flag belong to the same snapshot. Embedded effect ticks use a different
// server clock in some demos; our event time uses the observed source tick.
func (c *combatRecorder) onFrame() {
	c.finalizeBombFrame()
	keys := make([]*common.GrenadeProjectile, 0, len(c.observed))
	for g := range c.observed {
		keys = append(keys, g)
	}
	sort.Slice(keys, func(i, j int) bool { return keys[i].Entity.ID() < keys[j].Entity.ID() })
	for _, g := range keys {
		c.detectUtility(g)
	}
}
func (c *combatRecorder) detectUtility(g *common.GrenadeProjectile) {
	projectile := c.observed[g]
	if projectile == nil || c.linked[projectile.ID] {
		return
	}
	kind := projectile.Type
	active := false
	point := g.Position()
	if kind == "smoke" {
		if v, ok := g.Entity.PropertyValue("m_bDidSmokeEffect"); ok {
			active = v.BoolVal()
		}
		if active {
			if v, ok := g.Entity.PropertyValue("m_vSmokeDetonationPos"); ok {
				point = v.R3Vec()
			}
		}
	}
	if kind == "he" {
		if v, ok := g.Entity.PropertyValue("m_nExplodeEffectTickBegin"); ok {
			active = v.Int() > 0
		}
		if active {
			if v, ok := g.Entity.PropertyValue("m_vecExplodeEffectOrigin"); ok {
				point = v.R3Vec()
			}
		}
	}
	if active {
		c.utility(kind, events.GrenadeEvent{Thrower: g.Thrower, GrenadeEntityID: g.Entity.ID(), Position: point})
	}
}
