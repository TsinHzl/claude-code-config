#!/usr/bin/env bash
# test-report-trace-backend.sh — Unit tests for report-trace-backend.sh 的 _report_personal_trace
#
# 覆盖个人全局 AI coding 总产出上报函数：body 字段正确性、后端未配置时静默降级、
# 无 git 身份时静默跳过。不覆盖 _report_progress/_report_commit_stats/_report_ddp_binding
# ——它们已被 test-post-commit-reset.sh / test-bind-report-sync.sh 间接覆盖。
set -uo pipefail

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

# ── Setup: Codex-only fake HOME with backend-config.json ─────────────────────

export HOME="$TEST_DIR/home"
export DAC_RUNTIME=codex
export DAC_CONFIG_HOME="$HOME/.codex/skills/dashboard"
mkdir -p "$DAC_CONFIG_HOME"
cat > "$DAC_CONFIG_HOME/backend-config.json" <<'EOF'
{"base_url": "http://fake-backend.test", "token": "fake-token"}
EOF

# ── Setup: fake curl that logs the URL + -d body instead of hitting the network ──

CURL_BIN_DIR="$TEST_DIR/bin-curl"
mkdir -p "$CURL_BIN_DIR"
CURL_BODY_FILE="$TEST_DIR/last-body.json"
CURL_URL_FILE="$TEST_DIR/last-url.txt"
cat > "$CURL_BIN_DIR/curl" <<EOF
#!/bin/sh
prev=""
for arg in "\$@"; do
  case "\$arg" in
    http*) printf '%s' "\$arg" > "$CURL_URL_FILE" ;;
  esac
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

# ── Setup: fake git repo ──────────────────────────────────────────────────────

REPO_DIR="$TEST_DIR/repo"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"
git init -q
git config user.email "tester@example.com"
git config user.name "Tester"
git remote add origin git@example.com:group/project.git

echo "═══ test-report-trace-backend.sh ═══"
echo ""

# ── Test 1: 正常场景 → body 携带 committer/repo_path/write_lines_added ────────

echo "Test 1: 正常场景，body 字段完整正确"
rm -f "$CURL_BODY_FILE" "$CURL_URL_FILE"
bash -c "source '$SCRIPTS_DIR/metrics/report-trace-backend.sh'; _report_personal_trace 128"
assert_contains "上报 URL 命中 personal-report 端点" "/api/v1/trace/personal-report" "$CURL_URL_FILE"
assert_contains "上报 body 携带 committer" '"committer":"tester@example.com"' "$CURL_BODY_FILE"
assert_contains "上报 body 携带 committer_name" '"committer_name":"Tester"' "$CURL_BODY_FILE"
assert_contains "上报 body 携带 repo_path" '"repo_path":"group/project"' "$CURL_BODY_FILE"
assert_contains "上报 body 携带 write_lines_added" '"write_lines_added":128' "$CURL_BODY_FILE"
assert_eq "两参调用不带 unused_workflow_lines（旧 hook 兼容）" "true" \
  "$(jq -r 'has("unused_workflow_lines") | not' "$CURL_BODY_FILE")"

# ── Test 1b: 第三参 unused_workflow_lines 显式上报（含 0）────────────────────

echo ""
echo "Test 1b: 第三参 unused_workflow_lines 写入 body"
rm -f "$CURL_BODY_FILE" "$CURL_URL_FILE"
bash -c "source '$SCRIPTS_DIR/metrics/report-trace-backend.sh'; _report_personal_trace 128 3 40"
assert_contains "unused_workflow_lines=40" '"unused_workflow_lines":40' "$CURL_BODY_FILE"

# ── Test 2: 后端未配置（无 backend-config.json）→ 静默跳过，不调用 curl ──────

echo ""
echo "Test 2: 后端未配置时静默跳过，不产生任何上报"
NO_CONFIG_HOME="$TEST_DIR/home-empty"
mkdir -p "$NO_CONFIG_HOME"
rm -f "$CURL_BODY_FILE" "$CURL_URL_FILE"
env -u DAC_CONFIG_HOME -u DAC_RUNTIME HOME="$NO_CONFIG_HOME" bash -c "source '$SCRIPTS_DIR/metrics/report-trace-backend.sh'; _report_personal_trace 99"
EXIT_CODE=$?
assert_eq "无后端配置时函数仍返回 0（不阻塞调用方）" "0" "$EXIT_CODE"
assert_eq "未生成任何上报 body" "" "$(cat "$CURL_BODY_FILE" 2>/dev/null || echo "")"

# ── Test 3: 无 git 身份（git config user.email 为空）→ 静默跳过 ──────────────

echo ""
echo "Test 3: 无 git committer 身份时静默跳过"
NO_GIT_DIR="$TEST_DIR/no-git-repo"
mkdir -p "$NO_GIT_DIR"
rm -f "$CURL_BODY_FILE" "$CURL_URL_FILE"
(
  cd "$NO_GIT_DIR" || exit 1
  git init -q
  bash -c "source '$SCRIPTS_DIR/metrics/report-trace-backend.sh'; _report_personal_trace 42"
)
assert_eq "无 git 身份时未生成任何上报 body" "" "$(cat "$CURL_BODY_FILE" 2>/dev/null || echo "")"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
