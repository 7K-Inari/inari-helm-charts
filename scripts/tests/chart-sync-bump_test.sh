#!/usr/bin/env bash
# Tests for scripts/chart-sync-bump.sh against fixture charts in a temp dir.
# Run: scripts/tests/chart-sync-bump_test.sh
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$repo_root/scripts/chart-sync-bump.sh"
pass=0
fail=0

check() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $1 — expected [$2], got [$3]" >&2
  fi
}

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/charts/inari-server" "$sandbox/charts/inari-console"

cat > "$sandbox/charts/inari-server/Chart.yaml" <<'EOF'
apiVersion: v2
name: inari-server
version: 0.1.9  # x-release-please-version
appVersion: 3.0.0
EOF

cat > "$sandbox/charts/inari-console/Chart.yaml" <<'EOF'
apiVersion: v2
name: inari-console
version: 0.3.1  # x-release-please-version
appVersion: 2.0.0
EOF

cat > "$sandbox/charts/inari-console/values.yaml" <<'EOF'
replicaCount: 2
bundle:
  repository: ghcr.io/7k-inari/inari-ui-bundle
  tag: 2.0.0
keycloakUrl: http://localhost:8080
image:
  tag: should-not-change
EOF

cd "$sandbox"

# --- case 1: bump server appVersion ----------------------------------------
out="$(bash "$script" inari-server 3.1.0)"
check "server bump reports changed" "changed=true" "$(echo "$out" | tail -1)"
check "server appVersion bumped" "appVersion: 3.1.0" "$(grep '^appVersion:' charts/inari-server/Chart.yaml)"
check "server chart version untouched" "version: 0.1.9  # x-release-please-version" "$(grep '^version:' charts/inari-server/Chart.yaml)"

# --- case 2: idempotent no-op ----------------------------------------------
out="$(bash "$script" inari-server 3.1.0)"
check "no-op reports unchanged" "changed=false" "$(echo "$out" | tail -1)"

# --- case 3: console bumps appVersion AND bundle.tag only -------------------
out="$(bash "$script" inari-console v2.5.0)"
check "console bump reports changed" "changed=true" "$(echo "$out" | tail -1)"
check "console appVersion bumped (v stripped)" "appVersion: 2.5.0" "$(grep '^appVersion:' charts/inari-console/Chart.yaml)"
check "console bundle.tag bumped" "  tag: 2.5.0" "$(sed -n '/^bundle:/,/^[a-z]/p' charts/inari-console/values.yaml | grep '^  tag:')"
check "console image.tag untouched" "  tag: should-not-change" "$(grep -A1 '^image:' charts/inari-console/values.yaml | grep 'tag:')"

# --- case 4: unknown chart rejected -----------------------------------------
bash "$script" inari-platform 1.0.0 2>/dev/null
check "unknown chart exits 1" "1" "$?"

# --- case 5: bad version rejected -------------------------------------------
bash "$script" inari-server 3.1 2>/dev/null
check "bad version exits 1" "1" "$?"
bash "$script" inari-server '3.1.0; rm -rf /' 2>/dev/null
check "injection-ish version exits 1" "1" "$?"

# --- case 6: missing Chart.yaml rejected ------------------------------------
mkdir -p "$sandbox/empty" && cd "$sandbox/empty"
bash "$script" inari-server 3.1.0 2>/dev/null
check "missing Chart.yaml exits 1" "1" "$?"
cd "$sandbox"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
