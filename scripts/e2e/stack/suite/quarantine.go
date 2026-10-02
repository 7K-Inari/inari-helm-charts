// Quarantine mechanism for the Go stack suite — the direct analog of
// inari-server's `flaky` build-tag convention and the Playwright
// `@quarantine` tag: a quarantined test NEVER runs in the release gate and
// runs only in the nightly, which passes `-args -include-quarantined`.
//
// Implemented as a runtime flag (not a build tag) so the single existing
// `e2e` tag keeps selecting the suite; the flag only decides whether
// quarantined bodies execute. This file intentionally carries NO e2e build
// tag so the helper is unit-testable without a cluster.
package suite

import (
	"testing"

	"7k-inari/inari-release-bundle/scripts/e2e/stack/internal/quarflag"
)

// The flag itself lives in internal/quarflag (registered on go test's flag
// set): `-args -include-quarantined` is passed to EVERY test binary matched
// by `go test ./...`, so binaries that neither import suite nor define the
// flag (internal/kc, internal/poll) would die with "flag provided but not
// defined". quarflag's tiny footprint lets those packages blank-import it.

// Quarantined marks a flaky test/subtest: it skips unless the suite runs
// with -include-quarantined. Call it as the first statement of the
// quarantined body, with a reason that names the tracked issue:
//
//	suite.Quarantined(t, "flake: agent reconnect race, issue #123")
//
// De-quarantine by removing the call once the test has been stable in the
// nightly for ~2 weeks (same policy as the Playwright `@quarantine` tag).
func Quarantined(t testing.TB, reason string) {
	t.Helper()
	if !*quarflag.IncludeQuarantined {
		t.Skipf("quarantined: %s (pass -args -include-quarantined to run)", reason)
	}
}
