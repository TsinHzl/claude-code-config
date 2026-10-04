#!/usr/bin/env bash
# =============================================================================
# report-ddp-binding.sh — 工作流起点将 trace req_name 绑定到 DDP 需求
# =============================================================================
#
# 职责：
#   SKILL.md 阶段 1.2 在 DDP 验证通过后调用，向后端 dac_req_binding 表写入一条
#   trace↔DDP 绑定。看板（dashboard-server.py / dashboard-template.html）的 trace 卡
#   与 DDP 卡合并完全依赖此绑定表（前端 _BINDINGS），不做 req_name/id 字符串匹配，
#   因此起点不写绑定则两张卡在看板上各自独立、无法体现「本 trace 属于该 DDP 需求」。
#
# 用法：
#   report-ddp-binding.sh --trace-req <req_name> --ddp-req <T-IBT-xxx | R-IBG-xxx>
#
#   --trace-req  本地 trace 的 req_name（小写，如 r-ibg-689979）
#   --ddp-req    看板 DDP 卡的 req_name（大写 T-IBT-xxx 或 R-IBG-xxx 形式，与
#                fetch-ddp-detail.sh 的解析结果一致，默认任务级）
#
# 失败处理：
#   后端未配置（backend-config.json 缺失/字段空/jq 不可用）时静默跳过（沿用
#   report-trace-backend.sh 的降级语义），退出码 0，绝不阻断工作流。
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../runtime.sh"
dac_resolve_runtime || exit 0
# shellcheck source=/dev/null
source "$SCRIPT_DIR/report-trace-backend.sh"

TRACE_REQ=""
DDP_REQ=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --trace-req)
      [[ -z "${2-}" ]] && { echo "[report-ddp-binding] ❌ --trace-req 缺少值" >&2; exit 1; }
      TRACE_REQ="$2"; shift 2 ;;
    --ddp-req)
      [[ -z "${2-}" ]] && { echo "[report-ddp-binding] ❌ --ddp-req 缺少值" >&2; exit 1; }
      DDP_REQ="$2"; shift 2 ;;
    *) echo "[report-ddp-binding] ❌ 未知参数: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$TRACE_REQ" || -z "$DDP_REQ" ]]; then
  echo "[report-ddp-binding] ❌ 必须同时提供 --trace-req 和 --ddp-req" >&2
  exit 1
fi

# 防御性归一化 ddp_req：看板 DDP 卡的 req_name 恒为大写 T-IBT-<num> 或 R-IBG-<num>（取决于
# fetch-ddp-detail.sh 的解析结果），而绑定表是精确字符串匹配。上游 fetch-ddp-detail.sh 的
# sequence 字段为空、且用户输入纯数字时，传入值可能是裸数字（如 689979），与看板卡 req_name
# 不匹配会导致绑定静默失效。此处兜底：纯数字按任务优先语义补 T-IBT- 前缀（与
# fetch-ddp-detail.sh 的默认解析优先级一致），再统一转大写。
case "$DDP_REQ" in
  [0-9]*) DDP_REQ="T-IBT-$DDP_REQ" ;;
esac
DDP_REQ=$(printf '%s' "$DDP_REQ" | tr '[:lower:]' '[:upper:]')

_report_ddp_binding "$TRACE_REQ" "$DDP_REQ"
