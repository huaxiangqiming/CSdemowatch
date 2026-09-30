package demo

import (
	"fmt"
	dem "github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/events"
	"os"
	"testing"
)

func TestDamageProbe(t *testing.T) {
	path := os.Getenv("CS2_DAMAGE_PROBE")
	if path == "" {
		t.Skip()
	}
	f, _ := os.Open(path)
	defer f.Close()
	p := dem.NewParser(f)
	defer p.Close()
	n := 0
	h := 0
	p.RegisterEventHandler(func(e events.PlayerHurt) {
		h++
		if h < 4 {
			fmt.Printf("HURT %+v\n", e)
		}
	})
	p.RegisterEventHandler(func(e events.GenericGameEvent) {
		if e.Name == "player_hurt" {
			n++
			if n < 4 {
				fmt.Println("RAW", e.Data)
			}
		}
	})
	if err := p.ParseToEnd(); err != nil {
		t.Fatal(err)
	}
	fmt.Println("DAMAGE", h, n)
}
