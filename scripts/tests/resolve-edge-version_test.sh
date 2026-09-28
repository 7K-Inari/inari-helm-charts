#!/usr/bin/env bash
# Tests for scripts/resolve-edge-version.sh using a fake gh on PATH.
# Run: scripts/tests/resolve-edge-version_test.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$repo_root/scripts/resolve-edge-version.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

export GITHUB_REPOSITORY="7K-Inari/test-repo"
export GITHUB_SHA="0123456789abcdef"

pass=0
fail=0
check() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL: $1 — expected '$2', got '$3'" >&2
    fail=$((fail + 1))
  fi
}

cd "$work"

# --- case 1: pending Release PR carries the next version -------------------
cat > bin/gh <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ]; then
  echo "release-please--branches--main"
elif [ "$1" = "api" ]; then
  # --jq '.content' already applied by the real gh: print raw base64.
  echo "eyJjaGFydHMvaW5hcmktc2VydmVyIjogIjAuMi4wIiwgIi4iOiAiMy4xLjAifQ=="
fi
EOF
chmod +x bin/gh
echo '{"charts/inari-server": "0.1.9", ".": "3.0.0"}' > .release-please-manifest.json
export PATH="$work/bin:$PATH"

check "pending PR version for chart path" "0.2.0-edge.0123456" \
  "$("$script" charts/inari-server)"
check "pending PR version for root component" "3.1.0-edge.0123456" \
  "$("$script" .)"
check "RAW prints base only" "0.2.0" \
  "$(RAW=1 "$script" charts/inari-server)"

# --- case 2: no Release PR -> manifest + patch -----------------------------
cat > bin/gh <<'EOF'
#!/usr/bin/env bash
exit 0  # pr list prints nothing
EOF
chmod +x bin/gh
check "fallback patch bump" "0.1.10-edge.0123456" \
  "$("$script" charts/inari-server)"
check "fallback patch bump root" "3.0.1-edge.0123456" \
  "$("$script" .)"

# --- case 3: unknown manifest path -> error --------------------------------
if "$script" charts/nope 2>/dev/null; then
  check "unknown path exits non-zero" "non-zero" "zero"
else
  check "unknown path exits non-zero" "non-zero" "non-zero"
fi

# --- case 4: no manifest (simple mode) -> latest stable tag + patch --------
rm .release-please-manifest.json
git init -q .
git config user.email t@t && git config user.name t
git commit -q --allow-empty -m init
git tag v1.2.0
git commit -q --allow-empty -m more
git tag v1.2.3
git tag v9.9.9-edge.deadbeef  # prerelease tags must be ignored
check "simple mode latest stable tag + patch" "1.2.4-edge.0123456" \
  "$("$script" .)"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
