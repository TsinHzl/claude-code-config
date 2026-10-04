#!/usr/bin/env bash
# test-uninstall-codex-hooks.sh — Codex Hook 卸载无损与故障恢复契约
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL="$ROOT_DIR/scripts/metrics/install-codex-hooks.sh"
UNINSTALL="$ROOT_DIR/scripts/metrics/uninstall-codex-hooks.sh"
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

run_install() { bash "$INSTALL" --config "$1" --skill-home "$2" >/dev/null 2>&1; }
run_uninstall() { bash "$UNINSTALL" --config "$1" --skill-home "$2" >/dev/null 2>&1; }

printf '═══ test-uninstall-codex-hooks.sh ═══\n\n'

CONFIG="$TEST_DIR/hooks.json"
SKILL_HOME="$TEST_DIR/.codex/skills/gd-ai-coding"
printf '{"hooks":{"PreToolUse":[{"_source":"third-party","matcher":"apply_patch","hooks":[{"type":"command","command":"third-pre"}]}],"PostToolUse":[]}}\n' > "$CONFIG"
run_install "$CONFIG" "$SKILL_HOME"
assert_eq '安装 fixture 成功' 0 "$?"
run_uninstall "$CONFIG" "$SKILL_HOME"
assert_eq '卸载成功' 0 "$?"
assert_eq 'PreToolUse 仅保留第三方条目' 1 "$(jq '.hooks.PreToolUse | length' "$CONFIG")"
assert_eq '第三方条目未改变' third-pre "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$CONFIG")"
assert_eq 'PostToolUse 空事件节点保留' true "$(jq -e '.hooks.PostToolUse == []' "$CONFIG" >/dev/null && printf true || printf false)"
assert_eq '已卸载后重复执行安全' 0 "$(run_uninstall "$CONFIG" "$SKILL_HOME"; printf '%s' "$?")"

run_install "$CONFIG" "$SKILL_HOME"
cp "$CONFIG" "$TEST_DIR/before-fault.json"
DAC_HOOKS_FAIL_AFTER_WRITE=1 run_uninstall "$CONFIG" "$SKILL_HOME"
assert_eq '故障注入退出 1' 1 "$?"
assert_eq '故障注入保留卸载前配置' 0 "$(cmp -s "$TEST_DIR/before-fault.json" "$CONFIG"; printf '%s' "$?")"

NO_DAC_CONFIG="$TEST_DIR/no-dac.json"
printf '{"hooks":{"UserPromptSubmit":[]}}\n' > "$NO_DAC_CONFIG"
cp "$NO_DAC_CONFIG" "$TEST_DIR/no-dac-before.json"
run_uninstall "$NO_DAC_CONFIG" "$SKILL_HOME"
assert_eq '不存在 DAC Hook 时卸载成功' 0 "$?"
assert_eq '不存在 DAC Hook 时不新增事件节点' 0 "$(cmp -s "$TEST_DIR/no-dac-before.json" "$NO_DAC_CONFIG"; printf '%s' "$?")"

EXTRA_CONFIG="$TEST_DIR/extra.json"
printf '{"hooks":{"PreToolUse":[{"_source":"gd-ai-coding","matcher":"apply_patch","enabled":true,"hooks":[{"type":"command","command":"bad"}]}]}}\n' > "$EXTRA_CONFIG"
cp "$EXTRA_CONFIG" "$TEST_DIR/extra-before.json"
run_uninstall "$EXTRA_CONFIG" "$SKILL_HOME"
assert_eq '带额外字段的 DAC 标记拒绝卸载' 1 "$?"
assert_eq '带额外字段的 DAC 标记保持配置不变' 0 "$(cmp -s "$TEST_DIR/extra-before.json" "$EXTRA_CONFIG"; printf '%s' "$?")"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
