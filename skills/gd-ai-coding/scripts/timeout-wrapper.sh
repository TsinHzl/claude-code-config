#!/usr/bin/env bash
# timeout-wrapper.sh <timeout_seconds> <command...>
# 为 openspec 等长时操作提供超时保护
# 超时后终止进程并输出标准错误码

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "用法: timeout-wrapper.sh <seconds> <command...>" >&2
  exit 1
fi

TIMEOUT=$1
shift

# 优先使用系统 timeout 命令
if command -v gtimeout &>/dev/null; then
  gtimeout "${TIMEOUT}s" "$@"
  EXIT_CODE=$?
elif command -v timeout &>/dev/null; then
  timeout "${TIMEOUT}s" "$@"
  EXIT_CODE=$?
else
  # macOS 无 coreutils 时的 fallback：后台进程 + 定时器
  "$@" &
  CMD_PID=$!

  (
    sleep "$TIMEOUT"
    if kill -0 $CMD_PID 2>/dev/null; then
      kill -TERM $CMD_PID 2>/dev/null
      sleep 2
      kill -9 $CMD_PID 2>/dev/null || true
    fi
  ) &
  TIMER_PID=$!

  wait $CMD_PID 2>/dev/null
  EXIT_CODE=$?

  kill $TIMER_PID 2>/dev/null || true
  wait $TIMER_PID 2>/dev/null || true
fi

# 退出码 124 (GNU timeout)、137 (SIGKILL)、143 (SIGTERM, macOS fallback) 表示超时
if [[ $EXIT_CODE -eq 124 ]] || [[ $EXIT_CODE -eq 137 ]] || [[ $EXIT_CODE -eq 143 ]]; then
  echo "[DAC-GEN-005] ❌ 操作超时（${TIMEOUT}s），已终止"
  echo "   请检查网络连接或减小功能范围后重试"
  exit 1
fi

exit $EXIT_CODE
