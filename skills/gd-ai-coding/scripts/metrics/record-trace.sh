#!/usr/bin/env bash
# =============================================================================
# record-trace.sh — 向 .dac/trace/<req>.json 追加工作流追踪事件
# =============================================================================
#
# 职责：
#   将每次 phase 切换或 feature 状态变更记录到追踪文件中，供后续通过
#   git notes（refs/notes/dac-trace）持久化到 git 历史，以及后端分析使用。
#
# 用法：
#   record-trace.sh --phase <phase_name>              # 记录 phase 切换
#   record-trace.sh --feature <feat_id> <status>      # 记录 feature 状态变更
#
# 追踪文件结构（.dac/trace/<req_name>.json）：
#   {
#     "req_name": "driver-side",           # 需求名，来自 state.json
#     "workflow_session_ids": ["<uuid1>", "<uuid2>"],  # 所有参与本需求的 Claude session UUID
#                                                       # 一个需求可能横跨多次会话（resume），全部保存
#                                                       # 后端通过此字段与 refs/notes/ai 关联
#     "phases": [                          # phase 流水，按时间追加
#       { "phase": "init",         "ts": 1234567890000 },
#       { "phase": "prd-parsing",  "ts": 1234567891000 },
#       ...
#     ],
#     "features": [                        # feature 状态变更，按时间追加
#       { "id": "home-card", "status": "in_progress", "ts": 1234567892000 },
#       { "id": "home-card", "status": "done",        "ts": 1234567893000 },
#       ...
#     ]
#   }
#
# 注意：
#   - 同一 feature 会出现多条记录（每次状态变更都追加），后端取最后一条作为最终状态
#   - 时间戳单位为毫秒（Unix ms）
#   - 本脚本由 state-update.sh 调用，调用方已加 || true，失败不影响主流程
#   - atomic_jq 来自 lib.sh，使用文件锁保证并发写入安全
#
# 调用方：
#   state-update.sh（phase 模式 和 feature 模式均调用此脚本）
# =============================================================================

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPTS_DIR/runtime.sh"
dac_resolve_runtime || exit 0
source "$SCRIPTS_DIR/lib.sh"
source "$SCRIPTS_DIR/metrics/report-trace-backend.sh"

STATE_FILE=".dac/state.json"
TRACE_ERROR_LOG=".dac/logs/trace-errors.log"

# state.json 不存在说明工作流未初始化，静默退出
[[ -f "$STATE_FILE" ]] || exit 0

# 从 state.json 读取需求名，生成追踪文件路径
# req_name 中特殊字符替换为 "_" 避免文件名问题
_req_name="$(jq -r '.req_name // "untitled"' "$STATE_FILE")"
_req_id_json="$(jq '.req_id // null' "$STATE_FILE")"
# DDP 司机端版本名（bind-ddp-req.sh 写入 state.json）；空串表示未捕获，不写入 trace
_rvn="$(jq -r '.release_version_name // empty' "$STATE_FILE" 2>/dev/null)"
_session_id="$(cat ".dac/workflow_session_id" 2>/dev/null || echo "unknown")"
_safe_req="${_req_name//[^A-Za-z0-9._-]/_}"
_trace_file=".dac/trace/${_safe_req}.json"
mkdir -p ".dac/trace" ".dac/logs"

_log_error() {
  mkdir -p ".dac/logs"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$TRACE_ERROR_LOG"
}

# untitled.json 迁移：prd-parsing 阶段 req_name 尚未确定，数据先写入 untitled.json。
# 当 req_name 首次确定时，将 untitled.json 迁移到正确文件名，保留 init/prd-parsing 等
# 早期 phase 记录，避免这些数据孤立在 untitled.json 中永远丢失。
if [[ "$_req_name" != "untitled" && -f ".dac/trace/untitled.json" && ! -f "$_trace_file" ]]; then
  # 清理 untitled 的残留锁，避免迁移后 atomic_jq 被旧锁阻塞
  [[ -d ".dac/trace/untitled.json.lock" ]] && rmdir ".dac/trace/untitled.json.lock" 2>/dev/null || true
  mv ".dac/trace/untitled.json" "$_trace_file" 2>/dev/null || true
  # mv 成功后更新文件内的 req_name 字段，与文件名保持一致
  if [[ -f "$_trace_file" ]]; then
    atomic_jq '.req_name = $r' "$_trace_file" --arg r "$_req_name" 2>/dev/null || \
      _log_error "untitled.json 迁移后 req_name 更新失败"
  fi
fi

# 清理残留的锁目录（进程 crash 后 RETURN trap 不触发，锁不会自动释放）
# 不清理会导致后续所有 atomic_jq 调用等待 10 秒后失败
_lock_dir="${_trace_file}.lock"
if [[ -d "$_lock_dir" ]]; then
  rmdir "$_lock_dir" 2>/dev/null || true
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] 清理残留锁: $_lock_dir" >> "$TRACE_ERROR_LOG"
fi

# 追踪文件不存在时创建初始结构
# 正常流程中此文件由 init-trace.sh + 首次 --phase 调用已创建，这里是兜底
if [[ ! -f "$_trace_file" ]]; then
  # 尽量从 state.json 的 created_at 反推工作流开始时间，保证时序准确
  _created_at="$(jq -r '.created_at // ""' "$STATE_FILE")"
  if [[ -n "$_created_at" ]]; then
    _init_ts="$(( $(iso_to_epoch "$_created_at") * 1000 ))"
  else
    _init_ts="$(jq -rn 'now * 1000 | floor')"
  fi
  # workflow_session_ids 用数组存储：一个需求可能横跨多次 Claude 会话（resume），
  # 每次会话有独立 UUID，全部保存才能与 git-ai 的 refs/notes/ai 完整关联
  # release_version_name 非空时一并写入初始结构（去前缀的司机端版本名，见 bind-ddp-req.sh）
  jq -n --arg r "$_req_name" --argjson rid "$_req_id_json" --arg s "$_session_id" --argjson its "$_init_ts" --arg rvn "$_rvn" \
    '{req_name:$r, req_id:$rid, workflow_session_ids:[$s], phases:[{phase:"init",ts:$its}], features:[]}
     + (if $rvn != "" then {release_version_name:$rvn} else {} end)' >"$_trace_file"
else
  # 文件已存在（resume 场景）：如果当前 session 还不在列表里则追加
  # unknown 不追加，避免污染数据
  if [[ "$_session_id" != "unknown" ]]; then
    _already=$(jq -r --arg s "$_session_id" \
      '(.workflow_session_ids // []) | map(. == $s) | any' "$_trace_file" 2>/dev/null || echo "false")
    if [[ "$_already" != "true" ]]; then
      atomic_jq '.workflow_session_ids += [$s]' "$_trace_file" --arg s "$_session_id" || \
        _log_error "session 追加失败: session=$_session_id"
    fi
  fi
  # 版本名补全（含 untitled 迁移后落入本分支的场景）：state 有、trace 缺（或空）时补写，
  # 不覆盖 trace 已有的非空版本名
  if [[ -n "$_rvn" ]]; then
    _existing_rvn=$(jq -r '.release_version_name // empty' "$_trace_file" 2>/dev/null || echo "")
    if [[ -z "$_existing_rvn" ]]; then
      atomic_jq '.release_version_name = $rvn' "$_trace_file" --arg rvn "$_rvn" || \
        _log_error "版本名补写失败: rvn=$_rvn trace=$_trace_file"
    fi
  fi
fi

case "${1:-}" in
  --phase)
    # 记录 phase 切换事件，时间戳取当前时刻
    PHASE="${2:?用法: record-trace.sh --phase <name>}"
    if ! atomic_jq '.phases += [{phase: $phase, ts: (now * 1000 | floor)}]' "$_trace_file" \
        --arg phase "$PHASE"; then
      _log_error "phase 写入失败: phase=$PHASE trace=$_trace_file"
      exit 1
    fi
    _report_progress "$_trace_file" || true
    ;;
  --feature)
    # 记录 feature 状态变更事件（in_progress / done / failed / skipped）
    FEAT_ID="${2:?用法: record-trace.sh --feature <feat_id> <status>}"
    STATUS="${3:?用法: record-trace.sh --feature <feat_id> <status>}"
    if ! atomic_jq '.features += [{id: $fid, status: $st, ts: (now * 1000 | floor)}]' "$_trace_file" \
        --arg fid "$FEAT_ID" --arg st "$STATUS"; then
      _log_error "feature 写入失败: feat=$FEAT_ID status=$STATUS trace=$_trace_file"
      exit 1
    fi
    _report_progress "$_trace_file" || true
    ;;
  --skip-stage)
    # 记录被跳过的工作流阶段（prd_parse / mastergo / feature_plan / scaffold）
    STAGE="${2:?用法: record-trace.sh --skip-stage <name>}"
    if ! atomic_jq 'if (.skipped_stages // []) | any(. == $s) then . else
        .skipped_stages = ((.skipped_stages // []) + [$s]) end' "$_trace_file" \
        --arg s "$STAGE"; then
      _log_error "skipped_stages 写入失败: stage=$STAGE trace=$_trace_file"
      exit 1
    fi
    _report_progress "$_trace_file" || true
    ;;
  *)
    echo "用法: record-trace.sh --phase <name> | --feature <feat_id> <status> | --skip-stage <name>" >&2
    exit 1
    ;;
esac
