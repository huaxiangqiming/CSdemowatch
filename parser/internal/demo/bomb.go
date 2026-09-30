package demo

import (
	"csdemowatch/parser/internal/replay"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/common"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/events"
)

// Bomb callbacks are derived by demoinfocs from actual Source 2 C4 entities.
// Round reset prevents the previous round's terminal state leaking forward.
func (c *combatRecorder) registerBomb() {
	record := func(kind string, player *common.Player) {
		if !c.r.started {
			return
		}
		e := c.event(kind, player)
		if kind != "bomb_reset" {
			point := pos(c.p.GameState().Bomb().Position())
			if kind == "bomb_pickup" && player != nil {
				point = pos(player.Position())
			}
			e.Position = &point
		}
		c.bombPending = append(c.bombPending, e)
		c.bombDropped = nil
		if kind == "bomb_drop" {
			c.bombDropped = e
		}
	}
	c.p.RegisterEventHandler(func(e events.BombPickup) { record("bomb_pickup", e.Player) })
	c.p.RegisterEventHandler(func(e events.BombDropped) { record("bomb_drop", e.Player) })
	c.p.RegisterEventHandler(func(e events.BombPlanted) { record("bomb_plant", e.Player) })
	c.p.RegisterEventHandler(func(e events.BombDefused) { record("bomb_defuse", e.Player) })
	c.p.RegisterEventHandler(func(e events.BombExplode) { record("bomb_explode", e.Player) })
	c.p.RegisterEventHandler(func(e events.RoundStart) { record("bomb_reset", nil) })
}

func (c *combatRecorder) finalizeBombFrame() {
	// Owner callbacks run before the library updates Carrier. Read world
	// position only after all properties in the packet have been applied.
	for _, e := range c.bombPending {
		if e.Type != "bomb_reset" && e.Type != "bomb_pickup" {
			point := pos(c.p.GameState().Bomb().Position())
			e.Position = &point
		}
	}
	c.bombPending = nil
}

func (c *combatRecorder) captureBomb() {
	e := c.bombDropped
	if e == nil {
		return
	}
	point := pos(c.p.GameState().Bomb().Position())
	frame := replay.ProjectileFrame{Time: c.now(), Tick: c.p.GameState().IngameTick(), Position: point}
	if len(e.PositionFrames) == 0 || frame.Time > e.PositionFrames[len(e.PositionFrames)-1].Time {
		e.PositionFrames = append(e.PositionFrames, frame)
	}
}
