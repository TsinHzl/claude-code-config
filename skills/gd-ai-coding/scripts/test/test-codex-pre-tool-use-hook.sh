#!/usr/bin/env bash
# test-codex-pre-tool-use-hook.sh — PreToolUse 事件快照与幂等降级
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT_DIR/scripts/metrics/codex-pre-tool-use-hook.sh"
FIXTURE="$ROOT_DIR/scripts/test/fixtures/codex-hooks/codex-0.153.4-apply-patch.json"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
PASS=0
FAIL=0

assert_eq() {
  local description="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then printf '  ✓ %s\n' "$description"; PASS=$((PASS+1));
  else printf '  ✗ %s (expected %s, got %s)\n' "$description" "$expected" "$actual"; FAIL=$((FAIL+1)); fi
}

printf '═══ test-codex-pre-tool-use-hook.sh ═══\n\n'
REPO="$TEST_DIR/repo"
mkdir -p "$REPO/lib" "$TEST_DIR/home/.codex/skills/gd-ai-coding/state"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
printf 'before\n' > "$REPO/lib/example.dart"
git -C "$REPO" add . && git -C "$REPO" commit -qm initial
INPUT=$(jq --arg cwd "$REPO" '.pre_tool_use | .cwd=$cwd | .tool_input.command |= gsub("/tmp/dac-codex-fixture-repo"; $cwd)' "$FIXTURE")
HOME="$TEST_DIR/home" DAC_RUNTIME=codex DAC_SKILL_HOME="$TEST_DIR/home/.codex/skills/gd-ai-coding" DAC_STATE_HOME="$TEST_DIR/home/.codex/skills/gd-ai-coding/state" DAC_CONFIG_HOME="$TEST_DIR/home/.codex/skills/dashboard" bash "$HOOK" <<<"$INPUT"
SNAPSHOT_ROOT="$TEST_DIR/home/.codex/skills/gd-ai-coding/state/codex-hook-snapshots/v1"
SNAPSHOT=$(find "$SNAPSHOT_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n 1)
assert_eq '有效事件创建快照' true "$(test -f "$SNAPSHOT/meta.json" && printf true || printf false)"
assert_eq '快照保留事件三元组' fixture-tool-use "$(jq -r '.event.tool_use_id' "$SNAPSHOT/meta.json")"
assert_eq '快照保存变更前内容' before "$(tr -d '\n' < "$SNAPSHOT/files/000001.before")"
assert_eq '快照目录权限为 0700' 700 "$(stat -f '%Lp' "$SNAPSHOT")"
assert_eq '快照文件权限为 0600' 600 "$(stat -f '%Lp' "$SNAPSHOT/files/000001.before")"
HOME="$TEST_DIR/home" DAC_RUNTIME=codex DAC_SKILL_HOME="$TEST_DIR/home/.codex/skills/gd-ai-coding" DAC_STATE_HOME="$TEST_DIR/home/.codex/skills/gd-ai-coding/state" DAC_CONFIG_HOME="$TEST_DIR/home/.codex/skills/dashboard" bash "$HOOK" <<<"$INPUT"
assert_eq '重复 Pre 不覆盖快照' 1 "$(find "$SNAPSHOT_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
UNKNOWN=$(jq '.pre_tool_use | .tool_name="unknown"' "$FIXTURE")
HOME="$TEST_DIR/home" DAC_RUNTIME=codex DAC_SKILL_HOME="$TEST_DIR/home/.codex/skills/gd-ai-coding" DAC_STATE_HOME="$TEST_DIR/home/.codex/skills/gd-ai-coding/state" DAC_CONFIG_HOME="$TEST_DIR/home/.codex/skills/dashboard" bash "$HOOK" <<<"$UNKNOWN"
assert_eq '未知工具安全退出且不新建快照' 1 "$(find "$SNAPSHOT_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
OUTSIDE=$(jq --arg cwd "$REPO" '.pre_tool_use | .cwd=$cwd | .tool_use_id="outside" | .tool_input.command |= gsub("/tmp/dac-codex-fixture-repo/lib/example.dart"; "/tmp/outside.dart")' "$FIXTURE")
HOME="$TEST_DIR/home" DAC_RUNTIME=codex DAC_SKILL_HOME="$TEST_DIR/home/.codex/skills/gd-ai-coding" DAC_STATE_HOME="$TEST_DIR/home/.codex/skills/gd-ai-coding/state" DAC_CONFIG_HOME="$TEST_DIR/home/.codex/skills/dashboard" bash "$HOOK" <<<"$OUTSIDE"
assert_eq '工作树外路径不创建快照' 1 "$(find "$SNAPSHOT_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
mkdir "$TEST_DIR/outside" && ln -s "$TEST_DIR/outside" "$REPO/link"
SYMLINK=$(jq --arg cwd "$REPO" '.pre_tool_use | .cwd=$cwd | .tool_use_id="symlink" | .tool_input.command |= gsub("/tmp/dac-codex-fixture-repo/lib/example.dart"; ($cwd + "/link/example.dart"))' "$FIXTURE")
HOME="$TEST_DIR/home" DAC_RUNTIME=codex DAC_SKILL_HOME="$TEST_DIR/home/.codex/skills/gd-ai-coding" DAC_STATE_HOME="$TEST_DIR/home/.codex/skills/gd-ai-coding/state" DAC_CONFIG_HOME="$TEST_DIR/home/.codex/skills/dashboard" bash "$HOOK" <<<"$SYMLINK"
assert_eq '符号链接目录路径不创建快照' 1 "$(find "$SNAPSHOT_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
ln -s "$REPO/lib/example.dart" "$REPO/lib/final-link.dart"
FINAL_LINK=$(jq --arg cwd "$REPO" '.pre_tool_use | .cwd=$cwd | .tool_use_id="final-link" | .tool_input.command |= gsub("/tmp/dac-codex-fixture-repo/lib/example.dart"; ($cwd + "/lib/final-link.dart"))' "$FIXTURE")
HOME="$TEST_DIR/home" DAC_RUNTIME=codex DAC_SKILL_HOME="$TEST_DIR/home/.codex/skills/gd-ai-coding" DAC_STATE_HOME="$TEST_DIR/home/.codex/skills/gd-ai-coding/state" DAC_CONFIG_HOME="$TEST_DIR/home/.codex/skills/dashboard" bash "$HOOK" <<<"$FINAL_LINK"
assert_eq '最终文件符号链接不创建快照' 1 "$(find "$SNAPSHOT_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
