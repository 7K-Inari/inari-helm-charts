//go:build e2e

package suite

import (
	"os"
	"testing"
)

// Run is the TestGoldenPath body: ordered subtests, each naming one
// assertion phase so CI output identifies the exact failing phase. The
// golden path is inherently sequential — later phases depend on earlier
// state — so a failed phase aborts the rest via require-style t.Fatal.
func Run(t *testing.T) {
	e := Load(t)
	if os.Getenv("E2E_PROVISION_ONLY") == "1" {
		t.Log("E2E_PROVISION_ONLY=1: stack provisioned; skipping assertions " +
			"(nightly bring-up parity with the old script)")
		return
	}
	e.requireHAMigrations(t)
	t.Run("tenant", func(t *testing.T) { Tenant(t, e) })
	t.Run("cluster", func(t *testing.T) { Cluster(t, e) })
	t.Run("rbac_materialization", func(t *testing.T) { RBACMaterialization(t, e) })
	t.Run("policy_evaluate", func(t *testing.T) { PolicyEvaluate(t, e) })
	t.Run("disruption", func(t *testing.T) { Disruption(t, e) })
}
