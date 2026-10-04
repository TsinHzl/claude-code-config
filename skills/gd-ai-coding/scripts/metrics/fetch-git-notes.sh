#!/usr/bin/env bash
# fetch-git-notes.sh — 从 Flutter 仓库拉取 refs/notes/ai 和 refs/notes/dac-trace
# 环境变量：
#   FLUTTER_REPO_URL  目标仓库 SSH/HTTPS 地址（必须）
# 输出文件：
#   /tmp/dac-git-ai-notes.json    每人 AI 使用量统计
#   /tmp/dac-git-trace-notes.json 每人 dac-trace 需求进度

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="${FLUTTER_REPO_URL:?'FLUTTER_REPO_URL 未设置'}"
WORK_DIR="/tmp/dac-git-notes-work"

echo "[$(date '+%H:%M:%S')] 初始化 git notes 工作目录 (repo: ${REPO_URL})"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
git init -q
git remote add origin "$REPO_URL"

# 拉取 refs/notes/ai（失败不中断）
if git fetch origin 'refs/notes/ai:refs/notes/ai' 2>/dev/null; then
    count=$(git notes --ref=refs/notes/ai list 2>/dev/null | wc -l | tr -d ' ')
    echo "[git-notes] refs/notes/ai 获取成功：${count} 条 note"
else
    echo "[git-notes] refs/notes/ai 不存在，跳过"
fi

# 拉取 refs/notes/dac-trace（失败不中断）
if git fetch origin 'refs/notes/dac-trace:refs/notes/dac-trace' 2>/dev/null; then
    count=$(git notes --ref=refs/notes/dac-trace list 2>/dev/null | wc -l | tr -d ' ')
    echo "[git-notes] refs/notes/dac-trace 获取成功：${count} 条 note"
else
    echo "[git-notes] refs/notes/dac-trace 不存在，跳过"
fi

python3 "$SCRIPT_DIR/transform-git-notes.py" "$WORK_DIR"
