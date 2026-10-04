#!/usr/bin/env bash
# test-inject-runtime-env.sh — Claude/Codex shell runtime 环境注入
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INJECT="$ROOT_DIR/scripts/permission/inject-runtime-env.sh"
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

run_inject() {
  HOME="$1" bash "$INJECT" >/dev/null 2>&1
}

printf '═══ test-inject-runtime-env.sh ═══\n\n'

HOME_DIR="$TEST_DIR/home"
mkdir -p "$HOME_DIR/.claude" "$HOME_DIR/.codex"
printf '{"env":{"KEEP":"yes"}}\n' > "$HOME_DIR/.claude/settings.json"
printf 'model = "test"\n\n[third_party]\nvalue = "keep"\n' > "$HOME_DIR/.codex/config.toml"
run_inject "$HOME_DIR"
assert_eq '首次注入成功' 0 "$?"
assert_eq 'Claude 环境注入 runtime' claude "$(jq -r '.env.DAC_RUNTIME' "$HOME_DIR/.claude/settings.json")"
assert_eq 'Claude 原有环境保留' yes "$(jq -r '.env.KEEP' "$HOME_DIR/.claude/settings.json")"
assert_eq 'Codex 环境注入 runtime' codex "$(awk -F ' = ' '/^DAC_RUNTIME =/{gsub(/"/, "", $2); print $2}' "$HOME_DIR/.codex/config.toml")"
assert_eq 'Codex 第三方配置保留' 1 "$(grep -c '^\[third_party\]$' "$HOME_DIR/.codex/config.toml")"
assert_eq 'Claude 配置权限为 0600' 600 "$(stat -f '%Lp' "$HOME_DIR/.claude/settings.json")"
assert_eq 'Codex 配置权限为 0600' 600 "$(stat -f '%Lp' "$HOME_DIR/.codex/config.toml")"
run_inject "$HOME_DIR"
assert_eq '重复注入保持幂等' 0 "$?"

CONFLICT_HOME="$TEST_DIR/conflict"
mkdir -p "$CONFLICT_HOME/.codex"
cat > "$CONFLICT_HOME/.codex/config.toml" <<'EOF'
[shell_environment_policy]
set = { USER_VALUE = "keep" }
EOF
run_inject "$CONFLICT_HOME"
assert_eq 'inline set 冲突不覆盖配置' 1 "$?"
assert_eq 'inline set 配置保留' 'set = { USER_VALUE = "keep" }' "$(grep '^set =' "$CONFLICT_HOME/.codex/config.toml")"

DAC_CONFLICT_HOME="$TEST_DIR/dac-conflict"
mkdir -p "$DAC_CONFLICT_HOME/.codex"
printf 'DAC_RUNTIME = "other"\n' > "$DAC_CONFLICT_HOME/.codex/config.toml"
cp "$DAC_CONFLICT_HOME/.codex/config.toml" "$DAC_CONFLICT_HOME/original.toml"
run_inject "$DAC_CONFLICT_HOME"
assert_eq '冲突 DAC 键拒绝覆盖配置' 1 "$?"
assert_eq '冲突 DAC 键失败后配置不变' 0 "$(cmp -s "$DAC_CONFLICT_HOME/original.toml" "$DAC_CONFLICT_HOME/.codex/config.toml"; printf '%s' "$?")"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
