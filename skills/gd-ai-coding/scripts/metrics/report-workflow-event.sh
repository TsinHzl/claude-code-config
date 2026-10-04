#!/usr/bin/env bash
# report-workflow-event.sh — 上报工作流关键节点事件到 dac-trace-service
#
# 用法：
#   report-workflow-event.sh <event_type> <payload_json>
#
# 示例：
#   report-workflow-event.sh "codegen_check_started" '{"feat_id":"f1"}'
#   report-workflow-event.sh "codegen_check_passed" '{"feat_id":"f1","exit_code":0}'
#   report-workflow-event.sh "codegen_check_failed" '{"feat_id":"f1","exit_code":1}'
#   report-workflow-event.sh "cr_issue_found" '{"feat_id":"f1","critical_count":2,"normal_count":1}'
#
# 失败处理：
#   后端未配置、字段缺失、curl 超时，均静默降级，不影响主流程。
#   调用方统一加 || true 保证脚本失败不中断主流程。

set -euo pipefail

EVENT_TYPE="${1:-}"
PAYLOAD_JSON="${2:-}"
[[ -z "$PAYLOAD_JSON" ]] && PAYLOAD_JSON="{}"

if [[ -z "$EVENT_TYPE" ]]; then
  echo "[report-workflow-event] ❌ event_type 不能为空" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../runtime.sh"
dac_resolve_runtime || exit 0
BACKEND_CONFIG="$DAC_CONFIG_HOME/backend-config.json"
STATE_FILE=".dac/state.json"

# ── 读取后端配置 ──────────────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then exit 0; fi
if [[ ! -f "$BACKEND_CONFIG" ]]; then exit 0; fi

BASE_URL=$(jq -r '.base_url // empty' "$BACKEND_CONFIG" 2>/dev/null)
TOKEN=$(jq -r '.token // empty' "$BACKEND_CONFIG" 2>/dev/null)
if [[ -z "$BASE_URL" || -z "$TOKEN" ]]; then exit 0; fi

# ── 读取 committer / req_name / session_id ────────────────────────────────────
COMMITTER=$(git config user.email 2>/dev/null || true)
if [[ -z "$COMMITTER" ]]; then exit 0; fi

REQ_NAME=""
if [[ -f "$STATE_FILE" ]]; then
  REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE" 2>/dev/null || true)
fi
if [[ -z "$REQ_NAME" ]]; then exit 0; fi

# session 与 record-trace.sh 同源：.dac/workflow_session_id（state.json 没有 session_id）
SESSION_ID=""
if [[ -f ".dac/workflow_session_id" ]]; then
  SESSION_ID=$(tr -d '[:space:]' < ".dac/workflow_session_id" 2>/dev/null || true)
fi

# ── 推导 repo_path（取不到则留空，后端查询侧按 req_name 聚合兜底）─────────────
REPO_PATH=$(git remote get-url origin 2>/dev/null \
  | sed -E 's#^[a-zA-Z]+://[^/]+/##; s#^[^@]+@[^:]+:##; s#\.git$##' || true)
REPO_PATH="${REPO_PATH:-}"

# ── 组装请求体并上报 ───────────────────────────────────────────────────────────
OCCURRED_AT=$(( $(date +%s) * 1000 ))

BODY=$(jq -cn \
  --arg et "$EVENT_TYPE" \
  --arg c "$COMMITTER" \
  --arg rn "$REQ_NAME" \
  --arg rp "$REPO_PATH" \
  --arg sid "$SESSION_ID" \
  --argjson payload "$PAYLOAD_JSON" \
  --argjson ts "$OCCURRED_AT" \
  '{event_type:$et, committer:$c, req_name:$rn, repo_path:$rp,
    session_id:($sid | if . == "" then null else . end),
    payload:$payload, occurred_at:$ts}' 2>/dev/null) || exit 0

curl --max-time 3 --silent --fail \
  -X POST "$BASE_URL/api/v1/trace/events" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$BODY" >/dev/null 2>&1 || true
