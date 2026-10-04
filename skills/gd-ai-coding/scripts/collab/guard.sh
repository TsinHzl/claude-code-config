#!/usr/bin/env bash
# guard.sh — 多人协作模式下的 feature 启动门禁
# 用法：guard.sh <feat_id>
# 判定规则（按 openspec/changes/{req}/collab.json 是否存在决定是否处于协作模式）：
#   1) 单人模式（无 collab.json）：
#      - assignee 为空 或 assignee == 当前 git email → exit 0
#      - assignee 非空且 != 当前 git email → [DAC-STATE-020]（规划期"锁"语义）
#      不做 rules 3/4/5：单人模式下 status.json 从未被写入，检查全部误伤
#   2) [DAC-STATE-020] 协作模式下 assignee 非空且不是当前 git email
#   3) [DAC-STATE-021] status.json.claimed_by 为他人且 status=in_progress（claimed_by == 当前用户视为恢复，放行）
#   4) [DAC-DEP-003]   任一 dependency 的 status.json.status 不是 done
#   5) [DAC-PLAN-006]  与其他 in_progress feature 的 proposal_scope 文件集合有交集

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../paths.sh"

FEAT_ID="${1:-}"
if [[ -z "$FEAT_ID" ]]; then
  echo "用法：guard.sh <feat_id>" >&2
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

CHANGE_DIR="$(get_change_dir "$REQ_NAME")"
PLAN_JSON="$CHANGE_DIR/feature-plan.json"
COLLAB_JSON="$CHANGE_DIR/collab.json"
FEATURES_DIR="$CHANGE_DIR/features"

if [[ ! -f "$PLAN_JSON" ]]; then
  echo "[DAC-PLAN-007] ❌ feature-plan.json 不存在：$PLAN_JSON" >&2
  exit 1
fi

# 从 plan 里取目标 feature 的 assignee / dependencies / proposal_scope
FEAT_JSON=$(jq -c --arg fid "$FEAT_ID" '
  (if type=="object" then .features else . end)
  | map(select(.id == $fid)) | .[0] // empty
' "$PLAN_JSON")

if [[ -z "$FEAT_JSON" ]]; then
  echo "[DAC-DEP-004] ❌ feat_id 不存在于 feature-plan.json：$FEAT_ID" >&2
  exit 1
fi

ASSIGNEE=$(echo "$FEAT_JSON" | jq -r '.assignee // ""')

# 协作模式判定：仅以 collab.json 存在为准
COLLAB_MODE=false
[[ -f "$COLLAB_JSON" ]] && COLLAB_MODE=true

CURRENT_EMAIL=$(git config user.email 2>/dev/null || true)
# email 比较：trim + 小写
norm() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'; }
CUR_NORM=$(norm "$CURRENT_EMAIL")
ASN_NORM=$(norm "$ASSIGNEE")

# 单人模式（无 collab.json）：assignee 是"规划期锁"，不做 status.json 相关的 rules 3/4/5
#   - assignee 空 或 == 自己 → 短路 exit 0
#   - assignee 是他人 → STATE-020
if [[ "$COLLAB_MODE" == "false" ]]; then
  if [[ -z "$ASSIGNEE" || "$ASN_NORM" == "$CUR_NORM" ]]; then
    exit 0
  fi
  echo "[DAC-STATE-020] ❌ 该 feature 指派给 ${ASSIGNEE}，当前用户 ${CURRENT_EMAIL} 无权启动" >&2
  echo "   若确需转让，请规划发起人重新 assign 或人工调整 feature-plan.json" >&2
  exit 1
fi

# 规则 2：协作模式下 assignee 非空且不是当前用户
if [[ -n "$ASSIGNEE" && "$ASN_NORM" != "$CUR_NORM" ]]; then
  echo "[DAC-STATE-020] ❌ 该 feature 指派给 ${ASSIGNEE}，当前用户 ${CURRENT_EMAIL} 无权启动" >&2
  echo "   若确需转让，请规划发起人重新 assign 或人工调整 feature-plan.json" >&2
  exit 1
fi

# 规则 3：他人 in_progress 认领
STATUS_JSON="$FEATURES_DIR/$FEAT_ID/status.json"
if [[ -f "$STATUS_JSON" ]]; then
  CB=$(jq -r '.claimed_by // ""' "$STATUS_JSON")
  CS=$(jq -r '.status // ""' "$STATUS_JSON")
  CB_NORM=$(norm "$CB")
  if [[ "$CS" == "in_progress" && -n "$CB" && "$CB_NORM" != "$CUR_NORM" ]]; then
    echo "[DAC-STATE-021] ❌ 该 feature 已被 ${CB} 认领（in_progress），不要抢认领" >&2
    echo "   请等待 ${CB} 完成并 push，本机 git pull 到 status.json=done 后再启动" >&2
    exit 1
  fi
  # claimed_by == 当前用户 视为恢复：不阻断,继续走下方依赖/交叉校验
fi

# 规则 4：dependencies 未 done
DEPS=$(echo "$FEAT_JSON" | jq -r '.dependencies[]?' 2>/dev/null)
while IFS= read -r dep; do
  [[ -z "$dep" ]] && continue
  DEP_STATUS_FILE="$FEATURES_DIR/$dep/status.json"
  # 从 plan 里查依赖的 assignee 用于提示（依赖 status.json 缺失时才有意义）
  DEP_ASSIGNEE=$(jq -r --arg fid "$dep" '
    (if type=="object" then .features else . end)
    | map(select(.id == $fid)) | .[0].assignee // ""
  ' "$PLAN_JSON")
  if [[ ! -f "$DEP_STATUS_FILE" ]]; then
    hint=""
    [[ -n "$DEP_ASSIGNEE" ]] && hint="（指派给 ${DEP_ASSIGNEE}）"
    echo "[DAC-DEP-003] ❌ 依赖 ${dep}${hint} 的 status.json 不存在（未认领/未完成）" >&2
    echo "   请等待依赖方完成并 git commit + push，然后 git pull 该 status.json" >&2
    exit 1
  fi
  DS=$(jq -r '.status // ""' "$DEP_STATUS_FILE")
  DEP_CB=$(jq -r '.claimed_by // ""' "$DEP_STATUS_FILE")
  if [[ "$DS" != "done" ]]; then
    hint=""
    [[ -n "$DEP_CB" ]] && hint="（by ${DEP_CB}）"
    echo "[DAC-DEP-003] ❌ 依赖 ${dep} 的 status.json.status='${DS}'${hint}（应为 done）" >&2
    exit 1
  fi
done <<< "$DEPS"

# 规则 5：与其他 in_progress feature 文件交叉
TARGET_FILES=$(echo "$FEAT_JSON" | jq -r '(.proposal_scope.new_files // []) + (.proposal_scope.modified_files // []) | .[]?' | sort -u)

if [[ -d "$FEATURES_DIR" && -n "$TARGET_FILES" ]]; then
  while IFS= read -r other_dir; do
    [[ -z "$other_dir" ]] && continue
    other_id=$(basename "$other_dir")
    [[ "$other_id" == "$FEAT_ID" ]] && continue
    other_status_file="$other_dir/status.json"
    [[ -f "$other_status_file" ]] || continue
    other_status=$(jq -r '.status // ""' "$other_status_file")
    [[ "$other_status" == "in_progress" ]] || continue
    other_cb=$(jq -r '.claimed_by // ""' "$other_status_file")

    other_files=$(jq -r --arg fid "$other_id" '
      (if type=="object" then .features else . end)
      | map(select(.id == $fid)) | .[0]
      | (.proposal_scope.new_files // []) + (.proposal_scope.modified_files // [])
      | .[]?
    ' "$PLAN_JSON" | sort -u)

    inter=$(comm -12 <(echo "$TARGET_FILES") <(echo "$other_files") | sed '/^$/d')
    if [[ -n "$inter" ]]; then
      hint=""
      [[ -n "$other_cb" ]] && hint="（by ${other_cb}）"
      echo "[DAC-PLAN-006] ❌ 与 in_progress feature ${other_id}${hint} 的文件集合有交集：" >&2
      echo "$inter" | sed 's/^/   /' >&2
      exit 1
    fi
  done < <(find "$FEATURES_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
fi

exit 0