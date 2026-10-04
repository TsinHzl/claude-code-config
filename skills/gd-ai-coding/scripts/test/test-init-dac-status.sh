#!/usr/bin/env bash
# test-init-dac-status.sh — init-dac.sh --status / leftover-dir init
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_DAC="$SCRIPT_DIR/../init-dac.sh"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

status_field() {
  bash "$INIT_DAC" --status | jq -r "$1"
}

echo "═══ test-init-dac-status.sh ═══"
echo ""
cd "$TEST_DIR"
git init -q
git config user.email "test@example.com"
git config user.name "test"

# ── Test 1: no .dac ──────────────────────────────────────────────────────────
echo "Test 1: no .dac directory"
assert_eq "exists=false" "false" "$(status_field '.exists')"
assert_eq "resumable=false" "false" "$(status_field '.resumable')"
assert_eq "no phase field" "null" "$(status_field '.phase')"

# ── Test 2: leftover empty .dac/ (user deleted contents) ─────────────────────
echo "Test 2: leftover empty .dac/"
mkdir -p .dac
assert_eq "empty dir exists=false" "false" "$(status_field '.exists')"
assert_eq "empty dir resumable=false" "false" "$(status_field '.resumable')"
assert_eq "empty dir no phase" "null" "$(status_field '.phase')"

# ── Test 3: leftover .dac/ without state.json ────────────────────────────────
echo "Test 3: leftover .dac/ with knowledge, no state.json"
mkdir -p .dac/knowledge .dac/logs
echo "# leftover" > .dac/knowledge/constraints.md
assert_eq "no state.json exists=false" "false" "$(status_field '.exists')"
assert_eq "no state.json resumable=false" "false" "$(status_field '.resumable')"
assert_eq "no state.json no phase=unknown" "true" "$(bash "$INIT_DAC" --status | jq -r '.phase != "unknown"')"

# ── Test 4: valid in-progress state ──────────────────────────────────────────
echo "Test 4: valid feature-loop state.json"
cat > .dac/state.json <<'EOF'
{"phase": "feature-loop", "req_name": "demo"}
EOF
assert_eq "valid exists=true" "true" "$(status_field '.exists')"
assert_eq "valid resumable=true" "true" "$(status_field '.resumable')"
assert_eq "valid phase" "feature-loop" "$(status_field '.phase')"
assert_eq "valid req_name preserved" "demo" "$(status_field '.req_name')"

# ── Test 5: done is resumable (completed branch, not fresh init) ─────────────
echo "Test 5: phase=done is resumable"
cat > .dac/state.json <<'EOF'
{"phase": "done", "req_name": "demo"}
EOF
assert_eq "done resumable=true" "true" "$(status_field '.resumable')"
assert_eq "done phase" "done" "$(status_field '.phase')"

# ── Test 6: garbage phase is not resumable ───────────────────────────────────
echo "Test 6: unknown/garbage phase"
cat > .dac/state.json <<'EOF'
{"phase": "unknown", "req_name": "demo"}
EOF
assert_eq "garbage phase exists=true" "true" "$(status_field '.exists')"
assert_eq "garbage phase resumable=false" "false" "$(status_field '.resumable')"

# ── Test 7: malformed JSON ───────────────────────────────────────────────────
echo "Test 7: malformed state.json"
echo '{not json' > .dac/state.json
assert_eq "malformed exists=false" "false" "$(status_field '.exists')"
assert_eq "malformed resumable=false" "false" "$(status_field '.resumable')"

# ── Test 8: leftover dir without state.json → default init does not error ────
echo "Test 8: leftover dir is treated as uninitialized"
rm -rf .dac
mkdir -p .dac/logs
if bash "$INIT_DAC" >/tmp/dac-init-out.$$ 2>/tmp/dac-init-err.$$; then
  assert_eq "leftover init exit 0" "0" "0"
  assert_eq "leftover init wrote state.json" "true" "$([ -f .dac/state.json ] && echo true || echo false)"
  assert_eq "new state is resumable" "true" "$(status_field '.resumable')"
else
  echo "  ✗ leftover init should succeed"
  echo "    stderr: $(cat /tmp/dac-init-err.$$)"
  FAIL=$((FAIL + 1))
fi
rm -f /tmp/dac-init-out.$$ /tmp/dac-init-err.$$

# ── Test 9: existing valid state.json → default init errors ──────────────────
echo "Test 9: valid .dac blocks default init"
set +e
bash "$INIT_DAC" >/dev/null 2>/tmp/dac-init-err.$$
_rc=$?
set -e
assert_eq "valid dir init exit 1" "1" "$_rc"
assert_eq "error mentions --force/--resume" "true" \
  "$(grep -q -- '--force' /tmp/dac-init-err.$$ && echo true || echo false)"
rm -f /tmp/dac-init-err.$$

echo ""
# ── Test 10: garbage phase → default init does not error ─────────────────────
echo "Test 10: garbage phase is treated as uninitialized"
cat > .dac/state.json <<'EOF'
{"phase": "unknown"}
EOF
if bash "$INIT_DAC" >/tmp/dac-init-out.$$ 2>/tmp/dac-init-err.$$; then
  assert_eq "garbage phase init exit 0" "0" "0"
  assert_eq "garbage phase init wrote valid state" "true" "$(status_field '.resumable')"
  assert_eq "garbage phase replaced" "init" "$(status_field '.phase')"
else
  echo "  ✗ garbage phase init should succeed"
  echo "    stderr: $(cat /tmp/dac-init-err.$$)"
  FAIL=$((FAIL + 1))
fi
rm -f /tmp/dac-init-out.$$ /tmp/dac-init-err.$$

echo ""
echo "═══ $PASS passed, $FAIL failed ═══"
[[ "$FAIL" -eq 0 ]]
