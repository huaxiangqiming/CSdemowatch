// Package demo is the only package that knows the CS2 protocol library.
package demo

import (
	"fmt"
	"io"
	"math"
	"sort"
	"strconv"
	"strings"

	"csdemowatch/parser/internal/replay"
	dem "github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/common"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/events"
	"github.com/markus-wa/demoinfocs-golang/v5/pkg/demoinfocs/msg"
)

type recorder struct {
	r              *replay.Replay
	players        map[string]replay.Player
	tracks         map[string][]replay.Frame
	localIDs       map[*common.Player]string
	gate           SampleGate
	started        bool
	lastTick       int
	lastSampleTick int
}

// Parse reads offline Source 2 data only. No network or game process access.
func Parse(input io.Reader, warnings io.Writer) (out *replay.Replay, err error) {
	return parseVersion(input, warnings, replay.Version)
}

func ParseV2(input io.Reader, warnings io.Writer) (*replay.Replay, error) {
	return parseVersion(input, warnings, replay.Version2)
}

func parseVersion(input io.Reader, warnings io.Writer, version int) (out *replay.Replay, err error) {
	// Sequential dispatch keeps protocol panics inside this recover boundary.
	defer func() {
		if cause := recover(); cause != nil {
			out = nil
			err = fmt.Errorf("corrupt/unsupported CS2 demo: %v", cause)
		}
	}()
	config := dem.DefaultParserConfig
	config.MsgQueueBufferSize = 0
	config.DisableMimicSource1Events = version == replay.Version
	// Keep ownership of the caller's reader with the caller (the library closes
	// readers implementing io.Closer when its parser is closed).
	p := dem.NewParserWithConfig(struct{ io.Reader }{input}, config)
	defer p.Close()
	r := &recorder{r: &replay.Replay{Version: replay.Version, Metadata: replay.Metadata{SampleRate: replay.SampleRate, CoordinateSystem: "cs2_raw"}},
		players: map[string]replay.Player{}, tracks: map[string][]replay.Frame{}, localIDs: map[*common.Player]string{}, gate: SampleGate{Rate: replay.SampleRate}, lastSampleTick: -1}
	r.r.Version = version
	var combat *combatRecorder
	if version == replay.Version2 {
		combat = newCombatRecorder(r, p)
		combat.register()
	}
	p.RegisterNetMessageHandler(func(m *msg.CDemoFileHeader) { r.r.Metadata.Map = m.GetMapName() })
	p.RegisterNetMessageHandler(func(m *msg.CSVCMsg_ServerInfo) {
		if r.r.Metadata.Map == "" {
			r.r.Metadata.Map = m.GetMapName()
		}
	})
	warningCount := 0
	p.RegisterEventHandler(func(w events.ParserWarn) {
		warningCount++
		if warningCount <= 5 && warnings != nil {
			fmt.Fprintf(warnings, "WARNING: %s\n", w.Message)
		}
	})
	var captureErr error
	p.RegisterEventHandler(func(_ events.FrameDone) {
		if captureErr != nil {
			return
		}
		tick, rate := p.GameState().IngameTick(), p.TickRate()
		if tick < 0 || !replay.Finite(rate) || rate <= 0 {
			return
		} // sign-on packets
		if !r.started {
			if rate < replay.SampleRate {
				captureErr = fmt.Errorf("source tick rate %.3f is lower than 16 Hz", rate)
				return
			}
			r.started = true
			r.r.Metadata.SourceStartTick, r.r.Metadata.SourceTickRate = tick, rate
			r.lastTick = tick
		} else {
			if math.Abs(rate-r.r.Metadata.SourceTickRate) > 1e-6 {
				captureErr = fmt.Errorf("changing source tick rate is unsupported")
				return
			}
			if tick < r.lastTick {
				captureErr = fmt.Errorf("source tick rewound from %d to %d; refusing an ambiguous timeline", r.lastTick, tick)
				return
			}
		}
		r.lastTick = tick
		if combat != nil {
			combat.onFrame()
		}
		seconds := float64(tick-r.r.Metadata.SourceStartTick) / rate
		if r.gate.Due(seconds) {
			captureErr = r.capture(p, tick, seconds)
			if combat != nil {
				combat.capture()
			}
		}
	})
	if err = p.ParseToEnd(); err != nil {
		return nil, fmt.Errorf("parse demo: %w", err)
	}
	if captureErr != nil {
		return nil, captureErr
	}
	if !r.started || r.lastTick <= r.r.Metadata.SourceStartTick {
		return nil, fmt.Errorf("demo contains no valid source timeline")
	}
	r.r.Metadata.SourceEndTick = r.lastTick
	r.r.Metadata.Duration = float64(r.lastTick-r.r.Metadata.SourceStartTick) / r.r.Metadata.SourceTickRate
	if r.lastSampleTick < r.lastTick {
		if err := r.capture(p, r.lastTick, r.r.Metadata.Duration); err != nil {
			return nil, err
		}
	}
	if combat != nil {
		combat.finish()
	}
	keys := make([]string, 0, len(r.players))
	for id := range r.players {
		keys = append(keys, id)
	}
	sort.Strings(keys)
	for _, id := range keys {
		frames := r.tracks[id]
		if len(frames) == 0 {
			continue
		}
		if frames[0].Time > 0 {
			// Player did not exist at replay start. Explicitly hide the padding.
			padding := replay.Frame{Time: 0, Tick: r.r.Metadata.SourceStartTick, Team: r.players[id].Team}
			frames = append([]replay.Frame{padding}, frames...)
		}
		r.r.Players = append(r.r.Players, r.players[id])
		r.r.Tracks = append(r.r.Tracks, replay.Track{PlayerID: id, Frames: frames})
	}
	if warningCount > 5 && warnings != nil {
		fmt.Fprintf(warnings, "WARNING: %d additional library warnings suppressed\n", warningCount-5)
	}
	if err := replay.Validate(r.r); err != nil {
		return nil, fmt.Errorf("replay validation: %w", err)
	}
	return r.r, nil
}

func (r *recorder) capture(p dem.Parser, tick int, seconds float64) error {
	if tick <= r.lastSampleTick {
		return nil
	}
	r.lastSampleTick = tick
	observed := map[string]replay.Frame{}
	participants := p.GameState().Participants().All()
	// Stable fallback IDs even though the upstream participant map is unordered.
	sort.Slice(participants, func(i, j int) bool { return participants[i].EntityID < participants[j].EntityID })
	for _, player := range participants {
		team := teamName(player.Team)
		if team == "" || !player.IsConnected {
			continue
		}
		id := r.playerID(player)
		if _, ok := r.players[id]; !ok {
			name := strings.TrimSpace(player.Name)
			if name == "" {
				name = id
			}
			steam := ""
			if player.SteamID64 != 0 {
				steam = strconv.FormatUint(player.SteamID64, 10)
			}
			r.players[id] = replay.Player{ID: id, SteamID: steam, Name: name, Team: team}
		}
		if r.players[id].SteamID == "" && player.SteamID64 != 0 {
			roster := r.players[id]
			roster.SteamID = strconv.FormatUint(player.SteamID64, 10)
			r.players[id] = roster
		}
		state := replay.Frame{Time: seconds, Tick: tick, Team: team}
		if previous := r.tracks[id]; len(previous) > 0 {
			state.Position = previous[len(previous)-1].Position
			state.Yaw = previous[len(previous)-1].Yaw
		}
		if player.PlayerPawnEntity() != nil {
			pos := player.Position()
			state.Position = replay.Position{X: pos.X, Y: pos.Y, Z: pos.Z}
			state.Yaw = float64(player.ViewDirectionX())
			state.Health = player.Health()
			state.Alive = player.IsAlive()
			state.Available = true
			if !replay.Finite(pos.X) || !replay.Finite(pos.Y) || !replay.Finite(pos.Z) || !replay.Finite(state.Yaw) {
				return fmt.Errorf("nonfinite player coordinates at tick %d for %s", tick, id)
			}
		}
		observed[id] = state
	}
	for id, player := range r.players {
		state, exists := observed[id]
		if !exists {
			state = replay.Frame{Time: seconds, Tick: tick, Team: player.Team}
			if frames := r.tracks[id]; len(frames) > 0 {
				previous := frames[len(frames)-1]
				state.Position = previous.Position
				state.Yaw = previous.Yaw
				state.Team = previous.Team
			}
		}
		r.tracks[id] = append(r.tracks[id], state)
	}
	return nil
}

func (r *recorder) playerID(p *common.Player) string {
	if id, ok := r.localIDs[p]; ok {
		return id
	}
	if p.SteamID64 != 0 {
		id := "steam:" + strconv.FormatUint(p.SteamID64, 10)
		r.localIDs[p] = id
		return id
	}
	id := fmt.Sprintf("local:%04d", len(r.localIDs)+1)
	r.localIDs[p] = id
	return id
}

func teamName(team common.Team) string {
	if team == common.TeamTerrorists {
		return "T"
	}
	if team == common.TeamCounterTerrorists {
		return "CT"
	}
	return ""
}
