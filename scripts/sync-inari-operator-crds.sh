#!/usr/bin/env bash
# Sync inari-operator CRDs from the operator repository into the platform chart.
#
# Usage:
#   scripts/sync-inari-operator-crds.sh [ref] [--check]
#
#   ref      Git ref to sync from (default: main)
#   --check  Exit with error if the vendored CRDs differ from the operator repo.
#            Use this in CI to prevent drift.

set -euo pipefail

REPO="https://github.com/7k-inari/inari-operator.git"
REF="main"
CHECK=false

for arg in "$@"; do
  case "$arg" in
    --check)
      CHECK=true
      ;;
    *)
      REF="$arg"
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${SCRIPT_DIR}/../charts/inari-platform"
OUT_FILE="${CHART_DIR}/templates/crds/inari-operator.yaml"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Fetching inari-operator CRDs from ${REPO} @ ${REF} ..."
git clone --depth 1 --branch "${REF}" "${REPO}" "${TMP_DIR}/operator" >/dev/null 2>&1

CRD_DIR="${TMP_DIR}/operator/config/crd/bases"
if [[ ! -d "${CRD_DIR}" ]]; then
  echo "ERROR: ${CRD_DIR} not found" >&2
  exit 1
fi

{
  echo '{{- if .Values.crds.inariOperator.enabled }}'
  # Sort files for deterministic output.
  for f in $(ls "${CRD_DIR}"/*.yaml | sort); do
    cat "$f"
    echo
  done
  echo '{{- end }}'
} > "${TMP_DIR}/inari-operator-crds.yaml"

if [[ "${CHECK}" == "true" ]]; then
  if ! diff -q "${OUT_FILE}" "${TMP_DIR}/inari-operator-crds.yaml" >/dev/null 2>&1; then
    echo "ERROR: vendored inari-operator CRDs are out of sync with ${REPO} @ ${REF}" >&2
    echo "Run 'scripts/sync-inari-operator-crds.sh' to update them." >&2
    exit 1
  fi
  echo "CRDs are in sync."
else
  cp "${TMP_DIR}/inari-operator-crds.yaml" "${OUT_FILE}"
  echo "Updated ${OUT_FILE} from ${REPO} @ ${REF}"
fi
