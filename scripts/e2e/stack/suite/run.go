//go:build e2e

package suite

import "testing"

// Run is the TestGoldenPath body: ordered subtests, each naming one
// assertion phase so CI output identifies the exact failing phase. The
// golden path is inherently sequential — later phases depend on earlier
// state — so a failed phase aborts the rest via require-style t.Fatal.
func Run(t *testing.T) {
	e := Load(t)
	t.Run("tenant", func(t *testing.T) { Tenant(t, e) })
	t.Run("cluster", func(t *testing.T) { Cluster(t, e) })
	t.Run("rbac_materialization", func(t *testing.T) { RBACMaterialization(t, e) })
	t.Run("policy_evaluate", func(t *testing.T) { PolicyEvaluate(t, e) })
	t.Run("disruption", func(t *testing.T) { Disruption(t, e) })
}
