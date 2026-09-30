// Package serialization is the replaceable output boundary for domain models.
package serialization

import (
	"csdemowatch/parser/internal/replay"
	"encoding/json"
	"io"
)

func WriteJSON(w io.Writer, r *replay.Replay) error {
	encoder := json.NewEncoder(w)
	encoder.SetEscapeHTML(false)
	if r.Version == replay.Version2 {
		events := r.Events
		if events == nil {
			events = []replay.Event{}
		}
		projectiles := r.Projectiles
		if projectiles == nil {
			projectiles = []replay.Projectile{}
		}
		return encoder.Encode(struct {
			*replay.Replay
			Events      []replay.Event      `json:"events"`
			Projectiles []replay.Projectile `json:"projectiles"`
		}{r, events, projectiles})
	}
	return encoder.Encode(r)
}
