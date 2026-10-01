package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"csdemowatch/parser/internal/demo"
	"csdemowatch/parser/internal/replay"
	"csdemowatch/parser/internal/serialization"
)

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 1 && args[0] == "--version" {
		fmt.Fprintln(stdout, "0.9.0")
		return 0
	}
	v1 := len(args) > 0 && args[0] == "--v1"
	if v1 {
		args = args[1:]
	}
	if len(args) != 2 {
		fmt.Fprintln(stderr, "Usage: cs2parser [--v1] input.dem output.replay.json|output.replay (default: V2)")
		return 2
	}
	input, output := args[0], args[1]
	f, err := os.Open(input)
	if err != nil {
		fmt.Fprintf(stderr, "ERROR: open input: %v\n", err)
		return 1
	}
	defer f.Close()
	inInfo, err := f.Stat()
	if err != nil || !inInfo.Mode().IsRegular() {
		fmt.Fprintln(stderr, "ERROR: input must be a regular .dem file")
		return 1
	}
	if outInfo, e := os.Stat(output); e == nil && os.SameFile(inInfo, outInfo) {
		fmt.Fprintln(stderr, "ERROR: input and output must be different files")
		return 1
	}
	magic := make([]byte, 8)
	if _, err := io.ReadFull(f, magic); err != nil || string(magic) != "PBDEMS2\x00" {
		fmt.Fprintln(stderr, "ERROR: unsupported or corrupted demo: expected CS2 PBDEMS2 header")
		return 1
	}
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		fmt.Fprintf(stderr, "ERROR: seek input: %v\n", err)
		return 1
	}
	fmt.Fprintf(stdout, "Input demo: %s\nParsing with demoinfocs v5.2.0...\n", input)
	start := time.Now()
	parse := demo.ParseV2
	if v1 {
		parse = demo.Parse
	}
	r, err := parse(f, stderr)
	if err != nil {
		fmt.Fprintf(stderr, "ERROR: %v\n", err)
		return 1
	}
	if err := writeReplay(output, r); err != nil {
		fmt.Fprintf(stderr, "ERROR: output: %v\n", err)
		return 1
	}
	frames := 0
	for _, t := range r.Tracks {
		frames += len(t.Frames)
	}
	size, _ := os.Stat(output)
	counts := map[string]int{}
	for _, e := range r.Events {
		counts[e.Type]++
	}
	for _, kind := range []string{"player_hurt", "bomb_pickup", "bomb_drop", "bomb_plant", "bomb_defuse", "bomb_explode", "bomb_reset"} {
		fmt.Fprintf(stdout, "%s: %d\n", kind, counts[kind])
	}
	fmt.Fprintf(stdout, "Replay Version: %d\nEvents: %d\nProjectiles: %d\nSmoke: %d\nFire: %d\nHE: %d\nFlash: %d\nShot: %d\nKill: %d\n", r.Version, len(r.Events), len(r.Projectiles), counts["smoke"], counts["fire"], counts["he"], counts["flash"], counts["shot"], counts["kill"])
	fmt.Fprintf(stdout, "Map: %s\nPlayers: %d\nTracks: %d\nDuration: %.6f seconds\nTick Rate: %.6f\nSource Ticks: %d .. %d\nSample Rate: %.0f Hz\nFrame Count: %d\nOutput File: %s\nOutput Bytes: %d\nElapsed: %s\n", r.Metadata.Map, len(r.Players), len(r.Tracks), r.Metadata.Duration, r.Metadata.SourceTickRate, r.Metadata.SourceStartTick, r.Metadata.SourceEndTick, r.Metadata.SampleRate, frames, output, size.Size(), time.Since(start).Round(time.Millisecond))
	return 0
}

func writeReplay(path string, r *replay.Replay) error {
	if err := replay.Validate(r); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".replay-*.tmp")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	write := serialization.WriteJSON
	if strings.EqualFold(filepath.Ext(path), ".replay") {
		write = serialization.WriteBinary
	}
	if err := write(f, r); err != nil {
		f.Close()
		return err
	}
	if err := f.Sync(); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(f.Name(), path)
}
