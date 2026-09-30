package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLooseLayoutAndUnsupportedPhysics(t *testing.T) {
	game := t.TempDir()
	folder := filepath.Join(game, "maps", "de_arbitrary", "nested")
	if e := os.MkdirAll(folder, 0700); e != nil {
		t.Fatal(e)
	}
	if e := os.WriteFile(filepath.Join(folder, "arena.vwrld_c"), []byte("fixture"), 0600); e != nil {
		t.Fatal(e)
	}
	r := resolveMap("de_arbitrary", game, "absent-tool")
	if !r.Found || r.CanPrepare || r.ErrorCode != "MAP_PHYSICS_UNSUPPORTED" {
		t.Fatalf("wrong unsupported result: %+v", r)
	}
	if e := os.WriteFile(filepath.Join(folder, "collision.vmdl_c"), []byte("fixture"), 0600); e != nil {
		t.Fatal(e)
	}
	r = resolveMap("de_arbitrary", game, "absent-tool")
	if !r.CanPrepare || r.Layout != "loose" {
		t.Fatalf("loose model unresolved: %+v", r)
	}
	if len(sourceFiles(r)) != 1 {
		t.Fatal("loose source fingerprint missing")
	}
	r = resolveMap("de_missing", game, "absent-tool")
	if r.Found || r.ErrorCode != "MAP_SOURCE_NOT_FOUND" {
		t.Fatalf("wrong missing result: %+v", r)
	}
}

func TestGenericResourceLayouts(t *testing.T) {
	for _, name := range []string{"de_fixture_a", "de_fixture_b"} {
		w, p, n := resources(name, []string{"maps/" + name + "/nested/arena.vwrld_c", "maps/" + name + "/nested/collision.vmdl_c", "maps/" + name + ".nav", "maps/de_other/world_physics.vmdl_c"})
		if w == "" || p != "maps/"+name+"/nested/collision.vmdl_c" || n == "" {
			t.Fatalf("nested layout unresolved: %s %s %s", w, p, n)
		}
	}
	_, p, _ := resources("de_fixture", []string{"maps/de_fixture_extra/world_physics.vmdl_c"})
	if p != "" {
		t.Fatal("prefix collision accepted")
	}
	if !numberedVPK("pak01_001.vpk") || numberedVPK("pak01_dir.vpk") || numberedVPK("de_dust2.vpk") {
		t.Fatal("VPK container enumeration")
	}
}
