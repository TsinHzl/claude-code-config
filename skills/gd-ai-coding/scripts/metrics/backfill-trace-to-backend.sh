#!/usr/bin/env bash
# =============================================================================
# backfill-trace-to-backend.sh — 一次性将存量 dac-trace notes 回填到后端
# =============================================================================
#
# 背景：
#   已删除的 aggregate-trace-multi.sh 会把所有仓库的数据按 committer 合并成单一数组，
#   合并过程中丢失了每条 requirement 来自哪个仓库（repo_path）的归属信息。
#   后端 /api/v1/trace/backfill 的唯一键含 repo_path，因此本脚本必须对
#   repos.json 中的每个仓库单独调用 aggregate-trace.sh，在合并前打上
#   repo_path 标记，再批量 POST，而不能复用该已删除脚本的输出。
#
# 用法：backfill-trace-to-backend.sh
#
# 依赖：~/.claude/skills/dashboard/repos.json（仓库列表）
#       ~/.claude/skills/dashboard/backend-config.json（后端地址 + token）
#
# 性质：一次性手动运行的迁移脚本（design.md 决策 6），不做成定时任务或后端接口。
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../runtime.sh"
dac_resolve_runtime || { echo "[backfill] ❌ 无法解析 DAC 运行时" >&2; exit 1; }
REPOS_JSON="$DAC_CONFIG_HOME/repos.json"
BACKEND_CONFIG="$DAC_CONFIG_HOME/backend-config.json"
CACHE_BASE="/tmp/dac-trace-cache"
FETCH_REPO_SH="${SCRIPT_DIR}/fetch-repo-trace.sh"

command -v jq >/dev/null 2>&1 || { echo "[backfill] ❌ jq 未安装" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "[backfill] ❌ curl 未安装" >&2; exit 1; }
[[ -f "$FETCH_REPO_SH" ]] || { echo "[backfill] ❌ fetch-repo-trace.sh 不存在: ${FETCH_REPO_SH}" >&2; exit 1; }
[[ -f "$REPOS_JSON" ]] || { echo "[backfill] ❌ ${REPOS_JSON} 不存在" >&2; exit 1; }
[[ -f "$BACKEND_CONFIG" ]] || { echo "[backfill] ❌ ${BACKEND_CONFIG} 不存在，请先配置后端地址与 token" >&2; exit 1; }

BASE_URL=$(jq -r '.base_url // empty' "$BACKEND_CONFIG")
TOKEN=$(jq -r '.token // empty' "$BACKEND_CONFIG")
[[ -n "$BASE_URL" && -n "$TOKEN" ]] || { echo "[backfill] ❌ backend-config.json 缺少 base_url/token" >&2; exit 1; }

mkdir -p "${CACHE_BASE}"
TMP_ITEMS="${CACHE_BASE}/_backfill_items_$$"
mkdir -p "${TMP_ITEMS}"
trap 'rm -rf "${TMP_ITEMS}"' EXIT

_ok=0
_fail=0

# ──────────────────────────────────────────────────────────────────────────────
# 逐仓库拉取 notes 并聚合（bare 缓存复用已删除的 aggregate-trace-multi.sh 的缓存目录约定）
# --force：无条件 fetch（对应本脚本原有的无 TTL 概念的行为）
# --strict：notes fetch 失败时直接跳过该仓库，不回退缓存中的旧 notes
#           （对应本脚本原有的 fetch 失败即 continue 的行为）
# ──────────────────────────────────────────────────────────────────────────────
while IFS= read -r repo_path; do
  repo_slug="${repo_path//\//__}"
  echo "[backfill] ${repo_path}: fetch + 聚合..." >&2
  _out="${TMP_ITEMS}/${repo_slug}.json"
  if bash "$FETCH_REPO_SH" "${repo_path}" --force --strict > "$_out"; then
    _cnt=$(jq 'length' "$_out")
    echo "[backfill]   → ${_cnt} 位成员，repo_path=${repo_path}" >&2
    _ok=$(( _ok + 1 ))
  else
    rm -f "$_out"
    _fail=$(( _fail + 1 ))
  fi
done < <(jq -r '.repos[].gitlab_path' "${REPOS_JSON}")

echo "[backfill] 共 ${_ok} 个仓库有数据，${_fail} 个失败/跳过" >&2

shopt -s nullglob
PARTIAL_FILES=("${TMP_ITEMS}"/*.json)
shopt -u nullglob

if [[ ${#PARTIAL_FILES[@]} -eq 0 ]]; then
  echo "[backfill] ⚠️  无任何数据可上报" >&2
  exit 0
fi

BODY_FILE="${TMP_ITEMS}/_body.json"
jq -s 'add' "${PARTIAL_FILES[@]}" > "$BODY_FILE"

_total_items=$(jq 'length' "$BODY_FILE")
echo "[backfill] 共 ${_total_items} 个 committer 条目，POST 到 ${BASE_URL}/api/v1/trace/backfill ..." >&2

_resp=$(curl --max-time 30 --silent --show-error --fail -X POST "${BASE_URL}/api/v1/trace/backfill" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  --data-binary @"${BODY_FILE}") || { echo "[backfill] ❌ 上报请求失败" >&2; exit 1; }

echo "[backfill] 后端响应: ${_resp}" >&2
echo "${_resp}" | jq -r '"inserted=\(.inserted) skipped=\(.skipped | length) errors=\(.errors | length)"'
