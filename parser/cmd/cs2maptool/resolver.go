package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

const converterVersion = "0.8.1"

type MapSource struct {
	Map        string `json:"map"`
	Found      bool   `json:"found"`
	CanPrepare bool   `json:"can_prepare"`
	Source     string `json:"source"`
	Layout     string `json:"layout"`
	World      string `json:"world_resource"`
	Physics    string `json:"physics_resource"`
	Navigation string `json:"navigation_resource"`
	Reason     string `json:"reason"`
	ErrorCode  string `json:"error_code,omitempty"`
}

func resources(name string, entries []string) (world, physics, nav string) {
	candidates := []string{}
	for _, entry := range entries {
		path := strings.ReplaceAll(strings.TrimSpace(entry), "\\", "/")
		if path == "maps/"+name+".nav" {
			nav = path
		}
		if !strings.HasPrefix(path, "maps/"+name+"/") {
			continue
		}
		if strings.HasSuffix(path, ".vwrld_c") {
			world = path
		}
		base := strings.ToLower(filepath.Base(path))
		if strings.HasSuffix(base, ".vmdl_c") && (strings.Contains(base, "physics") || strings.Contains(base, "collision")) {
			candidates = append(candidates, path)
		}
	}
	sort.Slice(candidates, func(i, j int) bool {
		a, b := candidates[i], candidates[j]
		if len(a) == len(b) {
			return a < b
		}
		return len(a) < len(b)
	})
	if len(candidates) > 0 {
		physics = candidates[0]
	}
	return
}

// Resolve inspects actual resources, never treats a guessed filename as proof.
// Map VPKs, shared pak*_dir containers and loose compiled map trees share one selector.
func resolveMap(name, game, cli string) MapSource {
	result := MapSource{Map: name, Reason: "Map resource not found", ErrorCode: "MAP_SOURCE_NOT_FOUND"}
	loose := []string{}
	filepath.WalkDir(filepath.Join(game, "maps", name), func(path string, d os.DirEntry, e error) error {
		if e == nil && !d.IsDir() {
			rel, _ := filepath.Rel(game, path)
			loose = append(loose, filepath.ToSlash(rel))
		}
		return nil
	})
	w, p, n := resources(name, loose)
	looseNav := "maps/" + name + ".nav"
	if exists(filepath.Join(game, filepath.FromSlash(looseNav))) {
		n = looseNav
	}
	if p != "" {
		return MapSource{Map: name, Found: true, CanPrepare: true, Source: game, Layout: "loose", World: w, Physics: p, Navigation: n, Reason: "Compiled loose collision model found"}
	}
	if w != "" {
		result = MapSource{Map: name, Found: true, Source: game, Layout: "loose", World: w, Navigation: n, Reason: "World found, supported collision model missing", ErrorCode: "MAP_PHYSICS_UNSUPPORTED"}
	}
	containers := []string{}
	filepath.WalkDir(filepath.Join(game, "maps"), func(path string, d os.DirEntry, e error) error {
		if e == nil && !d.IsDir() && strings.HasSuffix(strings.ToLower(path), ".vpk") && !numberedVPK(path) {
			containers = append(containers, path)
		}
		return nil
	})
	shared, _ := filepath.Glob(filepath.Join(game, "pak*_dir.vpk"))
	containers = append(containers, shared...)
	sort.SliceStable(containers, func(i, j int) bool {
		return filepath.Base(containers[i]) == name+".vpk" && filepath.Base(containers[j]) != name+".vpk"
	})
	for _, container := range containers {
		cmd := exec.Command(cli, "-i", container, "-l", "-f", "maps/"+name)
		hide(cmd)
		out, e := cmd.CombinedOutput()
		if e != nil {
			continue
		}
		entries := []string{}
		for _, line := range strings.Split(string(out), "\n") {
			fields := strings.Fields(line)
			if len(fields) > 0 {
				entries = append(entries, fields[0])
			}
		}
		w, p, n = resources(name, entries)
		if w != "" || p != "" {
			result = MapSource{Map: name, Found: true, Source: container, Layout: "vpk", World: w, Physics: p, Navigation: n, Reason: "World found, supported collision model missing", ErrorCode: "MAP_PHYSICS_UNSUPPORTED"}
		}
		if p != "" {
			result.CanPrepare = true
			result.ErrorCode = ""
			result.Reason = "Collision model resolved from container index"
			return result
		}
	}
	return result
}
func numberedVPK(path string) bool {
	base := strings.TrimSuffix(filepath.Base(path), ".vpk")
	i := strings.LastIndex(base, "_")
	if i < 0 {
		return false
	}
	suffix := base[i+1:]
	if len(suffix) != 3 {
		return false
	}
	for _, c := range suffix {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}
func sourceFiles(source MapSource) []map[string]any {
	paths := []string{source.Source}
	if source.Layout == "loose" {
		paths = []string{filepath.Join(source.Source, filepath.FromSlash(source.Physics))}
		if source.Navigation != "" {
			paths = append(paths, filepath.Join(source.Source, filepath.FromSlash(source.Navigation)))
		}
	}
	if strings.HasSuffix(source.Source, "_dir.vpk") {
		chunks, _ := filepath.Glob(strings.TrimSuffix(source.Source, "dir.vpk") + "*.vpk")
		paths = chunks
	}
	out := []map[string]any{}
	for _, path := range paths {
		if info, e := os.Stat(path); e == nil {
			out = append(out, map[string]any{"path": path, "size": info.Size(), "mtime": info.ModTime().Unix()})
		}
	}
	return out
}
func resourceCommand(cli string, source MapSource, resource, output string, model bool) *exec.Cmd {
	input := source.Source
	args := []string{}
	if source.Layout == "loose" {
		input = filepath.Join(source.Source, filepath.FromSlash(resource))
	} else {
		args = append(args, "-f", resource)
	}
	args = append(args, "-i", input, "-o", output)
	if model {
		args = append(args, "-d", "--gltf_export_format", "glb")
	}
	cmd := exec.Command(cli, args...)
	hide(cmd)
	return cmd
}
func capabilityError(code string, err error) error { return fmt.Errorf("%s: %w", code, err) }
