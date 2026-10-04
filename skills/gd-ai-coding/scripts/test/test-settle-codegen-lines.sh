#!/usr/bin/env bash
# test-settle-codegen-lines.sh — 代码比例「流程 · 自动生成」桶：checkpoint diff 按 feat 取 max
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/.."
SETTLE="$SCRIPTS_DIR/metrics/settle-codegen-lines.sh"
HARNESS="$SCRIPTS_DIR/feature/feature-harness.sh"
STATE_UPDATE="$SCRIPTS_DIR/state-update.sh"
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

assert_contains() {
  local desc="$1" needle="$2" filepath="$3"
  if grep -qF "$needle" "$filepath" 2>/dev/null; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc (not found: '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

export HOME="$TEST_DIR/home"
export DAC_RUNTIME=claude
export DAC_SKILL_HOME="$HOME/.claude/skills/gd-ai-coding"
export DAC_STATE_HOME="$DAC_SKILL_HOME/state"
export DAC_CONFIG_HOME="$HOME/.claude/skills/dashboard"
mkdir -p "$HOME/.claude/skills/dashboard"
cat > "$HOME/.claude/skills/dashboard/backend-config.json" <<'EOF'
{"base_url": "http://fake-backend.test", "token": "fake-token"}
EOF

CURL_BIN_DIR="$TEST_DIR/bin-curl"
mkdir -p "$CURL_BIN_DIR"
CURL_BODY_FILE="$TEST_DIR/last-body.json"
cat > "$CURL_BIN_DIR/curl" <<EOF
#!/bin/sh
prev=""
for arg in "\$@"; do
  if [ "\$prev" = "-d" ]; then printf '%s' "\$arg" > "$CURL_BODY_FILE"; fi
  prev="\$arg"
done
exit 0
EOF
chmod +x "$CURL_BIN_DIR/curl"
export PATH="$CURL_BIN_DIR:$PATH"

REPO_DIR="$TEST_DIR/repo"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"
git init -q
git config user.email "tester@example.com"
git config user.name "Tester"
git remote add origin git@example.com:group/project.git
printf 'readme\n' > README.md
git add README.md
git commit -q -m "init"
BASE=$(git rev-parse HEAD)

mkdir -p .dac/trace openspec/changes/R-TEST-1/features/login-page
printf '%s\n' '{"req_name":"R-TEST-1"}' > .dac/state.json
printf '%s\n' '{"req_name":"R-TEST-1","phases":[],"features":[]}' > .dac/trace/R-TEST-1.json
printf '%s\n' "{\"base_commit\":\"$BASE\",\"started_at\":\"2026-01-01T00:00:00Z\"}" \
  > openspec/changes/R-TEST-1/features/login-page/.codegen_checkpoint
cat > openspec/changes/R-TEST-1/features/login-page/code-scope.md <<'EOF'
## 代码改动范围：登录页

### 新增文件
| 文件路径 | 用途 |
|---------|------|
| lib/foo.dart | 登录页 |

### 修改文件
| 文件路径 | 修改说明 |
|---------|--------|
EOF

echo "═══ test-settle-codegen-lines.sh ═══"
echo ""

echo "Test 1: 未跟踪 code-scope 文件计入；范围外文件不计"
mkdir -p lib
printf 'a\nb\nc\nd\ne\n' > lib/foo.dart
printf 'x\ny\n' > lib/out.dart
bash "$SETTLE" login-page
assert_eq "codegen_lines_added=5（只计 foo.dart）" "5" \
  "$(jq -r '.codegen_lines_added' .dac/trace/R-TEST-1.json)"
assert_eq "codegen_by_feature.login-page=5" "5" \
  "$(jq -r '.codegen_by_feature["login-page"]' .dac/trace/R-TEST-1.json)"
assert_contains "/report 带 codegen_lines_added" '"codegen_lines_added":5' "$CURL_BODY_FILE"

echo ""
echo "Test 2: 同一 feat 取 max（行变少不回退）"
printf 'a\nb\n' > lib/foo.dart
bash "$SETTLE" login-page
assert_eq "变少后仍保持 5" "5" \
  "$(jq -r '.codegen_by_feature["login-page"]' .dac/trace/R-TEST-1.json)"

echo ""
echo "Test 3: 行变多则推进 max"
printf 'a\nb\nc\nd\ne\nf\ng\nh\n' > lib/foo.dart
bash "$SETTLE" login-page
assert_eq "变多后为 8" "8" \
  "$(jq -r '.codegen_by_feature["login-page"]' .dac/trace/R-TEST-1.json)"
assert_eq "需求级合计=8" "8" \
  "$(jq -r '.codegen_lines_added' .dac/trace/R-TEST-1.json)"

echo ""
echo "Test 4: 缺 checkpoint 不改已有值、不报错"
rm -f openspec/changes/R-TEST-1/features/login-page/.codegen_checkpoint
bash "$SETTLE" login-page
assert_eq "缺 checkpoint 保持 8" "8" \
  "$(jq -r '.codegen_lines_added' .dac/trace/R-TEST-1.json)"

echo ""
echo "Test 5: L2 通过才结算、feature done 再结算（静态调用点）"
assert_contains "harness L2 通过后调用 settle" 'settle-codegen-lines.sh' "$HARNESS"
assert_contains "state-update done 再结算" 'settle-codegen-lines.sh' "$STATE_UPDATE"
assert_contains "harness 仅 0/3 结算" 'POST_EXIT -eq 0 || $POST_EXIT -eq 3' "$HARNESS"
assert_contains "state-update 仅 done 结算" 'done_with_issues' "$STATE_UPDATE"
assert_contains "pre-codegen 写 checkpoint" 'write_codegen_checkpoint' "$HARNESS"

echo ""
echo "Test 6: pre-codegen 锚点写入；已有文件不覆盖"
# shellcheck source=/dev/null
source "$SCRIPTS_DIR/feature/codegen-checkpoint.sh"
CKPT_DIR="$REPO_DIR/openspec/changes/R-TEST-1/features/ckpt-feat"
rm -rf "$CKPT_DIR"
write_codegen_checkpoint "$CKPT_DIR"
assert_eq "缺文件时写入 HEAD" "$BASE" \
  "$(jq -r '.base_commit' "$CKPT_DIR/.codegen_checkpoint")"
printf '%s\n' '{"base_commit":"OLD","started_at":"x"}' > "$CKPT_DIR/.codegen_checkpoint"
write_codegen_checkpoint "$CKPT_DIR"
assert_eq "已有文件不覆盖" "OLD" \
  "$(jq -r '.base_commit' "$CKPT_DIR/.codegen_checkpoint")"

echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
