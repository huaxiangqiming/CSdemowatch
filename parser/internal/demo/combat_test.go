package demo

import (
	"csdemowatch/parser/internal/replay"
	"fmt"
	dem "github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/common"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/events"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/msg"
	"io"
	"math"
	"os"
	"reflect"
	"strings"
	"testing"
)

func TestCombatPublicDemo(t *testing.T) {
	path := os.Getenv("CS2_TEST_DEMO")
	if path == "" {
		t.Skip("set CS2_TEST_DEMO")
	}
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	r, err := ParseV2(f, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	counts := map[string]int{}
	byTick := map[string][]replay.Event{}
	for _, e := range r.Events {
		if strings.HasPrefix(e.Type, "bomb_") || e.Type == "player_hurt" {
			continue
		}
		counts[e.Type]++
		key := fmt.Sprintf("%s:%d", e.Type, e.Tick)
		byTick[key] = append(byTick[key], e)
		if e.ActorTeam == "UNKNOWN" {
			t.Errorf("unresolved actor in fixture: %s", e.ID)
		}
	}
	expected := map[string]int{"smoke": 48, "fire": 41, "he": 67, "flash": 68, "shot": 3023, "kill": 163}
	if !reflect.DeepEqual(counts, expected) {
		t.Fatalf("fixture event counts: %v", counts)
	}
	f.Seek(0, io.SeekStart)
	v1, err := Parse(f, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(v1.Tracks, r.Tracks) || !reflect.DeepEqual(v1.Players, r.Players) || v1.Metadata != r.Metadata {
		t.Fatal("V1 movement regression")
	}
	// Independent parse checks wire shot samples, Inferno/Flash/Kill counts,
	// and historical ownership at the original projectile creation snapshot.
	f.Seek(0, io.SeekStart)
	config := dem.DefaultParserConfig
	config.MsgQueueBufferSize = 0
	p := dem.NewParserWithConfig(struct{ io.Reader }{f}, config)
	defer p.Close()
	sourceCounts := map[string]int{}
	checkedShots := 0
	throwTeams := map[string]string{}
	p.RegisterNetMessageHandler(func(m *msg.CMsgTEFireBullets) {
		sourceCounts["shot"]++
		if checkedShots >= 12 {
			return
		}
		tick := p.GameState().IngameTick()
		player := p.GameState().Participants().FindByPawnHandle(uint64(m.GetPlayer()))
		if player == nil {
			t.Fatal("source shooter missing")
		}
		found := false
		for _, e := range byTick[fmt.Sprintf("shot:%d", tick)] {
			if e.ActorPlayerID == fmt.Sprintf("steam:%d", player.SteamID64) {
				expected := replay.Position{X: float64(m.Origin.GetX()), Y: float64(m.Origin.GetY()), Z: float64(m.Origin.GetZ())}
				if *e.Origin != expected || e.ActorTeam != teamName(player.Team) {
					t.Fatal("wire shot origin/team mismatch")
				}
				found = true
				checkedShots++
			}
		}
		if !found {
			t.Fatal("wire shot absent")
		}
	})
	p.RegisterEventHandler(func(e events.InfernoStart) { sourceCounts["fire"]++ })
	p.RegisterEventHandler(func(e events.FlashExplode) { sourceCounts["flash"]++ })
	p.RegisterEventHandler(func(e events.Kill) { sourceCounts["kill"]++ })
	p.RegisterEventHandler(func(e events.GrenadeProjectileThrow) {
		g := e.Projectile
		if g.Thrower != nil {
			throwTeams[fmt.Sprintf("steam:%d:%d:%s", g.Thrower.SteamID64, p.GameState().IngameTick(), grenadeType(g.WeaponInstance.Type))] = teamName(g.Thrower.Team)
		}
	})
	if err := p.ParseToEnd(); err != nil {
		t.Fatal(err)
	}
	for _, kind := range []string{"shot", "fire", "flash", "kill"} {
		if sourceCounts[kind] != counts[kind] {
			t.Errorf("source count %s = %d", kind, sourceCounts[kind])
		}
	}
	historical := 0
	for _, g := range r.Projectiles {
		tick := int(math.Round(g.ThrowTime*r.Metadata.SourceTickRate)) + r.Metadata.SourceStartTick
		key := fmt.Sprintf("%s:%d:%s", g.ActorPlayerID, tick, g.Type)
		if throwTeams[key] != g.ActorTeam {
			t.Fatalf("throw-time team mismatch %s", key)
		}
		for _, track := range r.Tracks {
			if track.PlayerID == g.ActorPlayerID && track.Frames[len(track.Frames)-1].Team != g.ActorTeam {
				historical++
				break
			}
		}
	}
	for _, e := range r.Events {
		if e.Type == "fire" {
			end := e.Time
			for _, patch := range e.Patches {
				end = math.Max(end, patch.ExpireTime)
			}
			if end != e.ExpireTime {
				t.Fatal("fire lingered after last patch")
			}
		}
	}
	if historical == 0 {
		t.Fatal("fixture lacks side-switch utility")
	}
	t.Logf("counts %v; %d direct shot snapshots; %d throws retain historical side; V1 tracks identical", counts, checkedShots, historical)
	_ = common.TeamTerrorists
}
