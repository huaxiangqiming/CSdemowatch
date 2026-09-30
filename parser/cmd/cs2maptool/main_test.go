package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestValidateInstallation(t *testing.T) {
	root := t.TempDir()
	if validate(root) != "" {
		t.Fatal("accepted empty directory")
	}
	game := filepath.Join(root, "game", "csgo")
	os.MkdirAll(filepath.Join(game, "maps"), 0700)
	for _, name := range []string{"gameinfo.gi", "pak01_dir.vpk", "maps/de_example.vpk"} {
		os.WriteFile(filepath.Join(game, name), []byte("fixture"), 0600)
	}
	if validate(root) != game || validate(game) != game || validate(filepath.Join(root, "game")) != game {
		t.Fatal("installation roots not normalized")
	}
	os.Remove(filepath.Join(game, "pak01_dir.vpk"))
	if validate(root) != "" {
		t.Fatal("accepted installation missing core VPK")
	}
}
func TestPreparationRejectsInvalidNamesBeforeIO(t *testing.T) {
	for _, name := range []string{"../de_mirage", "de_mirage/../../x", "de_map;whoami", "C:/map"} {
		if prepare(name, "invalid") == nil {
			t.Fatal("accepted", name)
		}
	}
}
