package serialization

import (
	"bytes"
	"compress/zlib"
	"crypto/sha256"
	"csdemowatch/parser/internal/replay"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"sort"
	"strings"
)

const BinaryVersion = 1
const ChunkSeconds = 10.0

var BinaryMagic = [8]byte{'C', 'S', '2', 'R', 'P', 'L', 'Y', 0}

type Chunk struct {
	Kind    string  `json:"kind"`
	Start   float64 `json:"start"`
	End     float64 `json:"end"`
	Offset  int     `json:"offset"`
	Size    int     `json:"size"`
	RawSize int     `json:"raw_size"`
	SHA256  string  `json:"sha256"`
}
type BinaryHeader struct {
	ReplayVersion int             `json:"replay_version"`
	Metadata      replay.Metadata `json:"metadata"`
	Players       []replay.Player `json:"players"`
	Bounds        [2][3]float64   `json:"bounds"`
	ChunkSeconds  float64         `json:"chunk_seconds"`
	Chunks        []Chunk         `json:"chunks"`
}

// WriteBinary leaves domain facts untouched. Only track positions are quantized
// to 1/32 Source unit; time is reconstructed exactly from original source ticks.
func WriteBinary(w io.Writer, r *replay.Replay) error {
	if err := replay.Validate(r); err != nil {
		return err
	}
	h := BinaryHeader{ReplayVersion: r.Version, Metadata: r.Metadata, Players: r.Players, ChunkSeconds: ChunkSeconds}
	var payload bytes.Buffer
	appendChunk := func(kind string, start, end float64, raw []byte) error {
		if len(raw) > 32<<20 {
			return fmt.Errorf("%s chunk exceeds 32 MiB", kind)
		}
		var encoded bytes.Buffer
		zw := zlib.NewWriter(&encoded)
		if _, err := zw.Write(raw); err != nil {
			return err
		}
		if err := zw.Close(); err != nil {
			return err
		}
		if encoded.Len() > 32<<20 {
			return fmt.Errorf("compressed chunk exceeds 32 MiB")
		}
		sum := sha256.Sum256(encoded.Bytes())
		h.Chunks = append(h.Chunks, Chunk{kind, start, end, payload.Len(), encoded.Len(), len(raw), hex.EncodeToString(sum[:])})
		_, err := payload.Write(encoded.Bytes())
		return err
	}
	initialized := false
	tracks := map[string][]replay.Frame{}
	for _, track := range r.Tracks {
		tracks[track.PlayerID] = track.Frames
		for _, f := range track.Frames {
			if f.Alive && f.Available {
				p := [3]float64{f.Position.X, f.Position.Y, f.Position.Z}
				if !initialized {
					h.Bounds = [2][3]float64{p, p}
					initialized = true
				}
				for k := 0; k < 3; k++ {
					h.Bounds[0][k] = math.Min(h.Bounds[0][k], p[k])
					h.Bounds[1][k] = math.Max(h.Bounds[1][k], p[k])
				}
			}
		}
	}
	jsonChunk := func(kind string, value any) error {
		b, e := json.Marshal(value)
		if e != nil {
			return e
		}
		return appendChunk(kind, 0, r.Metadata.Duration, b)
	}
	// Keep event families independently addressable. The viewer currently loads
	// these compact fact streams eagerly to preserve full-match timeline semantics.
	type indexedEvent struct {
		replay.Event
		Order int `json:"_order"`
	}
	families := map[string][]indexedEvent{"events": {}, "damage": {}, "bomb": {}}
	for order, e := range r.Events {
		kind := "events"
		if e.Type == "player_hurt" {
			kind = "damage"
		}
		if strings.HasPrefix(e.Type, "bomb_") {
			kind = "bomb"
		}
		families[kind] = append(families[kind], indexedEvent{e, order})
	}
	for _, kind := range []string{"events", "damage", "bomb"} {
		if e := jsonChunk(kind, families[kind]); e != nil {
			return e
		}
	}
	projectiles := r.Projectiles
	if projectiles == nil {
		projectiles = []replay.Projectile{}
	}
	if e := jsonChunk("projectiles", projectiles); e != nil {
		return e
	}
	// Round facts do not exist in V2 yet. Never infer rounds from bomb outcomes.
	if e := jsonChunk("rounds", []any{}); e != nil {
		return e
	}
	for start := 0.0; start < r.Metadata.Duration; start += ChunkSeconds {
		end := math.Min(start+ChunkSeconds, r.Metadata.Duration)
		var raw bytes.Buffer
		put := func(v int32) { _ = binary.Write(&raw, binary.LittleEndian, v) }
		put(int32(len(r.Players)))
		for playerIndex, p := range r.Players {
			frames := tracks[p.ID]
			lo := sort.Search(len(frames), func(i int) bool { return frames[i].Time >= start })
			if lo > 0 {
				lo--
			}
			hi := sort.Search(len(frames), func(i int) bool { return frames[i].Time > end })
			if hi < len(frames) {
				hi++
			}
			if hi-lo < 2 {
				lo = max(0, hi-2)
			}
			put(int32(playerIndex))
			put(int32(hi - lo))
			previous := [4]int64{}
			for _, f := range frames[lo:hi] {
				values := [4]int64{int64(f.Tick), int64(math.Round(f.Position.X * 32)), int64(math.Round(f.Position.Y * 32)), int64(math.Round(f.Position.Z * 32))}
				for k, v := range values {
					if v < math.MinInt32 || v > math.MaxInt32 {
						return fmt.Errorf("absolute track value out of range")
					}
					delta := v - previous[k]
					if delta < math.MinInt32 || delta > math.MaxInt32 {
						return fmt.Errorf("track delta out of range")
					}
					put(int32(delta))
					previous[k] = v
				}
				if math.Abs(f.Yaw) > math.MaxFloat32 {
					return fmt.Errorf("yaw out of range")
				}
				_ = binary.Write(&raw, binary.LittleEndian, float32(f.Yaw))
				if f.Health > math.MaxInt32 {
					return fmt.Errorf("health out of range")
				}
				put(int32(f.Health))
				flags := int32(0)
				if f.Alive {
					flags |= 1
				}
				if f.Available {
					flags |= 2
				}
				if f.Team == "CT" {
					flags |= 4
				}
				put(flags)
			}
		}
		if e := appendChunk("tracks", start, end, raw.Bytes()); e != nil {
			return e
		}
	}
	header, err := json.Marshal(h)
	if err != nil {
		return err
	}
	if len(header) > 4<<20 {
		return fmt.Errorf("header too large")
	}
	if _, err = w.Write(BinaryMagic[:]); err != nil {
		return err
	}
	if err = binary.Write(w, binary.LittleEndian, uint32(BinaryVersion)); err != nil {
		return err
	}
	if err = binary.Write(w, binary.LittleEndian, uint32(len(header))); err != nil {
		return err
	}
	if _, err = w.Write(header); err != nil {
		return err
	}
	_, err = w.Write(payload.Bytes())
	return err
}
