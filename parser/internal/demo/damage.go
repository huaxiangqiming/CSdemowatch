package demo

import (
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/events"
	"strings"
)

// Keep source facts. Status durations and icon choices belong to the viewer.
func (c *combatRecorder) registerDamage() {
	c.p.RegisterEventHandler(func(h events.PlayerHurt) {
		if !c.r.started || h.Player == nil {
			return
		}
		victim, team := c.actor(h.Player)
		if victim == "" {
			return
		}
		e := c.event("player_hurt", h.Attacker)
		e.VictimPlayerID, e.VictimTeam = victim, team
		e.Damage, e.HealthRemaining = h.HealthDamage, h.Health
		e.DamageSource = strings.ToLower(strings.TrimSpace(h.WeaponString))
		if e.DamageSource == "" {
			e.DamageSource = "unknown"
		}
	})
}
