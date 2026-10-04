#!/usr/bin/env bash
# =============================================================================
# fetch-repo-trace.sh — 单仓库 dac-trace notes bare 缓存 fetch + 聚合（共享实现）
# =============================================================================
#
# 从 aggregate-trace-multi.sh（已删除，取代方案见 dac-trace-service）与
# backfill-trace-to-backend.sh 中抽取的单仓库 fetch 逻辑，供后者及
# dashboard-server.py 新增的 GitLab 多线程扫描共同调用，避免各自实现、行为逐渐漂移。
#
# 用法：fetch-repo-trace.sh <repo_path> [--force] [--strict]
#   <repo_path>  GitLab 仓库路径（如 global-driver/demo）
#   --force      跳过 TTL 判断，无条件 fetch（对应 backfill 现状：无 TTL 概念）
#   --strict     notes fetch 失败时直接跳过该仓库，不回退缓存中的旧 notes
#                （对应 backfill 现状：fetch 失败即 continue）。不传时 fetch 失败
#                仍尝试用缓存中已有 notes 继续聚合（对应 aggregate-trace-multi.sh 原有行为，该脚本已删除）
#
# stdout: 成功时输出打上 repo_path 标记的聚合 JSON 数组（与 aggregate-trace.sh
#         输出结构相同，每个 committer 对象额外带 repo_path 字段）
# stderr: 进度/警告信息（不污染 stdout）
# exit 0: 成功，stdout 有数据
# exit 1: 该仓库被跳过（bare 初始化失败 / 无 notes / fetch 失败且 --strict /
#         聚合无有效数据 / 获取缓存锁超时），stdout 为空，不影响其余仓库处理
# exit 2: 硬错误（依赖缺失、repos.json 不存在），所有仓库都会失败，应中止调用方
#
# 依赖：aggregate-trace.sh（同目录）、~/.claude/skills/dashboard/repos.json（读取 gitlab_host）
#
# 并发安全：内部对 <cache_dir>.lock 使用 mkdir 作为跨平台互斥锁（与 scripts/lib.sh
# atomic_jq 一致，macOS 无 flock），保护整个 fetch+聚合过程，避免多个调用方
# （手动 backfill / 并发 dashboard 会话 / GitLab 扫描线程池）同时对同一仓库缓存
# 目录执行 git 操作。
# =============================================================================

set -euo pipefail

REPO_PATH="${1:-}"
[[ -n "$REPO_PATH" ]] || { echo "[fetch-repo-trace] ❌ 缺少 <repo_path> 参数" >&2; exit 2; }
shift

FORCE=false
STRICT=false
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    --strict) STRICT=true ;;
    *) echo "[fetch-repo-trace] ❌ 未知参数: $arg" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../runtime.sh"
dac_resolve_runtime || { echo "[fetch-repo-trace] ❌ 无法解析 DAC 运行时" >&2; exit 2; }
REPOS_JSON="$DAC_CONFIG_HOME/repos.json"
CACHE_BASE="/tmp/dac-trace-cache"
AGGREGATE_SH="${SCRIPT_DIR}/aggregate-trace.sh"
FETCH_TTL=300  # 秒，与 aggregate-trace-multi.sh 原有行为一致（该脚本已删除）

command -v jq >/dev/null 2>&1 || { echo "[fetch-repo-trace] ❌ jq 未安装" >&2; exit 2; }
[[ -f "$AGGREGATE_SH" ]] || { echo "[fetch-repo-trace] ❌ aggregate-trace.sh 不存在: ${AGGREGATE_SH}" >&2; exit 2; }
[[ -f "$REPOS_JSON" ]] || { echo "[fetch-repo-trace] ❌ ${REPOS_JSON} 不存在" >&2; exit 2; }

GITLAB_HOST=$(jq -r '.gitlab_host' "${REPOS_JSON}")
repo_slug="${REPO_PATH//\//__}"
cache_dir="${CACHE_BASE}/${repo_slug}"
ssh_url="git@${GITLAB_HOST}:${REPO_PATH}.git"

mkdir -p "${CACHE_BASE}"

# 跨平台互斥锁（mkdir，与 scripts/lib.sh atomic_jq 一致；macOS 无 flock）
lockdir="${cache_dir}.lock"
max_wait=30 waited=0
stale_threshold=180  # 秒；大于 dashboard-server.py 侧 subprocess timeout(120s)+余量，
                     # 超过视为孤儿锁（持锁进程被 SIGKILL 后 trap 未执行，锁目录残留）
while ! mkdir "$lockdir" 2>/dev/null; do
  if [[ -d "$lockdir" ]]; then
    _lock_mtime=$(stat -f %m "$lockdir" 2>/dev/null || stat -c %Y "$lockdir" 2>/dev/null || echo 0)
    _lock_age=$(( $(date +%s) - _lock_mtime ))
    if [[ $_lock_age -ge $stale_threshold ]]; then
      echo "[fetch-repo-trace] ⚠️  检测到孤儿锁（${_lock_age}s 未释放），强制清理: ${lockdir}" >&2
      rmdir "$lockdir" 2>/dev/null
      continue
    fi
  fi
  sleep 0.1
  waited=$((waited + 1))
  if [[ $waited -ge $((max_wait * 10)) ]]; then
    echo "[fetch-repo-trace] ⚠️  获取缓存锁超时，跳过: ${REPO_PATH}" >&2
    exit 1
  fi
done
_raw="${cache_dir}/_aggregate_$$.json"
trap 'rm -f "${_raw}"; rmdir "$lockdir" 2>/dev/null' EXIT

# 初始化 bare 缓存（幂等）
if [[ ! -f "${cache_dir}/HEAD" ]]; then
  if ! git init --bare -q "${cache_dir}" 2>/dev/null; then
    echo "[fetch-repo-trace] ❌ ${REPO_PATH}: init 失败，跳过" >&2
    exit 1
  fi
fi

_GIT_SSH="ssh -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2"
_ts_file="${cache_dir}/_last_fetch"
_now=$(date +%s)
_last=0
[[ -f "${_ts_file}" ]] && _last=$(cat "${_ts_file}" 2>/dev/null || echo "0")

_should_fetch=true
if [[ "$FORCE" != "true" ]] && (( _now - _last < FETCH_TTL )); then
  _should_fetch=false
  echo "[fetch-repo-trace] ${REPO_PATH}: TTL 未过期（剩余 $(( FETCH_TTL - _now + _last ))s）" >&2
fi

if [[ "$_should_fetch" == "true" ]]; then
  echo "[fetch-repo-trace] ${REPO_PATH}: fetch notes..." >&2
  _notes_ok=false
  if (cd "${cache_dir}" && GIT_SSH_COMMAND="$_GIT_SSH" \
      git fetch "${ssh_url}" '+refs/notes/dac-trace:refs/notes/dac-trace' --quiet 2>/dev/null); then
    _notes_ok=true
    echo "[fetch-repo-trace]   notes fetch 成功" >&2
  else
    echo "[fetch-repo-trace]   ⚠️  notes fetch 失败（SSH 不可达或仓库无 dac-trace notes）" >&2
  fi

  # 无论成功还是失败，都更新 TTL（防止 SSH 不可达时每次全量 timeout）
  echo "${_now}" > "${_ts_file}"

  if [[ "$_notes_ok" != "true" ]] && [[ "$STRICT" == "true" ]]; then
    echo "[fetch-repo-trace]   --strict 模式下 fetch 失败，跳过该仓库" >&2
    exit 1
  fi

  _cache_notes=$(cd "${cache_dir}" && \
    git notes --ref=refs/notes/dac-trace list 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  if [[ "${_cache_notes}" -gt 0 ]]; then
    echo "[fetch-repo-trace]   fetch 所有分支（depth=50，获取 commit 对象）..." >&2
    (cd "${cache_dir}" && GIT_SSH_COMMAND="$_GIT_SSH" \
      git fetch "${ssh_url}" '+refs/heads/*:refs/heads/*' --depth=50 --no-tags --quiet 2>/dev/null) && \
      echo "[fetch-repo-trace]   分支 fetch 成功" >&2 || \
      echo "[fetch-repo-trace]   ⚠️  分支 fetch 失败，旧 note 将无 committer 信息" >&2
  fi
fi

_note_count=$(cd "${cache_dir}" && \
  git notes --ref=refs/notes/dac-trace list 2>/dev/null | wc -l | tr -d ' ' || echo "0")
if [[ "${_note_count}" -eq 0 ]]; then
  echo "[fetch-repo-trace]   无 dac-trace notes，跳过" >&2
  exit 1
fi

echo "[fetch-repo-trace]   ${_note_count} 条 notes，聚合中..." >&2
if ! (cd "${cache_dir}" && bash "$AGGREGATE_SH" 2>/dev/null) > "${_raw}" 2>/dev/null || \
    ! jq -e 'type == "array" and length > 0' "${_raw}" >/dev/null 2>&1; then
  echo "[fetch-repo-trace]   聚合失败或无有效数据（note 无 committer 字段且无 commit 对象）" >&2
  exit 1
fi

jq --arg rp "$REPO_PATH" 'map(. + {repo_path: $rp})' "${_raw}"
