#!/usr/bin/env bash
# Smoke/verify checks for the Inari platform stack.
# Used by bootstrap.sh (post-install) and dr-drill.sh (post-restore).
# Expects lib/common.sh to be sourced already.

verify_workloads() {
  log "verifying workloads are ready"
  wait_cnpg_cluster "$PG_CLUSTER" 600
  wait_statefulset keycloak 600s
  wait_statefulset nats 300s
  wait_deployment nats-box 300s
  wait_deployment openfga 300s
}

verify_keycloak_realm() {
  log "verifying Keycloak realm 'inari'"
  kubectl_ns run inari-verify-realm --rm -i --restart=Never \
    --image=curlimages/curl:8.10.1 --quiet -- \
    -fsS --retry 30 --retry-delay 5 --retry-all-errors \
    http://keycloak/realms/inari > /dev/null \
    || die "Keycloak realm 'inari' is not reachable"
}

verify_postgres() {
  log "verifying PostgreSQL databases"
  local dbs
  dbs=$(pg_exec -Atc "SELECT datname FROM pg_database WHERE datname IN ('inari','keycloak','openfga') ORDER BY 1")
  local expected=$'inari\nkeycloak\nopenfga'
  [[ "$dbs" == "$expected" ]] || die "expected databases inari/keycloak/openfga, got: ${dbs:-<none>}"
}

verify_openfga() {
  log "verifying OpenFGA health"
  kubectl_ns run inari-verify-openfga --rm -i --restart=Never \
    --image=curlimages/curl:8.10.1 --quiet -- \
    -fsS --retry 12 --retry-delay 5 --retry-all-errors \
    http://openfga:8080/healthz > /dev/null \
    || die "OpenFGA /healthz failed"
}

verify_nats() {
  log "verifying NATS JetStream"
  local report
  report=$(kubectl_ns exec deployment/nats-box -- \
    nats server report jetstream 2>/dev/null || true)
  [[ -n "$report" ]] || die "NATS JetStream is not enabled/reachable"
}

verify_stack() {
  verify_workloads
  verify_postgres
  verify_keycloak_realm
  verify_openfga
  verify_nats
  log "smoke check passed: platform stack is healthy"
}
