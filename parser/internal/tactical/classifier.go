package tactical

import (
	"math"
	"sort"
	"strings"
)

const ClassifierVersion = "2"

type GeometryStats struct {
	SourceTriangles            int            `json:"source_triangles"`
	RenderTriangles            int            `json:"render_triangles"`
	StructuralTriangles        int            `json:"kept_structural_triangles"`
	RoofRemovedTriangles       int            `json:"roof_removed_triangles"`
	DecorativeRemovedTriangles int            `json:"decorative_removed_triangles"`
	UnknownTriangles           int            `json:"unknown_triangles"`
	NavigationTriangles        int            `json:"navigation_triangles"`
	ProtectedTriangles         int            `json:"walkable_protected_triangles"`
	Classes                    map[string]int `json:"classes"`
}
type SurfaceGroup struct {
	Class     string  `json:"class"`
	Reason    string  `json:"reason"`
	Triangles int     `json:"triangles"`
	Area      float64 `json:"area_source_units_squared"`
	Min, Max  vec
	Protected bool `json:"walkable_protected"`
	NavBelow  bool `json:"navigation_below"`
}
type bounds struct{ min, max vec }

func triBounds(t triangle) bounds {
	b := bounds{t.vertices[0], t.vertices[0]}
	for _, v := range t.vertices {
		for k := 0; k < 3; k++ {
			b.min[k] = math.Min(b.min[k], v[k])
			b.max[k] = math.Max(b.max[k], v[k])
		}
	}
	return b
}
func normalArea(t triangle) (vec, float64) {
	n := cross(sub(t.vertices[1], t.vertices[0]), sub(t.vertices[2], t.vertices[0]))
	l := math.Sqrt(n[0]*n[0] + n[1]*n[1] + n[2]*n[2])
	if l > 0 {
		for k := range n {
			n[k] /= l
		}
	}
	return n, l / 2
}

type navIndex struct {
	bins  map[[2]int][]int
	items []bounds
}

func indexNav(nav []triangle) navIndex {
	index := navIndex{bins: map[[2]int][]int{}}
	for _, t := range nav {
		n, _ := normalArea(t)
		if math.Abs(n[1]) < 0.5 {
			continue
		} // Ladders cannot prove a floor.
		b := triBounds(t)
		i := len(index.items)
		index.items = append(index.items, b)
		for x := int(math.Floor((b.min[0] - 24) / 128)); x <= int(math.Floor((b.max[0]+24)/128)); x++ {
			for z := int(math.Floor((b.min[2] - 24) / 128)); z <= int(math.Floor((b.max[2]+24)/128)); z++ {
				index.bins[[2]int{x, z}] = append(index.bins[[2]int{x, z}], i)
			}
		}
	}
	return index
}

// Bounding-box overlap intentionally over-protects: nav erosion, stairs and small
// gaps must not make a real floor disappear. All hulls and all elevations count.
func (nav navIndex) evidence(b bounds) (protected, below bool) {
	seen := map[int]bool{}
	for x := int(math.Floor(b.min[0] / 128)); x <= int(math.Floor(b.max[0]/128)); x++ {
		for z := int(math.Floor(b.min[2] / 128)); z <= int(math.Floor(b.max[2]/128)); z++ {
			for _, i := range nav.bins[[2]int{x, z}] {
				if seen[i] {
					continue
				}
				seen[i] = true
				n := nav.items[i]
				if b.max[0] < n.min[0]-24 || b.min[0] > n.max[0]+24 || b.max[2] < n.min[2]-24 || b.min[2] > n.max[2]+24 {
					continue
				}
				if b.min[1] <= n.max[1]+72 && b.max[1] >= n.min[1]-72 {
					protected = true
				}
				if b.min[1]-n.max[1] >= 128 {
					below = true
				}
			}
		}
	}
	return
}

// Classification happens once at preparation. No map names or absolute heights.
// Connected near-horizontal surfaces use shared quantized edges, area, height
// range and authored navigation. Missing navigation preserves uncertain geometry.
func classify(input, nav []triangle) (kept, removed []triangle, stats GeometryStats, groups []SurfaceGroup) {
	stats.Classes = map[string]int{}
	stats.NavigationTriangles = len(nav)
	ni := indexNav(nav)
	parent := make([]int, len(input))
	normals := make([]vec, len(input))
	areas := make([]float64, len(input))
	boxes := make([]bounds, len(input))
	var root func(int) int
	root = func(i int) int {
		if parent[i] != i {
			parent[i] = root(parent[i])
		}
		return parent[i]
	}
	type edge [2]vec
	edges := map[edge]int{}
	less := func(a, b vec) bool {
		for k := 0; k < 3; k++ {
			if a[k] != b[k] {
				return a[k] < b[k]
			}
		}
		return false
	}
	for i, t := range input {
		parent[i] = i
		normals[i], areas[i] = normalArea(t)
		boxes[i] = triBounds(t)
		if math.Abs(normals[i][1]) < 0.5 {
			continue
		}
		for c := 0; c < 3; c++ {
			a, b := t.vertices[c], t.vertices[(c+1)%3]
			if less(b, a) {
				a, b = b, a
			}
			key := edge{a, b}
			if j, ok := edges[key]; ok {
				dot := normals[i][0]*normals[j][0] + normals[i][1]*normals[j][1] + normals[i][2]*normals[j][2]
				// Do not let a shallow bevel join a flat ceiling to an inclined
				// component and erase the existing horizontal roof evidence.
				if math.Abs(dot) > 0.98 && (math.Abs(normals[i][1]) >= 0.94) == (math.Abs(normals[j][1]) >= 0.94) {
					parent[root(i)] = root(j)
				}
			} else {
				edges[key] = i
			}
		}
	}
	members := map[int][]int{}
	for i := range input {
		r := root(i)
		members[r] = append(members[r], i)
	}
	keys := make([]int, 0, len(members))
	for k := range members {
		keys = append(keys, k)
	}
	sort.Ints(keys)
	for _, key := range keys {
		ids := members[key]
		g := SurfaceGroup{Class: "UNKNOWN", Reason: "insufficient semantic evidence", Min: boxes[key].min, Max: boxes[key].max, Triangles: len(ids)}
		sky := true
		horizontal := true
		inclinedCover := true
		allAboveNav := true
		projectedArea := 0.0
		vertical := true
		for _, i := range ids {
			g.Area += areas[i]
			for k := 0; k < 3; k++ {
				g.Min[k] = math.Min(g.Min[k], boxes[i].min[k])
				g.Max[k] = math.Max(g.Max[k], boxes[i].max[k])
			}
			p, b := ni.evidence(boxes[i])
			g.Protected = g.Protected || p
			g.NavBelow = g.NavBelow || b
			allAboveNav = allAboveNav && b
			projectedArea += areas[i] * math.Abs(normals[i][1])
			inclinedCover = inclinedCover && math.Abs(normals[i][1]) >= 0.5
			sky = sky && (input[i].label == "physics_sky" || strings.Contains(strings.ToLower(input[i].label), "skybox"))
			horizontal = horizontal && math.Abs(normals[i][1]) >= 0.94
			vertical = vertical && math.Abs(normals[i][1]) < 0.2
		}
		switch {
		case g.Protected && horizontal:
			g.Class = "FLOOR"
			g.Reason = "authored navigation overlaps surface or slab within 72 units"
		case sky && !g.Protected && len(ni.items) > 0:
			g.Class = "ROOF"
			g.Reason = "authored sky boundary, not walkable geometry"
		case horizontal && g.Area >= 65536 && g.Max[1]-g.Min[1] <= 64 && g.NavBelow && !g.Protected:
			g.Class = "ROOF"
			if normals[key][1] < 0 {
				g.Class = "CEILING"
			}
			g.Reason = "large connected horizontal cover over navigation; no nearby walkable level"
		case inclinedCover && !horizontal && projectedArea >= 65536 && allAboveNav && !g.Protected:
			g.Class = "ROOF"
			g.Reason = "large connected inclined cover; every face above navigation, no nearby walkable level"
		case vertical:
			g.Class = "WALL"
			g.Reason = "near vertical surface preserved"
		case g.Protected && math.Abs(normals[key][1]) >= 0.2:
			g.Class = "STAIR"
			g.Reason = "inclined navigation-adjacent structure preserved"
		case horizontal && g.Area < 65536 && g.NavBelow:
			g.Class = "MAJOR_COVER"
			g.Reason = "small elevated cover preserved"
		}
		roof := g.Class == "ROOF" || g.Class == "CEILING"
		for _, i := range ids {
			if roof {
				removed = append(removed, input[i])
			} else {
				kept = append(kept, input[i])
			}
		}
		stats.Classes[g.Class] += len(ids)
		if roof {
			stats.RoofRemovedTriangles += len(ids)
		} else if g.Class == "UNKNOWN" {
			stats.UnknownTriangles += len(ids)
		} else {
			stats.StructuralTriangles += len(ids)
		}
		if g.Protected {
			stats.ProtectedTriangles += len(ids)
		}
		groups = append(groups, g)
	}
	stats.RenderTriangles = len(kept)
	return
}
