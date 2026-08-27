#!/usr/bin/env bash
# Installs the cluster operators the inari-platform chart assumes:
# CloudNativePG (CNPG) and the Keycloak operator, incl. their CRDs.
# The chart never installs operators itself — this script is the day-0
# prerequisite step for clusters that don't have them yet. Idempotent.
set -euo pipefail

# The chart requires CNPG >= 1.25 (declarative managed roles + Database CRs).
CNPG_VERSION="${CNPG_VERSION:-0.29.0}"
KC_VERSION="${KC_VERSION:-26.3.2}"

log() { printf '\033[1;34m[operators]\033[0m %s\n' "$*"; }

command -v kubectl >/dev/null || { echo "kubectl required" >&2; exit 1; }

# --- CloudNativePG operator ---
if kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1; then
  log "CNPG operator CRDs present — skipping"
else
  log "installing CNPG operator $CNPG_VERSION"
  command -v helm >/dev/null || { echo "helm required for the CNPG operator" >&2; exit 1; }
  helm repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null
  helm repo update cnpg >/dev/null
  helm upgrade --install cnpg cnpg/cloudnative-pg \
    --version "$CNPG_VERSION" \
    --namespace cnpg-system --create-namespace --wait --timeout 5m
fi

# --- Keycloak operator (CRDs + deployment) ---
if kubectl get crd keycloaks.k8s.keycloak.org >/dev/null 2>&1; then
  log "Keycloak operator CRDs present — skipping"
else
  log "installing Keycloak operator $KC_VERSION"
  BASE="https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/$KC_VERSION/kubernetes"
  # the upstream manifests reference the 'keycloak' namespace but never create it
  kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "$BASE/keycloaks.k8s.keycloak.org-v1.yml"
  kubectl apply -f "$BASE/keycloakrealmimports.k8s.keycloak.org-v1.yml"
  # the operator Deployment carries no namespace in the upstream manifest —
  # apply it into 'keycloak' explicitly
  kubectl -n keycloak apply -f "$BASE/kubernetes.yml"

  # The upstream manifest is namespace-scoped: the operator only watches its
  # install namespace, but the chart renders Keycloak/KeycloakRealmImport CRs
  # into the release namespace. Widen it to cluster-wide (mirroring upstream's
  # cluster-wide kustomization, which only exists for >= 26.7):
  # ClusterRoleBindings for the two controller ClusterRoles, plus the
  # pod/configmap permissions the namespaced Role only grants locally.
  kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: keycloak-operator-cluster-wide
  labels:
    app.kubernetes.io/name: keycloak-operator
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: keycloakrealmimportcontroller-cluster-role-binding
  labels:
    app.kubernetes.io/name: keycloak-operator
roleRef:
  kind: ClusterRole
  apiGroup: rbac.authorization.k8s.io
  name: keycloakrealmimportcontroller-cluster-role
subjects:
  - kind: ServiceAccount
    name: keycloak-operator
    namespace: keycloak
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: keycloakcontroller-cluster-role-binding
  labels:
    app.kubernetes.io/name: keycloak-operator
roleRef:
  kind: ClusterRole
  apiGroup: rbac.authorization.k8s.io
  name: keycloakcontroller-cluster-role
subjects:
  - kind: ServiceAccount
    name: keycloak-operator
    namespace: keycloak
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: keycloak-operator-cluster-wide-binding
  labels:
    app.kubernetes.io/name: keycloak-operator
roleRef:
  kind: ClusterRole
  apiGroup: rbac.authorization.k8s.io
  name: keycloak-operator-cluster-wide
subjects:
  - kind: ServiceAccount
    name: keycloak-operator
    namespace: keycloak
EOF
  # JOSDK_ALL_NAMESPACES: reconcile Keycloak/KeycloakRealmImport CRs in every
  # namespace instead of only the operator's own.
  kubectl -n keycloak patch deployment keycloak-operator --type=strategic -p '
spec:
  template:
    spec:
      containers:
        - name: keycloak-operator
          env:
            - name: QUARKUS_OPERATOR_SDK_CONTROLLERS_KEYCLOAKREALMIMPORTCONTROLLER_NAMESPACES
              value: JOSDK_ALL_NAMESPACES
            - name: QUARKUS_OPERATOR_SDK_CONTROLLERS_KEYCLOAKCONTROLLER_NAMESPACES
              value: JOSDK_ALL_NAMESPACES
'
  kubectl -n keycloak rollout status deployment/keycloak-operator --timeout=300s
fi

log "operators ready"
