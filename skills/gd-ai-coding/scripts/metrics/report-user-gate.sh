#!/usr/bin/env bash
# report-user-gate.sh — 用户门（澄清 / proposal / 功能列表）拒绝、调整、接受
#
# 用法：
#   report-user-gate.sh <gate> <outcome> [--msg TEXT] [--reason TEXT] [--adjustment TYPE]
#
#   gate:     clarify | proposal | feature_plan
#   outcome:  rejected | accepted | adjusted
#
# 接受（accepted）由 state-update.sh --phase 自动调用，skill 不要再报。
# 拒绝/调整：Claude Code 由主会话调本脚本；VS Code 插件由 ApprovalCard 调
# （须带 DAC_GATE_UI_REPORT=1）。插件进程里模型再调且只有 DAC_UI_MODE=1 时
# 对 rejected/adjusted 空跑，避免双写。accepted 不挡。
# 失败静默，不阻断主流程。

set -euo pipefail

GATE="${1:-}"
OUTCOME="${2:-}"
if [[ -z "$GATE" || -z "$OUTCOME" ]]; then
  echo "[report-user-gate] 用法: report-user-gate.sh <clarify|proposal|feature_plan> <rejected|accepted|adjusted> [--msg ...] [--reason ...] [--adjustment ...]" >&2
  exit 1
fi
shift 2

# 插件环境：拒绝/调整改由卡片上报。模型同进程再调 → 空跑。接受仍走 state-update。
if [[ "${DAC_UI_MODE:-}" == "1" && "${DAC_GATE_UI_REPORT:-}" != "1" ]]; then
  case "$OUTCOME" in
    rejected|adjusted) exit 0 ;;
  esac
fi

MSG=""
REASON=""
ADJUSTMENT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --msg) MSG="${2-}" ; shift 2 ;;
    --reason) REASON="${2-}" ; shift 2 ;;
    --adjustment) ADJUSTMENT="${2-}" ; shift 2 ;;
    *) shift ;;
  esac
done

EVENT_TYPE=""
case "${GATE}:${OUTCOME}" in
  clarify:rejected)           EVENT_TYPE="prd_clarify_rejected" ;;
  clarify:accepted)           EVENT_TYPE="prd_clarify_accepted" ;;
  proposal:rejected)          EVENT_TYPE="proposal_rejected" ;;
  proposal:accepted)          EVENT_TYPE="proposal_accepted" ;;
  feature_plan:adjusted)      EVENT_TYPE="feature_plan_adjusted" ;;
  feature_plan:accepted)      EVENT_TYPE="feature_plan_accepted" ;;
  *)
    echo "[report-user-gate] 未知组合: gate=$GATE outcome=$OUTCOME" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PAYLOAD=$(jq -cn \
  --arg msg "$MSG" \
  --arg reason "$REASON" \
  --arg adj "$ADJUSTMENT" \
  --arg gate "$GATE" \
  --arg outcome "$OUTCOME" \
  '{
    gate: $gate,
    outcome: $outcome,
    user_message: (if ($msg | length) > 2048 then $msg[0:2048] else $msg end),
    reason: $reason
  } + (if $adj == "" then {} else {adjustment: $adj} end)' 2>/dev/null) || PAYLOAD="{}"

bash "$SCRIPT_DIR/report-workflow-event.sh" "$EVENT_TYPE" "$PAYLOAD" || true
