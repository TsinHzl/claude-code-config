#!/usr/bin/env bash
# test-runtime-paths.sh — 四个 DAC 运行时路径变量解析契约
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RUNTIME_SH="$ROOT_DIR/scripts/runtime.sh"
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

assert_exit() {
  local description="$1" expected="$2"
  shift 2
  "$@" >/dev/null 2>&1
  local actual=$?
  assert_eq "$description" "$expected" "$actual"
}

resolve() {
  local home="$1"
  shift
  env -i HOME="$home" PATH="$PATH" "$@" bash -c '
    source "$1"
    dac_resolve_runtime
    printf "%s|%s|%s|%s\n" "$DAC_RUNTIME" "$DAC_SKILL_HOME" "$DAC_STATE_HOME" "$DAC_CONFIG_HOME"
  ' bash "$RUNTIME_SH"
}

printf '═══ test-runtime-paths.sh ═══\n\n'
CODEX_HOME="$TEST_DIR/codex"
CLAUDE_HOME="$TEST_DIR/claude"
mkdir -p "$CODEX_HOME/.codex/skills/gd-ai-coding" "$CLAUDE_HOME/.claude/skills/gd-ai-coding"

actual=$(resolve "$CODEX_HOME" DAC_RUNTIME=codex)
assert_eq '显式 codex 补齐三个 Codex 默认路径' "codex|$CODEX_HOME/.codex/skills/gd-ai-coding|$CODEX_HOME/.codex/skills/gd-ai-coding/state|$CODEX_HOME/.codex/skills/dashboard" "$actual"
actual=$(resolve "$CODEX_HOME" DAC_RUNTIME=codex DAC_STATE_HOME=/tmp/custom-dac-state)
assert_eq '部分覆盖保留并补齐同一 runtime 默认值' "codex|$CODEX_HOME/.codex/skills/gd-ai-coding|/tmp/custom-dac-state|$CODEX_HOME/.codex/skills/dashboard" "$actual"
actual=$(resolve "$CODEX_HOME")
assert_eq '仅存在 Codex 安装目录时不访问 Claude 路径' "codex|$CODEX_HOME/.codex/skills/gd-ai-coding|$CODEX_HOME/.codex/skills/gd-ai-coding/state|$CODEX_HOME/.codex/skills/dashboard" "$actual"
assert_exit '显式 Codex 与 Claude 路径冲突退出 1' 1 env -i HOME="$CODEX_HOME" PATH="$PATH" DAC_RUNTIME=codex DAC_SKILL_HOME="$CODEX_HOME/.claude/skills/gd-ai-coding" bash -c 'source "$1"; dac_resolve_runtime' bash "$RUNTIME_SH"
for path_var in DAC_SKILL_HOME DAC_STATE_HOME DAC_CONFIG_HOME; do
  for segment in . ..; do
    assert_exit "$path_var 含 $segment 路径段退出 1" 1 env -i HOME="$CODEX_HOME" PATH="$PATH" DAC_RUNTIME=codex "$path_var=$CODEX_HOME/.codex/$segment/skills/gd-ai-coding" bash -c 'source "$1"; dac_resolve_runtime' bash "$RUNTIME_SH"
  done
done
auto_discovery=$(sed -n '/if \[\[ ${#signals\[@\]} -eq 0 \]\]; then/,/^[[:space:]]*fi/p' "$RUNTIME_SH")
assert_eq '自动发现不硬编码 Claude 候选路径' '' "$(printf '%s' "$auto_discovery" | grep -F '.claude/skills/gd-ai-coding' || true)"
BOTH_HOME="$TEST_DIR/both"
mkdir -p "$BOTH_HOME/.codex/skills/gd-ai-coding" "$BOTH_HOME/.claude/skills/gd-ai-coding"
assert_exit '双客户端候选未指定 runtime 退出 1' 1 env -i HOME="$BOTH_HOME" PATH="$PATH" bash -c 'source "$1"; dac_resolve_runtime' bash "$RUNTIME_SH"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
