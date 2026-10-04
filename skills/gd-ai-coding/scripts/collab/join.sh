#!/usr/bin/env bash
# join.sh — 第二人加入已有多人协作规划
# 用法：join.sh --req <req_name>
# 前置：
#   - openspec/changes/{req}/collab.json 存在
#   - openspec/changes/{req}/feature-plan.json 存在
#   - git config user.email 非空
#   - .dac/state.json 若已存在，其 req_name 必须与 <req> 相同（避免覆盖进行中任务）
# 行为（成功路径）：
#   1) 新建 .dac/（走 init-dac.sh --force 兜底）
#   2) 首次 join：覆写 state.json（phase=feature-planned、req_name、owner_committer、ddp_id、
#      completed/skipped/issues_features 从各 features/{id}/status.json 回填）
#      rejoin（同 req_name state.json 已存在）：只回填 completed/skipped/issues_features + updated_at，
#      保留 owner_committer / ddp_id / collab_token_summary_at 等本机手工调整过的字段
#   3) init-trace + record-trace --phase feature-planned
#   4) collab.json.ddp_id 非空则调用 report-ddp-binding.sh（仅首次 join；rejoin 认为已上报过）
#   5) setup-hook-wrapper（幂等）
# 备注：不写 state.json.collab_mode——所有读侧都以 openspec/changes/{req}/collab.json 存在为准，
#      collab_mode 字段无人读，写了反而在 reconcile 后出现假不同步。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../paths.sh"
source "$SCRIPT_DIR/../lib.sh"

METRICS_DIR="$SCRIPT_DIR/../metrics"
INIT_DAC="$SCRIPT_DIR/../init-dac.sh"

REQ=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --req) REQ="$2"; shift 2 ;;
    -h|--help)
      echo "用法：join.sh --req <req_name>"
      exit 0 ;;
    *) echo "❌ 未知参数：$1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REQ" ]]; then
  echo "❌ 缺少 --req <req_name>" >&2
  exit 1
fi

CURRENT_EMAIL=$(git config user.email 2>/dev/null || true)
if [[ -z "$CURRENT_EMAIL" ]]; then
  echo "❌ git config user.email 为空，无法加入（需求管道与个人管道都无法记到本人）" >&2
  echo "   请先执行：git config --global user.email you@didichuxing.com" >&2
  exit 1
fi

CHANGE_DIR="openspec/changes/$REQ"
COLLAB_JSON="$CHANGE_DIR/collab.json"
PLAN_JSON="$CHANGE_DIR/feature-plan.json"
FEATURES_DIR="$CHANGE_DIR/features"

if [[ ! -f "$COLLAB_JSON" ]]; then
  echo "❌ $COLLAB_JSON 不存在：该需求不是多人协作规划" >&2
  exit 1
fi
if [[ ! -f "$PLAN_JSON" ]]; then
  echo "[DAC-PLAN-007] ❌ feature-plan.json 不存在：$PLAN_JSON" >&2
  exit 1
fi

# 已有 .dac/state.json 且 req_name 不同 → 拒绝
REJOIN=false
if [[ -f ".dac/state.json" ]]; then
  EXIST_REQ=$(jq -r '.req_name // empty' .dac/state.json 2>/dev/null)
  if [[ -n "$EXIST_REQ" && "$EXIST_REQ" != "$REQ" ]]; then
    echo "❌ 本地已有进行中的任务：req_name=$EXIST_REQ，与目标 $REQ 不同" >&2
    echo "   请先完成或备份 .dac/，再重新 join；本脚本不做自动 --force 覆盖" >&2
    exit 1
  fi
  [[ "$EXIST_REQ" == "$REQ" ]] && REJOIN=true
fi

# 读取 collab.json.ddp_id（可能为空）
DDP_ID=$(jq -r '.ddp_id // ""' "$COLLAB_JSON")

# 步骤 1：初始化 .dac/
#   - 首次 join（无同名 state.json）→ init-dac.sh --force 保证干净
#   - rejoin（同 req_name state.json 已存在）→ 不 --force，避免清掉 .dac/trace/ 里已有的写入/提交事件
if [[ "$REJOIN" == "true" ]]; then
  echo "ℹ️  检测到已有同名 req 的 .dac/（req=$REQ），走幂等 rejoin，不清 trace" >&2
else
  bash "$INIT_DAC" --force >/dev/null
fi

# 步骤 2：更新 state.json
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# 从 features/{id}/status.json 回填 completed/skipped/issues
# - completed：done + done_with_issues（与 state-update.sh:353 / recovery.sh:169 一致）
# - issues：done_with_issues 单独一份，避免 rejoin 丢失严重度
# - skipped：skipped + failed
COMPLETED_JSON="[]"
SKIPPED_JSON="[]"
ISSUES_JSON="[]"
if [[ -d "$FEATURES_DIR" ]]; then
  COMPLETED_JSON=$(find "$FEATURES_DIR" -mindepth 2 -maxdepth 2 -name status.json \
    -exec sh -c 'jq -r "if .status==\"done\" or .status==\"done_with_issues\" then (.feature_id // \"\") else empty end" "$1" 2>/dev/null' _ {} \; 2>/dev/null \
    | sort -u | jq -R -s -c 'split("\n") | map(select(length > 0))')
  [[ -z "$COMPLETED_JSON" ]] && COMPLETED_JSON="[]"
  SKIPPED_JSON=$(find "$FEATURES_DIR" -mindepth 2 -maxdepth 2 -name status.json \
    -exec sh -c 'jq -r "if .status==\"skipped\" or .status==\"failed\" then (.feature_id // \"\") else empty end" "$1" 2>/dev/null' _ {} \; 2>/dev/null \
    | sort -u | jq -R -s -c 'split("\n") | map(select(length > 0))')
  [[ -z "$SKIPPED_JSON" ]] && SKIPPED_JSON="[]"
  ISSUES_JSON=$(find "$FEATURES_DIR" -mindepth 2 -maxdepth 2 -name status.json \
    -exec sh -c 'jq -r "if .status==\"done_with_issues\" then (.feature_id // \"\") else empty end" "$1" 2>/dev/null' _ {} \; 2>/dev/null \
    | sort -u | jq -R -s -c 'split("\n") | map(select(length > 0))')
  [[ -z "$ISSUES_JSON" ]] && ISSUES_JSON="[]"
fi

if [[ "$REJOIN" == "true" ]]; then
  # rejoin：只回填从 status.json 派生的字段，保留其他手工调整（owner_committer/ddp_id/collab_token_summary_at 等）
  atomic_jq '
    .completed_features = ($completed | unique)
    | .skipped_features = ($skipped | unique)
    | .issues_features = ($issues | unique)
    | .updated_at = $ts
  ' .dac/state.json \
    --arg ts "$NOW_ISO" \
    --argjson completed "$COMPLETED_JSON" \
    --argjson skipped "$SKIPPED_JSON" \
    --argjson issues "$ISSUES_JSON"
else
  # 首次 join：写入完整初始 state（不写 collab_mode，读侧全部以 collab.json 存在为准）
  atomic_jq '
    .phase = "feature-planned"
    | .req_name = $req
    | .owner_committer = $email
    | .ddp_id = (if $ddp == "" then null else $ddp end)
    | .completed_features = $completed
    | .skipped_features = $skipped
    | .issues_features = $issues
    | .updated_at = $ts
  ' .dac/state.json \
    --arg req "$REQ" \
    --arg email "$CURRENT_EMAIL" \
    --arg ddp "$DDP_ID" \
    --arg ts "$NOW_ISO" \
    --argjson completed "$COMPLETED_JSON" \
    --argjson skipped "$SKIPPED_JSON" \
    --argjson issues "$ISSUES_JSON"
fi

# 步骤 3：init-trace + record-trace --phase feature-planned
if [[ -x "$METRICS_DIR/init-trace.sh" ]]; then
  bash "$METRICS_DIR/init-trace.sh" || true
fi
if [[ -x "$METRICS_DIR/record-trace.sh" ]]; then
  bash "$METRICS_DIR/record-trace.sh" --phase feature-planned || true
fi

# 步骤 4：ddp_id 非空且非 rejoin 时报备绑定（rejoin 认为首次 join 已上报，不重复）
if [[ -n "$DDP_ID" && "$REJOIN" != "true" ]]; then
  if [[ -x "$METRICS_DIR/report-ddp-binding.sh" ]]; then
    bash "$METRICS_DIR/report-ddp-binding.sh" --trace-req "$REQ" --ddp-req "$DDP_ID" || true
  fi
fi

# 步骤 5：setup-hook-wrapper 幂等注入
if [[ -x "$METRICS_DIR/setup-hook-wrapper.sh" ]]; then
  bash "$METRICS_DIR/setup-hook-wrapper.sh" || true
fi

if [[ "$REJOIN" == "true" ]]; then
  echo "✅ 已 rejoin 协作需求：${REQ}（回填 completed/skipped/issues，保留本机 owner_committer/ddp_id）"
else
  echo "✅ 已加入协作需求：${REQ}（owner_committer=${CURRENT_EMAIL}，phase=feature-planned）"
fi