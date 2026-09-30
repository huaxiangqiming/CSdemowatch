// Package tactical converts authored collision geometry into texture-free tactical GLB.
package tactical

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"regexp"
	"sort"
)

type vec [3]float64
type matrix [16]float64
type primitive struct {
	Attributes map[string]int
	Indices    int
	Mode       *int
}
type gltf struct {
	Scene  int
	Scenes []struct{ Nodes []int }
	Nodes  []struct {
		Name                         string
		Mesh                         *int
		Matrix                       []float64
		Translation, Rotation, Scale []float64
		Children                     []int
	}
	Meshes []struct {
		Name       string
		Primitives []primitive
	}
	Accessors []struct {
		BufferView                       int
		ByteOffset, ComponentType, Count int
		Type                             string
	}
	BufferViews []struct{ Buffer, ByteOffset, ByteLength, ByteStride int }
}
type triangle struct {
	vertices [3]vec
	label    string
}
type part struct {
	positions []vec
	indices   []uint32
}
type Metrics struct {
	Triangles int `json:"triangles"`
	Bytes     int `json:"bytes"`
	Chunks    int `json:"chunks"`
	Excluded  int `json:"excluded_nodes"`
	Min, Max  vec
	Geometry  GeometryStats `json:"geometry_stats"`
}

func identity() matrix { return matrix{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1} }
func mul(a, b matrix) (c matrix) {
	for col := 0; col < 4; col++ {
		for row := 0; row < 4; row++ {
			for k := 0; k < 4; k++ {
				c[col*4+row] += a[k*4+row] * b[col*4+k]
			}
		}
	}
	return
}
func point(m matrix, v vec) vec {
	var r vec
	for i := 0; i < 3; i++ {
		r[i] = m[i]*v[0] + m[4+i]*v[1] + m[8+i]*v[2] + m[12+i]
	}
	return r
}
func sub(a, b vec) vec { return vec{a[0] - b[0], a[1] - b[1], a[2] - b[2]} }
func cross(a, b vec) vec {
	return vec{a[1]*b[2] - a[2]*b[1], a[2]*b[0] - a[0]*b[2], a[0]*b[1] - a[1]*b[0]}
}

// Convert never modifies its source. Coordinates match the existing M3 converter:
// exporter (Y,Z,X) metres -> (X,Z,-Y) Source units. Replay coordinates stay raw.
func Convert(source, target string) (Metrics, error) {
	return ConvertWithNavigation(source, target, "")
}

func ConvertWithNavigation(source, target, navigation string) (metrics Metrics, err error) {
	triangles, metrics, err := readTriangles(source, true)
	if err != nil {
		return metrics, err
	}
	var nav []triangle
	if navigation != "" {
		nav, _, err = readTriangles(navigation, false)
		if err != nil {
			return metrics, fmt.Errorf("navigation GLB: %w", err)
		}
	}
	kept, removed, stats, groups := classify(triangles, nav)
	stats.SourceTriangles = metrics.Geometry.SourceTriangles
	stats.DecorativeRemovedTriangles = metrics.Geometry.DecorativeRemovedTriangles
	metrics.Geometry = stats
	if err = writeGeometry(target, kept, &metrics); err != nil {
		return metrics, err
	}
	// Removed geometry remains inspectable, but is never loaded by the normal viewer.
	if len(removed) > 0 {
		debug := Metrics{}
		if err = writeGeometry(target+".roofs.glb", removed, &debug); err != nil {
			return metrics, err
		}
	}
	encoded, err := json.MarshalIndent(groups, "", "  ")
	if err != nil {
		return metrics, err
	}
	err = os.WriteFile(target+".classification.json", encoded, 0600)
	return metrics, err
}

func readTriangles(source string, filter bool) (triangles []triangle, metrics Metrics, err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("invalid collision GLB: %v", r)
		}
	}()

	blob, err := os.ReadFile(source)
	if err != nil {
		return
	}
	if len(blob) < 28 || binary.LittleEndian.Uint32(blob) != 0x46546c67 {
		return nil, metrics, fmt.Errorf("invalid GLB header")
	}
	n := int(binary.LittleEndian.Uint32(blob[12:]))
	var doc gltf
	if err = json.Unmarshal(blob[20:20+n], &doc); err != nil {
		return
	}
	data := blob[28+n:]
	access := func(index, components int) []float64 {
		a := doc.Accessors[index]
		v := doc.BufferViews[a.BufferView]
		width := map[int]int{5126: 4, 5125: 4, 5123: 2, 5121: 1}[a.ComponentType]
		if width == 0 || v.Buffer != 0 {
			panic("unsupported accessor")
		}
		stride := v.ByteStride
		if stride == 0 {
			stride = width * components
		}
		out := make([]float64, a.Count*components)
		for i := 0; i < a.Count; i++ {
			for c := 0; c < components; c++ {
				offset := v.ByteOffset + a.ByteOffset + i*stride + c*width
				b := data[offset : offset+width]
				var f float64
				switch a.ComponentType {
				case 5126:
					f = float64(math.Float32frombits(binary.LittleEndian.Uint32(b)))
				case 5125:
					f = float64(binary.LittleEndian.Uint32(b))
				case 5123:
					f = float64(binary.LittleEndian.Uint16(b))
				case 5121:
					f = float64(b[0])
				}
				if math.IsNaN(f) || math.IsInf(f, 0) {
					panic("non-finite coordinate")
				}
				out[i*components+c] = f
			}
		}
		return out
	}
	excluded := regexp.MustCompile(`(?i)npcclip|playerclip|grenadeclip|blocklight|overlay|water|dust|candle|foliage|fern|ivy|grass|leaf|leaves|vine|tree|banyan|trunk|yucca|palm|shrub|flower|pottery|lantern|decal|cable|rope|cloth|debris|garbage|trash|skybox`)

	visiting := map[int]bool{}
	var visit func(int, matrix)
	visit = func(index int, parent matrix) {
		if visiting[index] {
			panic("cyclic nodes")
		}
		visiting[index] = true
		defer delete(visiting, index)
		node := doc.Nodes[index]
		local := identity()
		if len(node.Translation)+len(node.Rotation)+len(node.Scale) > 0 {
			panic("unsupported exporter TRS")
		}
		if len(node.Matrix) > 0 {
			if len(node.Matrix) != 16 {
				panic("invalid matrix")
			}
			copy(local[:], node.Matrix)
		}
		m := mul(parent, local)
		if node.Mesh != nil {
			mesh := doc.Meshes[*node.Mesh]
			if filter && excluded.MatchString(mesh.Name) {
				for _, p := range mesh.Primitives {
					count := doc.Accessors[p.Indices].Count / 3
					metrics.Geometry.SourceTriangles += count
					metrics.Geometry.DecorativeRemovedTriangles += count
				}
				metrics.Excluded++
			} else {
				for _, p := range mesh.Primitives {
					if p.Mode != nil && *p.Mode != 4 {
						continue
					}
					posIndex, ok := p.Attributes["POSITION"]
					if !ok {
						panic("missing POSITION")
					}
					raw := access(posIndex, 3)
					ind := access(p.Indices, 1)
					if len(ind)%3 != 0 {
						panic("invalid triangles")
					}
					metrics.Geometry.SourceTriangles += len(ind) / 3
					for i := 0; i < len(ind); i += 3 {
						var tri [3]vec
						var center vec
						for c := 0; c < 3; c++ {
							j := int(ind[i+c]) * 3
							q := point(m, vec{raw[j], raw[j+1], raw[j+2]})
							tri[c] = vec{q[2] / 0.0254, q[1] / 0.0254, -q[0] / 0.0254}
							for k := 0; k < 3; k++ {
								tri[c][k] = math.Round(tri[c][k]*1000) / 1000
								center[k] += tri[c][k] / 3
							}
						}
						triangles = append(triangles, triangle{tri, mesh.Name})
					}
				}
			}
		}
		for _, child := range node.Children {
			visit(child, m)
		}
	}
	for _, root := range doc.Scenes[doc.Scene].Nodes {
		visit(root, identity())
	}
	return triangles, metrics, nil
}

func writeGeometry(target string, triangles []triangle, metrics *Metrics) error {
	if len(triangles) == 0 {
		return fmt.Errorf("no structural collision triangles")
	}
	buckets := map[[2]int]*part{}
	for _, t := range triangles {
		var center vec
		for _, v := range t.vertices {
			for k := 0; k < 3; k++ {
				center[k] += v[k] / 3
			}
		}
		cell := [2]int{int(math.Floor(center[0] / 512)), int(math.Floor(center[2] / 512))}
		chunk := buckets[cell]
		if chunk == nil {
			chunk = &part{}
			buckets[cell] = chunk
		}
		for _, v := range t.vertices {
			chunk.positions = append(chunk.positions, v)
		}
	}
	var bin bytes.Buffer
	views := []any{}
	accessors := []any{}
	nodes := []any{}
	meshes := []any{}
	roots := []int{}
	add := func(value any, count int, kind string, component int, bounds []vec) int {
		for bin.Len()%4 != 0 {
			bin.WriteByte(0)
		}
		offset := bin.Len()
		if e := binary.Write(&bin, binary.LittleEndian, value); e != nil {
			panic(e)
		}
		views = append(views, map[string]any{"buffer": 0, "byteOffset": offset, "byteLength": bin.Len() - offset})
		a := map[string]any{"bufferView": len(views) - 1, "componentType": component, "count": count, "type": kind}
		if len(bounds) > 0 {
			a["min"] = bounds[0]
			a["max"] = bounds[1]
		}
		accessors = append(accessors, a)
		return len(accessors) - 1
	}
	keys := make([][2]int, 0, len(buckets))
	for k := range buckets {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i][0] == keys[j][0] {
			return keys[i][1] < keys[j][1]
		}
		return keys[i][0] < keys[j][0]
	})
	metrics.Min = vec{math.Inf(1), math.Inf(1), math.Inf(1)}
	metrics.Max = vec{math.Inf(-1), math.Inf(-1), math.Inf(-1)}
	for _, key := range keys {
		chunk := buckets[key]
		unique := map[vec]uint32{}
		positions := []vec{}
		indices := make([]uint32, len(chunk.positions))
		for i, v := range chunk.positions {
			j, ok := unique[v]
			if !ok {
				j = uint32(len(positions))
				unique[v] = j
				positions = append(positions, v)
			}
			indices[i] = j
		}
		normals := make([]vec, len(positions))
		minV, maxV := positions[0], positions[0]
		for i := 0; i < len(indices); i += 3 {
			a, b, c := indices[i], indices[i+1], indices[i+2]
			normal := cross(sub(positions[b], positions[a]), sub(positions[c], positions[a]))
			for _, j := range []uint32{a, b, c} {
				for k := 0; k < 3; k++ {
					normals[j][k] += normal[k]
				}
			}
		}
		pos, norm := make([]float32, 0, len(positions)*3), make([]float32, 0, len(positions)*3)
		for i, v := range positions {
			length := math.Sqrt(normals[i][0]*normals[i][0] + normals[i][1]*normals[i][1] + normals[i][2]*normals[i][2])
			if length < 1e-9 {
				length = 1
			}
			for k := 0; k < 3; k++ {
				minV[k] = math.Min(minV[k], v[k])
				maxV[k] = math.Max(maxV[k], v[k])
				pos = append(pos, float32(v[k]))
				norm = append(norm, float32(normals[i][k]/length))
			}
		}
		for k := 0; k < 3; k++ {
			metrics.Min[k] = math.Min(metrics.Min[k], minV[k])
			metrics.Max[k] = math.Max(metrics.Max[k], maxV[k])
		}
		p := add(pos, len(positions), "VEC3", 5126, []vec{minV, maxV})
		no := add(norm, len(positions), "VEC3", 5126, nil)
		ix := add(indices, len(indices), "SCALAR", 5125, nil)
		roots = append(roots, len(nodes))
		nodes = append(nodes, map[string]any{"name": fmt.Sprintf("Structure_%d_%d", key[0], key[1]), "mesh": len(meshes)})
		meshes = append(meshes, map[string]any{"primitives": []any{map[string]any{"attributes": map[string]int{"POSITION": p, "NORMAL": no}, "indices": ix, "material": 0}}})
		metrics.Triangles += len(indices) / 3
	}
	output := map[string]any{"asset": map[string]string{"version": "2.0", "generator": "CS2 Tactical Map 0.7.1 / Source2Viewer 20 collision"}, "scene": 0, "scenes": []any{map[string]any{"nodes": roots}}, "nodes": nodes, "meshes": meshes, "accessors": accessors, "bufferViews": views, "buffers": []any{map[string]int{"byteLength": bin.Len()}}, "materials": []any{map[string]any{"name": "Tactical gray", "doubleSided": true, "pbrMetallicRoughness": map[string]any{"baseColorFactor": []float64{0.55, 0.57, 0.60, 1}, "metallicFactor": 0, "roughnessFactor": 1}}}}
	encoded, e := json.Marshal(output)
	if e != nil {
		return e
	}
	for len(encoded)%4 != 0 {
		encoded = append(encoded, ' ')
	}
	for bin.Len()%4 != 0 {
		bin.WriteByte(0)
	}
	var result bytes.Buffer
	for _, v := range []uint32{0x46546c67, 2, uint32(28 + len(encoded) + bin.Len()), uint32(len(encoded)), 0x4e4f534a} {
		binary.Write(&result, binary.LittleEndian, v)
	}
	result.Write(encoded)
	binary.Write(&result, binary.LittleEndian, uint32(bin.Len()))
	binary.Write(&result, binary.LittleEndian, uint32(0x004e4942))
	result.Write(bin.Bytes())
	metrics.Bytes = result.Len()
	metrics.Chunks = len(keys)
	return os.WriteFile(target, result.Bytes(), 0600)
}
