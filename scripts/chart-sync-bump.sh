#!/usr/bin/env bash
# chart-sync-bump.sh — bump charts/<chart>/Chart.yaml appVersion (and, for
# inari-console, values.yaml bundle.tag) to <version>. Idempotent: a no-op
# when appVersion already equals <version>.
#
# Usage: scripts/chart-sync-bump.sh <chart> <version>   (run from repo root)
#   <chart>    inari-server or inari-console
#   <version>  X.Y.Z (a leading "v" is stripped)
#
# Prints "changed=true|false"; also appends changed=... to $GITHUB_OUTPUT
# when that variable is set (GitHub Actions).
set -euo pipefail

chart="${1:?usage: chart-sync-bump.sh <chart> <version>}"
version="${2:?usage: chart-sync-bump.sh <chart> <version>}"
version="${version#v}"

report() {
  echo "changed=$1"
  [ -n "${GITHUB_OUTPUT:-}" ] && echo "changed=$1" >> "$GITHUB_OUTPUT"
}

case "$chart" in
  inari-server|inari-console) ;;
  *) echo "chart-sync-bump: unknown chart '$chart' (expected inari-server or inari-console)" >&2; exit 1 ;;
esac
echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || { echo "chart-sync-bump: bad version '$version' (expected X.Y.Z)" >&2; exit 1; }

chart_yaml="charts/$chart/Chart.yaml"
[ -f "$chart_yaml" ] || { echo "chart-sync-bump: no Chart.yaml at charts/$chart" >&2; exit 1; }

current="$(grep -E '^appVersion:' "$chart_yaml" | awk '{print $2}' | tr -d '"')"
if [ "$current" = "$version" ]; then
  echo "appVersion already $version — no-op"
  report false
  exit 0
fi

sed -i "s/^appVersion:.*/appVersion: $version/" "$chart_yaml"
if [ "$chart" = "inari-console" ]; then
  # Keep the bundle tag pinned to the same UI release.
  sed -i "/^bundle:/,/^[a-z]/ s/^  tag:.*/  tag: $version/" charts/inari-console/values.yaml
fi
report true
