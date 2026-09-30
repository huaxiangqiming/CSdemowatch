package replay

import (
	"fmt"
	"math"
)

const Version2 = 2

// Event carries immutable event-time ownership, never a lookup of current team.
type Event struct {
	Damage           int               `json:"damage"`
	HealthRemaining  int               `json:"health_remaining"`
	DamageSource     string            `json:"damage_source,omitempty"`
	PositionFrames   []ProjectileFrame `json:"position_frames,omitempty"`
	ID               string            `json:"id"`
	Type             string            `json:"type"`
	Time             float64           `json:"time"`
	Tick             int               `json:"tick"`
	ActorPlayerID    string            `json:"actor_player_id"`
	ActorTeam        string            `json:"actor_team"`
	Position         *Position         `json:"position,omitempty"`
	ProjectileID     string            `json:"projectile_id,omitempty"`
	GrenadeType      string            `json:"grenade_type,omitempty"`
	ThrowTime        float64           `json:"throw_time"`
	ActivateTime     float64           `json:"activate_time"`
	ExpireTime       float64           `json:"expire_time"`
	EndReason        string            `json:"end_reason,omitempty"`
	Patches          []FirePatch       `json:"patches,omitempty"`
	AffectedPlayers  []FlashEffect     `json:"affected_players,omitempty"`
	Origin           *Position         `json:"origin,omitempty"`
	Direction        *Position         `json:"direction,omitempty"`
	Impact           *Position         `json:"impact,omitempty"`
	DirectionSource  string            `json:"direction_source,omitempty"`
	VictimPlayerID   string            `json:"victim_player_id,omitempty"`
	VictimTeam       string            `json:"victim_team,omitempty"`
	AssisterPlayerID string            `json:"assister_player_id,omitempty"`
	Weapon           string            `json:"weapon,omitempty"`
	Headshot         bool              `json:"headshot"`
}
type FirePatch struct {
	Position     Position `json:"position"`
	ActivateTime float64  `json:"activate_time"`
	ExpireTime   float64  `json:"expire_time"`
}
type FlashEffect struct {
	PlayerID      string   `json:"player_id"`
	FlashDuration float64  `json:"flash_duration"`
	FlashAmount   *float64 `json:"flash_amount,omitempty"`
}
type Projectile struct {
	ID            string            `json:"id"`
	Type          string            `json:"type"`
	ActorPlayerID string            `json:"actor_player_id"`
	ActorTeam     string            `json:"actor_team"`
	ThrowTime     float64           `json:"throw_time"`
	EndTime       float64           `json:"end_time"`
	EndReason     string            `json:"end_reason"`
	Frames        []ProjectileFrame `json:"frames"`
}
type ProjectileFrame struct {
	Time     float64  `json:"time"`
	Tick     int      `json:"tick"`
	Position Position `json:"position"`
}

func validPosition(p *Position) bool { return p != nil && Finite(p.X) && Finite(p.Y) && Finite(p.Z) }
func ValidateEvents(r *Replay, players map[string]bool) error {
	if r.Version == 1 {
		if len(r.Events)+len(r.Projectiles) != 0 {
			return fmt.Errorf("V1 cannot contain V2 events")
		}
		return nil
	}
	validTime := func(t float64) bool { return Finite(t) && t >= 0 && t <= r.Metadata.Duration+1e-6 }
	actor := func(id, team string) bool {
		return (id == "" && team == "UNKNOWN") || (players[id] && (ValidTeam(team) || team == "UNKNOWN"))
	}
	ids := map[string]bool{}
	projectileIDs := map[string]bool{}
	for _, p := range r.Projectiles {
		if p.ID == "" || ids[p.ID] || !actor(p.ActorPlayerID, p.ActorTeam) || !validTime(p.ThrowTime) || !validTime(p.EndTime) || p.EndTime < p.ThrowTime || len(p.Frames) == 0 {
			return fmt.Errorf("invalid projectile %s", p.ID)
		}
		if p.Type != "smoke" && p.Type != "molotov" && p.Type != "incendiary" && p.Type != "he" && p.Type != "flash" {
			return fmt.Errorf("unknown projectile type")
		}
		ids[p.ID] = true
		projectileIDs[p.ID] = true
		previous := -1.0
		for _, f := range p.Frames {
			if !validTime(f.Time) || f.Time < p.ThrowTime || f.Time > p.EndTime+1e-6 || f.Time <= previous || !validPosition(&f.Position) || math.Abs(f.Time-float64(f.Tick-r.Metadata.SourceStartTick)/r.Metadata.SourceTickRate) > 1e-6 {
				return fmt.Errorf("invalid projectile frame %s", p.ID)
			}
			previous = f.Time
		}
	}
	previous := -1.0
	for _, e := range r.Events {
		if e.ID == "" || ids[e.ID] || !validTime(e.Time) || e.Time < previous || !actor(e.ActorPlayerID, e.ActorTeam) || math.Abs(e.Time-float64(e.Tick-r.Metadata.SourceStartTick)/r.Metadata.SourceTickRate) > 1e-6 {
			return fmt.Errorf("invalid event %s", e.ID)
		}
		previous = e.Time
		if e.ProjectileID != "" && !projectileIDs[e.ProjectileID] {
			return fmt.Errorf("unknown projectile reference %s", e.ID)
		}
		ids[e.ID] = true
		switch e.Type {
		case "bomb_pickup", "bomb_drop", "bomb_plant", "bomb_defuse", "bomb_explode", "bomb_reset":
			if e.Position != nil && !validPosition(e.Position) {
				return fmt.Errorf("invalid bomb position %s", e.ID)
			}
			last := e.Time - 1e-6
			for _, f := range e.PositionFrames {
				if e.Type != "bomb_drop" || !validTime(f.Time) || f.Time <= last || !validPosition(&f.Position) || math.Abs(f.Time-float64(f.Tick-r.Metadata.SourceStartTick)/r.Metadata.SourceTickRate) > 1e-6 {
					return fmt.Errorf("invalid dropped bomb frame %s", e.ID)
				}
				last = f.Time
			}
		case "smoke", "fire", "he", "flash":
			if !validPosition(e.Position) || !validTime(e.ThrowTime) || e.ThrowTime > e.Time || e.ActivateTime != e.Time || !validTime(e.ExpireTime) || e.ExpireTime < e.Time {
				return fmt.Errorf("invalid utility interval %s", e.ID)
			}
			for _, patch := range e.Patches {
				if !validPosition(&patch.Position) || !validTime(patch.ActivateTime) || !validTime(patch.ExpireTime) || patch.ActivateTime < e.Time || patch.ExpireTime > e.ExpireTime+1e-6 || patch.ExpireTime < patch.ActivateTime {
					return fmt.Errorf("invalid fire patch %s", e.ID)
				}
			}
			for _, effect := range e.AffectedPlayers {
				if !players[effect.PlayerID] || !Finite(effect.FlashDuration) || effect.FlashDuration < 0 || (effect.FlashAmount != nil && (!Finite(*effect.FlashAmount) || *effect.FlashAmount < 0 || *effect.FlashAmount > 1)) {
					return fmt.Errorf("invalid flash effect")
				}
			}
		case "shot":
			if !validPosition(e.Origin) || !validPosition(e.Direction) || math.Abs(e.Direction.X*e.Direction.X+e.Direction.Y*e.Direction.Y+e.Direction.Z*e.Direction.Z-1) > 0.001 || (e.Impact != nil && !validPosition(e.Impact)) {
				return fmt.Errorf("invalid shot %s", e.ID)
			}
		case "player_hurt":
			if !players[e.VictimPlayerID] || (!ValidTeam(e.VictimTeam) && e.VictimTeam != "UNKNOWN") || e.Damage < 0 || e.HealthRemaining < 0 || e.DamageSource == "" {
				return fmt.Errorf("invalid player hurt %s", e.ID)
			}
		case "kill":
			if !players[e.VictimPlayerID] || (!ValidTeam(e.VictimTeam) && e.VictimTeam != "UNKNOWN") || (e.AssisterPlayerID != "" && !players[e.AssisterPlayerID]) {
				return fmt.Errorf("invalid kill %s", e.ID)
			}
		default:
			return fmt.Errorf("unsupported event type %s", e.Type)
		}
	}
	return nil
}
