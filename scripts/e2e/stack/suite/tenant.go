//go:build e2e

package suite

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"7k-inari/inari-release-bundle/scripts/e2e/stack/internal/kube"
	"7k-inari/inari-release-bundle/scripts/e2e/stack/internal/poll"
)

// Tenant asserts the tenant phase of the golden path (the script created the
// tenant during provisioning; these are the observations that prove the
// wiring): platform group sync → org_creator tuple, /me/permissions,
// creator auto-membership via outbox, outbox drain through the NATS relay,
// and the cache-layer metrics series.
func Tenant(t *testing.T, e *Env) {
	// HA(c) companion: the replicas' FGA store bootstrap must have converged
	// on exactly ONE store named "inari" — a duplicate means the bootstrap
	// lease (authz-fga-bootstrap) failed and each replica pinned its own
	// store (split-brain authz).
	if e.HA {
		n, err := e.FGA.CountStores("inari")
		require.NoError(t, err)
		require.Equal(t, 1, n,
			"HA(c): OpenFGA stores named 'inari' (store bootstrap race — replicas would split-brain)")
	}
	storeID, err := e.FGA.StoreID()
	require.NoError(t, err, "resolving the OpenFGA store")

	// The org_creator tuple lands via GAP(kc-platform-group) membership →
	// platform group sync reconciler → outbox → tuple writer. Poll, never
	// assert immediately (no k8s condition exists for it).
	poll.Eventually(t, 90*time.Second, 5*time.Second, func() (bool, error) {
		return e.FGA.Check(storeID, "user:"+e.KCUID, "org_creator", "platform:inari")
	}, "org_creator tuple for dev-admin on platform:inari")

	perms, err := e.API.MePermissions()
	require.NoError(t, err)
	assert.True(t, perms.CanCreateOrganizations,
		"/me/permissions must reflect the org_creator tuple")

	// CreateTenant added the creator to the Keycloak org + platform-team
	// group; the outbox dispatcher seeds team membership and team→org role
	// tuples asynchronously.
	poll.Eventually(t, 90*time.Second, 5*time.Second, func() (bool, error) {
		return e.FGA.Check(storeID, "user:"+e.KCUID, "tenant_admin", "organization:"+e.OrgKCID)
	}, "creator tenant_admin tuple on organization:"+e.OrgKCID)

	// Tenant creation emitted several events; the relay marks rows published
	// only after the JetStream PubAck, so a drained backlog proves
	// relay → stream → consumer delivery end-to-end (ADR-0014).
	poll.Eventually(t, 120*time.Second, 5*time.Second, func() (bool, error) {
		n, err := kube.PSQLInari(e.Namespace, "SELECT count(*) FROM outbox WHERE published_at IS NULL")
		if err != nil {
			return false, err
		}
		return n == "0", nil
	}, "outbox drained through the NATS relay")

	// /metrics must expose the cache-layer series. Tenant creation already
	// drove org lookups + FGA checks through the caches, so the series exist.
	// HA: the Service hits a RANDOM replica and OTel counters export only
	// after a pod's first observation — scrape every server pod IP directly
	// and require the series on at least one.
	var body string
	if e.HA {
		ips, err := kube.Kubectl("-n", e.Namespace, "get", "pods",
			"-l", "app.kubernetes.io/name=inari-server",
			"-o", "jsonpath={.items[*].status.podIP}")
		require.NoError(t, err)
		for _, ip := range strings.Fields(ips) {
			b, err := e.API.Metrics(ip + ":8080")
			if err == nil {
				body += b
			}
		}
	} else {
		body, err = e.API.Metrics("inari-server:8080")
		require.NoError(t, err)
	}
	assert.Contains(t, body, "inari_cache_operations_total")
	assert.Contains(t, body, "inari_fga_check_duration_seconds")
}
