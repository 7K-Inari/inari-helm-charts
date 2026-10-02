//go:build e2e

package suite

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// denyLatestRego is the deny-latest-image policy (target=request, Rego) from
// the script's policy matrix (issue #77): deny :latest and untagged images,
// allow pinned tags and digests.
const denyLatestRego = `package inari.policy

deny contains {"rule": "deny-latest-image", "reason": "image uses the :latest tag", "remediation": "pin an immutable tag or digest"} if {
	endswith(input.spec.image, ":latest")
}

deny contains {"rule": "deny-latest-image", "reason": "image has no tag or digest", "remediation": "pin an immutable tag or digest"} if {
	parts := split(input.spec.image, "/")
	last := parts[count(parts) - 1]
	not contains(last, ":")
	not contains(last, "@")
}
`

// PolicyEvaluate asserts the policy evaluate matrix: :latest/untagged denied
// with the deny-latest-image rule, pinned tag/digest allowed, and a disabled
// policy must not gate the request (negative control).
func PolicyEvaluate(t *testing.T, e *Env) {
	policyID, err := e.API.CreatePolicy("deny-latest-image", "request", "rego", denyLatestRego)
	require.NoError(t, err, "policy creation failed")
	require.NotEmpty(t, policyID)

	deny := func(image string) {
		t.Helper()
		ev, err := e.API.Evaluate(e.ClusterID, image)
		require.NoError(t, err, "evaluate %s", image)
		assert.False(t, ev.Decision.Allow, "%s must be denied", image)
	}
	allow := func(image string) {
		t.Helper()
		ev, err := e.API.Evaluate(e.ClusterID, image)
		require.NoError(t, err, "evaluate %s", image)
		assert.True(t, ev.Decision.Allow, "%s must be allowed (violations: %+v)", image, ev.Decision.Violations)
		assert.Empty(t, ev.Decision.Violations)
	}

	ev, err := e.API.Evaluate(e.ClusterID, "ghcr.io/acme/app:latest")
	require.NoError(t, err)
	assert.False(t, ev.Decision.Allow, ":latest image must be denied")
	rules := []string{}
	for _, v := range ev.Decision.Violations {
		rules = append(rules, v.Rule)
	}
	assert.Contains(t, rules, "deny-latest-image",
		":latest must carry a deny-latest-image violation")

	deny("ghcr.io/acme/app")
	deny("registry:5000/acme/app") // untagged with a registry port
	allow("ghcr.io/acme/app:1.4.2")
	allow("ghcr.io/acme/app@sha256:" + strings.Repeat("a", 64))

	// Negative control: a disabled policy must not deny.
	require.NoError(t, e.API.SetPolicyEnabled(policyID, denyLatestRego, false))
	ev, err = e.API.Evaluate(e.ClusterID, "ghcr.io/acme/app:latest")
	require.NoError(t, err)
	assert.True(t, ev.Decision.Allow, "disabled policy must not deny")
	require.NoError(t, e.API.SetPolicyEnabled(policyID, denyLatestRego, true))
}
