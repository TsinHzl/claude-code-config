#!/usr/bin/env bash
# 本地 server 版看板：停旧进程 → 启新进程 → 等就绪 → 打开浏览器
# 供终端命令 dashboard-gd 调用（在部署机上执行以对外提供看板服务）。
# 注：/dashboard 技能与终端 dashboard 命令已改为直接打开团队集中部署的固定地址，
# 见同目录 start-dashboard.sh。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${DAC_PORT:-47890}"
PID_FILE="/tmp/dac-dashboard-server.pid"
LOG_FILE="/tmp/dac-dashboard-server.log"

# 若旧进程存在，先停止（确保每次都加载最新代码）
_kill_pid() {
  local pid="$1"
  kill "$pid" 2>/dev/null || true
  for _ in $(seq 1 10); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.3
  done
  kill -9 "$pid" 2>/dev/null || true
}

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  OLD_PID="$(cat "$PID_FILE")"
  _kill_pid "$OLD_PID"
  echo "↺ 已停止旧 server (pid=$OLD_PID)"
fi
rm -f "$PID_FILE"

# 兜底：PID 文件丢失但端口仍被占用时，按端口杀残留进程
PORT_PID="$(lsof -ti tcp:$PORT 2>/dev/null || true)"
if [[ -n "$PORT_PID" ]]; then
  echo "↺ 端口 $PORT 仍被占用 (pid=$PORT_PID)，强制停止..."
  _kill_pid "$PORT_PID"
  sleep 0.5
fi

# 启动新 server（server 启动时会自动处理初始数据：/tmp/dac-metrics-data.json
# 不存在时从 dashboard-demo.json 复制一份）
nohup python3 "$SCRIPT_DIR/dashboard-server.py" > "$LOG_FILE" 2>&1 &

# 等待 server 就绪（最多 5 秒）：需同时满足 PID 文件存在 + HTTP 可达，
# 避免旧残留进程响应 curl 导致误判。
ready=0
for i in $(seq 1 10); do
  sleep 0.5
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null \
     && curl -s "http://localhost:$PORT/api/data" > /dev/null 2>&1; then
    ready=1
    break
  fi
done

if [[ "$ready" -ne 1 ]]; then
  echo "❌ server 启动失败，请检查日志：$LOG_FILE" >&2
  exit 1
fi

# 无浏览器场景（服务器/headless，或显式 DAC_NO_BROWSER）：跳过 open，仅打印地址。
# 默认（未设 DAC_NO_BROWSER 且 open 可用）行为不变。
if [[ -n "${DAC_NO_BROWSER:-}" ]] || ! command -v open >/dev/null 2>&1; then
  echo "✅ 看板已就绪（未打开浏览器）：http://localhost:$PORT"
else
  # 加时间戳 query 参数：避免 macOS open 命令识别为已打开的相同 URL 而直接聚焦旧标签页，
  # 导致浏览器沿用重启前的旧页面 JS（不含最新 SSE 事件处理逻辑）
  open "http://localhost:$PORT/?t=$(date +%s)"
  echo "✅ 看板已在浏览器中打开：http://localhost:$PORT"
fi

echo "   点击页面右上角「↻ 刷新数据」按钮可获取最新 DDP 数据（约 30s）"
echo "   Server 日志：$LOG_FILE"
