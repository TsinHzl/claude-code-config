#!/usr/bin/env bash
# fetch-ddp-detail.sh — 通过 mcporter 调用 DDP MCP 获取需求/任务详情
#
# 用法：fetch-ddp-detail.sh --ddp-id <R-IBG-XXXXXX(需求) | T-IBT-XXXXXX(任务) | 纯数字 | DDP链接>
#
# 解析优先级：T-IBT- 直接按任务解析；纯数字优先按任务(getIssueDetail)尝试，未命中回退按需求
# (getRequirementDetail)解析；R-IBG- 直接按需求解析。需求解析成功后按关联任务数向下解析：
# 0 个→退回需求级；1 个→自动采用该任务；≥2 个→exit 3 由用户消歧。
#
# Exit codes:
#   0 = 成功（stdout 输出 JSON: {"title","prd","requirementId","releaseVersion","resolvedKind"}）
#   1 = MCP 不可用 / 网络错误 / 参数错误
#   2 = 需求/任务不存在或无权限
#   3 = 需求关联多个任务，需用户消歧（stdout 输出 JSON: {"requirementTitle","candidates":[{"id","title"}]}）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

TIMEOUT=30

# --- 参数解析 ---
DDP_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ddp-id)
      [[ -z "${2-}" ]] && { echo "[fetch-ddp-detail] ❌ --ddp-id 缺少值" >&2; exit 1; }
      DDP_ID="$2"; shift 2 ;;
    *) echo "[fetch-ddp-detail] ❌ 未知参数: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$DDP_ID" ]] && { echo "[fetch-ddp-detail] ❌ 必须提供 --ddp-id <id>" >&2; exit 1; }

# --- 格式校验 + 标准化 ---
DDP_ID_RAW="$DDP_ID"
DDP_ID=$(validate_ddp_id "$DDP_ID") || {
  echo "[fetch-ddp-detail] ❌ 格式无效（支持：DDP 链接如 .../requirement/story/R-IBG-XXXXXX 或 .../issue/story/T-IBT-XXXXXX、R-IBG-XXXXXX、T-IBT-XXXXXX、纯数字）：$DDP_ID_RAW" >&2
  exit 1
}

# --- 依赖预检 ---
if ! command -v mcporter &>/dev/null; then
  echo "[fetch-ddp-detail] ❌ mcporter CLI 未安装" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "[fetch-ddp-detail] ❌ jq 未安装" >&2
  exit 1
fi

# --- DDP MCP 可用性检测 ---
# mcporter 会聚合多来源 MCP 配置（~/.mcporter/mcporter.json、~/.claude.json、
# ~/.claude/settings.json 等）并据此路由 `mcporter call ddp.*`。只 grep 单个 mcporter.json
# 会在 ddp 仅注册于 Claude Code 配置（~/.claude.json）时误判"未配置"，而实际调用可用。
# 以 mcporter 自身识别的服务器清单为准（config list 不走网络探活，启动无阻塞风险）。
# 严格区分「命令执行失败」与「确实未配置」：把 config list 放进 if 条件捕获退出码，非零时
# 报「执行失败」而非「未配置」，避免 CLI 版本不兼容/内部异常时重蹈同类误报。stderr 一并
# 捕获用于诊断。命中判定再用 herestring 匹配（避免 `| grep -q` 在 pipefail 下因 grep 提前退出
# 触发 SIGPIPE 误判失败）。
if ! _mcp_servers=$(mcporter config list 2>&1); then
  echo "[DAC-DEP-010] mcporter config list 执行失败，无法确认 DDP 配置状态：$_mcp_servers" >&2
  exit 1
fi
if ! grep -Eqi '(^|[(, ])ddp([), ]|$)' <<<"$_mcp_servers"; then
  echo "[DAC-DEP-010] DDP MCP 未配置（mcporter 在任何来源均未识别到名为 ddp 的服务器）。请在 ~/.mcporter/mcporter.json 或 ~/.claude.json 的 mcpServers 中添加 ddp 配置" >&2
  exit 1
fi

# macOS 兼容：优先 timeout，其次 gtimeout（brew install coreutils），均无则不限时
_timeout_cmd=""
if command -v timeout &>/dev/null; then
  _timeout_cmd="timeout $TIMEOUT"
elif command -v gtimeout &>/dev/null; then
  _timeout_cmd="gtimeout $TIMEOUT"
fi

# _driver_version_of_issue — 从单个任务的 dpmVersion 字段提取司机端版本名（去 [MMDD] 前缀）
# 参数：$1 = 任务纯数字 ID
# 输出：版本名（如 "Global司机端7.10.42"）并 return 0；未匹配到司机端版本则输出空并 return 1
_driver_version_of_issue() {
  local task_id="$1" field_args field_result version_name
  [[ -z "$task_id" ]] && return 1
  field_args=$(jq -n --argjson id "$task_id" '{"businessType":"issue","businessId":$id,"fieldNames":["dpmVersion"]}')
  field_result=$($_timeout_cmd mcporter call ddp.getFieldMetas --args "$field_args" --output json 2>/dev/null) || return 1

  # 从 currentValue + options 树中匹配司机端版本名
  version_name=$(echo "$field_result" | jq -r '
    .data[0] as $f |
    ($f.currentValue // []) as $cur |
    [($f.options[]?.children[]?) | select(.id as $i | $cur | index($i)) | .name] |
    map(select(test("司机端"))) |
    first // ""
  ' 2>/dev/null | sed 's/^\[[0-9]*\]//')

  [[ -n "$version_name" ]] || return 1
  echo "$version_name"
}

# _associated_task_ids — 从需求详情响应 JSON 中提取关联任务 ID 列表
# 参数：$1 = getRequirementDetail 返回的完整响应 JSON
# 输出：每行一个纯数字任务 ID；无关联任务时无输出
_associated_task_ids() {
  local req_result="$1"
  echo "$req_result" | jq -r '
    [.data.modules[]?
     | select(.name == "tech-info")
     | .subModules[]?
     | select(.fieldName == "issue-table")
     | .value[]?.id // empty] | .[]' 2>/dev/null
}

# _fetch_detail — 调用给定 DDP MCP 方法并统一分类结果（超时/网络错误 vs 不存在/无权限）
# 参数：$1 = DETAIL_METHOD  $2 = CALL_ARGS(JSON)
# 返回：0=成功（设置 _FETCH_RESULT 为完整响应、_FETCH_DATA 为 .data）；1=网络/进程错误；
#       2=不存在或无权限（业务错误）
# 副作用：失败时把错误信息写入 _FETCH_ERR_MSG
_fetch_detail() {
  local method="$1" call_args="$2" exit_code=0 result

  result=$($_timeout_cmd mcporter call "$method" --args "$call_args" --output json 2>/dev/null) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    # 超时优先判定
    if [ "$exit_code" -eq 124 ]; then
      _FETCH_ERR_MSG="DDP MCP 调用超时（${TIMEOUT}s）"
      return 1
    fi
    # mcporter 对 MCP 工具的 isError 响应（记录不存在/无权限）同样返回非零退出码，
    # 但 result 已捕获到 isError JSON。这类归为 2（不存在/无权限）；
    # 仅真正的网络/进程错误（result 为空或非 isError）才归 1。
    if [ -n "$result" ] && [ "$(echo "$result" | jq -r '.isError // false' 2>/dev/null)" = "true" ]; then
      _FETCH_ERR_MSG=$(echo "$result" | jq -r '.content[0].text // "记录不存在或无权限"' 2>/dev/null)
      [ -n "$_FETCH_ERR_MSG" ] || _FETCH_ERR_MSG="记录不存在或无权限"
      return 2
    fi
    _FETCH_ERR_MSG="DDP MCP 调用失败（exit ${exit_code}）"
    return 1
  fi

  if [ -z "$result" ]; then
    _FETCH_ERR_MSG="不存在或无权限"
    return 2
  fi

  if [ "$(echo "$result" | jq -r '.isError // false' 2>/dev/null)" = "true" ]; then
    _FETCH_ERR_MSG=$(echo "$result" | jq -r '.content[0].text // "未知错误"' 2>/dev/null)
    return 2
  fi

  local biz_code
  biz_code=$(echo "$result" | jq -r '.code // 0' 2>/dev/null)
  if [ "$biz_code" != "0" ]; then
    _FETCH_ERR_MSG=$(echo "$result" | jq -r '.message // "未知错误"' 2>/dev/null)
    return 2
  fi

  local data
  data=$(echo "$result" | jq '.data // empty' 2>/dev/null)
  if [ -z "$data" ] || [ "$data" = "null" ]; then
    _FETCH_ERR_MSG="不存在或无权限"
    return 2
  fi

  _FETCH_RESULT="$result"
  _FETCH_DATA="$data"
  return 0
}

# _dispatch_fail — 统一"网络错误 exit 1 / 不存在 exit 2"收尾，读取 _FETCH_ERR_MSG 作为详情
# 参数：$1 = _fetch_detail 的返回码（1 或 2）  $2 = 不存在时的提示前缀
_dispatch_fail() {
  local status="$1" not_found_msg="$2"
  if [ "$status" -eq 1 ]; then
    echo "[fetch-ddp-detail] ❌ ${_FETCH_ERR_MSG}" >&2
    exit 1
  fi
  echo "[fetch-ddp-detail] ${not_found_msg}：${_FETCH_ERR_MSG}" >&2
  exit 2
}

# --- 解析入口分流 ---
# T-IBT- 直接按任务；R-IBG- 直接按需求；纯数字任务优先，未命中（非网络错误）再回退按需求。
# DDP MCP 只接受纯数字 ID，从前缀中剥离数字部分。
RESOLVED_KIND=""
NUMERIC_ID=""

if [[ "$DDP_ID" == T-IBT-* ]]; then
  NUMERIC_ID="${DDP_ID#T-IBT-}"
  CALL_ARGS=$(jq -n --arg id "$NUMERIC_ID" '{"issueId":$id}')
  if _fetch_detail "ddp.getIssueDetail" "$CALL_ARGS"; then
    RESOLVED_KIND="issue"
  else
    _dispatch_fail "$?" "任务 $DDP_ID 查询失败"
  fi
elif [[ "$DDP_ID" == R-IBG-* ]]; then
  NUMERIC_ID="${DDP_ID#R-IBG-}"
  CALL_ARGS=$(jq -n --arg id "$NUMERIC_ID" '{"requirementId":$id}')
  if _fetch_detail "ddp.getRequirementDetail" "$CALL_ARGS"; then
    RESOLVED_KIND="requirement"
  else
    _dispatch_fail "$?" "需求 $DDP_ID 查询失败"
  fi
else
  NUMERIC_ID="$DDP_ID"
  ISSUE_ARGS=$(jq -n --arg id "$NUMERIC_ID" '{"issueId":$id}')
  if _fetch_detail "ddp.getIssueDetail" "$ISSUE_ARGS"; then
    RESOLVED_KIND="issue"
  else
    ISSUE_STATUS=$?
    [ "$ISSUE_STATUS" -eq 1 ] && _dispatch_fail "$ISSUE_STATUS" "任务 $DDP_ID 查询失败"
    REQ_ARGS=$(jq -n --arg id "$NUMERIC_ID" '{"requirementId":$id}')
    if _fetch_detail "ddp.getRequirementDetail" "$REQ_ARGS"; then
      RESOLVED_KIND="requirement"
    else
      _dispatch_fail "$?" "需求/任务 $DDP_ID 查询失败"
    fi
  fi
fi

# --- issue 分支：任务自身即为最终结果，行为与本次变更前一致 ---
if [[ "$RESOLVED_KIND" == "issue" ]]; then
  TITLE=$(echo "$_FETCH_DATA" | jq -r '.name // empty' 2>/dev/null)
  SEQ=$(echo "$_FETCH_DATA" | jq -r '.sequence // empty' 2>/dev/null)
  # PRD 链接在 modules[].fields[] 中：需求为 prdLink，任务为 requirement.prdLink（任务级常为 null）
  PRD_URL=$(echo "$_FETCH_DATA" | jq -r '
    [.modules[]?.fields[]? | select(.fieldName == "prdLink" or .fieldName == "requirement.prdLink") | .value // empty]
    | first // empty' 2>/dev/null)

  if [ -z "$TITLE" ] && [ -z "$SEQ" ]; then
    echo "[fetch-ddp-detail] 任务 $DDP_ID 不存在或无权限" >&2
    exit 2
  fi

  RELEASE_VERSION=$(_driver_version_of_issue "$NUMERIC_ID" 2>/dev/null || true)

  jq -n \
    --arg title "${TITLE:-}" \
    --arg prd "${PRD_URL:-}" \
    --arg requirementId "${SEQ:-$DDP_ID}" \
    --arg releaseVersion "${RELEASE_VERSION:-}" \
    --arg resolvedKind "issue" \
    '{"title":$title,"prd":$prd,"requirementId":$requirementId,"releaseVersion":$releaseVersion,"resolvedKind":$resolvedKind}'
  exit 0
fi

# --- requirement 分支：按关联任务数向下解析（0/1/≥2） ---
REQ_TITLE=$(echo "$_FETCH_DATA" | jq -r '.name // empty' 2>/dev/null)
REQ_SEQ=$(echo "$_FETCH_DATA" | jq -r '.sequence // empty' 2>/dev/null)
REQ_PRD_URL=$(echo "$_FETCH_DATA" | jq -r '
  [.modules[]?.fields[]? | select(.fieldName == "prdLink" or .fieldName == "requirement.prdLink") | .value // empty]
  | first // empty' 2>/dev/null)

if [ -z "$REQ_TITLE" ] && [ -z "$REQ_SEQ" ]; then
  echo "[fetch-ddp-detail] 需求 $DDP_ID 不存在或无权限" >&2
  exit 2
fi

TASK_IDS=$(_associated_task_ids "$_FETCH_RESULT")
if [ -z "$TASK_IDS" ]; then
  TASK_COUNT=0
else
  TASK_COUNT=$(echo "$TASK_IDS" | wc -l | tr -d ' ')
fi

if [ "$TASK_COUNT" -eq 0 ]; then
  # 0 个关联任务：无法向下解析，退回需求级绑定，releaseVersion 为空
  jq -n \
    --arg title "${REQ_TITLE:-}" \
    --arg prd "${REQ_PRD_URL:-}" \
    --arg requirementId "${REQ_SEQ:-$DDP_ID}" \
    --arg releaseVersion "" \
    --arg resolvedKind "requirement" \
    '{"title":$title,"prd":$prd,"requirementId":$requirementId,"releaseVersion":$releaseVersion,"resolvedKind":$resolvedKind}'
  exit 0
fi

if [ "$TASK_COUNT" -eq 1 ]; then
  # 1 个关联任务：无歧义，自动采用，复用单任务拉取逻辑精确查询该任务
  TASK_ID=$(echo "$TASK_IDS" | head -1)
  TASK_ARGS=$(jq -n --arg id "$TASK_ID" '{"issueId":$id}')
  if ! _fetch_detail "ddp.getIssueDetail" "$TASK_ARGS"; then
    _dispatch_fail "$?" "需求 $DDP_ID 关联任务 $TASK_ID 查询失败"
  fi

  TASK_TITLE=$(echo "$_FETCH_DATA" | jq -r '.name // empty' 2>/dev/null)
  TASK_SEQ=$(echo "$_FETCH_DATA" | jq -r '.sequence // empty' 2>/dev/null)
  TASK_PRD_URL=$(echo "$_FETCH_DATA" | jq -r '
    [.modules[]?.fields[]? | select(.fieldName == "prdLink" or .fieldName == "requirement.prdLink") | .value // empty]
    | first // empty' 2>/dev/null)
  [ -n "$TASK_PRD_URL" ] || TASK_PRD_URL="$REQ_PRD_URL"
  RELEASE_VERSION=$(_driver_version_of_issue "$TASK_ID" 2>/dev/null || true)

  jq -n \
    --arg title "${TASK_TITLE:-$REQ_TITLE}" \
    --arg prd "${TASK_PRD_URL:-}" \
    --arg requirementId "${TASK_SEQ:-T-IBT-$TASK_ID}" \
    --arg releaseVersion "${RELEASE_VERSION:-}" \
    --arg resolvedKind "issue" \
    '{"title":$title,"prd":$prd,"requirementId":$requirementId,"releaseVersion":$releaseVersion,"resolvedKind":$resolvedKind}'
  exit 0
fi

# ≥2 个关联任务：无法自动判定，exit 3 交由上层用户消歧
CANDIDATES="[]"
while IFS= read -r task_id; do
  [ -z "$task_id" ] && continue
  task_args=$(jq -n --arg id "$task_id" '{"issueId":$id}')
  if _fetch_detail "ddp.getIssueDetail" "$task_args"; then
    task_title=$(echo "$_FETCH_DATA" | jq -r '.name // empty' 2>/dev/null)
    task_seq=$(echo "$_FETCH_DATA" | jq -r '.sequence // empty' 2>/dev/null)
    CANDIDATES=$(echo "$CANDIDATES" | jq --arg id "${task_seq:-T-IBT-$task_id}" --arg title "${task_title:-}" '. + [{"id":$id,"title":$title}]')
  else
    echo "[fetch-ddp-detail] ⚠️ 任务 $task_id 详情获取失败，已从候选列表跳过：${_FETCH_ERR_MSG}" >&2
  fi
done <<< "$TASK_IDS"

jq -n \
  --arg requirementTitle "${REQ_TITLE:-}" \
  --argjson candidates "$CANDIDATES" \
  '{"requirementTitle":$requirementTitle,"candidates":$candidates}'
exit 3