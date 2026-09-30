package demo

import (
	"bytes"
	"fmt"
	"io"
	"math"
	"os"
	"strings"
	"testing"

	"csdemowatch/parser/internal/replay"
	dem "github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/common"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/events"
)

func TestSampling16Hz(t *testing.T) {
	gate := SampleGate{Rate: 16}
	count := 0
	for tick := 0; tick <= 640; tick++ {
		if gate.Due(float64(tick) / 64) {
			if tick%4 != 0 {
				t.Fatal("sample outside schedule")
			}
			count++
		}
	}
	if count != 161 {
		t.Fatalf("got %d samples, want 161", count)
	}
	gate = SampleGate{Rate: 16}
	if !gate.Due(0) || !gate.Due(2) || gate.Due(2.001) || !gate.Due(2.0625) {
		t.Fatal("gaps must not duplicate states")
	}
}

func TestIdentity(t *testing.T) {
	r := recorder{localIDs: map[*common.Player]string{}}
	a, b := &common.Player{Name: "same"}, &common.Player{Name: "same"}
	if r.playerID(a) == r.playerID(b) || r.playerID(a) != r.playerID(a) {
		t.Fatal("local identities are not unique and stable")
	}
	a.SteamID64 = 76561198123456789
	if !strings.HasPrefix(r.playerID(a), "local:") {
		t.Fatal("late SteamID must not split an existing track")
	}
	c := &common.Player{SteamID64: 76561198111111111}
	d := &common.Player{SteamID64: c.SteamID64}
	if r.playerID(c) != r.playerID(d) {
		t.Fatal("steam reconnect must retain identity")
	}
}

func TestCorruptDemo(t *testing.T) {
	for _, contents := range []string{"", "garbage", "PBDEMS2\x00" + strings.Repeat("\x00", 32)} {
		if _, err := Parse(bytes.NewBufferString(contents), io.Discard); err == nil {
			t.Fatal("corrupted demo should fail")
		}
	}
}

// Optional real-data test: re-read independent source snapshots at exported ticks.
// This checks the actual XYZ/yaw/health/alive/team, not just the JSON structure.
func TestPublicDemo(t *testing.T) {
	path := os.Getenv("CS2_TEST_DEMO")
	if path == "" {
		t.Skip("set CS2_TEST_DEMO to run real-demo integration")
	}
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	r, err := Parse(f, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	if err := replay.Validate(r); err != nil {
		t.Fatal(err)
	}
	if r.Metadata.SampleRate != 16 || len(r.Players) == 0 || len(r.Players) != len(r.Tracks) {
		t.Fatal("invalid integration output")
	}
	targets := map[int]map[string]replay.Frame{}
	for _, track := range r.Tracks {
		chosen := 0
		for _, frame := range track.Frames {
			if frame.Available && frame.Alive && frame.Time >= float64(chosen)*600 {
				if targets[frame.Tick] == nil {
					targets[frame.Tick] = map[string]replay.Frame{}
				}
				targets[frame.Tick][track.PlayerID] = frame
				chosen++
				if chosen == 3 {
					break
				}
			}
		}
	}
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		t.Fatal(err)
	}
	config := dem.DefaultParserConfig
	config.MsgQueueBufferSize = 0
	config.DisableMimicSource1Events = true
	p := dem.NewParserWithConfig(f, config)
	defer p.Close()
	checked := 0
	p.RegisterEventHandler(func(_ events.FrameDone) {
		tick := p.GameState().IngameTick()
		wanted, ok := targets[tick]
		if !ok {
			return
		}
		for _, player := range p.GameState().Participants().All() {
			id := fmt.Sprintf("steam:%d", player.SteamID64)
			frame, ok := wanted[id]
			if !ok {
				continue
			}
			pos := player.Position()
			if frame.Position != (replay.Position{X: pos.X, Y: pos.Y, Z: pos.Z}) || math.Abs(frame.Yaw-float64(player.ViewDirectionX())) > 1e-6 || frame.Health != player.Health() || frame.Alive != player.IsAlive() || frame.Team != teamName(player.Team) {
				t.Errorf("source snapshot mismatch: %s tick %d", id, tick)
			}
			delete(wanted, id)
			checked++
		}
		if len(wanted) == 0 {
			delete(targets, tick)
		}
	})
	if err := p.ParseToEnd(); err != nil {
		t.Fatal(err)
	}
	if len(targets) != 0 || checked == 0 {
		t.Fatal("source verification did not visit all selected snapshots")
	}
	t.Logf("verified %d raw source snapshots; %d players, %d tracks, %.6f seconds", checked, len(r.Players), len(r.Tracks), r.Metadata.Duration)
}
