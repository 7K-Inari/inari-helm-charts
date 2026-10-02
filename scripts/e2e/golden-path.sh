#!/usr/bin/env bash
# e2e golden path (CI gate), PROVISIONING ONLY — phase 2 of the shell→Go
# migration (parent design §3). Remaining in shell: kind cluster lifecycle,
# the git-root hostPath, image load, the operators prereq script, and the
# Keycloak realm/user seeding (+ tenant/cluster registration) that
# interleaves with it. EVERY helm install/upgrade moved to the Go stack
# suite (scripts/e2e/stack, suite/provision.go — dependency-layered,
# concurrent installs); the assertions live there too. This script invokes
# the Go provisioners mid-flow:
#
#   kind create + hostPath + load images + install-operators.sh
#   → go test -run TestProvisionStack   (all platform/server/operator/console charts)
#   → KC seeding + tenant + cluster registration (below)
#   → go test -run TestProvisionAgent   (inari-agent chart + ESO wiring)
#   → groups mapper + rbac-viewer + handoff JSON ($E2E_HANDOFF_PATH)
#
# Phase 3 moves the remaining shell (kind, hostPath, KC seeding) into Go
# and deletes this script.
#
# All HTTP calls run through a toolbox pod in the cluster (kubectl exec) so
# the script is immune to port-forward fragility. The toolbox pod is created
# by TestProvisionStack. The script intentionally performs a few Keycloak
# provisioning steps imperatively (audience mapper) that are not yet
# automated in inari-server — each is marked GAP(n) and maps to a tracked
# upstream fix; the script must keep passing once those land. The OIDC
# client-secret delivery is fully automated: Vault (dev mode) + ESO + the
# manifest-rendered ExternalSecret.
#
# This script lives in inari-release-bundle (scripts/e2e/) and is the
# canonical golden-path e2e; it was relocated from the inari-server repo.
#
# Prereqs: docker, kind, kubectl, helm, jq, go, git, base64, curl.
# Configurable via env:
#   CLUSTER_NAME (default inari-e2e)
#   SERVER_IMAGE / AGENT_IMAGE (default inari/server:e2e / inari/agent:e2e)
#   HELM_CHARTS_DIR (default: this repo's root, resolved from the script
#     location) plus the chart-dir knobs (PLATFORM/SERVER/CONSOLE/AGENT/
#     OPERATOR/OPERATOR_CRDS_CHART_DIR) — all passed through to the Go
#     provisioner; see scripts/e2e/stack/suite/provision.go for defaults
#   KEEP_CLUSTER=true to skip teardown
#   E2E_HANDOFF_PATH — when set, write the Go-suite handoff JSON here and
#     keep the git host dir after exit (the suite reads materialized state
#     repos from it)
#   E2E_AGENT_INPUT_PATH (default $E2E_HANDOFF_PATH.agent.json or a temp
#     file) — registration outputs for TestProvisionAgent
#   INARI_E2E_CACHE_BACKEND=memory|redis (default memory; default redis when
#     INARI_HA=true) — passed through to the Go provisioner
#   INARI_HA=true (default false) — HA mode: mirrored to E2E_HA for the Go
#     provisioner, which flips helm replica values (inari-server
#     replicaCount=2, OpenFGA scale-out after migrations, redis cache,
#     3-node NATS + R=3 streams; the non-HA leg is stack-trimmed to a
#     single NATS node + R=1 streams). Backend constraints in HA mode:
#     - INARI_GIT_PROVIDER=local stays: the bare-repo root is a hostPath
#       shared by every replica through the kind node mount.
#     - TZF fake AWS backends keep state per-pod (in-memory): the golden
#       path makes no TZF-zone assertions, and any future one must be
#       skipped or pinned to a single pod under INARI_HA.
#     - No assertion needs the github provider; if one is added, gate it
#       on INARI_GITHUB_APP_ID + INARI_GITHUB_APP_PRIVATE_KEY_FILE.
set -euo pipefail

log() { printf '\033[1;34m[e2e]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[e2e] %s\033[0m\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing prerequisite: $1"; }

CLUSTER_NAME="${CLUSTER_NAME:-inari-e2e}"
SERVER_IMAGE="${SERVER_IMAGE:-inari/server:e2e}"
AGENT_IMAGE="${AGENT_IMAGE:-inari/agent:e2e}"
export HELM_CHARTS_DIR="${HELM_CHARTS_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
export PLATFORM_CHART_DIR="${PLATFORM_CHART_DIR:-$HELM_CHARTS_DIR/charts/inari-platform}"
export SERVER_CHART_DIR="${SERVER_CHART_DIR:-$HELM_CHARTS_DIR/charts/inari-server}"
export CONSOLE_CHART_DIR="${CONSOLE_CHART_DIR:-$HELM_CHARTS_DIR/charts/inari-console}"
export AGENT_CHART_DIR="${AGENT_CHART_DIR:-$HELM_CHARTS_DIR/../inari-agent/charts/inari-agent}"
export OPERATOR_CHART_DIR="${OPERATOR_CHART_DIR:-$HELM_CHARTS_DIR/../inari-operator/charts/inari-operator}"
export OPERATOR_CRDS_CHART_DIR="${OPERATOR_CRDS_CHART_DIR:-$OPERATOR_CHART_DIR/../inari-operator-crds}"
export NAMESPACE="${NAMESPACE:-inari}"
TENANT="${TENANT:-e2e-org}"
KEEP_CLUSTER="${KEEP_CLUSTER:-false}"
E2E_HANDOFF_PATH="${E2E_HANDOFF_PATH:-}"
TOOLS=golden-path-tools
KC_FQDN="keycloak-service.${NAMESPACE}.svc:8080"
SERVER_SVC="inari-server"
VAULT_DEV_TOKEN="${VAULT_DEV_TOKEN:-e2e-root-token}"
STACK_DIR="$(cd "$(dirname "$0")/stack" && pwd)"
# HA mode (default off). The script no longer branches on it for helm — it
# is mirrored to E2E_HA for the Go provisioner/assertions, which own every
# replica/values flip (stack trimming included).
INARI_HA="${INARI_HA:-false}"
[ "$INARI_HA" = "true" ] || [ "$INARI_HA" = "false" ] || \
  die "INARI_HA must be true or false (got: $INARI_HA)"
E2E_HA=0
$INARI_HA && E2E_HA=1
export E2E_HA INARI_E2E_CACHE_BACKEND="${INARI_E2E_CACHE_BACKEND:-}" \
  SERVER_IMAGE AGENT_IMAGE VAULT_DEV_TOKEN NAMESPACE TENANT

need docker; need kubectl; need helm; need jq; need kind; need git; need base64; need curl; need go

# Host-side git root for INARI_GIT_PROVIDER=local: the server writes real
# bare repos here (mounted into the kind node), and this script clones and
# applies baseline/rbac/ from them — GAP(rbac-e2e-argocd): this stands in
# for the tenant-local ArgoCD, which the e2e platform stack does not
# install ("platform stack without ArgoCD", see below).
GIT_HOST_DIR="$(mktemp -d /tmp/inari-e2e-git.XXXXXX)"
# mktemp dirs are 0700; the server container runs non-root, so open the
# shared git root up (it is bind-mounted into the kind node at /git and
# hostPath-mounted into the server pod at /var/lib/inari/git).
chmod 0777 "$GIT_HOST_DIR"

cleanup() {
  # The toolbox pod is the Go suite's ONLY transport (every HTTP call is a
  # kubectl exec curl through it), so it must survive script exit when a
  # handoff was requested. It dies with the kind cluster teardown either way.
  if [ -z "$E2E_HANDOFF_PATH" ]; then
    kubectl -n "$NAMESPACE" delete pod "$TOOLS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
  $KEEP_CLUSTER || kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
  # The git host dir must survive script exit when a Go-suite handoff was
  # requested: the stack suite reads the materialized state repos from it.
  if ! $KEEP_CLUSTER && [ -z "$E2E_HANDOFF_PATH" ]; then
    rm -rf "$GIT_HOST_DIR" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# xcurl runs curl inside the toolbox pod (never on the host).
xcurl() { kubectl -n "$NAMESPACE" exec "$TOOLS" -- curl -sf -m 20 "$@"; }

log "creating kind cluster '$CLUSTER_NAME'"
kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
# extraMounts: the host git root lands at /git inside the kind node so the
# server pod can hostPath-mount it for the local git provider.
kind create cluster --name "$CLUSTER_NAME" --wait 60s \
  --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraMounts:
      - hostPath: $GIT_HOST_DIR
        containerPath: /git
EOF
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

log "loading images ($SERVER_IMAGE, $AGENT_IMAGE)"
kind load docker-image "$SERVER_IMAGE" "$AGENT_IMAGE" --name "$CLUSTER_NAME"

log "installing prerequisite operators (CNPG + Keycloak — the charts never install operators)"
"$HELM_CHARTS_DIR/scripts/install-operators.sh"

# ---------------------------------------------------------------------------
# All helm installs: Go provisioner (dependency-layered, concurrent — see
# scripts/e2e/stack/suite/provision.go for the graph). Ends with the toolbox
# pod running, the Keycloak issuer converged, the console smoke-verified and
# the INARI_OUTBOX stream formed.
# ---------------------------------------------------------------------------
log "installing all charts via the Go provisioner (go test -run TestProvisionStack)"
(cd "$STACK_DIR" && go test -tags "e2e e2eprovision" -count=1 -run '^TestProvisionStack$' ./...) \
  || die "chart provisioning failed (logs: kubectl -n $NAMESPACE get pods)"

admin_token() {
  local secret
  secret=$(kubectl -n "$NAMESPACE" get secret inari-keycloak-admin -o jsonpath='{.data.client-secret}' | base64 -d)
  xcurl "http://keycloak-service:8080/realms/inari/protocol/openid-connect/token" \
    -d grant_type=client_credentials -d client_id=inari-platform-admin -d client_secret="$secret" \
    | jq -r .access_token
}
user_token() {
  xcurl "http://keycloak-service:8080/realms/inari/protocol/openid-connect/token" \
    -d grant_type=password -d client_id=inari-server \
    -d username=dev-admin -d password=dev-admin -d scope="openid organization:*" \
    | jq -r .access_token
}

AT="$(admin_token)"

log "GAP(kc-realm): ensuring dev user + public client with correct scopes"
KC_UID=$(xcurl -H "Authorization: Bearer $AT" "http://keycloak-service:8080/admin/realms/inari/users?username=dev-admin" | jq -r '.[0].id // empty')
if [ -z "$KC_UID" ]; then
  xcurl -X POST -H "Authorization: Bearer $AT" -H "Content-Type: application/json" \
    -d '{"username":"dev-admin","enabled":true,"email":"dev-admin@inari.local","emailVerified":true,"firstName":"Dev","lastName":"Admin","credentials":[{"type":"password","value":"dev-admin","temporary":false}]}' \
    -o /dev/null "http://keycloak-service:8080/admin/realms/inari/users"
  KC_UID=$(xcurl -H "Authorization: Bearer $AT" "http://keycloak-service:8080/admin/realms/inari/users?username=dev-admin" | jq -r '.[0].id')
fi
# KC 26.x: create alone can leave the account unverified — force the final state.
xcurl -X PUT -H "Authorization: Bearer $AT" -H "Content-Type: application/json" \
  -d '{"emailVerified":true,"firstName":"Dev","lastName":"Admin","requiredActions":[],"enabled":true}' \
  -o /dev/null "http://keycloak-service:8080/admin/realms/inari/users/$KC_UID"
KC_CLIENT=$(xcurl -H "Authorization: Bearer $AT" "http://keycloak-service:8080/admin/realms/inari/clients?clientId=inari-server" | jq -r '.[0].id // empty')
if [ -z "$KC_CLIENT" ]; then
  xcurl -X POST -H "Authorization: Bearer $AT" -H "Content-Type: application/json" \
    -d '{"clientId":"inari-server","enabled":true,"publicClient":true,"standardFlowEnabled":true,"directAccessGrantsEnabled":true,"redirectUris":["http://localhost/*"],"webOrigins":["+"],"defaultClientScopes":["openid","profile","email","organization"]}' \
    -o /dev/null "http://keycloak-service:8080/admin/realms/inari/clients"
  KC_CLIENT=$(xcurl -H "Authorization: Bearer $AT" "http://keycloak-service:8080/admin/realms/inari/clients?clientId=inari-server" | jq -r '.[0].id')
fi
# GAP(aud-mapper): server validates aud=inari-server.
for i in 1 2 3; do
  MAPPERS=$(xcurl -H "Authorization: Bearer $AT" "http://keycloak-service:8080/admin/realms/inari/clients/$KC_CLIENT/protocol-mappers/models" | jq -r '.[].name' || true)
  grep -q audience-inari-server <<<"$MAPPERS" && break
  xcurl -X POST -H "Authorization: Bearer $AT" -H "Content-Type: application/json" \
    -d '{"name":"audience-inari-server","protocol":"openid-connect","protocolMapper":"oidc-audience-mapper","config":{"included.client.audience":"inari-server","id.token.claim":"false","access.token.claim":"true","userinfo.token.claim":"false"}}' \
    -o /dev/null "http://keycloak-service:8080/admin/realms/inari/clients/$KC_CLIENT/protocol-mappers/models" || true
  sleep 2
done
# GAP(default-scopes): when the realm import JSON carries an explicit
# clientScopes array, Keycloak skips creating its built-in default scopes
# (basic, organization, ...) and every token request dies with invalid_scope.
# Recreate the two scopes these flows depend on — with the built-in mapper
# shapes — and attach them to the client (idempotent).
ensure_scope() { # $1=name $2=creation-json (used only when missing)
  local name="$1" body="$2" sid
  sid=$(xcurl -H "Authorization: Bearer $AT" "http://keycloak-service:8080/admin/realms/inari/client-scopes" | jq -r --arg n "$name" '.[] | select(.name==$n) | .id // empty')
  if [ -z "$sid" ]; then
    xcurl -X POST -H "Authorization: Bearer $AT" -H "Content-Type: application/json" \
      -d "$body" -o /dev/null "http://keycloak-service:8080/admin/realms/inari/client-scopes"
    sid=$(xcurl -H "Authorization: Bearer $AT" "http://keycloak-service:8080/admin/realms/inari/client-scopes" | jq -r --arg n "$name" '.[] | select(.name==$n) | .id')
  fi
  kubectl -n "$NAMESPACE" exec "$TOOLS" -- curl -s -o /dev/null -X PUT -H "Authorization: Bearer $AT" \
    "http://keycloak-service:8080/admin/realms/inari/clients/$KC_CLIENT/default-client-scopes/$sid"
}
# Without the basic scope, tokens carry no sub claim (KC 26 user-profile model).
ensure_scope basic '{"name":"basic","protocol":"openid-connect","attributes":{"include.in.token.scope":"false","display.on.consent.screen":"false"},"protocolMappers":[{"name":"sub","protocol":"openid-connect","protocolMapper":"oidc-sub-mapper","config":{"access.token.claim":"true","id.token.claim":"true"}}]}'
# Without the organization scope, scope="openid organization:*" is rejected.
ensure_scope organization '{"name":"organization","protocol":"openid-connect","attributes":{"include.in.token.scope":"true","display.on.consent.screen":"false"},"protocolMappers":[{"name":"organization","protocol":"openid-connect","protocolMapper":"oidc-organization-membership-mapper","config":{"id.token.claim":"true","access.token.claim":"true","claim.name":"organization","jsonType.label":"String","multivalued":"true"}}]}'
# Sanity: a token must carry sub and aud=inari-server before we proceed.
PROBE="$(user_token)"
PAYLOAD=$(cut -d. -f2 <<<"$PROBE"); PAYLOAD="${PAYLOAD}$(printf '=%.0s' $(seq 1 $(( (4 - ${#PAYLOAD} % 4) % 4 ))))"
CLAIMS=$(base64 -d <<<"$PAYLOAD" 2>/dev/null || base64 -D <<<"$PAYLOAD")
jq -e '.sub != null' <<<"$CLAIMS" >/dev/null || die "token has no sub claim (basic scope missing)"
jq -e '.aud == "inari-server" or (.aud | type == "array" and index("inari-server"))' <<<"$CLAIMS" >/dev/null \
  || die "token has wrong aud (audience mapper missing): $(jq -c .aud <<<"$CLAIMS")"

API="http://$SERVER_SVC:8080/api/v1"
log "GAP(kc-platform-group): ensuring dev-admin is in platform-admins (drives org_creator tuple sync)"
GROUP_ID=$(xcurl -H "Authorization: Bearer $AT" "http://keycloak-service:8080/admin/realms/inari/groups?exact=true&search=platform-admins" | jq -r '.[0].id // empty')
if [ -z "$GROUP_ID" ]; then
  xcurl -X POST -H "Authorization: Bearer $AT" -H "Content-Type: application/json" \
    -d '{"name":"platform-admins"}' -o /dev/null -w '%{http_code}' \
    "http://keycloak-service:8080/admin/realms/inari/groups" | grep -qE '201|409' \
    || die "failed to create platform-admins group"
  GROUP_ID=$(xcurl -H "Authorization: Bearer $AT" "http://keycloak-service:8080/admin/realms/inari/groups?exact=true&search=platform-admins" | jq -r '.[0].id')
fi
# Join is idempotent (204); the server's platform group sync reconciler turns
# membership into platform:inari org_creator tuples within its poll interval.
xcurl -o /dev/null -X PUT \
  -H "Authorization: Bearer $AT" \
  "http://keycloak-service:8080/admin/realms/inari/users/$KC_UID/groups/$GROUP_ID" \
  || die "failed to add dev-admin to platform-admins"

log "creating tenant '$TENANT'"
# Bounded poll: retries cover transient token/Keycloak warm-up errors; the
# outcome is an API response, not a k8s condition.
TENANT_RESP=""
for i in $(seq 1 12); do
  TOKEN="$(user_token || true)"
  if [ -n "$TOKEN" ]; then
    TENANT_RESP=$(kubectl -n "$NAMESPACE" exec "$TOOLS" -- curl -s -m 15 -X POST \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "{\"slug\":\"$TENANT\",\"displayName\":\"E2E Org\"}" "$API/tenants")
    jq -e '.organization.keycloakOrgId' <<<"$TENANT_RESP" >/dev/null 2>&1 && break
  fi
  sleep 10
done
jq -e '.organization.keycloakOrgId' <<<"$TENANT_RESP" >/dev/null \
  || die "tenant creation failed after retries: $TENANT_RESP"
ORG_KC_ID=$(jq -r '.organization.keycloakOrgId' <<<"$TENANT_RESP")

log "registering cluster + issuing token"
TOKEN="$(user_token)"
CLUSTER_RESP=$(xcurl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"e2e-self","labels":{"e2e":"true"}}' "$API/tenants/$TENANT/clusters")
CLUSTER_ID=$(jq -r '.cluster.id' <<<"$CLUSTER_RESP")
ORG_ID=$(jq -r '.cluster.orgId' <<<"$CLUSTER_RESP")
TOK_RESP=$(xcurl -X POST -H "Authorization: Bearer $(user_token)" \
  "$API/tenants/$TENANT/clusters/$CLUSTER_ID/tokens")

log "installing agent via the inari-agent Helm chart (go test -run TestProvisionAgent)"
REG_TOKEN=$(jq -r '.token' <<<"$TOK_RESP")
E2E_AGENT_INPUT_PATH="${E2E_AGENT_INPUT_PATH:-${E2E_HANDOFF_PATH:-/tmp/inari-e2e}.agent.json}"
jq -n \
  --arg ns "$NAMESPACE" --arg cluster_id "$CLUSTER_ID" --arg org_id "$ORG_ID" \
  --arg reg_token "$REG_TOKEN" --arg agent_chart_dir "$AGENT_CHART_DIR" \
  --arg agent_image "$AGENT_IMAGE" --arg vault_dev_token "$VAULT_DEV_TOKEN" \
  '{namespace:$ns, cluster_id:$cluster_id, org_id:$org_id, reg_token:$reg_token,
    agent_chart_dir:$agent_chart_dir, agent_image:$agent_image,
    vault_dev_token:$vault_dev_token}' \
  > "$E2E_AGENT_INPUT_PATH"
export E2E_AGENT_INPUT_PATH
(cd "$STACK_DIR" && go test -tags "e2e e2eprovision" -count=1 -run '^TestProvisionAgent$' ./...) \
  || die "agent provisioning failed (logs: kubectl -n inari-system get pods)"

log "GAP(kc-groups-mapper): ensuring the groups claim carries full group paths"
AT="$(admin_token)"
MAPPERS=$(xcurl -H "Authorization: Bearer $AT" "http://keycloak-service:8080/admin/realms/inari/clients/$KC_CLIENT/protocol-mappers/models" | jq -r '.[].name')
if ! grep -q '^groups$' <<<"$MAPPERS"; then
  xcurl -X POST -H "Authorization: Bearer $AT" -H "Content-Type: application/json" \
    -d '{"name":"groups","protocol":"openid-connect","protocolMapper":"oidc-group-membership-mapper","config":{"claim.name":"groups","full.path":"true","id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}}' \
    -o /dev/null "http://keycloak-service:8080/admin/realms/inari/clients/$KC_CLIENT/protocol-mappers/models" \
    || die "failed to add the groups mapper"
fi

log "kubelogin-style check: group membership maps to real RBAC"
# A user in the viewers team group must read but not write.
log "ensuring the rbac-viewer Keycloak user"
VIEWER_UID=$(xcurl -H "Authorization: Bearer $AT" "http://keycloak-service:8080/admin/realms/inari/users?username=rbac-viewer" | jq -r '.[0].id // empty')
if [ -z "$VIEWER_UID" ]; then
  xcurl -X POST -H "Authorization: Bearer $AT" -H "Content-Type: application/json" \
    -d '{"username":"rbac-viewer","enabled":true,"emailVerified":true,"credentials":[{"type":"password","value":"rbac-viewer","temporary":false}]}' \
    -o /dev/null "http://keycloak-service:8080/admin/realms/inari/users"
  VIEWER_UID=$(xcurl -H "Authorization: Bearer $AT" "http://keycloak-service:8080/admin/realms/inari/users?username=rbac-viewer" | jq -r '.[0].id')
fi
# KC 26.x: create alone can leave the account unverified — force the final
# state, else the password grant fails with "Account is not fully set up".
xcurl -X PUT -H "Authorization: Bearer $AT" -H "Content-Type: application/json" \
  -d '{"email":"rbac-viewer@inari.local","emailVerified":true,"firstName":"RBAC","lastName":"Viewer","requiredActions":[],"enabled":true}' \
  -o /dev/null "http://keycloak-service:8080/admin/realms/inari/users/$VIEWER_UID"
log "adding rbac-viewer to the viewers team group"
VIEWERS_GRP=$(xcurl -H "Authorization: Bearer $AT" "http://keycloak-service:8080/admin/realms/inari/group-by-path/tenant-$TENANT/viewers" | jq -r '.id // empty')
[ -n "$VIEWERS_GRP" ] || die "Keycloak group tenant-$TENANT/viewers not found (tenant seeding broken?)"
xcurl -o /dev/null -X PUT -H "Authorization: Bearer $AT" \
  "http://keycloak-service:8080/admin/realms/inari/users/$VIEWER_UID/groups/$VIEWERS_GRP" || true

# ---------------------------------------------------------------------------
# Provisioning complete. All golden-path assertions live in the Go stack
# suite (scripts/e2e/stack, `go test -tags=e2e`). Export the handoff the
# suite consumes (contract: field renames must land in suite/env.go too).
# ---------------------------------------------------------------------------
if [ -n "$E2E_HANDOFF_PATH" ]; then
  jq -n \
    --arg ns "$NAMESPACE" --arg toolbox "$TOOLS" --arg tenant "$TENANT" \
    --arg kc_uid "$KC_UID" --arg org_kc_id "$ORG_KC_ID" \
    --arg cluster_id "$CLUSTER_ID" --arg org_id "$ORG_ID" \
    --arg git_host_dir "$GIT_HOST_DIR" --arg agent_chart_dir "$AGENT_CHART_DIR" \
    '{namespace:$ns, toolbox:$toolbox, tenant:$tenant, kc_uid:$kc_uid,
      org_kc_id:$org_kc_id, cluster_id:$cluster_id, org_id:$org_id,
      git_host_dir:$git_host_dir, agent_chart_dir:$agent_chart_dir}' \
    > "$E2E_HANDOFF_PATH"
  log "handoff written to $E2E_HANDOFF_PATH"
fi
log "PASS: golden-path stack provisioned — assertions: (cd scripts/e2e/stack && E2E_HANDOFF_PATH=$E2E_HANDOFF_PATH go test -tags=e2e ./...)"
