// Package replay defines the renderer-independent, raw-coordinate V1 contract.
package replay

import (
	"fmt"
	"math"
	"strings"
)

const Version = 1
const SampleRate = 16

type Replay struct {
	Version     int          `json:"version"`
	Metadata    Metadata     `json:"metadata"`
	Players     []Player     `json:"players"`
	Tracks      []Track      `json:"tracks"`
	Events      []Event      `json:"events,omitempty"`
	Projectiles []Projectile `json:"projectiles,omitempty"`
}

type Metadata struct {
	Map              string  `json:"map"`
	Duration         float64 `json:"duration"`
	SourceTickRate   float64 `json:"source_tick_rate"`
	SampleRate       float64 `json:"sample_rate"`
	CoordinateSystem string  `json:"coordinate_system"`
	SourceStartTick  int     `json:"source_start_tick"`
	SourceEndTick    int     `json:"source_end_tick"`
}

type Player struct {
	ID      string `json:"id"`
	SteamID string `json:"steam_id"`
	Name    string `json:"name"`
	Team    string `json:"team"`
}

type Position struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
	Z float64 `json:"z"`
}

type Frame struct {
	Time     float64  `json:"time"`
	Tick     int      `json:"tick"`
	Position Position `json:"position"`
	Yaw      float64  `json:"yaw"`
	Health   int      `json:"health"`
	Alive    bool     `json:"alive"`
	// Team is temporal: side swaps must not use the initial roster team.
	Team string `json:"team"`
	// False means no valid connected pawn at this sample (not a death event).
	Available bool `json:"available"`
}

type Track struct {
	PlayerID string  `json:"player_id"`
	Frames   []Frame `json:"frames"`
}

func Finite(v float64) bool   { return !math.IsNaN(v) && !math.IsInf(v, 0) }
func ValidTeam(v string) bool { return v == "T" || v == "CT" }

func Validate(r *Replay) error {
	if r == nil || (r.Version != Version && r.Version != Version2) {
		return fmt.Errorf("unsupported version; expected %d", Version)
	}
	m := r.Metadata
	if strings.TrimSpace(m.Map) == "" {
		return fmt.Errorf("metadata.map is required")
	}
	if !Finite(m.Duration) || m.Duration <= 0 {
		return fmt.Errorf("duration must be positive and finite")
	}
	if !Finite(m.SourceTickRate) || m.SourceTickRate <= 0 || !Finite(m.SampleRate) || m.SampleRate <= 0 || m.SampleRate > m.SourceTickRate {
		return fmt.Errorf("invalid source_tick_rate or sample_rate")
	}
	if m.CoordinateSystem != "cs2_raw" {
		return fmt.Errorf("coordinate_system must be cs2_raw")
	}
	if m.SourceStartTick < 0 || m.SourceEndTick <= m.SourceStartTick || math.Abs(m.Duration-float64(m.SourceEndTick-m.SourceStartTick)/m.SourceTickRate) > 1e-6 {
		return fmt.Errorf("source ticks do not match duration")
	}
	if len(r.Players) == 0 || len(r.Tracks) == 0 {
		return fmt.Errorf("players and tracks must be nonempty")
	}
	ids := map[string]bool{}
	for _, p := range r.Players {
		if p.ID == "" || ids[p.ID] || strings.TrimSpace(p.Name) == "" || !ValidTeam(p.Team) {
			return fmt.Errorf("invalid or duplicate player %q", p.ID)
		}
		ids[p.ID] = true
	}
	seen := map[string]bool{}
	for _, t := range r.Tracks {
		if !ids[t.PlayerID] || seen[t.PlayerID] {
			return fmt.Errorf("unknown or duplicate track player_id %q", t.PlayerID)
		}
		seen[t.PlayerID] = true
		if len(t.Frames) < 2 {
			return fmt.Errorf("track %s needs at least two frames", t.PlayerID)
		}
		prev, prevTick := -1.0, m.SourceStartTick-1
		for i, f := range t.Frames {
			if !Finite(f.Time) || f.Time < 0 || f.Time > m.Duration+1e-6 || f.Time <= prev || f.Tick <= prevTick || f.Tick > m.SourceEndTick {
				return fmt.Errorf("track %s frame %d: time/tick must strictly increase within duration", t.PlayerID, i)
			}
			if math.Abs(f.Time-float64(f.Tick-m.SourceStartTick)/m.SourceTickRate) > 1e-6 {
				return fmt.Errorf("track %s frame %d: tick/time mismatch", t.PlayerID, i)
			}
			if !Finite(f.Position.X) || !Finite(f.Position.Y) || !Finite(f.Position.Z) || !Finite(f.Yaw) {
				return fmt.Errorf("track %s frame %d: nonfinite position/yaw", t.PlayerID, i)
			}
			if f.Health < 0 || !ValidTeam(f.Team) || (!f.Available && f.Alive) {
				return fmt.Errorf("track %s frame %d: invalid player state", t.PlayerID, i)
			}
			prev, prevTick = f.Time, f.Tick
		}
		if t.Frames[0].Time != 0 || math.Abs(t.Frames[len(t.Frames)-1].Time-m.Duration) > 1e-6 {
			return fmt.Errorf("track %s must span 0 through duration", t.PlayerID)
		}
	}
	if len(seen) != len(ids) {
		return fmt.Errorf("each player needs one track")
	}
	return ValidateEvents(r, ids)
}
