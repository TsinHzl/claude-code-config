#!/usr/bin/env bash
# assign.sh — 将 feature 指派给某个 git email（写 feature-plan.json[].assignee）
# 用法：assign.sh --feat <feat_id> --to <email>
#   email 必须含 @，否则 exit 1
#   feat_id 不存在时 exit 1 [DAC-DEP-004]
# 走 lib.sh 的 atomic_jq，禁止手工 jq > tmp && mv

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../paths.sh"
source "$SCRIPT_DIR/../lib.sh"

FEAT=""
TO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --feat) FEAT="$2"; shift 2 ;;
    --to)   TO="$2"; shift 2 ;;
    -h|--help)
      echo "用法：assign.sh --feat <feat_id> --to <email>"
      exit 0 ;;
    *) echo "❌ 未知参数：$1" >&2; exit 1 ;;
  esac
done

if [[ -z "$FEAT" || -z "$TO" ]]; then
  echo "❌ 必需参数：--feat <id> --to <email>" >&2
  exit 1
fi

# email 校验（写入时把关，schema 层放行空串）
if [[ "$TO" != *"@"* ]]; then
  echo "❌ email 必须含 @：'$TO'" >&2
  exit 1
fi

STATE_FILE=".dac/state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "[DAC-STATE-003] ❌ .dac/state.json 不存在" >&2
  exit 1
fi
REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE" 2>/dev/null)
if [[ -z "$REQ_NAME" ]]; then
  echo "[DAC-STATE-003] ❌ state.json 缺少 req_name" >&2
  exit 1
fi

PLAN_JSON="$(get_change_dir "$REQ_NAME")/feature-plan.json"
if [[ ! -f "$PLAN_JSON" ]]; then
  echo "[DAC-PLAN-007] ❌ feature-plan.json 不存在：$PLAN_JSON" >&2
  exit 1
fi

# collab.json 缺失时警告：guard.sh 的单人短路条件是「无 collab.json 且 assignee 空」，
# 写了 assignee 但 collab.json 还没生成，guard.sh 会立刻 STATE-020 拦截本人以外的人。
# skill 分叉已保证「先写 collab.json 再 assign」，直接调 harness 的用户在这一步能拿到显式提醒。
COLLAB_JSON="$(get_change_dir "$REQ_NAME")/collab.json"
if [[ ! -f "$COLLAB_JSON" ]]; then
  echo "⚠️  $COLLAB_JSON 尚未生成；单独 assign 会让 guard.sh 立刻按协作规则拦截" >&2
  echo "   建议先写 collab.json（{\"mode\":\"multi\",\"initiated_by\":\"<发起人 email>\"}），再执行 assign" >&2
fi

# 判定 feat_id 是否存在（兼容 v0/v1）
EXISTS=$(jq -r --arg fid "$FEAT" '
  (if type=="object" then .features else . end)
  | map(select(.id == $fid)) | length
' "$PLAN_JSON")

if [[ "$EXISTS" != "1" ]]; then
  echo "[DAC-DEP-004] ❌ feat_id 不存在于 feature-plan.json：$FEAT" >&2
  exit 1
fi

# 原子写入 assignee
atomic_jq '
  if type=="object" then
    .features |= map(if .id == $fid then .assignee = $to else . end)
  else
    map(if .id == $fid then .assignee = $to else . end)
  end
' "$PLAN_JSON" --arg fid "$FEAT" --arg to "$TO"

echo "✅ 已将 feature=$FEAT 指派给 $TO"