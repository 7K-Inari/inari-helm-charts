#!/usr/bin/env bash
# Side-loads the private inari-operator image into a kind cluster. The image
# package on ghcr is not public, so anonymous pulls inside kind fail; the
# chart's pullPolicy is IfNotPresent, so a pre-loaded image is used as-is.
#
# Usage: scripts/preload-operator-image.sh <kind-cluster-name>
# Requires: GHCR_TOKEN (read:packages on ghcr), GH_TOKEN for gh api.
set -euo pipefail

CLUSTER="${1:?kind cluster name required}"
: "${GHCR_TOKEN:?GHCR_TOKEN (read:packages) required}"

echo "$GHCR_TOKEN" | docker login ghcr.io -u "${GHCR_USERNAME:-github}" --password-stdin

APP_VERSION="${OPERATOR_IMAGE_TAG:-}"
if [[ -z "$APP_VERSION" ]]; then
  # Read appVersion from the PUBLISHED chart (the one the ArgoCD Application
  # pins), not the repo working tree — the tree drifts ahead between
  # releases and would side-load a tag the deployed chart never references.
  CHART_REPO="${OPERATOR_CHART_REPO:-7k-inari/charts/inari-operator}"
  CHART_VERSION="${OPERATOR_CHART_VERSION:-0.1.1}"
  OCI_TOKEN=$(curl -sf "https://ghcr.io/token?scope=repository:${CHART_REPO}:pull" | jq -r .token)
  CONFIG_DIGEST=$(curl -sf -H "Authorization: Bearer $OCI_TOKEN" \
    -H "Accept: application/vnd.oci.image.manifest.v1+json" \
    "https://ghcr.io/v2/${CHART_REPO}/manifests/${CHART_VERSION}" | jq -r .config.digest)
  APP_VERSION=$(curl -sfL -H "Authorization: Bearer $OCI_TOKEN" \
    "https://ghcr.io/v2/${CHART_REPO}/blobs/${CONFIG_DIGEST}" | jq -r .appVersion)
fi

# 0.0.6 was pushed only as :latest (semver-tag bug fixed in
# inari-operator#18); retag latest to the chart's appVersion.
docker pull "ghcr.io/7k-inari/inari-operator:latest"
docker tag "ghcr.io/7k-inari/inari-operator:latest" \
  "ghcr.io/7k-inari/inari-operator:${APP_VERSION}"
kind load docker-image "ghcr.io/7k-inari/inari-operator:${APP_VERSION}" --name "$CLUSTER"
