//go:build e2e && e2eprovision

// Provisioning entry points, EXCLUDED from the plain `-tags=e2e` run (the
// e2eprovision tag is required): the assertion suite must never re-install
// charts as a side effect of `go test -tags=e2e ./...`. golden-path.sh
// (phase 2 of the shell→Go migration) invokes these explicitly with
// `-tags "e2e e2eprovision"` between its own kind/KC-seeding stages.
package stack_test

import (
	"testing"

	"7k-inari/inari-release-bundle/scripts/e2e/stack/suite"
)

// TestProvisionStack installs every helm chart of the golden path against
// an existing kind cluster (dependency-layered, concurrent).
func TestProvisionStack(t *testing.T) {
	suite.ProvisionStack(t)
}

// TestProvisionAgent installs the inari-agent chart + ESO wiring from the
// agent-input JSON the registration stage wrote ($E2E_AGENT_INPUT_PATH).
func TestProvisionAgent(t *testing.T) {
	suite.ProvisionAgent(t)
}
