#!/usr/bin/env bash
# report-cr-verdict.sh — 根据 cr-report.md（产物即事实）上报 CR 节点事件
#
# 用法：
#   report-cr-verdict.sh <feat_id> started   # 启动 CR sub-agent 前（assemble-cr-prompt 调用）
#   report-cr-verdict.sh <feat_id>           # 报告已写入后：passed / issue_found / skipped
#
# 失败静默，不阻断主流程。

set -euo pipefail

FEAT_ID="${1:?用法: report-cr-verdict.sh <feat_id> [started]}"
MODE="${2:-verdict}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPTS_DIR/paths.sh" 2>/dev/null || true

if [[ "$MODE" == "started" ]]; then
  bash "$SCRIPT_DIR/report-workflow-event.sh" \
    "cr_check_started" "{\"feat_id\":\"$FEAT_ID\"}" || true
  exit 0
fi

REQ_NAME=$(jq -r '.req_name // empty' .dac/state.json 2>/dev/null || true)
REPORT=""
if [[ -n "$REQ_NAME" ]]; then
  REPORT="$(get_feat_dir "$REQ_NAME" "$FEAT_ID")/cr-report.md"
fi
[[ -z "$REPORT" || ! -f "$REPORT" ]] && exit 0

if grep -qiE 'verdict:[[:space:]]*skipped' "$REPORT"; then
  bash "$SCRIPT_DIR/report-workflow-event.sh" \
    "cr_check_skipped" "{\"feat_id\":\"$FEAT_ID\"}" || true
  exit 0
fi

CRITICAL=$(grep -cE '^### 🔴' "$REPORT" 2>/dev/null || true)
NORMAL=$(grep -cE '^### 🟡' "$REPORT" 2>/dev/null || true)
[[ "$CRITICAL" =~ ^[0-9]+$ ]] || CRITICAL=0
[[ "$NORMAL" =~ ^[0-9]+$ ]] || NORMAL=0

if grep -qiE 'verdict:[[:space:]]*clean' "$REPORT" && [[ "$CRITICAL" -eq 0 && "$NORMAL" -eq 0 ]]; then
  bash "$SCRIPT_DIR/report-workflow-event.sh" \
    "cr_check_passed" "{\"feat_id\":\"$FEAT_ID\"}" || true
  exit 0
fi

bash "$SCRIPT_DIR/report-workflow-event.sh" \
  "cr_issue_found" \
  "{\"feat_id\":\"$FEAT_ID\",\"critical_count\":$CRITICAL,\"normal_count\":$NORMAL}" || true
