package demo

import (
	"fmt"
	dem "github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/events"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/msg"
	st "github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/sendtables"
	"os"
	"strings"
	"testing"
)

func TestSourceProbe(t *testing.T) {
	path := os.Getenv("CS2_PROBE")
	if path == "" {
		t.Skip("diagnostic")
	}
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	c := dem.DefaultParserConfig
	c.MsgQueueBufferSize = 0
	p := dem.NewParserWithConfig(f, c)
	defer p.Close()
	seen := map[string]bool{}
	updates := 0
	p.RegisterEventHandler(func(e events.GrenadeProjectileThrow) {
		g := e.Projectile
		kind := grenadeType(g.WeaponInstance.Type)
		if seen[kind] {
			return
		}
		seen[kind] = true
		fmt.Println("PROJECTILE", kind, p.GameState().IngameTick())
		for _, property := range g.Entity.Properties() {
			name := property.Name()
			if strings.Contains(strings.ToLower(name), "smoke") || strings.Contains(strings.ToLower(name), "deton") || strings.Contains(strings.ToLower(name), "expl") || strings.Contains(strings.ToLower(name), "effect") {
				fmt.Println(name, property.Value())
				property.OnUpdate(func(v st.PropertyValue) {
					if updates < 80 {
						fmt.Println("UPDATE", kind, name, p.GameState().IngameTick(), v)
						updates++
					}
				})
			}
		}
	})
	p.RegisterNetMessageHandler(func(m *msg.CMsgTEExplosion) { fmt.Println("EXPLOSION", p.GameState().IngameTick(), m) })
	bullets := 0
	p.RegisterNetMessageHandler(func(m *msg.CMsgTEFireBullets) {
		bullets++
		if bullets < 4 {
			fmt.Println("BULLET", p.GameState().IngameTick(), m)
			for _, pl := range p.GameState().Participants().All() {
				fmt.Println("PLAYER", pl.EntityID, pl.UserID, pl.Name)
			}
		}
	})
	defer func() { fmt.Println("BULLETS", bullets) }()
	counts := map[string]int{}
	p.RegisterEventHandler(func(e events.RoundEnd) { fmt.Println("ROUND_REASON", p.GameState().IngameTick(), e.Reason) })
	p.RegisterEventHandler(func(e events.GenericGameEvent) {
		counts[e.Name]++
		if e.Name == "round_start" || e.Name == "round_end" {
			fmt.Println("ROUND", e.Name, p.GameState().IngameTick())
		}
	})
	shots := 0
	p.RegisterEventHandler(func(e events.WeaponFire) { shots++ })
	if err := p.ParseToEnd(); err != nil {
		t.Fatal(err)
	}
	fmt.Println("GENERIC", counts, "SHOTS", shots)
}
