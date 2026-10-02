#!/usr/bin/env bash
# e2e golden path (CI gate), PROVISIONING ONLY: platform stack on kind →
# Keycloak seeding → tenant → cluster registration → agent install.
# Assertions live in the Go stack suite (scripts/e2e/stack, run with
# `go test -tags=e2e`) — phase 1 of the shell→Go migration (parent design
# §3). This script writes a handoff file ($E2E_HANDOFF_PATH) the suite
# consumes; provisioning (kind create, helm installs, KC seeding) moves to
# Go in phases 2–3.
#
# Mirrors the manually validated flow. All HTTP calls run through a toolbox
# pod in the cluster (kubectl exec) so the script is immune to
# port-forward fragility. It intentionally performs a few Keycloak
# provisioning steps imperatively (audience mapper)
# that are not yet automated in inari-server — each is marked GAP(n) and maps
# to a tracked upstream fix; the script must keep
# passing once those land. The OIDC client-secret delivery is fully
# automated: Vault (dev mode) + ESO + the manifest-rendered ExternalSecret.
#
# This script lives in inari-release-bundle (scripts/e2e/) and is the
# canonical golden-path e2e; it was relocated from the inari-server repo.
#
# Prereqs: docker, kind, kubectl, helm, jq. Configurable via env:
#   CLUSTER_NAME (default inari-e2e)
#   SERVER_IMAGE / AGENT_IMAGE (default inari/server:e2e / inari/agent:e2e)
#   HELM_CHARTS_DIR (default: this repo's root, resolved from the script
#     location — provides charts/inari-platform, charts/inari-server,
#     charts/inari-console, and scripts/install-operators.sh)
#   SERVER_CHART_DIR (default $HELM_CHARTS_DIR/charts/inari-server)
#   CONSOLE_CHART_DIR (default $HELM_CHARTS_DIR/charts/inari-console)
#   AGENT_CHART_DIR (default $HELM_CHARTS_DIR/../inari-agent/charts/inari-agent —
#     the inari-agent repo checkout the e2e workflow nests next to this repo;
#     CI pins it explicitly)
#   OPERATOR_CHART_DIR (default
#     $HELM_CHARTS_DIR/../inari-operator/charts/inari-operator — the
#     inari-operator repo checkout, resolved the same way as the agent chart)
#   KEEP_CLUSTER=true to skip teardown
#   E2E_HANDOFF_PATH — when set, write the Go-suite handoff JSON here and
#     keep the git host dir after exit (the suite reads materialized state
#     repos from it)
#   INARI_E2E_CACHE_BACKEND=memory|redis (default memory; default redis when
#     INARI_HA=true) — redis installs the chart's bitnami/redis subchart and
#     points the cache layer at it
#   INARI_HA=true (default false) — HA mode (Wave 2, 99.9% initiative):
#     inari-server replicaCount=2 via the W1 chart knobs (probes, PDB,
#     anti-affinity, rollingUpdate maxUnavailable: 0), OpenFGA
#     replicaCount=2. The HA-only disruption assertions (pod kill, rollout
#     restart under traffic, migration-lock race, leader-lease
#     single-execution, agent stream fencing) now live in the Go stack
#     suite (E2E_HA=1). The non-HA path is byte-identical in behavior and
#     timing and stays the fast default gate. NATS is 3-node JetStream in
#     BOTH modes (W1 provisioned it HA from day one). The inari-console +
#     inari-operator charts install alongside the server with smoke-level
#     assertions (charts healthy, console serves, console config points at
#     the Keycloak login); their full HA guardrails live in their own repos.
#     Backend constraints in HA mode:
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
HELM_CHARTS_DIR="${HELM_CHARTS_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
PLATFORM_CHART_DIR="${PLATFORM_CHART_DIR:-$HELM_CHARTS_DIR/charts/inari-platform}"
SERVER_CHART_DIR="${SERVER_CHART_DIR:-$HELM_CHARTS_DIR/charts/inari-server}"
CONSOLE_CHART_DIR="${CONSOLE_CHART_DIR:-$HELM_CHARTS_DIR/charts/inari-console}"
AGENT_CHART_DIR="${AGENT_CHART_DIR:-$HELM_CHARTS_DIR/../inari-agent/charts/inari-agent}"
OPERATOR_CHART_DIR="${OPERATOR_CHART_DIR:-$HELM_CHARTS_DIR/../inari-operator/charts/inari-operator}"
NAMESPACE="${NAMESPACE:-inari}"
TENANT="${TENANT:-e2e-org}"
KEEP_CLUSTER="${KEEP_CLUSTER:-false}"
E2E_HANDOFF_PATH="${E2E_HANDOFF_PATH:-}"
TOOLS=golden-path-tools
KC_FQDN="keycloak-service.${NAMESPACE}.svc:8080"
SERVER_SVC="inari-server"
VAULT_DEV_TOKEN="${VAULT_DEV_TOKEN:-e2e-root-token}"
# HA mode (default off). Only replica counts and HA-only assertion blocks
# branch on this — every other step is identical between modes.
INARI_HA="${INARI_HA:-false}"
[ "$INARI_HA" = "true" ] || [ "$INARI_HA" = "false" ] || \
  die "INARI_HA must be true or false (got: $INARI_HA)"
SERVER_REPLICAS=1
OPENFGA_REPLICAS=1
if $INARI_HA; then
  SERVER_REPLICAS=2
  OPENFGA_REPLICAS=2
fi
# Cache backend: memory is per-pod (the PEP generation bump is
# process-local, so cross-replica invalidation degrades to the 2s PEP
# TTL); HA defaults to the shared redis backend per the chart's
# multi-replica guidance. Non-HA default stays memory (unchanged).
CACHE_BACKEND="${INARI_E2E_CACHE_BACKEND:-}"
if [ -z "$CACHE_BACKEND" ]; then
  if $INARI_HA; then CACHE_BACKEND=redis; else CACHE_BACKEND=memory; fi
fi
[ "$CACHE_BACKEND" = "memory" ] || [ "$CACHE_BACKEND" = "redis" ] || \
  die "INARI_E2E_CACHE_BACKEND must be memory or redis (got: $CACHE_BACKEND)"

need docker; need kubectl; need helm; need jq; need kind; need git; need base64; need curl

# Component chart-dir sanity checks (die is defined above; INARI_HA too).
[ -d "$CONSOLE_CHART_DIR" ] || die "CONSOLE_CHART_DIR not found: $CONSOLE_CHART_DIR (set CONSOLE_CHART_DIR)"
[ -d "$OPERATOR_CHART_DIR" ] || die "OPERATOR_CHART_DIR not found: $OPERATOR_CHART_DIR (set OPERATOR_CHART_DIR)"

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
  kubectl -n "$NAMESPACE" delete pod "$TOOLS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
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

# Platform stack without ArgoCD: the gitops-composed pieces installed by hand
# (platform-config from git, NATS/OpenFGA from their public helm repos, values
# mirroring gitops/platform/*.yaml), then the inari-server chart from this
# repo with the e2e images.
log "installing platform-config (CNPG cluster + db secrets + Keycloak realm)"
helm upgrade --install platform-config "$PLATFORM_CHART_DIR" \
  --namespace "$NAMESPACE" --create-namespace \
  --set postgresql.storageSize=1Gi \
  --set keycloak.hostname.hostname=http://keycloak.local:8080 \
  --set keycloak.resources.requests.cpu=100m \
  --set keycloak.resources.requests.memory=256Mi \
  --wait --timeout 10m

# All helm repo setup serially up front: helm's local repo cache is shared
# state, and the component installs below run concurrently in background
# workers, where concurrent `helm repo` commands would race.
log "adding helm repos (serial; component installs run concurrently below)"
helm repo add openfga https://openfga.github.io/helm-charts >/dev/null
helm repo add nats https://nats-io.github.io/k8s/helm/charts/ >/dev/null
helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null
helm repo add external-secrets https://charts.external-secrets.io >/dev/null
# bitnami is vendored for the inari-server chart's optional redis subchart
# (helm verifies Chart.yaml dependencies even when disabled).
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null
helm repo update >/dev/null

# wait_cnpg blocks until the CNPG cluster is Ready. Everything except NATS
# and Vault/ESO derives from the platform database (Keycloak itself, and
# OpenFGA's datastore via the inari-db secret), so workers needing it call
# this first. Multiple workers may call it concurrently — kubectl wait is
# idempotent and safe to run in parallel.
wait_cnpg() {
  kubectl -n "$NAMESPACE" wait --for=condition=Ready \
    cluster.postgresql.cnpg.io/postgresql --timeout=600s
}

# ---------------------------------------------------------------------------
# Concurrent component installs. Keycloak's StatefulSet rollout is the long
# pole of the bring-up (two 420s rollout waits around the hostname patch),
# so the independent components install in background workers while it
# runs. Dependency order inside each worker is preserved.
#
# set -euo pipefail discipline: die() inside a background subshell would
# only kill that worker, so workers log and exit 1; the main shell collects
# PIDs and re-raises failures at the barrier below.
# ---------------------------------------------------------------------------
declare -a WORKER_PIDS=() WORKER_NAMES=()

# --- Worker: Keycloak (long pole) -----------------------------------------
# Wait for the database, roll the StatefulSet, pin the hostname (issuer
# consistency — MUST complete before inari-server installs), roll again.
(
  wait_cnpg || exit 1
  kubectl -n "$NAMESPACE" rollout status statefulset/keycloak --timeout=420s || exit 1
  kubectl -n "$NAMESPACE" wait --for=condition=complete job -l app.kubernetes.io/component=keycloak --timeout=300s 2>/dev/null || true
  kubectl -n "$NAMESPACE" patch keycloak keycloak --type merge \
    -p "{\"spec\":{\"hostname\":{\"hostname\":\"http://$KC_FQDN\",\"strict\":true}}}" || exit 1
  kubectl -n "$NAMESPACE" rollout status statefulset/keycloak --timeout=420s || exit 1
) &
WORKER_PIDS+=($!); WORKER_NAMES+=("keycloak")

# --- Worker: NATS (JetStream, 3-node cluster) ------------------------------
# NATS is the platform event bus (ADR-0014): the server refuses to boot
# without it — the outbox relay publishes to the INARI_OUTBOX stream and
# every handler is delivered via its own durable consumer group. It is
# provisioned HA (3-node, R=3 streams) — part of the 99.9% availability
# initiative. e2e/stack/testdata/nats-values.yaml mirrors the production posture:
#   - 3-node cluster (JetStream meta group quorum), one fileStore PVC per pod
#   - R=3 streams (replicas=3) so any single node loss keeps the stream live
#   - advised limits: size fileStore per retention budget and set explicit
#     max_memory_store/max_file_store; keep per-stream consumer counts
#     bounded (prefer few durable consumers over many ephemeral ones)
# The full operations docs page is a separate task.
(
  helm upgrade --install nats nats/nats --version 1.3.2 \
    --namespace "$NAMESPACE" \
    -f "$(dirname "$0")/stack/testdata/nats-values.yaml" \
    --wait --timeout 8m || exit 1
  # Belt-and-braces on top of helm --wait (the StatefulSet readiness probe
  # /healthz?js-server-only=true already gates on meta-group currency): assert
  # the JetStream meta group actually formed with 3 members and a leader.
  # The monitor port 8222 lives only on the nats-headless service (the nats
  # ClusterIP service exposes just 4222), so jsz must be scraped there.
  # Poll, don't sleep blindly: JetStream meta-group formation has no
  # API-visible Kubernetes condition, so the bounded poll below IS the wait.
  for i in $(seq 1 24); do
    JSZ=$(kubectl -n "$NAMESPACE" exec deploy/nats-box -- \
      sh -c 'curl -sf http://nats-headless:8222/jsz' 2>/dev/null || true)
    if jq -e '.meta_cluster.cluster_size == 3 and (.meta_cluster.leader | type == "string" and length > 0)' \
        <<<"$JSZ" >/dev/null 2>&1; then
      exit 0
    fi
    sleep 5
    [ "$i" = 24 ] && { log "nats: JetStream meta group never formed (jsz: ${JSZ:-empty}; logs: kubectl -n $NAMESPACE logs statefulset/nats)"; exit 1; }
  done
) &
WORKER_PIDS+=($!); WORKER_NAMES+=("nats")

# --- Worker: OpenFGA (postgres datastore via the inari-db secret) ----------
# Always installed single-replica first: OpenFGA runs its datastore
# migrations in a per-pod initContainer with no cross-pod locking, so a
# fresh 2-replica install would race goose migrations on an empty
# database. HA mode scales out AFTER the first pod has applied them.
(
  wait_cnpg || exit 1
  helm upgrade --install openfga openfga/openfga --version 0.2.27 \
    --namespace "$NAMESPACE" \
    --set fullnameOverride=openfga \
    --set replicaCount=1 \
    --set datastore.engine=postgres \
    --set datastore.existingSecret=inari-db \
    --set datastore.secretKeys.uriKey=openfga-uri \
    --set datastore.migrationType=initContainer \
    --set playground.enabled=false \
    --wait --timeout 5m || exit 1
  if [ "$OPENFGA_REPLICAS" -gt 1 ]; then
    log "openfga: HA scaling to $OPENFGA_REPLICAS replicas (migrations already applied)"
    kubectl -n "$NAMESPACE" scale deployment/openfga --replicas="$OPENFGA_REPLICAS" || exit 1
    kubectl -n "$NAMESPACE" rollout status deployment/openfga --timeout=240s || exit 1
  fi
) &
WORKER_PIDS+=($!); WORKER_NAMES+=("openfga")

# --- Worker: Vault (dev mode) + ESO ---------------------------------------
# OIDC client-secret delivery path: Vault (dev mode) + ESO + the
# manifest-rendered ExternalSecret.
(
  helm upgrade --install vault hashicorp/vault \
    --namespace "$NAMESPACE" \
    --set server.dev.enabled=true \
    --set server.dev.devRootToken="$VAULT_DEV_TOKEN" \
    --set injector.enabled=false \
    --wait --timeout 5m || exit 1
  helm upgrade --install external-secrets external-secrets/external-secrets \
    --namespace external-secrets --create-namespace \
    --set installCRDs=true \
    --wait --timeout 5m || exit 1
  # helm --wait covers the controller deployments, not CRD establishment;
  # applying a ClusterSecretStore before the API is established fails with
  # "no matches for kind".
  kubectl wait --for=condition=established crd/clustersecretstores.external-secrets.io --timeout=120s || exit 1
  kubectl wait --for=condition=established crd/externalsecrets.external-secrets.io --timeout=120s || exit 1
  kubectl -n "$NAMESPACE" create secret generic inari-vault \
    --from-literal=token="$VAULT_DEV_TOKEN" --dry-run=client -o yaml | kubectl apply -f - || exit 1
) &
WORKER_PIDS+=($!); WORKER_NAMES+=("vault-eso")

# Barrier: every worker must succeed before inari-server installs — the
# server requires the Keycloak issuer patch, NATS, OpenFGA, and Vault/ESO
# all in place. `wait ... ||` is safe under set -e; failures are re-raised
# here with the component name (die in the main shell, so cleanup runs).
wait_cnpg
FAILED_WORKERS=()
for i in "${!WORKER_PIDS[@]}"; do
  wait "${WORKER_PIDS[$i]}" || FAILED_WORKERS+=("${WORKER_NAMES[$i]}")
done
[ ${#FAILED_WORKERS[@]} -eq 0 ] \
  || die "component install(s) failed: ${FAILED_WORKERS[*]} (logs: kubectl -n $NAMESPACE get pods)"

log "installing inari-server chart (e2e image, cache backend: $CACHE_BACKEND)"
# The optional redis subchart must be vendored even when disabled: helm
# verifies all Chart.yaml dependencies are present in charts/ on install.
# (bitnami repo was added in the serial setup block above.)
helm dependency build "$SERVER_CHART_DIR" >/dev/null
CACHE_HELM_ARGS=()
if [ "$CACHE_BACKEND" = "redis" ]; then
  CACHE_HELM_ARGS+=(--set redis.enabled=true --set cache.backend=redis)
fi
EXTRA_ENV="[
    {\"name\":\"INARI_AGENT_GATEWAY_ADDRESS\",\"value\":\"http://$SERVER_SVC.${NAMESPACE}.svc:8080\"},
    {\"name\":\"INARI_AGENT_IMAGE_REPO\",\"value\":\"inari/agent\"},
    {\"name\":\"INARI_GIT_PROVIDER\",\"value\":\"local\"},
    {\"name\":\"INARI_GIT_LOCAL_ROOT\",\"value\":\"/var/lib/inari/git\"}"
if $INARI_HA; then
  # HA-only scaffold knobs: disruption block HA(a) drives a real scaffold
  # run to prove the claim-based reconcile loop keeps progressing work
  # after a pod loss. The templates are baked into the image at
  # /templates; the local git provider receives repos under
  # $INARI_GIT_LOCAL_ROOT/e2e-platform/. Never set in non-HA mode.
  EXTRA_ENV="$EXTRA_ENV,
    {\"name\":\"INARI_SCAFFOLD_TEMPLATE_DIR\",\"value\":\"/templates\"},
    {\"name\":\"INARI_SCAFFOLD_GIT_ORG\",\"value\":\"e2e-platform\"},
    {\"name\":\"INARI_SCAFFOLD_RECONCILE_INTERVAL\",\"value\":\"5s\"}"
fi
EXTRA_ENV="$EXTRA_ENV
  ]"
helm upgrade --install inari-server "$SERVER_CHART_DIR" \
  --namespace "$NAMESPACE" \
  --set replicaCount="$SERVER_REPLICAS" \
  --set image.repository="${SERVER_IMAGE%:*}" \
  --set image.tag="${SERVER_IMAGE##*:}" \
  --set image.pullPolicy=IfNotPresent \
  --set keycloak.baseUrl="http://$KC_FQDN" \
  --set vault.addr="http://vault.${NAMESPACE}.svc:8200" \
  --set nats.enabled=false \
  --set nats.url="nats://nats:4222" \
  --set nats.streamReplicas=3 \
  ${CACHE_HELM_ARGS[@]+"${CACHE_HELM_ARGS[@]}"} \
  --set-json "extraEnv=$EXTRA_ENV" \
  --set-json "extraVolumes=[
    {\"name\":\"git-repos\",\"hostPath\":{\"path\":\"/git\",\"type\":\"Directory\"}}
  ]" \
  --set-json "extraVolumeMounts=[
    {\"name\":\"git-repos\",\"mountPath\":\"/var/lib/inari/git\"}
  ]" \
  --wait --timeout 10m
kubectl -n "$NAMESPACE" rollout status deployment/inari-server --timeout=180s

# ---------------------------------------------------------------------------
# inari-operator + inari-console (smoke level). Both charts install alongside
# the server; the console is a stateless nginx SPA configured for the inari
# Keycloak realm, the operator reconciles platform.inari.io resources. The
# operator chart's CRDs ship as a sibling chart in the same repo and must be
# installed first. Images are the published ghcr defaults the charts pin
# (kind pulls them from ghcr.io directly; no kind load needed). Assertions
# are intentionally smoke-level (v1): releases installed, deployments
# healthy, the console route serves, and the console's runtime config points
# at the Keycloak login (the SPA redirects to Keycloak client-side via
# keycloak.js — there is no server-side 302 to assert against in the chart).
# ---------------------------------------------------------------------------
OPERATOR_CRDS_CHART_DIR="${OPERATOR_CRDS_CHART_DIR:-$OPERATOR_CHART_DIR/../inari-operator-crds}"
[ -d "$OPERATOR_CRDS_CHART_DIR" ] || die "OPERATOR_CRDS_CHART_DIR not found: $OPERATOR_CRDS_CHART_DIR"

log "installing inari-operator-crds + inari-operator charts (smoke)"
helm upgrade --install inari-operator-crds "$OPERATOR_CRDS_CHART_DIR" \
  --namespace "$NAMESPACE" \
  --wait --timeout 3m
helm upgrade --install inari-operator "$OPERATOR_CHART_DIR" \
  --namespace "$NAMESPACE" \
  --wait --timeout 5m
kubectl -n "$NAMESPACE" rollout status deployment/inari-operator --timeout=180s \
  || die "inari-operator deployment never became ready"

log "installing inari-console chart (smoke)"
helm upgrade --install inari-console "$CONSOLE_CHART_DIR" \
  --namespace "$NAMESPACE" \
  --set keycloakUrl="http://$KC_FQDN" \
  --set keycloakRealm=inari \
  --set nginx.corsOrigins="{http://$KC_FQDN}" \
  --wait --timeout 5m
kubectl -n "$NAMESPACE" rollout status deployment/inari-console --timeout=180s \
  || die "inari-console deployment never became ready"

log "verifying operator + console releases are installed and healthy"
for RELEASE in inari-operator inari-console; do
  helm list -n "$NAMESPACE" --filter "^$RELEASE\$" -q | grep -q "^$RELEASE\$" \
    || die "helm release $RELEASE missing in namespace $NAMESPACE"
done
kubectl -n "$NAMESPACE" wait --for=condition=available deployment/inari-operator --timeout=60s >/dev/null \
  || die "inari-operator deployment not available"
kubectl -n "$NAMESPACE" wait --for=condition=available deployment/inari-console --timeout=60s >/dev/null \
  || die "inari-console deployment not available"

log "verifying the console route serves and points at the Keycloak login"
CONSOLE_PID=""; CONSOLE_PORT=18080
kubectl -n "$NAMESPACE" port-forward "svc/inari-console" "$CONSOLE_PORT:80" >/dev/null 2>&1 &
CONSOLE_PID=$!
trap 'kill "$CONSOLE_PID" >/dev/null 2>&1 || true; cleanup' EXIT
sleep 2 # port-forward needs a moment before accepting connections
CONSOLE_INDEX=$(curl -sf -m 10 "http://127.0.0.1:$CONSOLE_PORT/" || true)
grep -qi "<html" <<<"$CONSOLE_INDEX" \
  || die "console route did not serve the SPA index.html (got: ${CONSOLE_INDEX:0:120})"
CONSOLE_CONFIG=$(curl -sf -m 10 "http://127.0.0.1:$CONSOLE_PORT/config.js" || true)
grep -q "keycloakUrl: \"http://$KC_FQDN\"" <<<"$CONSOLE_CONFIG" \
  || die "console config.js does not point at the Keycloak login (http://$KC_FQDN): $CONSOLE_CONFIG"
# B10 (run d701e2ba): also pin the realm, client id, and API base URL — a
# wrong value in any of them strands the SPA at login or points it at a
# dead API, and none of that is visible from the keycloakUrl grep alone.
grep -q 'keycloakRealm: "inari"' <<<"$CONSOLE_CONFIG" \
  || die "console config.js keycloakRealm is not \"inari\": $CONSOLE_CONFIG"
grep -q 'keycloakClientId: "inari-ui"' <<<"$CONSOLE_CONFIG" \
  || die "console config.js keycloakClientId is not \"inari-ui\": $CONSOLE_CONFIG"
grep -q 'apiBaseUrl: "/api/v1"' <<<"$CONSOLE_CONFIG" \
  || die "console config.js apiBaseUrl is not \"/api/v1\": $CONSOLE_CONFIG"
log "console serves the SPA and its config targets http://$KC_FQDN (realm inari, client inari-ui, api /api/v1)"

log "verifying the INARI_OUTBOX stream formed (R=3) on the external cluster"
# The server ensures the stream at boot (ADR-0014); the monitor CLI lives in
# the nats-box pod deployed with the NATS chart.
# Bounded poll: stream creation is app-level (server boot), with no k8s
# condition to wait on.
for i in $(seq 1 24); do
  STREAM=$(kubectl -n "$NAMESPACE" exec deploy/nats-box -- \
    nats stream info INARI_OUTBOX --server nats:4222 --json 2>/dev/null || true)
  if jq -e '.config.num_replicas == 3 and (.config.subjects | index("inari.outbox.>"))' \
      <<<"$STREAM" >/dev/null 2>&1; then
    break
  fi
  sleep 5
  [ "$i" = 24 ] && die "INARI_OUTBOX stream never formed at R=3 (stream info: ${STREAM:-empty})"
done

log "starting toolbox pod"
kubectl -n "$NAMESPACE" delete pod "$TOOLS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
kubectl -n "$NAMESPACE" run "$TOOLS" --image=curlimages/curl:8.10.1 --restart=Never \
  --overrides='{"spec":{"securityContext":{"runAsUser":1000}}}' --command -- sleep 3600 >/dev/null
kubectl -n "$NAMESPACE" wait --for=condition=ready "pod/$TOOLS" --timeout=120s >/dev/null

log "waiting for the Keycloak issuer to converge on the FQDN"
# Bounded poll: issuer convergence is observable only via the OIDC discovery
# document — no k8s condition exists for it.
for i in $(seq 1 24); do
  ISS=$(xcurl "http://keycloak-service:8080/realms/inari/.well-known/openid-configuration" | jq -r .issuer 2>/dev/null || true)
  [ "$ISS" = "http://$KC_FQDN/realms/inari" ] && break
  sleep 5
  [ "$i" = 24 ] && die "issuer did not converge to $KC_FQDN (got: $ISS)"
done

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

log "installing agent via the inari-agent Helm chart"
REG_TOKEN=$(jq -r '.token' <<<"$TOK_RESP")
# --namespace default: the chart renders and owns the inari-system
# Namespace itself, so the release namespace is irrelevant — but it must
# be pinned explicitly. Without it helm resolves the kubeconfig context's
# namespace, and when this script runs INSIDE a pod (KUBERNETES_SERVICE_HOST
# set, e.g. sandboxed runners) client-go falls back to the in-cluster
# serviceaccount namespace, producing "namespaces \"<pod-ns>\" not found".
# "default" is exactly what an empty context namespace yields on a normal
# runner, so CI semantics are unchanged.
# oidcSecret.remotePath: the control plane writes the OIDC client secret at
# the trimmed Vault path (secrets.ClusterOIDCPath strips the "cluster:"
# type prefix from the cluster ID).
helm upgrade --install inari-agent "$AGENT_CHART_DIR" \
  --namespace default \
  --set image.repository="${AGENT_IMAGE%:*}" \
  --set image.tag="${AGENT_IMAGE##*:}" \
  --set image.pullPolicy=IfNotPresent \
  --set config.tenantID="$ORG_ID" \
  --set config.controlPlane="http://$SERVER_SVC.${NAMESPACE}.svc:8080" \
  --set config.registrationToken="$REG_TOKEN" \
  --set config.clusterLabels="e2e=true" \
  --set oidcSecret.create=true \
  --set oidcSecret.secretStore=inari-platform \
  --set oidcSecret.remotePath="inari/clusters/${CLUSTER_ID#cluster:}/oidc-client-secret" \
  --wait --timeout 180s
# ESO wiring: the chart's opt-in ExternalSecret pulls from the
# ClusterSecretStore the registration response references
# (SecretDeliveryReference.esoSecretStore). ESO retries the ExternalSecret
# until the store exists, so this can be applied after the install.
kubectl -n inari-system create secret generic inari-vault-token \
  --from-literal=token="$VAULT_DEV_TOKEN" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: inari-platform
spec:
  provider:
    vault:
      server: http://vault.${NAMESPACE}.svc:8200
      path: secret
      version: v2
      auth:
        tokenSecretRef:
          name: inari-vault-token
          namespace: inari-system
          key: token
EOF

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
# suite (scripts/e2e/stack, `go test -tags=e2e`) — phase 1 of the shell→Go
# migration. Export the handoff the suite consumes (contract: field renames
# must land in suite/env.go too).
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
log "PASS: golden-path stack provisioned — assertions: E2E_HANDOFF_PATH=$E2E_HANDOFF_PATH go test -tags=e2e ./scripts/e2e/stack/..."
