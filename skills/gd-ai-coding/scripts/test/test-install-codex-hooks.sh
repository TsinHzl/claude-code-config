#!/usr/bin/env bash
# test-install-codex-hooks.sh — Codex Hook 安装的无损、幂等、原子回滚契约
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL="$ROOT_DIR/scripts/metrics/install-codex-hooks.sh"
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

run_install() {
  bash "$INSTALL" --config "$1" --skill-home "$2" >/dev/null 2>&1
}

file_mode() {
  if [[ "$(uname)" == "Darwin" ]]; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

printf '═══ test-install-codex-hooks.sh ═══\n\n'

CONFIG="$TEST_DIR/hooks.json"
SKILL_HOME="$TEST_DIR/.codex/skills/gd-ai-coding"
cat > "$CONFIG" <<'EOF'
{"hooks":{"PreToolUse":[{"_source":"third-party","matcher":"apply_patch","hooks":[{"type":"command","command":"third-pre"}]}],"PostToolUse":[{"_source":"third-party","matcher":"other","hooks":[{"type":"command","command":"third-post"}]}]}}
EOF
run_install "$CONFIG" "$SKILL_HOME"
assert_eq '首次安装成功' 0 "$?"
assert_eq '安装结果为合法 JSON' true "$(jq -e . "$CONFIG" >/dev/null && printf true || printf false)"
assert_eq '第三方 PreToolUse group 保留' third-pre "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$CONFIG")"
assert_eq '第三方 PostToolUse group 保留' third-post "$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$CONFIG")"
assert_eq 'PreToolUse 仅一个 DAC group' 1 "$(jq '[.hooks.PreToolUse[] | select(._source == "gd-ai-coding")] | length' "$CONFIG")"
assert_eq 'PostToolUse 仅一个 DAC group' 1 "$(jq '[.hooks.PostToolUse[] | select(._source == "gd-ai-coding")] | length' "$CONFIG")"
assert_eq 'DAC group matcher 精确匹配 apply_patch' apply_patch "$(jq -r '.hooks.PreToolUse[] | select(._source == "gd-ai-coding") | .matcher' "$CONFIG")"
assert_eq '配置权限为 0600' 600 "$(file_mode "$CONFIG")"
assert_eq '安装成功后备份已清理' '' "$(ls "$(dirname "$CONFIG")"/hooks.json.dac-backup.* 2>/dev/null)"
run_install "$CONFIG" "$SKILL_HOME"
assert_eq '重复安装成功' 0 "$?"
assert_eq '重复安装不累积 DAC group' 1 "$(jq '[.hooks.PreToolUse[] | select(._source == "gd-ai-coding")] | length' "$CONFIG")"

cp "$CONFIG" "$TEST_DIR/before-fault.json"
DAC_HOOKS_FAIL_AFTER_WRITE=1 run_install "$CONFIG" "$SKILL_HOME"
assert_eq '故障注入退出 1' 1 "$?"
assert_eq '故障注入恢复原配置' 0 "$(cmp -s "$TEST_DIR/before-fault.json" "$CONFIG"; printf '%s' "$?")"

NEW_CONFIG="$TEST_DIR/new/hooks.json"
run_install "$NEW_CONFIG" "$SKILL_HOME"
assert_eq '配置不存在时原子创建成功' 0 "$?"
assert_eq '新配置权限为 0600' 600 "$(file_mode "$NEW_CONFIG")"

UNSAFE_CONFIG="$TEST_DIR/unsafe.json"
UNSAFE_HOME="$TEST_DIR/unsafe\";touch $TEST_DIR/injected;#"
run_install "$UNSAFE_CONFIG" "$UNSAFE_HOME"
assert_eq '特殊 Skill 路径仍可安全写入 Hook' 0 "$?"
assert_eq '特殊 Skill 路径不执行注入命令' false "$(test -e "$TEST_DIR/injected" && printf true || printf false)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
