package replay

import (
	"math"
	"testing"
)

func TestV2Validation(t *testing.T) {
	makeReplay := func() *Replay {
		r := validReplay()
		r.Version = 2
		r.Events = []Event{{ID: "smoke1", Type: "smoke", Time: 0.25, Tick: 16, ActorPlayerID: "a", ActorTeam: "T", Position: &Position{}, ThrowTime: 0, ActivateTime: 0.25, ExpireTime: 0.75}}
		return r
	}
	r := makeReplay()
	if err := Validate(r); err != nil {
		t.Fatal(err)
	}
	// Team is event-time T although the final player frame is CT.
	if r.Events[0].ActorTeam != "T" {
		t.Fatal("historical ownership changed")
	}
	cases := map[string]func(*Replay){"end before start": func(r *Replay) { r.Events[0].ExpireTime = 0.1 }, "unknown actor": func(r *Replay) { r.Events[0].ActorPlayerID = "absent" }, "nonfinite": func(r *Replay) { r.Events[0].Position.X = math.NaN() }, "duplicate": func(r *Replay) { r.Events = append(r.Events, r.Events[0]) }, "projectile reference": func(r *Replay) { r.Events[0].ProjectileID = "missing" }, "wrong tick": func(r *Replay) { r.Events[0].Tick = 1 }}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			r := makeReplay()
			mutate(r)
			if Validate(r) == nil {
				t.Fatal("expected invalid V2")
			}
		})
	}
}
