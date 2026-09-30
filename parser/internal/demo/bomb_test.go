package demo

import (
	dem "github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/events"
	"io"
	"os"
	"reflect"
	"strings"
	"testing"
)

func TestBombPublicDemo(t *testing.T) {
	path := os.Getenv("CS2_TEST_DEMO")
	if path == "" {
		t.Skip("set CS2_TEST_DEMO")
	}
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	replay, err := ParseV2(f, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	counts := map[string]int{}
	ticks := map[string][]int{}
	for _, event := range replay.Events {
		if !strings.HasPrefix(event.Type, "bomb_") {
			continue
		}
		counts[event.Type]++
		ticks[event.Type] = append(ticks[event.Type], event.Tick)
		if event.Type != "bomb_reset" && event.Position == nil {
			t.Fatal("fixture bomb position missing")
		}
	}
	expected := map[string]int{"bomb_pickup": 32, "bomb_drop": 21, "bomb_plant": 11, "bomb_defuse": 5, "bomb_reset": 21}
	if !reflect.DeepEqual(counts, expected) {
		t.Fatalf("bomb counts: %v", counts)
	}
	f.Seek(0, io.SeekStart)
	config := dem.DefaultParserConfig
	config.MsgQueueBufferSize = 0
	p := dem.NewParserWithConfig(struct{ io.Reader }{f}, config)
	defer p.Close()
	source := map[string][]int{}
	record := func(kind string) { source[kind] = append(source[kind], p.GameState().IngameTick()) }
	p.RegisterEventHandler(func(e events.BombPickup) { record("bomb_pickup") })
	p.RegisterEventHandler(func(e events.BombDropped) { record("bomb_drop") })
	p.RegisterEventHandler(func(e events.BombPlanted) { record("bomb_plant") })
	p.RegisterEventHandler(func(e events.BombDefused) { record("bomb_defuse") })
	p.RegisterEventHandler(func(e events.BombExplode) { record("bomb_explode") })
	p.RegisterEventHandler(func(e events.RoundStart) { record("bomb_reset") })
	bombed := 0
	p.RegisterEventHandler(func(e events.RoundEnd) {
		if e.Reason == events.RoundEndReasonTargetBombed {
			bombed++
		}
	})
	if err := p.ParseToEnd(); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(ticks, source) {
		t.Fatal("exported bomb times differ from independent source events")
	}
	if bombed != 0 {
		t.Fatal("unexpected target-bombed round; investigate missing explode")
	}
	t.Logf("Source bomb counts=%v; target-bombed rounds=%d; all event ticks independently verified", counts, bombed)
}
