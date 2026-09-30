package tactical

import (
	"encoding/json"
	"math"
	"os"
	"testing"
)

func plane(y, size float64, label string) []triangle {
	return []triangle{{[3]vec{{0, y, 0}, {size, y, 0}, {size, y, size}}, label}, {[3]vec{{0, y, 0}, {size, y, size}, {0, y, size}}, label}}
}
func TestNavigationProtectsLevels(t *testing.T) {
	floor := append(plane(0, 1024, "floor"), plane(512, 1024, "upper")...)
	nav := append(plane(2, 1000, "nav"), plane(514, 1000, "nav")...)
	source := append(floor, plane(1024, 1024, "roof")...)
	kept, removed, stats, _ := classify(source, nav)
	if len(kept) != 4 || len(removed) != 2 || stats.ProtectedTriangles != 4 {
		t.Fatalf("multi-level loss: %+v", stats)
	}
	kept, removed, _, _ = classify(source, nil)
	if len(kept) != 6 || len(removed) != 0 {
		t.Fatal("missing nav must preserve uncertainty")
	}
	// Small cover and a slab immediately underneath an upper nav surface survive.
	source = append(plane(490, 1024, "slab"), plane(200, 64, "box")...)
	kept, removed, _, _ = classify(source, nav)
	if len(kept) != 4 || len(removed) != 0 {
		t.Fatal("cover/slab removed")
	}
}

func TestInclinedRoofAndWalkableRamp(t *testing.T) {
	slope := func(base float64) []triangle {
		tris := plane(base, 512, "structure")
		for i := range tris {
			for j := range tris[i].vertices {
				tris[i].vertices[j][1] += tris[i].vertices[j][0] * 0.5
			}
		}
		return tris
	}
	roof := slope(300)
	nav := plane(2, 512, "nav")
	_, removed, _, _ := classify(roof, nav)
	if len(removed) != 2 {
		t.Fatal("inclined overhead cover retained")
	}
	for _, navigation := range [][]triangle{nil, slope(302), append(nav, slope(302)...)} {
		kept, removed, _, _ := classify(roof, navigation)
		if len(kept) != 2 || len(removed) != 0 {
			t.Fatal("uncertain roof or walkable ramp removed")
		}
	}
	// High altitude alone is never a removal criterion.
	farNav := plane(2, 512, "nav")
	for i := range farNav {
		for j := range farNav[i].vertices {
			farNav[i].vertices[j][0] += 2048
		}
	}
	_, removed, _, _ = classify(roof, farNav)
	if len(removed) != 0 {
		t.Fatal("unsupported high geometry removed")
	}
}
func TestRealGeometry(t *testing.T) {
	source, nav, target := os.Getenv("TACTICAL_SOURCE"), os.Getenv("TACTICAL_NAV"), os.Getenv("TACTICAL_TARGET")
	if source == "" {
		t.Skip("optional local map acceptance")
	}
	m, e := ConvertWithNavigation(source, target, nav)
	if e != nil {
		t.Fatal(e)
	}
	b, _ := json.MarshalIndent(m, "", "  ")
	if e = os.WriteFile(target+".metrics.json", b, 0600); e != nil {
		t.Fatal(e)
	}
	t.Log(string(b))
	if m.Geometry.SourceTriangles != m.Geometry.RenderTriangles+m.Geometry.RoofRemovedTriangles+m.Geometry.DecorativeRemovedTriangles {
		t.Fatal("triangle conservation")
	}
	input, _, e := readTriangles(source, true)
	if e != nil {
		t.Fatal(e)
	}
	navigation, _, e := readTriangles(nav, false)
	if e != nil {
		t.Fatal(e)
	}
	kept, removed, _, _ := classify(input, navigation)
	for _, tri := range removed {
		n, _ := normalArea(tri)
		if math.Abs(n[1]) < 0.5 && tri.label != "physics_sky" {
			t.Fatal("non-horizontal structural wall removed")
		}
	}
	before, after := rayIndex(input), rayIndex(kept)
	levels := map[int][3]int{}
	lost := 0
	changed := 0
	for _, tri := range navigation {
		n, _ := normalArea(tri)
		if math.Abs(n[1]) < 0.5 {
			continue
		}
		p := vec{}
		for _, v := range tri.vertices {
			for k := 0; k < 3; k++ {
				p[k] += v[k] / 3
			}
		}
		b, a := before.support(p), after.support(p)
		key := int(math.Floor(p[1] / 256))
		v := levels[key]
		v[0]++
		if !math.IsInf(b, -1) {
			v[1]++
			if math.IsInf(a, -1) {
				lost++
			} else if math.Abs(a-b) > 0.01 {
				changed++
			}
		}
		if !math.IsInf(a, -1) {
			v[2]++
		}
		levels[key] = v
	}
	safety := map[string]any{"nav_height_bands_256": levels, "lost_support": lost, "changed_support": changed, "vertical_structure_preserved": true}
	b, _ = json.MarshalIndent(safety, "", "  ")
	os.WriteFile(target+".safety.json", b, 0600)
	t.Log(string(b))
	if lost != 0 || changed != 0 {
		t.Fatal("navigation support regression")
	}
}

type testRayIndex struct {
	tris []triangle
	bins map[[2]int][]int
}

func rayIndex(tris []triangle) testRayIndex {
	r := testRayIndex{tris: tris, bins: map[[2]int][]int{}}
	for i, t := range tris {
		n, _ := normalArea(t)
		if math.Abs(n[1]) < 0.01 {
			continue
		}
		b := triBounds(t)
		for x := int(math.Floor(b.min[0] / 128)); x <= int(math.Floor(b.max[0]/128)); x++ {
			for z := int(math.Floor(b.min[2] / 128)); z <= int(math.Floor(b.max[2]/128)); z++ {
				r.bins[[2]int{x, z}] = append(r.bins[[2]int{x, z}], i)
			}
		}
	}
	return r
}
func (r testRayIndex) support(p vec) float64 {
	best := math.Inf(-1)
	for _, i := range r.bins[[2]int{int(math.Floor(p[0] / 128)), int(math.Floor(p[2] / 128))}] {
		t := r.tris[i]
		a, b, c := t.vertices[0], t.vertices[1], t.vertices[2]
		den := (b[2]-c[2])*(a[0]-c[0]) + (c[0]-b[0])*(a[2]-c[2])
		if math.Abs(den) < 1e-9 {
			continue
		}
		u := ((b[2]-c[2])*(p[0]-c[0]) + (c[0]-b[0])*(p[2]-c[2])) / den
		v := ((c[2]-a[2])*(p[0]-c[0]) + (a[0]-c[0])*(p[2]-c[2])) / den
		if u < -1e-6 || v < -1e-6 || u+v > 1.000001 {
			continue
		}
		y := u*a[1] + v*b[1] + (1-u-v)*c[1]
		if y <= p[1]+32 && y >= p[1]-128 && y > best {
			best = y
		}
	}
	return best
}
