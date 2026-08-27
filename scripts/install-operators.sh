#!/usr/bin/env bash
# Installs the cluster operators the inari-platform chart assumes:
# CloudNativePG (CNPG) and the Keycloak operator, incl. their CRDs.
# The chart never installs operators itself — this script is the day-0
# prerequisite step for clusters that don't have them yet. Idempotent.
set -euo pipefail

CNPG_VERSION="${CNPG_VERSION:-0.22.1}"
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
  kubectl apply -f "$BASE/kubernetes.yml"
  kubectl -n keycloak rollout status deployment/keycloak-operator --timeout=300s
fi

log "operators ready"
