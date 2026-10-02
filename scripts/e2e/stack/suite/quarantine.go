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
	"flag"
	"testing"
)

// includeQuarantined is registered on go test's flag set; the gate simply
// omits it (default false → skip). Nightly:
//
//	go test -tags=e2e ... -args -include-quarantined
var includeQuarantined = flag.Bool("include-quarantined", false,
	"run tests quarantined for flakiness (nightly only; the release gate never sets this)")

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
	if !*includeQuarantined {
		t.Skipf("quarantined: %s (pass -args -include-quarantined to run)", reason)
	}
}
