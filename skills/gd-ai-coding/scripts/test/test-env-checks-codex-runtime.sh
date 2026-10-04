#!/usr/bin/env bash
# test-env-checks-codex-runtime.sh — env-checks.sh 在纯 Codex HOME 下不得依赖 Claude 路径
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../checks/env-checks.sh"
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

HOME="$TEST_DIR/home"
BIN_DIR="$TEST_DIR/bin"
mkdir -p "$HOME/.codex/skills/gd-ai-coding" "$HOME/.codex/skills/graphify" "$HOME/.mcporter" "$BIN_DIR"
printf '%s\n' '{}' > "$HOME/.codex/hooks.json"
printf '%s\n' '# graphify fixture' > "$HOME/.codex/skills/graphify/SKILL.md"
printf '%s\n' '{"mcpServers":{"Cooper":{},"mastergo-proxy":{},"mastergo_food":{}}}' > "$HOME/.mcporter/mcporter.json"

cat > "$BIN_DIR/mcporter" <<'EOF'
#!/bin/sh
[ "$1" = "config" ] && [ "$2" = "list" ] && printf '%s\n' ddp
EOF
cat > "$BIN_DIR/opsx" <<'EOF'
#!/bin/sh
[ "$1" = "--version" ] && printf '%s\n' 'opsx fixture'
EOF
cat > "$BIN_DIR/graphify" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$BIN_DIR/mcporter" "$BIN_DIR/opsx" "$BIN_DIR/graphify"
mkdir -p "$TEST_DIR/project/graphify-out"
printf '%s\n' '{}' > "$TEST_DIR/project/graphify-out/graph.json"

set +e
output=$(cd "$TEST_DIR/project" && env HOME="$HOME" PATH="$BIN_DIR:$PATH" DAC_RUNTIME=codex bash "$CHECK" 2>&1)
status=$?
set -e

assert_eq "Codex-only 环境检查通过" "0" "$status"
assert_eq "环境检查不创建 Claude 目录" "false" "$(test -e "$HOME/.claude" && echo true || echo false)"
assert_eq "Codex graphify 路径被识别" "false" "$(grep -q 'graphify skill 未安装' <<<"$output" && echo true || echo false)"

echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[[ $FAIL -eq 0 ]]
