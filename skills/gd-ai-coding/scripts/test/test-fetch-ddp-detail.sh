#!/usr/bin/env bash
# test-fetch-ddp-detail.sh — fetch-ddp-detail.sh 单元测试
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FETCH_SCRIPT="$SCRIPT_DIR/ddp/fetch-ddp-detail.sh"
PASS=0
FAIL=0

_assert_exit() {
  local desc="$1" expected="$2"
  shift 2
  set +e
  "$@" >/dev/null 2>&1
  local actual=$?
  set -e
  if [ "$actual" -eq "$expected" ]; then
    echo "  ✅ $desc (exit $actual)"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $desc — expected exit $expected, got $actual"
    FAIL=$((FAIL + 1))
  fi
}

# 断言 validate_ddp_id 输出（成功路径）；期望空串表示应校验失败（return 1）
_assert_validate() {
  local desc="$1" input="$2" expected="$3" actual
  set +e
  actual=$(validate_ddp_id "$input" 2>/dev/null)
  local rc=$?
  set -e
  [ "$rc" -ne 0 ] && actual=""   # 校验失败统一归一为空串比对
  if [ "$actual" = "$expected" ]; then
    echo "  ✅ $desc (→ '${actual}')"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $desc — expected '${expected}', got '${actual}'"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== test-fetch-ddp-detail.sh ==="

# --- 格式校验 ---
echo ""
echo "[格式校验]"
_assert_exit "无参数 → exit 1" 1 bash "$FETCH_SCRIPT"
_assert_exit "空 ID → exit 1" 1 bash "$FETCH_SCRIPT" --ddp-id ""
_assert_exit "非法格式 abc → exit 1" 1 bash "$FETCH_SCRIPT" --ddp-id "abc"
_assert_exit "非法格式含空格 → exit 1" 1 bash "$FETCH_SCRIPT" --ddp-id "R-IBG 123"
_assert_exit "非法格式下划线 → exit 1" 1 bash "$FETCH_SCRIPT" --ddp-id "R_IBG_123"

# --- validate_ddp_id 格式标准化（确定性，直接 source lib.sh，不依赖 MCP）---
echo ""
echo "[validate_ddp_id 格式标准化]"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib.sh"
_assert_validate "T-IBT 任务链接 → 提取并大写"      "https://ddp.intra.xiaojukeji.com/issue/story/T-IBT-626806?backUrl=/issue/list?issureDirId=53" "T-IBT-626806"
_assert_validate "T-IBT 裸 ID → 原样"               "T-IBT-626806" "T-IBT-626806"
_assert_validate "t-ibt 小写裸 ID → 标准化大写"     "t-ibt-626806" "T-IBT-626806"
_assert_validate "R-IBG 需求链接回归 → 提取并大写"  "https://ddp.intra.xiaojukeji.com/requirement/story/R-IBG-689979" "R-IBG-689979"
_assert_validate "R-IBG 裸 ID 回归 → 原样"          "R-IBG-689979" "R-IBG-689979"
_assert_validate "纯数字回归 → 原样"                "716631" "716631"
_assert_validate "T_IBT 下划线非法 → 拒绝"          "T_IBT_123" ""

# --- resolvedKind 字段格式契约（不依赖网络）---
# 契约来源：fetch-ddp-detail.sh 内联的 3 处结果组装 jq -n（issue 分支 L239-245 / requirement
# 0 关联任务分支 L270-276 / requirement 1 关联任务分支 L296-302，1 任务分支复用与 issue 分支
# 相同的过滤器模板）。JSON 组装逻辑内联在主流程中而非独立函数，此处按 design.md 已记录的取舍
# 逐字复制过滤器文本验证输出契约，不重构脚本为纯函数。若脚本内联过滤器变更，需手动同步此处。
echo ""
echo "[resolvedKind 格式契约]"

if ! command -v jq &>/dev/null; then
  echo "  ⏭️  jq 未安装，跳过"
else
  _assert_json_keys() {
    local desc="$1" json="$2" expected_kind="$3" ok=1 k kind
    for k in title prd requirementId releaseVersion resolvedKind; do
      echo "$json" | jq -e --arg k "$k" 'has($k)' >/dev/null 2>&1 || ok=0
    done
    kind=$(echo "$json" | jq -r '.resolvedKind' 2>/dev/null)
    [ "$kind" = "$expected_kind" ] || ok=0
    if [ "$ok" -eq 1 ]; then
      echo "  ✅ $desc"
      PASS=$((PASS + 1))
    else
      echo "  ❌ $desc — got: $json"
      FAIL=$((FAIL + 1))
    fi
  }

  ISSUE_JSON=$(jq -n \
    --arg title "任务标题" \
    --arg prd "https://prd.example.com" \
    --arg requirementId "T-IBT-123456" \
    --arg releaseVersion "Global司机端7.10.42" \
    --arg resolvedKind "issue" \
    '{"title":$title,"prd":$prd,"requirementId":$requirementId,"releaseVersion":$releaseVersion,"resolvedKind":$resolvedKind}')
  _assert_json_keys "issue 分支（T-IBT- 直接解析 / 需求 1 关联任务自动采用共用）输出含 5 个契约字段" "$ISSUE_JSON" "issue"

  REQ_ZERO_JSON=$(jq -n \
    --arg title "需求标题" \
    --arg prd "https://prd.example.com" \
    --arg requirementId "R-IBG-999999" \
    --arg releaseVersion "" \
    --arg resolvedKind "requirement" \
    '{"title":$title,"prd":$prd,"requirementId":$requirementId,"releaseVersion":$releaseVersion,"resolvedKind":$resolvedKind}')
  _assert_json_keys "requirement 0 关联任务分支输出含 5 个契约字段" "$REQ_ZERO_JSON" "requirement"

  _REQ_ZERO_RV=$(echo "$REQ_ZERO_JSON" | jq -r '.releaseVersion')
  if [ "$_REQ_ZERO_RV" = "" ]; then
    echo "  ✅ requirement 0 关联任务分支 releaseVersion 恒为空串（无法向下解析版本号）"
    PASS=$((PASS + 1))
  else
    echo "  ❌ requirement 0 关联任务分支 releaseVersion 应为空串，实际 '$_REQ_ZERO_RV'"
    FAIL=$((FAIL + 1))
  fi
fi

# --- exit code 3 候选列表 JSON 结构契约（不依赖网络）---
# 契约来源：fetch-ddp-detail.sh L306-323（≥2 关联任务分支：CANDIDATES 累加过滤器
# '. + [{"id":$id,"title":$title}]' + 收尾包装过滤器）。
echo ""
echo "[exit code 3 候选列表 JSON 结构契约]"

if ! command -v jq &>/dev/null; then
  echo "  ⏭️  jq 未安装，跳过"
else
  CANDIDATES="[]"
  CANDIDATES=$(echo "$CANDIDATES" | jq --arg id "T-IBT-111" --arg title "任务一" '. + [{"id":$id,"title":$title}]')
  CANDIDATES=$(echo "$CANDIDATES" | jq --arg id "T-IBT-222" --arg title "任务二" '. + [{"id":$id,"title":$title}]')
  EXIT3_JSON=$(jq -n \
    --arg requirementTitle "需求标题" \
    --argjson candidates "$CANDIDATES" \
    '{"requirementTitle":$requirementTitle,"candidates":$candidates}')

  _e3_has_keys=$(echo "$EXIT3_JSON" | jq -e 'has("requirementTitle") and has("candidates")' 2>/dev/null || echo "false")
  _e3_count=$(echo "$EXIT3_JSON" | jq '.candidates | length' 2>/dev/null || echo -1)
  _e3_item_keys=$(echo "$EXIT3_JSON" | jq -e '.candidates | all(has("id") and has("title"))' 2>/dev/null || echo "false")

  if [ "$_e3_has_keys" = "true" ] && [ "$_e3_count" -eq 2 ] && [ "$_e3_item_keys" = "true" ]; then
    echo "  ✅ exit 3 输出含 requirementTitle + candidates 数组，每项含 id/title"
    PASS=$((PASS + 1))
  else
    echo "  ❌ exit 3 JSON 结构不符：$EXIT3_JSON"
    FAIL=$((FAIL + 1))
  fi
fi

# --- mcporter 配置预检 ---
echo ""
echo "[mcporter 配置预检]"
# 与 fetch-ddp-detail.sh 同口径：mcporter 聚合多来源配置（~/.mcporter/mcporter.json、
# ~/.claude.json 等），用 `config list` 判定 ddp 是否可用（不走网络探活）。只读单个
# mcporter.json 会在 ddp 仅注册于 ~/.claude.json 时误判"未配置"，与运行时行为不一致。
# 命中判定用 herestring（避免 `| grep -q` 在 pipefail 下因 grep 提前退出触发 SIGPIPE 误判）。
if ! command -v mcporter &>/dev/null || ! command -v jq &>/dev/null; then
  echo "  ⏭️  mcporter 或 jq 未安装，跳过"
elif ! _mcp_servers=$(mcporter config list 2>&1) || ! grep -Eqi '(^|[(, ])ddp([), ]|$)' <<<"$_mcp_servers"; then
  # 任何来源均未识别到 ddp → 脚本应因缺配置 exit 1
  _assert_exit "ddp 未配置 → exit 1" 1 bash "$FETCH_SCRIPT" --ddp-id "R-IBG-999999"
else
  echo "  ⏭️  ddp 已配置，跳过配置缺失测试"
  # 测试不存在的需求/任务（假设极大 ID 不存在）——覆盖 R-IBG 需求 + T-IBT 任务两条主执行路径
  echo ""
  echo "[需求/任务不存在]"
  _assert_exit "不存在的 R-IBG 需求 ID → exit 2" 2 bash "$FETCH_SCRIPT" --ddp-id "R-IBG-000000001"
  _assert_exit "不存在的 T-IBT 任务 ID → exit 2" 2 bash "$FETCH_SCRIPT" --ddp-id "T-IBT-999999999"
fi

# --- 汇总 ---
echo ""
echo "=== 结果：✅ $PASS passed, ❌ $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1