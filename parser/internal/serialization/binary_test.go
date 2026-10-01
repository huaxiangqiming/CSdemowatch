package serialization

import (
	"bytes"
	"compress/zlib"
	"crypto/sha256"
	"csdemowatch/parser/internal/replay"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"io"
	"math"
	"testing"
)

func binaryFixture() *replay.Replay {
	r := &replay.Replay{Version: 2, Metadata: replay.Metadata{Map: "test_plane", Duration: 25, SourceTickRate: 64, SampleRate: 16, CoordinateSystem: "cs2_raw", SourceStartTick: 0, SourceEndTick: 1600}, Players: []replay.Player{{ID: "p", Name: "Synthetic", Team: "T"}}}
	tr := replay.Track{PlayerID: "p"}
	for i := 0; i <= 400; i++ {
		tr.Frames = append(tr.Frames, replay.Frame{Time: float64(i) / 16, Tick: i * 4, Position: replay.Position{X: float64(i) * 0.117, Y: -22.3, Z: 64.2}, Yaw: 179.99, Health: 100, Alive: true, Available: true, Team: "T"})
	}
	r.Tracks = []replay.Track{tr}
	return r
}
func TestBinaryWindowIntegrity(t *testing.T) {
	r := binaryFixture()
	var output bytes.Buffer
	if e := WriteBinary(&output, r); e != nil {
		t.Fatal(e)
	}
	data := output.Bytes()
	if !bytes.Equal(data[:8], BinaryMagic[:]) || binary.LittleEndian.Uint32(data[8:]) != 1 {
		t.Fatal("header")
	}
	length := int(binary.LittleEndian.Uint32(data[12:]))
	var h BinaryHeader
	if e := json.Unmarshal(data[16:16+length], &h); e != nil {
		t.Fatal(e)
	}
	payload := data[16+length:]
	windows := 0
	nextOffset := 0
	for _, c := range h.Chunks {
		if c.Offset != nextOffset {
			t.Fatal("non-contiguous chunks")
		}
		nextOffset += c.Size
		compressed := payload[c.Offset : c.Offset+c.Size]
		sum := sha256.Sum256(compressed)
		if hex.EncodeToString(sum[:]) != c.SHA256 {
			t.Fatal("checksum")
		}
		zr, e := zlib.NewReader(bytes.NewReader(compressed))
		if e != nil {
			t.Fatal(e)
		}
		raw, e := io.ReadAll(zr)
		zr.Close()
		if e != nil || len(raw) != c.RawSize {
			t.Fatal("decompression")
		}
		if c.Kind != "tracks" {
			continue
		}
		windows++
		reader := bytes.NewReader(raw)
		var roster, id, count int32
		for _, v := range []*int32{&roster, &id, &count} {
			if e := binary.Read(reader, binary.LittleEndian, v); e != nil {
				t.Fatal(e)
			}
		}
		if roster != 1 || id != 0 || count < 2 {
			t.Fatal("roster")
		}
		values := [4]int32{}
		first, last := -1.0, -1.0
		for i := int32(0); i < count; i++ {
			for k := range values {
				var delta int32
				binary.Read(reader, binary.LittleEndian, &delta)
				values[k] += delta
			}
			var yaw float32
			var health, flags int32
			binary.Read(reader, binary.LittleEndian, &yaw)
			binary.Read(reader, binary.LittleEndian, &health)
			binary.Read(reader, binary.LittleEndian, &flags)
			time := float64(values[0]) / 64
			if i == 0 {
				first = time
			}
			last = time
			expected := r.Tracks[0].Frames[values[0]/4]
			if math.Abs(float64(values[1])/32-expected.Position.X) > 1.0/64+1e-8 || health != 100 || flags != 3 || math.Abs(float64(yaw)-179.99) > 0.00002 {
				t.Fatal("roundtrip")
			}
		}
		if first > c.Start || last < c.End || reader.Len() != 0 {
			t.Fatal("window does not bracket seek interval")
		}
	}
	if windows != 3 || nextOffset != len(payload) {
		t.Fatal("index coverage")
	}
}

type failingWriter struct{}

func (failingWriter) Write(p []byte) (int, error) { return 0, io.ErrClosedPipe }
func TestBinaryWriteErrors(t *testing.T) {
	if WriteBinary(failingWriter{}, binaryFixture()) == nil {
		t.Fatal("ignored output error")
	}
	if WriteBinary(io.Discard, &replay.Replay{}) == nil {
		t.Fatal("accepted invalid replay")
	}
}
