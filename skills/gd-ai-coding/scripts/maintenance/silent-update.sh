#!/usr/bin/env bash
# silent-update.sh — SessionStart hook 触发的静默更新检测（每次会话启动都检测，不节流）
# 全程不产生 stdout 输出、不返回 hook additionalContext；日志写入 ~/Library/Logs/dac-auto-update.log

set -uo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/runtime.sh" 2>/dev/null || exit 0
dac_resolve_runtime 2>/dev/null || exit 0

DRY_RUN=false
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=true ;;
  *) exit 0 ;;
esac

LOG_DIR="$HOME/Library/Logs"
LOG_FILE="$LOG_DIR/dac-auto-update.log"
STATE_DIR="$DAC_STATE_HOME/auto-update"
LOCK_DIR="$STATE_DIR/lock"
SOURCE_REPO_MARKER="$DAC_SKILL_HOME/.source-repo-path"
STALE_LOCK_SECONDS=$((10 * 60))
GIT_TIMEOUT=60

log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || return 0
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null
}

release_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null
}

# 可移植超时包装：macOS 默认不带 GNU coreutils 的 timeout 命令，用后台 job + 定时 kill 代替
run_with_timeout() {
  local secs="$1"; shift
  "$@" &
  local cmd_pid=$!
  ( sleep "$secs"; kill -TERM "$cmd_pid" 2>/dev/null ) &
  local watcher_pid=$!
  wait "$cmd_pid" 2>/dev/null
  local status=$?
  kill "$watcher_pid" 2>/dev/null
  wait "$watcher_pid" 2>/dev/null
  return "$status"
}

# 陈旧锁回收：锁目录 mtime 超过阈值视为持锁进程已异常退出未能正常释放
acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    return 0
  fi
  local lock_mtime now
  lock_mtime=$(stat -f %m "$LOCK_DIR" 2>/dev/null || stat -c %Y "$LOCK_DIR" 2>/dev/null || echo 0)
  now=$(date +%s)
  if (( now - lock_mtime > STALE_LOCK_SECONDS )); then
    rmdir "$LOCK_DIR" 2>/dev/null
    mkdir "$LOCK_DIR" 2>/dev/null && return 0
  fi
  return 1
}

# --- 定位源仓库（标记文件缺失/为空 → 记录日志后退出，便于事后排查） ---
if [[ ! -f "$SOURCE_REPO_MARKER" ]]; then
  [[ "$DRY_RUN" == true ]] && exit 0
  log "⏭ 跳过：未找到源仓库标记文件 ${SOURCE_REPO_MARKER}（从未运行过 install.sh，或安装版本早于自动更新功能，需手动执行一次 install.sh）" || true
  exit 0
fi
REPO_DIR="$(cat "$SOURCE_REPO_MARKER" 2>/dev/null)"
if [[ -z "$REPO_DIR" || ! -d "$REPO_DIR" ]]; then
  [[ "$DRY_RUN" == true ]] && exit 0
  log "⏭ 跳过：源仓库路径标记内容为空或目录不存在：${REPO_DIR:-<空>}（仓库可能已被移动/删除，需重新运行 install.sh）"
  exit 0
fi

[[ "$DRY_RUN" == true ]] && exit 0

mkdir -p "$STATE_DIR"

# --- 上次 stash pop 失败告警（同步输出到 stdout，让用户立即注意到） ---
STASH_FAIL_MARKER="$STATE_DIR/stash-pop-failed"
if [[ -f "$STASH_FAIL_MARKER" ]]; then
  _fail_repo="$(cat "$STASH_FAIL_MARKER" 2>/dev/null)"
  echo "[DAC] ⚠️  gd-ai-coding 自动更新上次 stash pop 失败，${_fail_repo:-源仓库}中有未恢复的本地改动，请手动执行: cd ${_fail_repo:-~} && git stash pop"
  rm -f "$STASH_FAIL_MARKER"
fi

# --- 并发锁：锁被占用（且非陈旧）直接跳过，避免多窗口同时启动时重复 fetch/pull ---
if ! acquire_lock; then
  log "⏭ 跳过：并发锁被占用（$LOCK_DIR）"
  exit 0
fi

run_update() {
  cd "$REPO_DIR" || { log "❌ 仓库目录不存在或无法访问：$REPO_DIR"; return 1; }

  local retry_marker="$STATE_DIR/retry-$(printf '%s' "$REPO_DIR" | shasum -a 256 | cut -d' ' -f1)"
  local has_retry_marker=false
  [[ -f "$retry_marker" ]] && has_retry_marker=true

  if ! run_with_timeout "$GIT_TIMEOUT" git fetch >> "$LOG_FILE" 2>&1; then
    touch "$retry_marker"
    log "❌ git fetch 失败或超时，已写入重试标记，等待下次调度重试"
    return 1
  fi

  local ahead
  ahead="$(git rev-list HEAD..@{u} --count 2>/dev/null || echo 0)"

  if [[ "$ahead" -eq 0 && "$has_retry_marker" == "false" ]]; then
    log "无新提交，跳过"
    return 0
  fi

  local stashed=false
  pop_stash() {
    if [[ "$stashed" == "true" ]]; then
      if git stash pop >> "$LOG_FILE" 2>&1; then
        log "✓ stash pop 成功，本地改动已恢复"
      else
        log "⚠️ stash pop 失败（可能冲突），改动仍保留在 stash 中，请手动执行 git stash list / git stash pop 恢复"
        printf '%s' "$REPO_DIR" > "$STASH_FAIL_MARKER"
      fi
    fi
  }

  if [[ -n "$(git status --porcelain)" ]]; then
    if git stash push -u >> "$LOG_FILE" 2>&1; then
      stashed=true
      log "已 stash 本地未提交改动"
    else
      log "❌ git stash push 失败，终止本次执行"
      return 1
    fi
  fi

  if [[ "$ahead" -gt 0 ]]; then
    if ! run_with_timeout "$GIT_TIMEOUT" git pull --ff-only >> "$LOG_FILE" 2>&1; then
      touch "$retry_marker"
      log "❌ git pull --ff-only 失败（可能历史分叉或超时），已写入重试标记，终止本次执行，不执行 install.sh"
      pop_stash
      return 1
    fi
    log "✓ git pull 成功"
  fi

  if bash "$REPO_DIR/install.sh" >> "$LOG_FILE" 2>&1; then
    rm -f "$retry_marker"
    log "✓ install.sh 执行成功"
    pop_stash
    return 0
  else
    touch "$retry_marker"
    log "❌ install.sh 执行失败，已写入重试标记，等待下次调度重试"
    pop_stash
    return 1
  fi
}

# 锁必须在后台子进程执行完 run_update 后才释放（而非 hook 主进程返回时）——
# 主进程只负责同步完成源仓库定位与锁获取，实际 fetch/pull/install fork 到后台，
# 主进程立即返回，不阻塞会话启动
(
  trap release_lock EXIT
  run_update
) >/dev/null 2>&1 &
disown 2>/dev/null

exit 0
