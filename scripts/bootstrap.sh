#!/usr/bin/env bash
# Day-0 bootstrap: create a kind cluster and install the Inari platform
# umbrella chart end-to-end (plan §12.1/1 — Inari must never require Inari).
#
# Idempotent: reuses an existing kind cluster, upgrades an existing release.
#
# Usage: scripts/bootstrap.sh [--skip-kind]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/verify.sh
source "$SCRIPT_DIR/lib/verify.sh"

SKIP_KIND=false
[[ "${1:-}" == "--skip-kind" ]] && SKIP_KIND=true

require helm kubectl
$SKIP_KIND || require kind

if ! $SKIP_KIND; then
  if kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER_NAME"; then
    log "kind cluster '$KIND_CLUSTER_NAME' already exists, reusing"
  else
    log "creating kind cluster '$KIND_CLUSTER_NAME'"
    kind create cluster --name "$KIND_CLUSTER_NAME"
  fi
  kubectl config use-context "kind-${KIND_CLUSTER_NAME}" >/dev/null
fi

log "building chart dependencies"
# update (not build): works with the unmanaged repositories in Chart.yaml and
# stays idempotent across re-runs (a stale Chart.lock makes build require
# locally-configured helm repos)
helm dependency update "$CHART_DIR"

log "installing/upgrading release '$RELEASE' in namespace '$NAMESPACE'"
helm upgrade --install "$RELEASE" "$CHART_DIR" \
  --namespace "$NAMESPACE" --create-namespace \
  --values "$CHART_DIR/values-dev.yaml" \
  --wait --timeout 10m

verify_stack

log "bootstrap complete."
log "  Keycloak admin console: kubectl -n $NAMESPACE port-forward svc/keycloak 8080:80"
log "  (admin credentials from secret 'inari-db', key 'keycloak-admin-password')"
