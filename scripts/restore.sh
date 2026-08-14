#!/usr/bin/env bash
# Restore an Inari platform backup produced by scripts/backup.sh.
#
# Assumes the umbrella chart is already installed and healthy on the target
# cluster (e.g. a fresh kind cluster via bootstrap.sh / dr-drill.sh).
# Logical dumps carry --clean/--if-exists, so the target may be fresh or used.
#
# Usage: scripts/restore.sh <backup.tgz>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require kubectl jq tar

ARCHIVE="${1:?usage: restore.sh <backup.tgz>}"
[[ -f "$ARCHIVE" ]] || die "backup archive not found: $ARCHIVE"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
tar xzf "$ARCHIVE" -C "$WORK"
BK="$(find "$WORK" -mindepth 1 -maxdepth 1 -type d | head -1)"
[[ -f "$BK/manifest.json" ]] || die "not an Inari backup archive: $ARCHIVE"
log "restoring backup from $(jq -r .createdAt "$BK/manifest.json") (chart $(jq -r .chart "$BK/manifest.json"))"

box() { kubectl_ns exec deployment/nats-box -- sh -c "$1"; }
box_cp() { # local-path remote-path — copy into the nats-box pod
  local pod
  pod="$(kubectl_ns get pod -l app.kubernetes.io/component=nats-box -o jsonpath='{.items[0].metadata.name}')"
  kubectl_ns cp "$1" "$pod":"$2"
}

log "restoring PostgreSQL databases"
pg_exec -v ON_ERROR_STOP=1 -d inari -f - < "$BK/postgres/inari.sql" \
  || die "restore of database 'inari' failed"
pg_exec -v ON_ERROR_STOP=1 -d openfga -f - < "$BK/postgres/openfga.sql" \
  || die "restore of database 'openfga' failed"

# The openfga database was dropped/recreated under the running server —
# restart it so the migration init container re-applies the schema cleanly.
log "restarting OpenFGA to re-run migrations on the restored database"
kubectl_ns rollout restart deployment/openfga
wait_deployment openfga 300s

log "restoring Keycloak realm 'inari'"
KC_ADMIN_PW="$(kubectl_ns get secret inari-db -o jsonpath='{.data.keycloak-admin-password}' | base64 -d)"
KC_TOKEN="$(box "curl -sS -X POST http://keycloak/realms/master/protocol/openid-connect/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=password&client_id=admin-cli&username=admin&password=${KC_ADMIN_PW}' \
  | jq -r .access_token")"
[[ "$KC_TOKEN" != "null" && -n "$KC_TOKEN" ]] || die "could not obtain Keycloak admin token"
box_cp "$BK/keycloak/realm-inari.json" /tmp/realm-inari.json
# Replace the chart-imported realm with the exported one (orgs/clients included).
box "curl -sS -X DELETE http://keycloak/admin/realms/inari -H 'Authorization: Bearer ${KC_TOKEN}' -o /dev/null -w '%{http_code}'" | grep -qE '204|404' \
  || die "could not delete existing realm 'inari'"
box "curl -sS -X POST http://keycloak/admin/realms -H 'Authorization: Bearer ${KC_TOKEN}' \
  -H 'Content-Type: application/json' --data-binary @/tmp/realm-inari.json -o /dev/null -w '%{http_code}'" | grep -qE '201|409' \
  || die "could not re-import realm 'inari'"

if jq -e 'length > 0' "$BK/openfga/stores.json" > /dev/null 2>&1; then
  log "restoring OpenFGA store, model and tuples"
  box_cp "$BK/openfga/authorization-models.json" /tmp/fga-models.json
  box_cp "$BK/openfga/tuples.json" /tmp/fga-tuples.json
  FGA_STORE_ID="$(box "curl -sS -X POST http://openfga:8080/stores \
    -H 'Content-Type: application/json' -d '{\"name\": \"inari\"}' | jq -r .id")"
  [[ "$FGA_STORE_ID" != "null" && -n "$FGA_STORE_ID" ]] || die "could not create OpenFGA store"
  box "jq '.authorization_models[0] | del(.id)' /tmp/fga-models.json > /tmp/fga-model.json \
    && curl -sS -X POST http://openfga:8080/stores/${FGA_STORE_ID}/authorization-models \
      -H 'Content-Type: application/json' --data-binary @/tmp/fga-model.json -o /dev/null -w '%{http_code}'" \
    | grep -qE '201' || die "could not write OpenFGA authorization model"
  TUPLE_COUNT="$(jq '.tuples | length' "$BK/openfga/tuples.json")"
  if (( TUPLE_COUNT > 0 )); then
    box "jq '{writes: {tuple_keys: [.tuples[].key]}}' /tmp/fga-tuples.json > /tmp/fga-write.json \
      && curl -sS -X POST http://openfga:8080/stores/${FGA_STORE_ID}/write \
        -H 'Content-Type: application/json' --data-binary @/tmp/fga-write.json -o /dev/null -w '%{http_code}'" \
      | grep -qE '200' || die "could not write OpenFGA tuples"
  fi
else
  warn "backup contains no OpenFGA stores — skipping"
fi

if [[ -f "$BK/nats/jetstream-backup.tgz" ]]; then
  log "restoring NATS JetStream streams"
  box_cp "$BK/nats/jetstream-backup.tgz" /tmp/jetstream-backup.tgz
  box "rm -rf /tmp/js-restore && mkdir -p /tmp/js-restore \
    && tar xzf /tmp/jetstream-backup.tgz -C /tmp/js-restore \
    && nats stream restore /tmp/js-restore" \
    || die "NATS stream restore failed"
else
  warn "backup contains no JetStream snapshot — skipping"
fi

log "restore complete"
