package suite

import (
	"fmt"
	"strings"
	"testing"

	"7k-inari/inari-release-bundle/scripts/e2e/stack/internal/quarflag"
)

// fakeTB records Skipf calls so Quarantined's behavior can be asserted
// without skipping the real test.
type fakeTB struct {
	testing.TB
	skipped  bool
	skipText string
}

func (f *fakeTB) Helper() {}

func (f *fakeTB) Skipf(format string, args ...any) {
	f.skipped = true
	f.skipText = fmt.Sprintf(format, args...)
}

func TestQuarantined(t *testing.T) {
	t.Run("skips by default", func(t *testing.T) {
		*quarflag.IncludeQuarantined = false
		f := &fakeTB{}
		Quarantined(f, "flake: agent reconnect race, issue #123")
		if !f.skipped {
			t.Fatal("expected the test to be skipped when -include-quarantined is unset")
		}
		if !strings.Contains(f.skipText, "flake: agent reconnect race, issue #123") {
			t.Fatalf("skip message must carry the reason, got %q", f.skipText)
		}
	})

	t.Run("runs with -include-quarantined", func(t *testing.T) {
		*quarflag.IncludeQuarantined = true
		t.Cleanup(func() { *quarflag.IncludeQuarantined = false })
		f := &fakeTB{}
		Quarantined(f, "any reason")
		if f.skipped {
			t.Fatalf("expected the test to run when -include-quarantined is set, got skip %q", f.skipText)
		}
	})
}
