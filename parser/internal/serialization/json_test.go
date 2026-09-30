package serialization

import (
	"bytes"
	"csdemowatch/parser/internal/replay"
	"strings"
	"testing"
)

func TestEmptyV2Arrays(t *testing.T) {
	var b bytes.Buffer
	if err := WriteJSON(&b, &replay.Replay{Version: 2}); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(b.String(), `"events":[]`) || !strings.Contains(b.String(), `"projectiles":[]`) {
		t.Fatal(b.String())
	}
}
