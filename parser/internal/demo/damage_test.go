package demo

import (
	"csdemowatch/parser/internal/replay"
	"fmt"
	dem "github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/events"
	"io"
	"os"
	"reflect"
	"strings"
	"testing"
)

func TestDamageRealSource(t *testing.T) {
	path := os.Getenv("CS2_DAMAGE_DEMO")
	if path == "" {
		t.Skip("set CS2_DAMAGE_DEMO")
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
	actual := []string{}
	counts := map[string]int{}
	for _, e := range r.Events {
		if e.Type != "player_hurt" {
			continue
		}
		counts[e.DamageSource]++
		actual = append(actual, fmt.Sprintf("%d %s %s %s %s %d %d %s", e.Tick, e.ActorPlayerID, e.ActorTeam, e.VictimPlayerID, e.VictimTeam, e.Damage, e.HealthRemaining, e.DamageSource))
		if counts[e.DamageSource] <= 3 && (e.DamageSource == "inferno" || e.DamageSource == "hegrenade") {
			t.Log(actual[len(actual)-1])
		}
	}
	if len(actual) != 264 || counts["hegrenade"] != 15 || counts["inferno"] != 38 {
		t.Fatalf("unexpected hurt counts: %d %v", len(actual), counts)
	}
	f.Seek(0, io.SeekStart)
	config := dem.DefaultParserConfig
	config.MsgQueueBufferSize = 0
	p := dem.NewParserWithConfig(struct{ io.Reader }{f}, config)
	defer p.Close()
	expected := []string{}
	p.RegisterEventHandler(func(e events.PlayerHurt) {
		if e.Player == nil {
			return
		}
		attacker := ""
		team := "UNKNOWN"
		if e.Attacker != nil {
			attacker = fmt.Sprintf("steam:%d", e.Attacker.SteamID64)
			team = teamName(e.Attacker.Team)
		}
		source := strings.ToLower(strings.TrimSpace(e.WeaponString))
		if source == "" {
			source = "unknown"
		}
		expected = append(expected, fmt.Sprintf("%d %s %s steam:%d %s %d %d %s", p.GameState().IngameTick(), attacker, team, e.Player.SteamID64, teamName(e.Player.Team), e.HealthDamage, e.Health, source))
	})
	if err := p.ParseToEnd(); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(actual, expected) {
		t.Fatal("hurt facts differ from independent native callback pass")
	}
	if err := replay.Validate(r); err != nil {
		t.Fatal(err)
	}
	for i := range r.Events {
		if r.Events[i].Type == "player_hurt" {
			r.Events[i].VictimPlayerID = "missing"
			if replay.Validate(r) == nil {
				t.Fatal("accepted invalid victim")
			}
			break
		}
	}
}
