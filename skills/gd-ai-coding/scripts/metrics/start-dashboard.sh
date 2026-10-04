#!/usr/bin/env bash
# 打开 DAC 工作流数据看板（团队集中部署，固定地址）
# 供 /dashboard 技能与终端 dashboard 命令共用。若需在本机起 server，用 dashboard-gd
# （见同目录 start-dashboard-local.sh）。地址可用 DAC_DASHBOARD_URL 覆盖。
set -euo pipefail

DASHBOARD_URL="${DAC_DASHBOARD_URL:-http://172.24.244.18:47890}"
echo "打开看板：$DASHBOARD_URL"

if command -v open >/dev/null 2>&1; then
  open "$DASHBOARD_URL"                   # macOS
  echo "✅ 已尝试用浏览器打开：$DASHBOARD_URL"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$DASHBOARD_URL"               # Linux
  echo "✅ 已尝试用浏览器打开：$DASHBOARD_URL"
elif command -v cmd.exe >/dev/null 2>&1; then
  # start 是 cmd 内建命令，Git Bash 下 command -v start 查不到，故检测 cmd.exe
  cmd.exe /c start "" "$DASHBOARD_URL"    # Windows (Git Bash)
  echo "✅ 已尝试用浏览器打开：$DASHBOARD_URL"
else
  echo "⚠️  未找到浏览器打开命令（open/xdg-open/cmd.exe），请手动访问：$DASHBOARD_URL" >&2
  exit 1
fi
