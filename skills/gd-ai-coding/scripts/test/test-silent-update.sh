#!/usr/bin/env bash
# test-silent-update.sh — Codex source marker 与 dry-run 自动更新回归
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
UPDATE_SCRIPT="$ROOT_DIR/scripts/maintenance/silent-update.sh"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
PASS=0
FAIL=0

assert_eq() {
  local description="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  ✓ %s\n' "$description"
    PASS=$((PASS + 1))
  else
    printf '  ✗ %s (expected %s, got %s)\n' "$description" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_dry_run_has_no_side_effects() {
  local scenario="$1"
  assert_eq "$scenario 不创建 Claude 目录" false "$(test -e "$HOME_DIR/.claude" && printf true || printf false)"
  assert_eq "$scenario 不创建日志目录" false "$(test -e "$HOME_DIR/Library" && printf true || printf false)"
  assert_eq "$scenario 不创建自动更新状态目录" false "$(test -e "$STATE_HOME/auto-update" && printf true || printf false)"
}

HOME_DIR="$TEST_DIR/home"
SKILL_HOME="$HOME_DIR/.codex/skills/gd-ai-coding"
STATE_HOME="$SKILL_HOME/state"
CONFIG_HOME="$HOME_DIR/.codex/skills/dashboard"
REPO_DIR="$TEST_DIR/source-repo"
mkdir -p "$SKILL_HOME" "$STATE_HOME" "$CONFIG_HOME" "$REPO_DIR"
printf '%s' "$REPO_DIR" > "$SKILL_HOME/.source-repo-path"

set +e
env HOME="$HOME_DIR" DAC_RUNTIME=codex DAC_SKILL_HOME="$SKILL_HOME" \
  DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" \
  bash "$UPDATE_SCRIPT" --dry-run >/dev/null 2>&1
STATUS=$?
set -e

printf '═══ test-silent-update.sh ═══\n\n'
assert_eq 'Codex marker dry-run 退出 0' 0 "$STATUS"
assert_dry_run_has_no_side_effects '有效 marker 的 dry-run'

rm -f "$SKILL_HOME/.source-repo-path"
set +e
env HOME="$HOME_DIR" DAC_RUNTIME=codex DAC_SKILL_HOME="$SKILL_HOME" \
  DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" \
  bash "$UPDATE_SCRIPT" --dry-run >/dev/null 2>&1
STATUS=$?
set -e
assert_eq '缺失 marker 的 dry-run 静默退出 0' 0 "$STATUS"
assert_dry_run_has_no_side_effects '缺失 marker 的 dry-run'

printf '%s' "$TEST_DIR/missing-repo" > "$SKILL_HOME/.source-repo-path"
set +e
env HOME="$HOME_DIR" DAC_RUNTIME=codex DAC_SKILL_HOME="$SKILL_HOME" \
  DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" \
  bash "$UPDATE_SCRIPT" --dry-run >/dev/null 2>&1
STATUS=$?
set -e
assert_eq '无效 marker 的 dry-run 静默退出 0' 0 "$STATUS"
assert_dry_run_has_no_side_effects '无效 marker 的 dry-run'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
