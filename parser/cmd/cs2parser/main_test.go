package main

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestCLIErrorCodes(t *testing.T) {
	var out, stderr bytes.Buffer
	if run(nil, &out, &stderr) != 2 {
		t.Fatal("missing args must return usage status")
	}
	if run([]string{"does-not-exist.dem", "output.json"}, &out, &stderr) == 0 {
		t.Fatal("missing input must fail")
	}
	dir := t.TempDir()
	path := filepath.Join(dir, "bad.dem")
	output := filepath.Join(dir, "out.json")
	if err := os.WriteFile(path, []byte("not a cs2 demo"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(output, []byte("existing-output"), 0600); err != nil {
		t.Fatal(err)
	}
	if run([]string{path, output}, &out, &stderr) == 0 {
		t.Fatal("bad input must fail")
	}
	contents, _ := os.ReadFile(output)
	if string(contents) != "existing-output" {
		t.Fatal("failed parse changed existing output")
	}
	if run([]string{path, path}, &out, &stderr) == 0 {
		t.Fatal("same input/output must fail")
	}
	if stderr.Len() == 0 {
		t.Fatal("failure must provide diagnostics")
	}
}
