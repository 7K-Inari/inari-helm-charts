#!/usr/bin/env bash
# Backup the Inari platform state into a single tarball (plan §9 M0, §12.1/1).
#
# Captures:
#   - PostgreSQL logical dumps (inari + openfga databases) from the CNPG primary
#   - Keycloak realm export (admin REST partial-export)
#   - OpenFGA authorization model + tuples (if a store exists yet)
#   - NATS JetStream stream snapshots (if any streams exist)
#   - manifest.json with chart/cluster metadata
#
# All in-cluster HTTP work runs from the nats-box pod (ships curl + jq + nats CLI).
#
# Usage: scripts/backup.sh [output-dir]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require kubectl jq tar

OUT_DIR="${1:-${BACKUP_DIR:-./backups}}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
WORK="$(mktemp -d)/inari-backup-$TS"
mkdir -p "$WORK/postgres" "$WORK/keycloak" "$WORK/openfga" "$WORK/nats" "$OUT_DIR"
trap 'rm -rf "$(dirname "$WORK")"' EXIT

box() { kubectl_ns exec deployment/nats-box -- sh -c "$1"; }

log "backing up PostgreSQL databases (CNPG cluster: $PG_CLUSTER)"
pg_dump_db inari "$WORK/postgres/inari.sql"
pg_dump_db openfga "$WORK/postgres/openfga.sql"

log "exporting Keycloak realm 'inari' (admin REST partial-export)"
KC_ADMIN_PW="$(kubectl_ns get secret inari-db -o jsonpath='{.data.keycloak-admin-password}' | base64 -d)"
KC_TOKEN="$(box "curl -sS -X POST http://keycloak-service:8080/realms/master/protocol/openid-connect/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=password&client_id=admin-cli&username=admin&password=${KC_ADMIN_PW}' \
  | jq -r .access_token")"
[[ "$KC_TOKEN" != "null" && -n "$KC_TOKEN" ]] || die "could not obtain Keycloak admin token"
box "curl -sS -X POST 'http://keycloak-service:8080/admin/realms/inari/partial-export?exportClients=true&exportGroupsAndRoles=true' \
  -H 'Accept: application/json' -H 'Authorization: Bearer ${KC_TOKEN}'" \
  | jq '.' > "$WORK/keycloak/realm-inari.json"
jq -e '.realm == "inari"' "$WORK/keycloak/realm-inari.json" > /dev/null \
  || die "Keycloak realm export did not contain realm 'inari'"

log "exporting OpenFGA model and tuples"
box "curl -sS http://openfga:8080/stores" | jq -c '.stores // []' > "$WORK/openfga/stores.json"
STORE_COUNT="$(jq 'length' "$WORK/openfga/stores.json")"
if (( STORE_COUNT > 0 )); then
  STORE_ID="$(jq -r '.[0].id' "$WORK/openfga/stores.json")"
  box "curl -sS http://openfga:8080/stores/${STORE_ID}/authorization-models" \
    | jq '.' > "$WORK/openfga/authorization-models.json"
  box "curl -sS -X POST http://openfga:8080/stores/${STORE_ID}/read \
    -H 'Content-Type: application/json' -d '{}'" \
    | jq '.' > "$WORK/openfga/tuples.json"
else
  warn "no OpenFGA stores yet (control plane not deployed) — skipping model/tuple export"
fi

log "snapshotting NATS JetStream streams"
kubectl_ns exec deployment/nats-box -- nats stream ls --json 2>/dev/null \
  | jq -c '.' > "$WORK/nats/streams.json" || echo '[]' > "$WORK/nats/streams.json"
STREAM_COUNT="$(jq 'length' "$WORK/nats/streams.json")"
if (( STREAM_COUNT > 0 )); then
  box "rm -rf /tmp/js-backup && mkdir -p /tmp/js-backup && \
       for s in \$(nats stream ls --json | jq -r '.[]'); do \
         nats stream backup /tmp/js-backup \"\$s\" >/dev/null; \
       done && tar czf - -C /tmp/js-backup ." > "$WORK/nats/jetstream-backup.tgz" \
    || die "NATS stream backup failed"
else
  warn "no JetStream streams yet (control plane not deployed) — skipping stream snapshot"
fi

log "writing manifest"
jq -n \
  --arg ts "$TS" \
  --arg chartVersion "$(helm -n "$NAMESPACE" list -f "^${RELEASE}$" -o json 2>/dev/null | jq -r '.[0].chart // "unknown"')" \
  --arg pgCluster "$PG_CLUSTER" \
  --argjson openfgaStores "$STORE_COUNT" \
  --argjson natsStreams "$STREAM_COUNT" \
  '{createdAt: $ts, chart: $chartVersion, cnpgCluster: $pgCluster,
    openfgaStores: $openfgaStores, natsStreams: $natsStreams,
    contents: ["postgres/inari.sql", "postgres/openfga.sql",
               "keycloak/realm-inari.json", "openfga/", "nats/"]}' \
  > "$WORK/manifest.json"

ARCHIVE="$OUT_DIR/inari-backup-$TS.tgz"
tar czf "$ARCHIVE" -C "$(dirname "$WORK")" "$(basename "$WORK")"
log "backup written to $ARCHIVE"
