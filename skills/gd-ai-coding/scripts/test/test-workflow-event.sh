#!/usr/bin/env bash
# test-workflow-event.sh — L2 成对上报 + session_id 读取 + 不再双写 feature_failed
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
    echo "  ✗ $desc (not found: '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" filepath="$3"
  if grep -qF "$needle" "$filepath" 2>/dev/null; then
    echo "  ✗ $desc (unexpected: '$needle')"
    FAIL=$((FAIL + 1))
  else
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
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
export PATH="$CURL_BIN_DIR:$PATH"

REPO_DIR="$TEST_DIR/repo"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"
git init -q
git config user.email "tester@example.com"
git config user.name "Tester"
git remote add origin git@example.com:group/project.git
mkdir -p .dac
echo '{"req_name":"R-TEST-1"}' > .dac/state.json
echo 'sess-from-file-uuid' > .dac/workflow_session_id

REPORT="$SCRIPTS_DIR/metrics/report-workflow-event.sh"
HARNESS="$SCRIPTS_DIR/feature/feature-harness.sh"
STATE_UPDATE="$SCRIPTS_DIR/state-update.sh"

echo "═══ test-workflow-event.sh ═══"
echo ""

echo "Test 1: 上报命中 /events，session_id 读 workflow_session_id 文件"
rm -f "$CURL_BODY_FILE" "$CURL_URL_FILE"
bash "$REPORT" "codegen_check_passed" '{"feat_id":"f1","exit_code":0}'
assert_contains "URL 命中 /events" "/api/v1/trace/events" "$CURL_URL_FILE"
assert_contains "event_type=codegen_check_passed" '"event_type":"codegen_check_passed"' "$CURL_BODY_FILE"
assert_contains "session_id 来自文件" '"session_id":"sess-from-file-uuid"' "$CURL_BODY_FILE"
assert_contains "req_name 来自 state.json" '"req_name":"R-TEST-1"' "$CURL_BODY_FILE"

echo ""
echo "Test 2: 无 workflow_session_id 时 session_id 为 null（不读不存在的 state.session_id）"
rm -f .dac/workflow_session_id "$CURL_BODY_FILE" "$CURL_URL_FILE"
echo '{"req_name":"R-TEST-1","session_id":"should-not-use"}' > .dac/state.json
bash "$REPORT" "codegen_check_started" '{"feat_id":"f1"}'
assert_contains "session_id 为 JSON null" '"session_id":null' "$CURL_BODY_FILE"

echo ""
echo "Test 3: Codex-only HOME 从 DAC_CONFIG_HOME 读取后端配置"
CODEX_HOME="$TEST_DIR/codex-only-home"
CODEX_CONFIG="$CODEX_HOME/.codex/skills/dashboard"
mkdir -p "$CODEX_CONFIG"
printf '%s\n' '{"base_url":"http://fake-backend.test","token":"fake-token"}' > "$CODEX_CONFIG/backend-config.json"
rm -f "$CURL_BODY_FILE" "$CURL_URL_FILE"
env HOME="$CODEX_HOME" DAC_RUNTIME=codex \
  DAC_SKILL_HOME="$CODEX_HOME/.codex/skills/gd-ai-coding" \
  DAC_STATE_HOME="$CODEX_HOME/.codex/skills/gd-ai-coding/state" \
  DAC_CONFIG_HOME="$CODEX_CONFIG" \
  bash "$REPORT" "codegen_check_started" '{"feat_id":"f1"}'
assert_contains "Codex 后端配置生效" '"event_type":"codegen_check_started"' "$CURL_BODY_FILE"
assert_eq "Codex 上报不创建 Claude 目录" "false" "$(test -e "$CODEX_HOME/.claude" && echo true || echo false)"

echo ""
echo "Test 4: 无后端配置时静默跳过"
NO_CONFIG_HOME="$TEST_DIR/home-empty"
mkdir -p "$NO_CONFIG_HOME"
rm -f "$CURL_BODY_FILE" "$CURL_URL_FILE"
env -u DAC_RUNTIME -u DAC_SKILL_HOME -u DAC_STATE_HOME -u DAC_CONFIG_HOME \
  HOME="$NO_CONFIG_HOME" bash "$REPORT" "codegen_check_failed" '{"feat_id":"f1"}'
assert_eq "无配置仍 exit 0" "0" "$?"
assert_eq "未产生上报 body" "" "$(cat "$CURL_BODY_FILE" 2>/dev/null || echo "")"

echo ""
echo "Test 4: feature-harness post-codegen 成对事件（静态）"
assert_contains "started 在检查前" 'codegen_check_started' "$HARNESS"
assert_contains "passed 对应 exit 0" 'codegen_check_passed' "$HARNESS"
assert_contains "auto_fixed 对应 exit 3" 'codegen_check_auto_fixed' "$HARNESS"
assert_contains "failed 仍保留" 'codegen_check_failed' "$HARNESS"
assert_contains "L2 通过后结算自动生成行" 'settle-codegen-lines.sh' "$HARNESS"

echo ""
echo "Test 5: state-update 不再双写 feature_failed/skipped"
assert_not_contains "无 feature_failed 上报" 'feature_failed' "$STATE_UPDATE"
assert_not_contains "无 feature_skipped 上报" 'feature_skipped' "$STATE_UPDATE"
assert_contains "phase 推进时打用户门接受" 'report-user-gate.sh" clarify accepted' "$STATE_UPDATE"

echo ""
echo "Test 6: report-user-gate 拒绝带原话，接受映射事件名"
echo 'sess-from-file-uuid' > .dac/workflow_session_id
echo '{"req_name":"R-TEST-1"}' > .dac/state.json
rm -f "$CURL_BODY_FILE" "$CURL_URL_FILE"
bash "$SCRIPTS_DIR/metrics/report-user-gate.sh" clarify rejected --msg '不行重来' --reason '用户否定结论'
assert_contains "拒绝 → prd_clarify_rejected" '"event_type":"prd_clarify_rejected"' "$CURL_BODY_FILE"
assert_contains "原话写入 payload" '"user_message":"不行重来"' "$CURL_BODY_FILE"
rm -f "$CURL_BODY_FILE"
bash "$SCRIPTS_DIR/metrics/report-user-gate.sh" proposal accepted
assert_contains "接受 → proposal_accepted" '"event_type":"proposal_accepted"' "$CURL_BODY_FILE"

echo ""
echo "Test 7: 原话超过 2048 被截断"
LONG_MSG=$(printf 'x%.0s' {1..3000})
rm -f "$CURL_BODY_FILE"
bash "$SCRIPTS_DIR/metrics/report-user-gate.sh" feature_plan adjusted --msg "$LONG_MSG" --adjustment split
MSG_LEN=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["payload"]["user_message"]))' "$CURL_BODY_FILE")
assert_eq "user_message 截断为 2048" "2048" "$MSG_LEN"

echo ""
echo "Test 8: 插件 DAC_UI_MODE=1 无标记时拒绝不上报；有标记才报；接受仍报"
GATE_SH="$SCRIPTS_DIR/metrics/report-user-gate.sh"
echo 'sess-from-file-uuid' > .dac/workflow_session_id
echo '{"req_name":"R-TEST-1"}' > .dac/state.json
export DAC_UI_MODE=1
unset DAC_GATE_UI_REPORT || true
rm -f "$CURL_BODY_FILE" "$CURL_URL_FILE"
bash "$GATE_SH" clarify rejected --msg '模型在插件里再调'
assert_eq "无标记拒绝不产生 body" "" "$(cat "$CURL_BODY_FILE" 2>/dev/null || echo "")"
assert_eq "无标记拒绝不产生 URL" "" "$(cat "$CURL_URL_FILE" 2>/dev/null || echo "")"
rm -f "$CURL_BODY_FILE" "$CURL_URL_FILE"
bash "$GATE_SH" feature_plan adjusted --msg '模型调整'
assert_eq "无标记调整不产生 body" "" "$(cat "$CURL_BODY_FILE" 2>/dev/null || echo "")"
export DAC_GATE_UI_REPORT=1
rm -f "$CURL_BODY_FILE" "$CURL_URL_FILE"
bash "$GATE_SH" clarify rejected --msg '卡片调整'
assert_contains "有标记拒绝仍上报" '"event_type":"prd_clarify_rejected"' "$CURL_BODY_FILE"
unset DAC_GATE_UI_REPORT || true
rm -f "$CURL_BODY_FILE" "$CURL_URL_FILE"
bash "$GATE_SH" proposal accepted
assert_contains "无标记接受仍上报" '"event_type":"proposal_accepted"' "$CURL_BODY_FILE"
unset DAC_UI_MODE || true
unset DAC_GATE_UI_REPORT || true

echo ""
echo "Test 9: report-cr-verdict 按产物分流"
mkdir -p openspec/changes/R-TEST-1/features/f1
cat > openspec/changes/R-TEST-1/features/f1/cr-report.md <<'EOF'
## verdict: clean
EOF
rm -f "$CURL_BODY_FILE"
bash "$SCRIPTS_DIR/metrics/report-cr-verdict.sh" f1
assert_contains "clean → cr_check_passed" '"event_type":"cr_check_passed"' "$CURL_BODY_FILE"

cat > openspec/changes/R-TEST-1/features/f1/cr-report.md <<'EOF'
## verdict: with_issues
### 🔴 严重（必须修复）
### 🔴 另一条
### 🟡 一般
EOF
rm -f "$CURL_BODY_FILE"
bash "$SCRIPTS_DIR/metrics/report-cr-verdict.sh" f1
assert_contains "有问题 → cr_issue_found" '"event_type":"cr_issue_found"' "$CURL_BODY_FILE"
assert_contains "critical_count=2" '"critical_count":2' "$CURL_BODY_FILE"
assert_contains "normal_count=1" '"normal_count":1' "$CURL_BODY_FILE"

cat > openspec/changes/R-TEST-1/features/f1/cr-report.md <<'EOF'
verdict: skipped（净改动 < 10 行，用户选择跳过）
EOF
rm -f "$CURL_BODY_FILE"
bash "$SCRIPTS_DIR/metrics/report-cr-verdict.sh" f1
assert_contains "skipped → cr_check_skipped" '"event_type":"cr_check_skipped"' "$CURL_BODY_FILE"

rm -f "$CURL_BODY_FILE"
bash "$SCRIPTS_DIR/metrics/report-cr-verdict.sh" f1 started
assert_contains "started 事件" '"event_type":"cr_check_started"' "$CURL_BODY_FILE"

echo ""
echo "Test 10: assemble-cr-prompt 启动时打 cr started（静态）"
assert_contains "assemble 调用 report-cr-verdict started" 'report-cr-verdict.sh" "$FEAT_ID" started' "$SCRIPTS_DIR/feature/assemble-cr-prompt.sh"

echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
