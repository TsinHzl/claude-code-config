#!/usr/bin/env bash
# test-bind-report-sync.sh — Unit tests for bind-req.sh 绑定后立即同步后端的逻辑
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/.."
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
    echo "  ✗ $desc (not found in file: '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" filepath="$3"
  if ! grep -qF "$needle" "$filepath" 2>/dev/null; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc (should NOT be found: '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

# ── Setup: fake HOME with backend-config.json ────────────────────────────────

export HOME="$TEST_DIR/home"
export DAC_RUNTIME=claude
export DAC_SKILL_HOME="$HOME/.claude/skills/gd-ai-coding"
export DAC_STATE_HOME="$DAC_SKILL_HOME/state"
export DAC_CONFIG_HOME="$HOME/.claude/skills/dashboard"
mkdir -p "$HOME/.claude/skills/dashboard"
cat > "$HOME/.claude/skills/dashboard/backend-config.json" <<'EOF'
{"base_url": "http://fake-backend.test", "token": "fake-token"}
EOF

# ── Setup: fake curl that logs the -d body instead of hitting the network ────

CURL_BIN_DIR="$TEST_DIR/bin-curl"
mkdir -p "$CURL_BIN_DIR"
CURL_BODY_FILE="$TEST_DIR/last-body.json"
cat > "$CURL_BIN_DIR/curl" <<EOF
#!/bin/sh
prev=""
for arg in "\$@"; do
  if [ "\$prev" = "-d" ]; then
    printf '%s' "\$arg" > "$CURL_BODY_FILE"
  fi
  prev="\$arg"
done
exit 0
EOF
chmod +x "$CURL_BIN_DIR/curl"

ORIG_PATH="$PATH"
export PATH="$CURL_BIN_DIR:$ORIG_PATH"

# ── Setup: fake git repo for bind-req.sh ─────────────────────────────────────

REPO_DIR="$TEST_DIR/repo"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"
git init -q
git config user.email "tester@example.com"
git config user.name "Tester"
git remote add origin git@example.com:group/project.git
git checkout -q -b feature/test-branch

echo "═══ test-bind-report-sync.sh ═══"
echo ""

# ── Test 1: 本地已存在该 req_name 的真实 trace 文件 → 上报使用真实文件 ────────

echo "Test 1: 本地存在真实 trace 文件时，上报使用该文件（不清空真实 phases/features）"
mkdir -p .dac/trace
cat > .dac/trace/R-IBG-100.json <<'EOF'
{"req_name": "R-IBG-100", "phases": ["p1"], "features": ["f1"]}
EOF
rm -f "$CURL_BODY_FILE"
bash "$SCRIPTS_DIR/metrics/bind-req.sh" --req "R-IBG-100" >/dev/null 2>&1
assert_contains "上报 body 携带真实 phases" '"phases":["p1"]' "$CURL_BODY_FILE"
assert_contains "上报 body 携带真实 features" '"features":["f1"]' "$CURL_BODY_FILE"

# ── Test 2: 本地不存在该 req_name 的 trace 文件 → 上报使用空 phases/features ──

echo ""
echo "Test 2: 本地不存在 trace 文件时，上报使用空 phases/features 的临时 JSON"
rm -f "$CURL_BODY_FILE"
bash "$SCRIPTS_DIR/metrics/bind-req.sh" --req "R-IBG-200" >/dev/null 2>&1
assert_contains "上报 body 携带空 phases" '"phases":[]' "$CURL_BODY_FILE"
assert_contains "上报 body 携带空 features" '"features":[]' "$CURL_BODY_FILE"
assert_contains "上报 body 携带正确 req_name" '"req_name":"R-IBG-200"' "$CURL_BODY_FILE"

# ── Test 3: mktemp 失败时不因 set -e 整体退出，绑定文件仍正常写入 ────────────

echo ""
echo "Test 3: mktemp 失败时静默跳过上报，绑定主流程不受影响"
MKTEMP_FAIL_BIN_DIR="$TEST_DIR/bin-mktemp-fail"
mkdir -p "$MKTEMP_FAIL_BIN_DIR"
cat > "$MKTEMP_FAIL_BIN_DIR/mktemp" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$MKTEMP_FAIL_BIN_DIR/mktemp"

rm -f "$CURL_BODY_FILE"
export PATH="$MKTEMP_FAIL_BIN_DIR:$CURL_BIN_DIR:$ORIG_PATH"
set +e
bash "$SCRIPTS_DIR/metrics/bind-req.sh" --req "R-IBG-300" >"$TEST_DIR/scenario3.out" 2>"$TEST_DIR/scenario3.err"
SCENARIO3_EXIT=$?
set -e
export PATH="$CURL_BIN_DIR:$ORIG_PATH"

assert_eq "mktemp 失败时 bind-req.sh 退出码为 0" "0" "$SCENARIO3_EXIT"
assert_contains "绑定文件仍正常写入新 req" '"req": "R-IBG-300"' ".dac/req-bind"
assert_contains "stderr 提示 mktemp 失败" "mktemp 失败" "$TEST_DIR/scenario3.err"
assert_not_contains "未发生任何上报调用" "req_name" "$CURL_BODY_FILE"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
