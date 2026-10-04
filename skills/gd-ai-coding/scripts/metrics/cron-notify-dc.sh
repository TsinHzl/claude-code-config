#!/usr/bin/env bash
# ==============================================================================
# cron-notify-dc.sh - 定时执行 DAC 节点提醒调度脚本包装器
# 具备防重入文件锁、日志输出与参数透传机制
# ==============================================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="${SCRIPT_DIR}/notify-dc.py"
LOCK_DIR="/tmp/dac-notify-dc.lockdir"
LOG_DIR="${HOME}/Library/Logs"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
LOG_FILE="${LOG_DIR}/dac-notify-dc.log"

# 防重入原子目录锁检测
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  if [ -f "$LOCK_DIR/pid" ]; then
    PID=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] 调度脚本已在运行中 (PID: $PID)，跳过本次触发" >> "$LOG_FILE"
      exit 0
    fi
  fi
  # 进程已不存在但锁目录残留时清理并重新建锁
  rm -rf "$LOCK_DIR" 2>/dev/null || true
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    exit 0
  fi
fi
trap 'rm -rf "$LOCK_DIR"' EXIT INT TERM
echo $$ > "$LOCK_DIR/pid"

# 确保 python3 存在
if ! command -v python3 &>/dev/null; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [error] 未找到 python3 命令" | tee -a "$LOG_FILE" >&2
  exit 1
fi

if [ ! -f "$PYTHON_SCRIPT" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [error] 找不到调度脚本: $PYTHON_SCRIPT" | tee -a "$LOG_FILE" >&2
  exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] === 开始执行 DC 提醒定时调度 ===" >> "$LOG_FILE"
STATUS=0
python3 "$PYTHON_SCRIPT" "$@" >> "$LOG_FILE" 2>&1 || STATUS=$?
echo "[$(date '+%Y-%m-%d %H:%M:%S')] === 调度结束 (exit code: $STATUS) ===" >> "$LOG_FILE"

exit "$STATUS"
