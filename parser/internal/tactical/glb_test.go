package tactical

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"testing"
)

func TestCollisionConversion(t *testing.T) {
	// A translated authored triangle and a clip volume. Independently assert axes,
	// source units, material stripping and index validity rather than a golden file.
	var bin bytes.Buffer
	for _, v := range []float32{0, 0, 0, 0.0254, 0, 0, 0, 0.0254, 0} {
		binary.Write(&bin, binary.LittleEndian, v)
	}
	for _, v := range []uint32{0, 1, 2} {
		binary.Write(&bin, binary.LittleEndian, v)
	}
	primitive := map[string]any{"attributes": map[string]int{"POSITION": 0}, "indices": 1}
	doc := map[string]any{"scene": 0, "scenes": []any{map[string]any{"nodes": []int{0, 1}}}, "nodes": []any{map[string]any{"mesh": 0, "matrix": []float64{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0.0508, 1}}, map[string]any{"mesh": 1}}, "meshes": []any{map[string]any{"name": "floor", "primitives": []any{primitive}}, map[string]any{"name": "playerclip", "primitives": []any{primitive}}}, "accessors": []any{map[string]any{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"}, map[string]any{"bufferView": 1, "componentType": 5125, "count": 3, "type": "SCALAR"}}, "bufferViews": []any{map[string]int{"byteOffset": 0, "byteLength": 36}, map[string]int{"byteOffset": 36, "byteLength": 12}}}
	raw, _ := json.Marshal(doc)
	for len(raw)%4 != 0 {
		raw = append(raw, ' ')
	}
	var glb bytes.Buffer
	for _, v := range []uint32{0x46546c67, 2, uint32(28 + len(raw) + bin.Len()), uint32(len(raw)), 0x4e4f534a} {
		binary.Write(&glb, binary.LittleEndian, v)
	}
	glb.Write(raw)
	binary.Write(&glb, binary.LittleEndian, uint32(bin.Len()))
	binary.Write(&glb, binary.LittleEndian, uint32(0x004e4942))
	glb.Write(bin.Bytes())
	source, target := filepath.Join(t.TempDir(), "source.glb"), filepath.Join(t.TempDir(), "map.glb")
	os.WriteFile(source, glb.Bytes(), 0600)
	metrics, err := Convert(source, target)
	if err != nil {
		t.Fatal(err)
	}
	if metrics.Triangles != 1 || metrics.Excluded != 1 || math.Abs(metrics.Min[0]-2) > 0.001 || math.Abs(metrics.Min[2]+1) > 0.001 || math.Abs(metrics.Max[1]-1) > 0.001 {
		t.Fatalf("unexpected transformed triangle: %+v", metrics)
	}
	after, _ := os.ReadFile(source)
	if !bytes.Equal(after, glb.Bytes()) {
		t.Fatal("source modified")
	}
	output, _ := os.ReadFile(target)
	length := binary.LittleEndian.Uint32(output[12:])
	var result map[string]any
	if err = json.Unmarshal(output[20:20+length], &result); err != nil {
		t.Fatal(err)
	}
	if _, ok := result["textures"]; ok {
		t.Fatal("textures included")
	}
	if _, ok := result["images"]; ok {
		t.Fatal("images included")
	}
}
func TestMalformedCollisionFails(t *testing.T) {
	p := filepath.Join(t.TempDir(), "bad.glb")
	os.WriteFile(p, []byte("not a glb"), 0600)
	if _, err := Convert(p, p+".out"); err == nil {
		t.Fatal("accepted invalid GLB")
	}
}
