#!/usr/bin/env bash
# =============================================================================
# bind-req.sh — 轻量需求绑定：将 DDP 需求 ID 写入 .dac/req-bind
# =============================================================================
#
# 用法：
#   bind-req.sh --req <req_name>   # 绑定需求（支持 R-IBG-XXXXXX 或自定义名称）
#   bind-req.sh --clear            # 解绑（删除 .dac/req-bind）
#
# 特性：
#   - 写入 JSON 格式，同时记录当前分支名（防切换分支后残留污染）
#   - 自动创建 .dac/ 目录
#   - 自动将 .dac/req-bind 加入 .git/info/exclude（本地 gitignore，不影响他人）
#   - 幂等：同分支同 req 重复调用跳过
#
# 格式：.dac/req-bind
#   {"req": "R-IBG-667192", "branch": "feature/...", "committer": "user@example.com", "bound_at": "2026-07-22T09:34:11Z"}
#
# Hook 读取时校验 branch 字段与当前分支是否一致：
#   - 一致 → 生效
#   - 不一致（已切换分支）→ 忽略，降级到分支名自动提取
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../runtime.sh"
dac_resolve_runtime || exit 0
source "$SCRIPT_DIR/report-trace-backend.sh"

BIND_FILE=".dac/req-bind"

_usage() {
  echo "用法: bind-req.sh --req <req_name> | --clear" >&2
  exit 1
}

[[ $# -eq 0 ]] && _usage

MODE=""
REQ_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --req)
      [[ -z "${2-}" ]] && { echo "[bind-req] ❌ --req 缺少值" >&2; exit 1; }
      MODE="bind"; REQ_NAME="$2"; shift 2 ;;
    --clear)
      MODE="clear"; shift ;;
    *) echo "[bind-req] ❌ 未知参数: $1" >&2; _usage ;;
  esac
done

[[ -z "$MODE" ]] && _usage

# 确认当前在 git repo 内
git rev-parse --git-dir >/dev/null 2>&1 || { echo "[bind-req] ❌ 当前目录不是 git repo" >&2; exit 1; }

# ── clear 模式 ────────────────────────────────────────────────────────────────
if [[ "$MODE" == "clear" ]]; then
  if [[ -f "$BIND_FILE" ]]; then
    rm -f "$BIND_FILE"
    echo "[bind-req] ✅ 已解绑，删除 $BIND_FILE" >&2
  else
    echo "[bind-req] ℹ️  无绑定文件，跳过" >&2
  fi
  exit 0
fi

# ── bind 模式 ─────────────────────────────────────────────────────────────────

# 获取当前分支名（detached HEAD 时退为空串）
CUR_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
CUR_COMMITTER=$(git config user.email 2>/dev/null || echo "")

# 幂等检查：同分支同 req 则跳过
if [[ -f "$BIND_FILE" ]] && command -v jq >/dev/null 2>&1; then
  _existing_req=$(jq -r '.req // empty' "$BIND_FILE" 2>/dev/null || true)
  _existing_branch=$(jq -r '.branch // empty' "$BIND_FILE" 2>/dev/null || true)
  if [[ "$_existing_req" == "$REQ_NAME" && "$_existing_branch" == "$CUR_BRANCH" ]]; then
    echo "[bind-req] ℹ️  already bound: req=$REQ_NAME branch=$CUR_BRANCH" >&2
    exit 0
  fi
fi

# 创建 .dac/ 目录
mkdir -p ".dac"

# 写入绑定文件（JSON 含分支名 + committer 身份 + 绑定时间）
# bound_at：绑定时刻 ISO8601 UTC。backfill 以它为提交归属时间下界，
# 防止在 develop 等长期共享分支上把绑定前的历史提交误算进本需求。
_bound_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if command -v jq >/dev/null 2>&1; then
  jq -n --arg r "$REQ_NAME" --arg b "$CUR_BRANCH" --arg c "$CUR_COMMITTER" --arg t "$_bound_at" \
    '{"req": $r, "branch": $b, "committer": $c, "bound_at": $t}' > "$BIND_FILE"
else
  # jq 不可用时手写 JSON（值不含双引号/反斜杠，安全）
  printf '{"req":"%s","branch":"%s","committer":"%s","bound_at":"%s"}\n' "$REQ_NAME" "$CUR_BRANCH" "$CUR_COMMITTER" "$_bound_at" > "$BIND_FILE"
fi

echo "[bind-req] ✅ 绑定：req=$REQ_NAME  branch=${CUR_BRANCH:-<detached>}" >&2

# 立即同步到后端：优先使用本地已存在的真实 trace 文件（避免用空 phases/features
# 覆盖后端已有的真实历史数据），仅当本地确无该 req_name 的 trace 文件时才发一份
# 最简临时 JSON（此时视为新建记录，不存在覆盖风险）
if command -v jq >/dev/null 2>&1; then
  _safe() { local r="$1"; echo "${r//[^A-Za-z0-9._-]/_}"; }
  _bind_safe_req=$(_safe "$REQ_NAME")
  _bind_trace_file=".dac/trace/${_bind_safe_req}.json"
  if [[ -f "$_bind_trace_file" ]]; then
    _report_progress "$_bind_trace_file" || true
  else
    _bind_tmp_report=$(mktemp 2>/dev/null) || _bind_tmp_report=""
    if [[ -n "$_bind_tmp_report" ]]; then
      jq -n --arg r "$REQ_NAME" '{req_name:$r}' > "$_bind_tmp_report" 2>/dev/null \
        && _report_progress "$_bind_tmp_report"
      rm -f "$_bind_tmp_report"
    else
      echo "[bind-req] ⚠️  mktemp 失败，跳过本次后端同步" >&2
    fi
  fi
fi

# 自动加入 .git/info/exclude（本地 gitignore，不影响仓库其他人）
GIT_DIR=$(git rev-parse --git-dir)
EXCLUDE_FILE="${GIT_DIR}/info/exclude"
mkdir -p "${GIT_DIR}/info"
BIND_PATTERN=".dac/req-bind"
if ! grep -qF "$BIND_PATTERN" "$EXCLUDE_FILE" 2>/dev/null; then
  echo "$BIND_PATTERN" >> "$EXCLUDE_FILE"
  echo "[bind-req] 📝 已将 $BIND_PATTERN 加入 .git/info/exclude" >&2
fi
