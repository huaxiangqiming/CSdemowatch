package replay

import (
	"math"
	"testing"
)

func validReplay() *Replay {
	return &Replay{Version: 1, Metadata: Metadata{Map: "test", Duration: 1, SourceTickRate: 64, SampleRate: 16, CoordinateSystem: "cs2_raw", SourceEndTick: 64},
		Players: []Player{{ID: "a", Name: "Alpha", Team: "T"}},
		Tracks:  []Track{{PlayerID: "a", Frames: []Frame{{Tick: 0, Team: "T", Available: true, Alive: true, Health: 100}, {Time: 1, Tick: 64, Team: "CT", Available: true, Alive: false}}}}}
}

func TestValidate(t *testing.T) {
	if err := Validate(validReplay()); err != nil {
		t.Fatal(err)
	}
	cases := map[string]func(*Replay){
		"version":              func(r *Replay) { r.Version = 99 },
		"map":                  func(r *Replay) { r.Metadata.Map = " " },
		"duration":             func(r *Replay) { r.Metadata.Duration = math.NaN() },
		"players":              func(r *Replay) { r.Players = nil },
		"tracks":               func(r *Replay) { r.Tracks = nil },
		"unknown id":           func(r *Replay) { r.Tracks[0].PlayerID = "missing" },
		"duplicate id":         func(r *Replay) { r.Players = append(r.Players, r.Players[0]) },
		"nonfinite coordinate": func(r *Replay) { r.Tracks[0].Frames[1].Position.X = math.Inf(1) },
		"duplicate time":       func(r *Replay) { r.Tracks[0].Frames[1].Time = 0 },
		"wrong tick":           func(r *Replay) { r.Tracks[0].Frames[1].Tick = 63 },
		"raw coordinates":      func(r *Replay) { r.Metadata.CoordinateSystem = "godot_y_up" },
		"sample rate":          func(r *Replay) { r.Metadata.SampleRate = 128 },
		"availability":         func(r *Replay) { r.Tracks[0].Frames[0].Available = false },
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			r := validReplay()
			mutate(r)
			if Validate(r) == nil {
				t.Fatal("expected validation error")
			}
		})
	}
}
