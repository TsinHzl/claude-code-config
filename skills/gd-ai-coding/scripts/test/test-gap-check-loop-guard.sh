#!/usr/bin/env bash
# test-gap-check-loop-guard.sh — gap-check-loop-guard.sh 计数递增/重置/超限三种路径
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/.."
GUARD="$SCRIPTS_DIR/checks/gap-check-loop-guard.sh"
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

mkdir -p "$TEST_DIR/.dac"
cat > "$TEST_DIR/.dac/state.json" <<'EOF'
{"req_name": "test-req", "phase": "proposal-approved"}
EOF

cd "$TEST_DIR"

# ── increment：从 0 递增到 1 ──
out=$(bash "$GUARD" increment)
code=$?
assert_eq "increment 首次返回 1" "1" "$out"
assert_eq "increment 首次 exit 0（未超限）" "0" "$code"
assert_eq "state.json 持久化 attempt_count=1" "1" "$(jq -r '.gap_check.attempt_count' .dac/state.json)"

# ── 连续 increment 到第 5 轮，仍未超限 ──
for _ in 1 2 3 4; do bash "$GUARD" increment >/dev/null; done
out=$(jq -r '.gap_check.attempt_count' .dac/state.json)
assert_eq "连续 increment 后计数为 5" "5" "$out"

set +e
bash "$GUARD" is_exceeded >/dev/null
code=$?
set -e
assert_eq "第 5 轮 is_exceeded exit 0（未超限）" "0" "$code"

# ── 第 6 轮 increment：应超限，exit 2 ──
set +e
bash "$GUARD" increment >/dev/null
code=$?
set -e
assert_eq "第 6 轮 increment exit 2（超限）" "2" "$code"

set +e
bash "$GUARD" is_exceeded >/dev/null
code=$?
set -e
assert_eq "第 6 轮 is_exceeded exit 2（超限）" "2" "$code"

# ── reset：计数归零 ──
bash "$GUARD" reset >/dev/null
assert_eq "reset 后 attempt_count=0" "0" "$(jq -r '.gap_check.attempt_count' .dac/state.json)"

set +e
bash "$GUARD" is_exceeded >/dev/null
code=$?
set -e
assert_eq "reset 后 is_exceeded exit 0" "0" "$code"

echo ""
echo "通过: $PASS / 失败: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
