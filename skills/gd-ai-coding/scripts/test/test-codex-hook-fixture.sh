#!/usr/bin/env bash
# test-codex-hook-fixture.sh — Codex 0.153.4 Hook fixture 契约校验
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/metrics/validate-codex-hook-fixture.sh"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/codex-hooks"
VALID_FIXTURE="$FIXTURE_DIR/codex-0.153.4-apply-patch.json"
INVALID_FIXTURE="$FIXTURE_DIR/codex-0.153.4-unpaired.json"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
COLLISION_FIXTURE="$TEST_DIR/codex-0.153.4-key-collision.json"
DUPLICATE_FILES_FIXTURE="$TEST_DIR/codex-0.153.4-duplicate-files.json"

jq '.contract.affected_files += [.contract.affected_files[0]]' "$VALID_FIXTURE" > "$DUPLICATE_FILES_FIXTURE"

jq '
  .contract.event_key = {session_id: "a/b", turn_id: "c", tool_use_id: "d"}
  | .pre_tool_use.session_id = "a/b"
  | .pre_tool_use.turn_id = "c"
  | .pre_tool_use.tool_use_id = "d"
  | .post_tool_use.session_id = "a"
  | .post_tool_use.turn_id = "b/c"
  | .post_tool_use.tool_use_id = "d"
' "$VALID_FIXTURE" > "$COLLISION_FIXTURE"

PASS=0
FAIL=0

assert_exit() {
  local description="$1" expected="$2"
  shift 2
  "$@" >/dev/null 2>&1
  local actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    printf '  ✓ %s\n' "$description"
    PASS=$((PASS + 1))
  else
    printf '  ✗ %s (expected %s, got %s)\n' "$description" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

printf '═══ test-codex-hook-fixture.sh ═══\n\n'
assert_exit '真实脱敏 apply_patch fixture 通过' 0 "$VALIDATOR" "$VALID_FIXTURE"
assert_exit '无法配对的 Hook 事件退出 1' 1 "$VALIDATOR" "$INVALID_FIXTURE"
assert_exit '分隔符碰撞的不同事件三元组退出 1' 1 "$VALIDATOR" "$COLLISION_FIXTURE"
assert_exit '重复声明受影响文件退出 1' 1 "$VALIDATOR" "$DUPLICATE_FILES_FIXTURE"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
