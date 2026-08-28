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
  APP_VERSION=$(gh api repos/7K-Inari/inari-operator/contents/charts/inari-operator/Chart.yaml \
    --jq .content | base64 -d | awk '/^appVersion:/{gsub(/"/,"",$2); print $2}')
fi

# 0.0.6 was pushed only as :latest (semver-tag bug fixed in
# inari-operator#18); retag latest to the chart's appVersion.
docker pull "ghcr.io/7k-inari/inari-operator:latest"
docker tag "ghcr.io/7k-inari/inari-operator:latest" \
  "ghcr.io/7k-inari/inari-operator:${APP_VERSION}"
kind load docker-image "ghcr.io/7k-inari/inari-operator:${APP_VERSION}" --name "$CLUSTER"
