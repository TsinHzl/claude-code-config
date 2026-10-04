#!/usr/bin/env bash
# test-test-verify-loop-guard.sh — test-verify-loop-guard.sh 计数递增/重置/超限三种路径
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/.."
GUARD="$SCRIPTS_DIR/checks/test-verify-loop-guard.sh"
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
{"req_name": "test-req", "phase": "feature-loop"}
EOF

cd "$TEST_DIR"

FEAT_A="feat-a"

# ── increment：从 0 递增到 1 ──
out=$(bash "$GUARD" increment "$FEAT_A")
code=$?
assert_eq "increment 首次返回 1" "1" "$out"
assert_eq "increment 首次 exit 0（未超限）" "0" "$code"
assert_eq "state.json 持久化 attempt_count=1" "1" "$(jq -r '.test_verify.attempt_count' .dac/state.json)"
assert_eq "state.json 持久化 feat_id" "$FEAT_A" "$(jq -r '.test_verify.feat_id' .dac/state.json)"

# ── 第 2 轮 increment：计数为 2，仍未超限 ──
set +e
out=$(bash "$GUARD" increment "$FEAT_A")
code=$?
set -e
assert_eq "第 2 轮 increment 返回 2" "2" "$out"
assert_eq "第 2 轮 increment exit 0（未超限）" "0" "$code"

set +e
bash "$GUARD" is_exceeded "$FEAT_A" >/dev/null
code=$?
set -e
assert_eq "第 2 轮 is_exceeded exit 0（未超限）" "0" "$code"

# ── 第 3 轮 increment：计数达到 3，应超限，exit 2，且 feature 状态被置为 failed ──
set +e
out=$(bash "$GUARD" increment "$FEAT_A")
code=$?
set -e
assert_eq "第 3 轮 increment 返回 3" "3" "$out"
assert_eq "第 3 轮 increment exit 2（超限）" "2" "$code"
assert_eq "超限后 skipped_features 记录 feat-a" "$FEAT_A" "$(jq -r '.skipped_features[0] // empty' .dac/state.json)"

set +e
bash "$GUARD" is_exceeded "$FEAT_A" >/dev/null
code=$?
set -e
assert_eq "第 3 轮 is_exceeded exit 2（超限）" "2" "$code"

# ── reset：计数归零 ──
bash "$GUARD" reset "$FEAT_A" >/dev/null
assert_eq "reset 后 attempt_count=0" "0" "$(jq -r '.test_verify.attempt_count' .dac/state.json)"

set +e
bash "$GUARD" is_exceeded "$FEAT_A" >/dev/null
code=$?
set -e
assert_eq "reset 后 is_exceeded exit 0" "0" "$code"

# ── 切换到不同 feat_id：计数自动归零（不沿用上一个 feature 的历史计数） ──
FEAT_B="feat-b"
bash "$GUARD" increment "$FEAT_A" >/dev/null
bash "$GUARD" increment "$FEAT_A" >/dev/null
out=$(bash "$GUARD" increment "$FEAT_B")
assert_eq "切换 feat_id 后 increment 从 1 开始" "1" "$out"

echo ""
echo "通过: $PASS / 失败: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
