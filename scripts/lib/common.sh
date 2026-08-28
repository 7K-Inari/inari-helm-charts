#!/usr/bin/env bash
# Shared helpers for Inari platform scripts.

set -euo pipefail

log()  { printf '\033[1;34m[inari]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[inari:warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[inari:error]\033[0m %s\n' "$*" >&2; exit 1; }

require() {
  local missing=()
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  ((${#missing[@]} == 0)) || die "missing required tools: ${missing[*]}"
}

# Defaults shared by all scripts; override via env.
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-inari-platform}"
NAMESPACE="${NAMESPACE:-inari}"
RELEASE="${RELEASE:-inari}"
CHART_DIR="${CHART_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../charts/platform-config" && pwd)}"
GITOPS_DIR="${GITOPS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../gitops" && pwd)}"
PG_CLUSTER="${PG_CLUSTER:-postgresql}"

kubectl_ns() { kubectl --namespace "$NAMESPACE" "$@"; }

# Wait helpers ---------------------------------------------------------------

wait_deployment() { # name timeout
  log "waiting for deployment/$1"
  kubectl_ns rollout status "deployment/$1" --timeout="${2:-300s}"
}

wait_statefulset() {
  log "waiting for statefulset/$1"
  kubectl_ns rollout status "statefulset/$1" --timeout="${2:-300s}"
}

wait_cnpg_cluster() { # cluster timeout
  log "waiting for CNPG cluster $1"
  local deadline=$((SECONDS + ${2:-600}))
  while (( SECONDS < deadline )); do
    local phase
    phase=$(kubectl_ns get cluster.postgresql.cnpg.io "$1" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$phase" == "Cluster in healthy state" ]]; then
      log "CNPG cluster $1 is healthy"
      return 0
    fi
    sleep 5
  done
  die "CNPG cluster $1 did not become healthy in time (last phase: ${phase:-unknown})"
}

# Primary pod of a CNPG cluster.
pg_primary_pod() {
  kubectl_ns get pod -l "cnpg.io/cluster=${PG_CLUSTER},cnpg.io/instanceRole=primary" \
    -o jsonpath='{.items[0].metadata.name}'
}

pg_exec() { # args... — run psql on the CNPG primary as the postgres user
  local pod
  pod=$(pg_primary_pod)
  [[ -n "$pod" ]] || die "no CNPG primary pod found for cluster ${PG_CLUSTER}"
  kubectl_ns exec -i "$pod" -c postgres -- psql -U postgres "$@"
}

pg_dump_db() { # db outfile — plain-format pg_dump from the CNPG primary
  local pod
  pod=$(pg_primary_pod)
  [[ -n "$pod" ]] || die "no CNPG primary pod found for cluster ${PG_CLUSTER}"
  kubectl_ns exec "$pod" -c postgres -- \
    pg_dump -U postgres --clean --if-exists --no-owner --no-privileges "$1" > "$2"
}
