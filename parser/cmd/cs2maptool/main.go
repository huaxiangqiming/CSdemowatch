// Windows local asset preparation. Source game files are opened read-only.
package main

import (
	"crypto/sha256"
	"csdemowatch/parser/internal/tactical"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

var progressPath string

func emit(v any) {
	b, _ := json.Marshal(v)
	fmt.Println(string(b))
	if progressPath != "" {
		temp := progressPath + ".tmp"
		if os.WriteFile(temp, b, 0600) == nil {
			os.Rename(temp, progressPath)
		}
	}
}
func exists(p string) bool { s, e := os.Stat(p); return e == nil && !s.IsDir() }
func validate(p string) string {
	for _, base := range []string{p, filepath.Join(p, "game", "csgo"), filepath.Join(p, "csgo")} {
		if exists(filepath.Join(base, "pak01_dir.vpk")) && exists(filepath.Join(base, "gameinfo.gi")) {
			matches, _ := filepath.Glob(filepath.Join(base, "maps", "*.vpk"))
			if info, err := os.Stat(filepath.Join(base, "maps")); len(matches) > 0 || (err == nil && info.IsDir()) {
				abs, _ := filepath.Abs(base)
				return abs
			}
		}
	}
	return ""
}
func discover(manual string) map[string]any {
	if manual != "" {
		path := validate(manual)
		return map[string]any{"valid": path != "", "path": path, "source": "Manual", "message": "Expected CS2 game/csgo with gameinfo.gi, pak01_dir.vpk and map VPKs"}
	}
	candidates := []string{}
	cmd := exec.Command("reg.exe", "query", `HKCU\Software\Valve\Steam`, "/v", "SteamPath")
	hide(cmd)
	out, _ := cmd.Output()
	for _, line := range strings.Split(string(out), "\n") {
		if i := strings.Index(line, "REG_SZ"); i >= 0 {
			candidates = append(candidates, strings.TrimSpace(line[i+6:]))
		}
	}
	for _, key := range []string{"ProgramFiles(x86)", "ProgramFiles"} {
		if p := os.Getenv(key); p != "" {
			candidates = append(candidates, filepath.Join(p, "Steam"))
		}
	}
	libs := append([]string{}, candidates...)
	pattern := regexp.MustCompile(`"path"\s+"([^"]+)"`)
	for _, steam := range candidates {
		b, _ := os.ReadFile(filepath.Join(steam, "steamapps", "libraryfolders.vdf"))
		for _, m := range pattern.FindAllStringSubmatch(string(b), -1) {
			libs = append(libs, strings.ReplaceAll(m[1], `\\`, `\`))
		}
	}
	for _, lib := range libs {
		p := validate(filepath.Join(lib, "steamapps", "common", "Counter-Strike Global Offensive"))
		if p != "" {
			return map[string]any{"valid": true, "path": p, "source": "Detected", "message": "Valid CS2 installation"}
		}
	}
	return map[string]any{"valid": false, "path": "", "source": "Not detected", "message": "Browse to your CS2 installation in Settings"}
}
func hash(path string) (string, error) {
	f, e := os.Open(path)
	if e != nil {
		return "", e
	}
	defer f.Close()
	h := sha256.New()
	_, e = io.Copy(h, f)
	return hex.EncodeToString(h.Sum(nil)), e
}
func writeJSON(path string, v any) error {
	b, e := json.MarshalIndent(v, "", "  ")
	if e != nil {
		return e
	}
	return os.WriteFile(path, b, 0600)
}
func prepare(name, installation string) error {
	if !regexp.MustCompile(`^de_[a-z0-9_]+$`).MatchString(name) {
		return fmt.Errorf("unsupported map resource name")
	}
	game := validate(installation)
	if game == "" {
		return fmt.Errorf("invalid CS2 installation")
	}
	root := filepath.Join(os.Getenv("LOCALAPPDATA"), "CS2TacticalReplay", "maps")
	if override := os.Getenv("CS2_MAP_CACHE_ROOT"); override != "" {
		root = override
	}
	if !filepath.IsAbs(root) {
		return fmt.Errorf("LOCALAPPDATA unavailable")
	}
	if e := os.MkdirAll(root, 0700); e != nil {
		return e
	}
	resolved, e := filepath.EvalSymlinks(root)
	if e != nil {
		return e
	}
	if !strings.EqualFold(filepath.Clean(root), resolved) {
		return fmt.Errorf("map cache must not be redirected by junctions")
	}
	exe, _ := os.Executable()
	cli := filepath.Join(filepath.Dir(exe), "map-tools", "Source2Viewer-CLI.exe")
	if !exists(cli) {
		return fmt.Errorf("bundled map converter missing: %s", cli)
	}
	progressPath = filepath.Join(root, ".status-"+name+".json")
	emit(map[string]string{"stage": "Finding Map Resource", "map": name})
	resolvedSource := resolveMap(name, game, cli)
	emit(map[string]any{"stage": "Map source resolved", "source": resolvedSource})
	if !resolvedSource.CanPrepare {
		return capabilityError(resolvedSource.ErrorCode, fmt.Errorf("%s", resolvedSource.Reason))
	}
	vpk := resolvedSource.Source
	if resolvedSource.Layout == "loose" {
		vpk = filepath.Join(game, filepath.FromSlash(resolvedSource.Physics))
	}
	started := time.Now()
	stage, e := os.MkdirTemp(root, ".prepare-"+name+"-")
	if e != nil {
		return e
	}
	defer os.RemoveAll(stage) // generated child of verified cache root
	emit(map[string]string{"stage": "Extracting collision geometry", "map": name})
	cmd := resourceCommand(cli, resolvedSource, resolvedSource.Physics, filepath.Join(stage, "collision.glb"), true)
	output, e := cmd.CombinedOutput()
	if e != nil {
		return capabilityError("MAP_PHYSICS_UNSUPPORTED", fmt.Errorf("Source2Viewer failed: %w\n%s", e, output))
	}
	emit(map[string]string{"stage": "Collision extraction complete", "map": name})
	emit(map[string]string{"stage": "Building gray tactical geometry", "map": name})
	// Official VRF navigation export provides authored walkable levels. If absent
	// or unsupported, classification must preserve uncertain horizontal surfaces.
	navigation := ""
	navFile := filepath.Join(stage, "source.nav")
	navCmd := resourceCommand(cli, resolvedSource, resolvedSource.Navigation, navFile, false)
	hide(navCmd)
	if _, navErr := func() ([]byte, error) {
		if resolvedSource.Navigation == "" {
			return nil, fmt.Errorf("navigation absent")
		}
		return navCmd.CombinedOutput()
	}(); navErr == nil && exists(navFile) {
		navGLB := filepath.Join(stage, "navigation.glb")
		navCmd = exec.Command(cli, "-i", navFile, "-o", navGLB, "-d", "--gltf_export_format", "glb")
		hide(navCmd)
		if _, navErr = navCmd.CombinedOutput(); navErr == nil && exists(navGLB) {
			navigation = navGLB
		}
	}
	if navigation == "" {
		emit(map[string]string{"warning": "Navigation unavailable; uncertain roofs retained"})
	}
	emit(map[string]string{"stage": "Classifying Geometry", "map": name})
	metrics, e := tactical.ConvertWithNavigation(filepath.Join(stage, "collision_physics.glb"), filepath.Join(stage, "map.glb"), navigation)
	if e != nil {
		return e
	}
	emit(map[string]string{"stage": "Geometry conversion complete", "map": name})
	sourceHash, e := hash(vpk)
	if e != nil {
		return e
	}
	meshHash, e := hash(filepath.Join(stage, "map.glb"))
	if e != nil {
		return e
	}
	bounds := map[string]any{"min": metrics.Min, "max": metrics.Max, "coordinate_system": "normalized_source_y_up"}
	definition := map[string]any{"map": name, "model_path": "map.glb", "scale": 0.01, "rotation": 0, "offset": []int{0, 0, 0}, "source_identifier": sourceHash, "cache_version": 1, "bounds": bounds, "default_camera": map[string]int{"yaw": 38, "pitch": 45}, "triangles": metrics.Triangles, "glb_bytes": metrics.Bytes, "preparation_ms": time.Since(started).Milliseconds(), "converter_version": converterVersion, "classifier_version": tactical.ClassifierVersion, "geometry_stats": metrics.Geometry, "source_vpk": vpk}
	manifest := map[string]any{"cache_version": 1, "map": name, "source_identifier": sourceHash, "mesh_sha256": meshHash, "prepared_unix": time.Now().Unix(), "converter_version": converterVersion, "classifier_version": tactical.ClassifierVersion}
	definition["source_resource"] = resolvedSource
	definition["source_files"] = sourceFiles(resolvedSource)
	manifest["source_files"] = sourceFiles(resolvedSource)
	emit(map[string]string{"stage": "Writing Cache", "map": name})
	if e = writeJSON(filepath.Join(stage, "map.json"), definition); e != nil {
		return e
	}
	if e = writeJSON(filepath.Join(stage, "cache.json"), manifest); e != nil {
		return e
	}
	destination := filepath.Join(root, name)
	if info, e := os.Lstat(destination); e == nil {
		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("invalid map cache target")
		}
		canonical, e := filepath.EvalSymlinks(destination)
		if e != nil || !strings.EqualFold(canonical, destination) {
			return fmt.Errorf("redirected map cache target")
		}
	}
	if e = os.MkdirAll(destination, 0700); e != nil {
		return e
	}
	// Manifest is committed last. An interrupted update is rejected by checksum validation.
	files := []string{"map.glb", "map.glb.classification.json"}
	if exists(filepath.Join(stage, "map.glb.roofs.glb")) {
		files = append(files, "map.glb.roofs.glb")
	}
	files = append(files, "map.json", "cache.json")
	for _, file := range files {
		if e = os.Rename(filepath.Join(stage, file), filepath.Join(destination, file)); e != nil {
			return e
		}
	}
	emit(map[string]any{"ok": true, "map": name, "path": destination, "metrics": metrics, "preparation_ms": time.Since(started).Milliseconds()})
	return nil
}
func main() {
	args := os.Args[1:]
	if len(args) > 0 && args[0] == "discover" {
		p := ""
		if len(args) > 1 {
			p = args[1]
		}
		emit(discover(p))
		return
	}
	if len(args) == 3 && args[0] == "probe-map" {
		if !regexp.MustCompile(`^de_[a-z0-9_]+$`).MatchString(args[1]) {
			emit(MapSource{Map: args[1], ErrorCode: "MAP_SOURCE_NOT_FOUND", Reason: "Invalid map name"})
			os.Exit(1)
		}
		game := validate(args[2])
		if game == "" {
			emit(MapSource{Map: args[1], ErrorCode: "MAP_SOURCE_NOT_FOUND", Reason: "CS2 installation not found"})
			os.Exit(1)
		}
		exe, _ := os.Executable()
		result := resolveMap(args[1], game, filepath.Join(filepath.Dir(exe), "map-tools", "Source2Viewer-CLI.exe"))
		emit(result)
		if !result.CanPrepare {
			os.Exit(1)
		}
		return
	}
	if len(args) == 3 && args[0] == "prepare" {
		if e := prepare(args[1], args[2]); e != nil {
			code := "MAP_CONVERSION_FAILED"
			for _, c := range []string{"MAP_SOURCE_NOT_FOUND", "MAP_PHYSICS_UNSUPPORTED"} {
				if strings.HasPrefix(e.Error(), c) {
					code = c
				}
			}
			emit(map[string]any{"ok": false, "error_code": code, "error": e.Error()})
			os.Exit(1)
		}
		return
	}
	fmt.Fprintln(os.Stderr, "Usage: cs2maptool discover [CS2 directory] | probe-map de_map CS2-directory | prepare de_map CS2-directory")
	os.Exit(2)
}
