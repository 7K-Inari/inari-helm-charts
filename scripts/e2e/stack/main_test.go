//go:build e2e

// Golden-path e2e (CI gate): assertions against the stack provisioned by
// scripts/e2e/golden-path.sh — tenant → cluster registration → agent
// connect → capabilities streaming → RBAC materialization → policy
// evaluate → HA disruption (E2E_HA=1).
//
// Phase 1 of the shell→Go migration (parent design §3): the script owns
// provisioning; this suite owns assertions. Run:
//
//	E2E_HANDOFF_PATH=/tmp/inari-e2e-handoff.json go test -tags=e2e ./scripts/e2e/stack/...
package stack_test

import (
	"testing"

	"7k-inari/inari-release-bundle/scripts/e2e/stack/suite"
)

func TestGoldenPath(t *testing.T) {
	suite.Run(t)
}
