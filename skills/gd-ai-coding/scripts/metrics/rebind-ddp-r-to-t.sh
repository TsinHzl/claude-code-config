#!/usr/bin/env bash
# =============================================================================
# rebind-ddp-r-to-t.sh — 将历史遗留的 R- 需求级绑定自动纠正为 T- 任务级绑定
# =============================================================================
#
# 职责：
#   读取后端全量 trace↔DDP 绑定表，筛选出所有 ddp_req 为 R-IBG-xxx（需求级）的记录，
#   对每条用「任务优先解析」（复用 fetch-ddp-detail.sh）判断其是否已拆出唯一对应的
#   T-IBT-xxx 任务；能唯一确定则调用 report-ddp-binding.sh 改绑，否则跳过。
#
# 挂载点：
#   scripts/metrics/refresh-ddp.sh 每次刷新时作为 Step 5 调用。
#
# 退出码语义：
#   best-effort，任何阶段失败（后端未配置/绑定表拉取失败/单条记录处理异常）都不
#   中断脚本，最终始终 exit 0，绝不影响 refresh-ddp.sh 主流程退出码。
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../runtime.sh"
dac_resolve_runtime || exit 0
# shellcheck source=/dev/null
source "$SCRIPT_DIR/report-trace-backend.sh"

FETCH_DDP_DETAIL="$SCRIPT_DIR/../ddp/fetch-ddp-detail.sh"
REPORT_DDP_BINDING="$SCRIPT_DIR/report-ddp-binding.sh"

echo "[rebind-ddp-r-to-t] 开始检查历史 R- 绑定是否可自动纠正为 T-" >&2

_dac_trace_backend_config || { echo "[rebind-ddp-r-to-t] ℹ️  后端未配置，跳过" >&2; exit 0; }

BINDINGS_JSON=$(curl --max-time 8 --silent --fail \
  -H "Authorization: Bearer $_DAC_TRACE_TOKEN" \
  "$_DAC_TRACE_URL/api/v1/ddp/bindings" 2>/dev/null)
if [ -z "$BINDINGS_JSON" ]; then
  echo "[rebind-ddp-r-to-t] ⚠️  绑定表请求失败，跳过本轮" >&2
  exit 0
fi

# 候选集：ddp_req 匹配 R-IBG-xxx（大小写不敏感）的记录，转成 "trace_req\tddp_req" 行
CANDIDATES=$(echo "$BINDINGS_JSON" | jq -r '
  to_entries
  | map(select(.value | test("^[Rr]-[Ii][Bb][Gg]-[0-9]+$")))
  | .[] | [.key, .value] | @tsv' 2>/dev/null)

if [ -z "$CANDIDATES" ]; then
  echo "[rebind-ddp-r-to-t] ℹ️  没有待纠正的 R- 绑定，跳过" >&2
  exit 0
fi

CANDIDATE_COUNT=$(echo "$CANDIDATES" | wc -l | tr -d ' ')
echo "[rebind-ddp-r-to-t] 候选集 ${CANDIDATE_COUNT} 条" >&2

# 逐条处理候选集：任一条处理异常都只跳过该条，不中断循环，脚本级别恒定 exit 0
while IFS=$'\t' read -r trace_req ddp_req; do
  [ -z "$trace_req" ] && continue
  [ -z "$ddp_req" ] && continue

  DETAIL_JSON=$("$FETCH_DDP_DETAIL" --ddp-id "$ddp_req" 2>/dev/null)
  DETAIL_EXIT=$?

  case "$DETAIL_EXIT" in
    0)
      RESOLVED_KIND=$(echo "$DETAIL_JSON" | jq -r '.resolvedKind // empty' 2>/dev/null)
      if [ "$RESOLVED_KIND" = "issue" ]; then
        NEW_DDP_REQ=$(echo "$DETAIL_JSON" | jq -r '.requirementId // empty' 2>/dev/null)
        if [ -z "$NEW_DDP_REQ" ]; then
          echo "[rebind-ddp-r-to-t] ⚠️  ${trace_req}: 解析出 issue 但 requirementId 为空，跳过" >&2
          continue
        fi
        # report-ddp-binding.sh 对下游 POST 失败仅记日志、恒定 exit 0，退出码无法用于
        # 区分后端是否真实写入成功，因此不做二元成功/失败判定，只记录请求已提交
        "$REPORT_DDP_BINDING" --trace-req "$trace_req" --ddp-req "$NEW_DDP_REQ" >/dev/null 2>&1
        echo "[rebind-ddp-r-to-t] ✅ 已提交改绑请求: trace_req=${trace_req} ${ddp_req} -> ${NEW_DDP_REQ}"
      elif [ "$RESOLVED_KIND" = "requirement" ]; then
        echo "[rebind-ddp-r-to-t] ℹ️  ${trace_req}: ${ddp_req} 下暂无关联任务，保留原绑定" >&2
      else
        echo "[rebind-ddp-r-to-t] ⚠️  ${trace_req}: ${ddp_req} 返回结果无法解析（resolvedKind 异常），跳过" >&2
      fi
      ;;
    3)
      echo "[rebind-ddp-r-to-t] ⚠️  ${trace_req}: ${ddp_req} 关联多个候选任务，无法自动判断，跳过" >&2
      ;;
    *)
      echo "[rebind-ddp-r-to-t] ⚠️  ${trace_req}: ${ddp_req} 查询失败（exit ${DETAIL_EXIT}），跳过" >&2
      ;;
  esac
done <<< "$CANDIDATES"

echo "[rebind-ddp-r-to-t] 本轮处理完成" >&2
exit 0
