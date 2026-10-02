//go:build e2e

// Package suite holds the golden-path assertion phases. The stack is
// provisioned by scripts/e2e/golden-path.sh (phase 1 of the shell→Go
// migration); this package only asserts against the deployed stack.
package suite

import (
	"encoding/json"
	"fmt"
	"os"
	"testing"

	"7k-inari/inari-release-bundle/scripts/e2e/stack/internal/fga"
	"7k-inari/inari-release-bundle/scripts/e2e/stack/internal/inariapi"
	"7k-inari/inari-release-bundle/scripts/e2e/stack/internal/kc"
)

// GAP markers ported from golden-path.sh: each names an imperative
// workaround that maps to a tracked upstream fix. The constants exist so the
// upstream-fix tracking survives the port; remove a marker when its fix
// lands upstream.
const (
	// GapKCPlatformGroup: dev-admin is joined to the platform-admins
	// Keycloak group imperatively (by golden-path.sh) because org_creator
	// tuple sync is driven by platform group membership; the upstream fix
	// automates this seeding in the realm/platform chart.
	GapKCPlatformGroup = "kc-platform-group"
	// GapKCAudienceMapper: the audience-inari-server protocol mapper is
	// ensured imperatively because the server validates aud=inari-server
	// and realm import does not yet create it.
	GapKCAudienceMapper = "aud-mapper"
	// GapRBACE2EArgoCD: the suite applies the materialized baseline/rbac/
	// bundle from the host, standing in for the tenant-local ArgoCD that
	// the e2e platform stack does not install.
	GapRBACE2EArgoCD = "rbac-e2e-argocd"
)

// Handoff is the contract written by golden-path.sh after provisioning; the
// Go suite consumes it read-only. Field renames must land in both places.
type Handoff struct {
	Namespace     string `json:"namespace"`
	Toolbox       string `json:"toolbox"`
	Tenant        string `json:"tenant"`
	KCUID         string `json:"kc_uid"`     // dev-admin Keycloak user id
	OrgKCID       string `json:"org_kc_id"`  // tenant org's Keycloak organization id
	ClusterID     string `json:"cluster_id"` // registered e2e-self cluster id
	OrgID         string `json:"org_id"`     // cluster orgId (agent tenant id)
	GitHostDir    string `json:"git_host_dir"`
	AgentChartDir string `json:"agent_chart_dir"`
}

// Env carries the handoff plus ready clients and the HA selection.
type Env struct {
	Handoff
	HA            bool
	MigrationsDir string // SERVER_MIGRATIONS_DIR (HA(c) migration count)
	KC            *kc.Client
	API           *inariapi.Client
	FGA           *fga.Client
}

// Load reads E2E_HANDOFF_PATH (written by golden-path.sh) plus the E2E_HA
// and SERVER_MIGRATIONS_DIR env knobs, and builds the clients.
func Load(t *testing.T) *Env {
	t.Helper()
	path := os.Getenv("E2E_HANDOFF_PATH")
	if path == "" {
		t.Fatal("E2E_HANDOFF_PATH not set: run scripts/e2e/golden-path.sh first " +
			"(it provisions the stack and writes the handoff file)")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading handoff %s: %v", path, err)
	}
	var h Handoff
	if err := json.Unmarshal(raw, &h); err != nil {
		t.Fatalf("parsing handoff %s: %v", path, err)
	}
	for field, v := range map[string]string{
		"namespace": h.Namespace, "toolbox": h.Toolbox, "tenant": h.Tenant,
		"kc_uid": h.KCUID, "org_kc_id": h.OrgKCID, "cluster_id": h.ClusterID,
		"org_id": h.OrgID, "git_host_dir": h.GitHostDir, "agent_chart_dir": h.AgentChartDir,
	} {
		if v == "" {
			t.Fatalf("handoff %s: field %q is empty (stale handoff? re-run golden-path.sh)", path, field)
		}
	}
	e := &Env{
		Handoff:       h,
		HA:            os.Getenv("E2E_HA") == "1",
		MigrationsDir: os.Getenv("SERVER_MIGRATIONS_DIR"),
	}
	e.KC = &kc.Client{NS: h.Namespace, Toolbox: h.Toolbox}
	e.FGA = &fga.Client{NS: h.Namespace, Toolbox: h.Toolbox}
	e.API = &inariapi.Client{
		NS: h.Namespace, Toolbox: h.Toolbox, Tenant: h.Tenant,
		Token: e.KC.UserToken,
	}
	if e.HA && e.MigrationsDir == "" {
		t.Fatal("E2E_HA=1 requires SERVER_MIGRATIONS_DIR pointing at inari-server's internal/db/migrations")
	}
	fmt.Printf("[e2e] handoff loaded: ns=%s tenant=%s cluster=%s ha=%v\n",
		h.Namespace, h.Tenant, h.ClusterID, e.HA)
	return e
}
