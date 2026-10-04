#!/bin/sh
# =============================================================================
# report-trace-backend.sh — 向 dac-trace-service 后端上报追踪数据的函数库
# =============================================================================
#
# 职责：
#   封装 _report_progress / _report_commit_stats 两个函数，供 record-trace.sh
#   （bash）和 setup-hook-wrapper.sh 生成的 post-commit hook（/bin/sh）共同
#   source 调用。后端只是"团队可见性"增量能力，任何失败都必须静默降级，不能
#   影响本地 .dac/trace/<req>.json 的 file-first 主流程。
#
# 兼容性：
#   必须同时兼容 bash 与 POSIX /bin/sh（post-commit hook 用 #!/bin/sh），
#   因此不使用 [[ ]]、数组、+= 等 bashism，也不使用 local（非 POSIX）。
#   所有内部变量以 _dac_trace_ 前缀命名，降低污染调用方 shell 的风险。
#
# 配置来源：
#   DAC_CONFIG_HOME/backend-config.json（与 dashboard-server.py 共用）。
#   生成的 POSIX post-commit hook 必须在 source 本库前注入 DAC_CONFIG_HOME；未注入时静默跳过。
#   { "base_url": "http://...", "token": "..." }
#   文件不存在、jq 不可用、字段缺失，均视为"后端未配置"，静默跳过上报。
#
# 失败处理：
#   curl --max-time 3 --silent --fail，任何非 0 exit code 记录到
#   .dac/logs/trace-errors.log 后返回 0（成功码），绝不 set -e 中断调用方。
# =============================================================================

_DAC_TRACE_BACKEND_CONFIG="${DAC_CONFIG_HOME:+$DAC_CONFIG_HOME/backend-config.json}"
_DAC_TRACE_ERROR_LOG=".dac/logs/trace-errors.log"

_dac_trace_log_error() {
  mkdir -p ".dac/logs" 2>/dev/null
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$_DAC_TRACE_ERROR_LOG" 2>/dev/null
}

# 读取后端 base_url + token 到 _DAC_TRACE_URL / _DAC_TRACE_TOKEN
# 返回非 0 表示后端未配置，调用方应据此跳过本次上报
_dac_trace_backend_config() {
  command -v jq >/dev/null 2>&1 || return 1
  [ -f "$_DAC_TRACE_BACKEND_CONFIG" ] || return 1
  _DAC_TRACE_URL=$(jq -r '.base_url // empty' "$_DAC_TRACE_BACKEND_CONFIG" 2>/dev/null)
  _DAC_TRACE_TOKEN=$(jq -r '.token // empty' "$_DAC_TRACE_BACKEND_CONFIG" 2>/dev/null)
  [ -n "$_DAC_TRACE_URL" ] && [ -n "$_DAC_TRACE_TOKEN" ]
}

# 从当前 git remote 推导 repo_path（namespace/project 形式）
# 兼容 ssh（git@host:group/sub/project.git）和 https（https://host/group/sub/project.git）
# 无 git remote（非 git 仓库目录 / 未配 origin）时，用当前目录（.dac 所在目录）绝对
# 路径兜底，保证 repo_path 非空——否则实时 /report 会因取不到 repo_path 整体跳过上报，
# 导致在非 git 目录使用 skill 的数据永远进不了后端。
_dac_trace_repo_path() {
  _dac_trace_remote_url=$(git remote get-url origin 2>/dev/null)
  if [ -n "$_dac_trace_remote_url" ]; then
    printf '%s' "$_dac_trace_remote_url" | sed -E 's#^[a-zA-Z]+://[^/]+/##; s#^[^@]+@[^:]+:##; s#\.git$##'
    return 0
  fi
  _dac_trace_fallback=$(pwd 2>/dev/null)
  [ -n "$_dac_trace_fallback" ] || return 1
  printf 'local:%s' "$_dac_trace_fallback"
}

# 上报 phase/feature 进度（record-trace.sh 写完本地 trace 文件后调用）
# 用法：_report_progress <trace_file>
_report_progress() {
  _dac_trace_backend_config || return 0
  _dac_trace_file="$1"
  [ -f "$_dac_trace_file" ] || return 0
  _dac_trace_repo=$(_dac_trace_repo_path) || return 0
  _dac_trace_committer=$(git config user.email 2>/dev/null)
  [ -n "$_dac_trace_committer" ] || return 0
  _dac_trace_committer_name=$(git config user.name 2>/dev/null)

  _dac_trace_body=$(jq -c --arg c "$_dac_trace_committer" --arg cn "$_dac_trace_committer_name" \
      --arg rp "$_dac_trace_repo" \
      '{committer:$c, committer_name:$cn, req_name:(.req_name // "untitled"), req_id:.req_id,
        repo_path:$rp, workflow_session_ids:(.workflow_session_ids // []),
        phases:(.phases // []), features:(.features // []), write_events:(.write_events // []),
        skipped_stages:(.skipped_stages // []),
        write_lines_added:.write_lines_added,
        codegen_lines_added:.codegen_lines_added,
        release_version_name:(.release_version_name // null),
        source:"local-report"}' \
      "$_dac_trace_file" 2>/dev/null)
  if [ -z "$_dac_trace_body" ]; then
    _dac_trace_log_error "report body 构造失败: trace=$_dac_trace_file"
    return 0
  fi

  if ! curl --max-time 3 --silent --fail -X POST "$_DAC_TRACE_URL/api/v1/trace/report" \
      -H "Authorization: Bearer $_DAC_TRACE_TOKEN" -H "Content-Type: application/json" \
      -d "$_dac_trace_body" >/dev/null 2>&1; then
    _dac_trace_log_error "report 上报失败: trace=$_dac_trace_file"
  fi
  return 0
}

# 上报单次 commit 的统计数据（post-commit hook 写完 git notes 后调用）
# 用法：_report_commit_stats <req_name> <last_commit> <last_commit_ts_ms> <lines_added> <lines_deleted>
_report_commit_stats() {
  _dac_trace_backend_config || return 0
  _dac_trace_req="$1"
  _dac_trace_last_commit="$2"
  _dac_trace_last_commit_ts="${3:-0}"
  _dac_trace_lines_added="${4:-0}"
  _dac_trace_lines_deleted="${5:-0}"
  [ -n "$_dac_trace_req" ] && [ -n "$_dac_trace_last_commit" ] || return 0
  _dac_trace_repo=$(_dac_trace_repo_path) || return 0
  _dac_trace_committer=$(git config user.email 2>/dev/null)
  [ -n "$_dac_trace_committer" ] || return 0

  _dac_trace_body=$(jq -cn --arg c "$_dac_trace_committer" --arg r "$_dac_trace_req" \
      --arg rp "$_dac_trace_repo" --arg lc "$_dac_trace_last_commit" \
      --argjson lts "$_dac_trace_last_commit_ts" \
      --argjson la "$_dac_trace_lines_added" --argjson ld "$_dac_trace_lines_deleted" \
      '{committer:$c, req_name:$r, repo_path:$rp, last_commit:$lc, last_commit_ts:$lts,
        lines_added:$la, lines_deleted:$ld}' 2>/dev/null)
  if [ -z "$_dac_trace_body" ]; then
    _dac_trace_log_error "commit-stats body 构造失败: req=$_dac_trace_req commit=$_dac_trace_last_commit"
    return 0
  fi

  if ! curl --max-time 3 --silent --fail -X POST "$_DAC_TRACE_URL/api/v1/trace/commit-stats" \
      -H "Authorization: Bearer $_DAC_TRACE_TOKEN" -H "Content-Type: application/json" \
      -d "$_dac_trace_body" >/dev/null 2>&1; then
    _dac_trace_log_error "commit-stats 上报失败: req=$_dac_trace_req commit=$_dac_trace_last_commit"
  fi
  return 0
}

# 上报个人全局 AI coding 总产出（write-trace-hook.sh 公共前置逻辑无条件调用，与
# .dac 是否存在、是否绑定 DDP 需求无关）。SET 覆盖语义：write_lines_added/write_count
# 均为客户端本地累计总量，服务端整体覆盖而非累加。
# unused_workflow_lines 为「Write 当时没有 .dac/state.json 也没有 .dac/req-bind」的累计行；
# 第三参未传（旧 hook）则省略该键，服务端保留原值；显式传 0 也要带上。
# 用法：_report_personal_trace <write_lines_added> <write_count> [unused_workflow_lines]
_report_personal_trace() {
  _dac_trace_backend_config || return 0
  _dac_trace_write_lines="${1:-0}"
  _dac_trace_write_count="${2:-0}"
  _dac_trace_repo=$(_dac_trace_repo_path) || return 0
  _dac_trace_committer=$(git config user.email 2>/dev/null)
  [ -n "$_dac_trace_committer" ] || return 0
  _dac_trace_committer_name=$(git config user.name 2>/dev/null)

  if [ "${3+set}" = "set" ]; then
    _dac_trace_body=$(jq -cn --arg c "$_dac_trace_committer" --arg cn "$_dac_trace_committer_name" \
        --arg rp "$_dac_trace_repo" --argjson wla "$_dac_trace_write_lines" \
        --argjson wc "$_dac_trace_write_count" --argjson uw "$3" \
        '{committer:$c, committer_name:$cn, repo_path:$rp, write_lines_added:$wla,
          write_count:$wc, unused_workflow_lines:$uw}' 2>/dev/null)
  else
    _dac_trace_body=$(jq -cn --arg c "$_dac_trace_committer" --arg cn "$_dac_trace_committer_name" \
        --arg rp "$_dac_trace_repo" --argjson wla "$_dac_trace_write_lines" \
        --argjson wc "$_dac_trace_write_count" \
        '{committer:$c, committer_name:$cn, repo_path:$rp, write_lines_added:$wla, write_count:$wc}' 2>/dev/null)
  fi
  if [ -z "$_dac_trace_body" ]; then
    _dac_trace_log_error "personal-trace body 构造失败: repo=$_dac_trace_repo"
    return 0
  fi

  if ! curl --max-time 3 --silent --fail -X POST "$_DAC_TRACE_URL/api/v1/trace/personal-report" \
      -H "Authorization: Bearer $_DAC_TRACE_TOKEN" -H "Content-Type: application/json" \
      -d "$_dac_trace_body" >/dev/null 2>&1; then
    _dac_trace_log_error "personal-trace 上报失败: repo=$_dac_trace_repo"
  fi
  return 0
}

# 注册 trace↔DDP 需求绑定（工作流起点确认 DDP 后调用）。看板 trace 卡与 DDP 卡的合并
# 完全依赖后端 dac_req_binding 表（前端 _BINDINGS），不做 req_name/id 字符串匹配，因此
# 起点必须显式写入一条绑定，看板才会把本 trace 合并进对应 DDP 需求卡。
# ddp_req 需为看板 DDP 卡的 req_name（大写 R-IBG-xxx 形式）。
# 用法：_report_ddp_binding <trace_req> <ddp_req>
_report_ddp_binding() {
  _dac_trace_backend_config || return 0
  _dac_trace_bind_trace="$1"
  _dac_trace_bind_ddp="$2"
  [ -n "$_dac_trace_bind_trace" ] && [ -n "$_dac_trace_bind_ddp" ] || return 0

  _dac_trace_body=$(jq -cn --arg t "$_dac_trace_bind_trace" --arg d "$_dac_trace_bind_ddp" \
      '{trace_req:$t, ddp_req:$d, unbind:false}' 2>/dev/null)
  if [ -z "$_dac_trace_body" ]; then
    _dac_trace_log_error "ddp-binding body 构造失败: trace=$_dac_trace_bind_trace ddp=$_dac_trace_bind_ddp"
    return 0
  fi

  if ! curl --max-time 3 --silent --fail -X POST "$_DAC_TRACE_URL/api/v1/ddp/bindings" \
      -H "Authorization: Bearer $_DAC_TRACE_TOKEN" -H "Content-Type: application/json" \
      -d "$_dac_trace_body" >/dev/null 2>&1; then
    _dac_trace_log_error "ddp-binding 上报失败: trace=$_dac_trace_bind_trace ddp=$_dac_trace_bind_ddp"
  fi
  return 0
}
