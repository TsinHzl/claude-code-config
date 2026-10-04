#!/usr/bin/env bash
# codex-pre-tool-use-hook.sh — 对 Codex apply_patch 创建只读 Pre 快照；任何异常均不阻断工具调用
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../runtime.sh" 2>/dev/null || exit 0
dac_resolve_runtime 2>/dev/null || exit 0
[[ "$DAC_RUNTIME" == codex ]] || exit 0
source "$SCRIPT_DIR/../lib.sh" 2>/dev/null || exit 0
source "$SCRIPT_DIR/codex-hook-lib.sh" 2>/dev/null || exit 0
# 自动更新仅由 SessionStart 挂点触发（见 silent-update.sh 安装逻辑）；
# PreToolUse 每次写入调用都同步跑 git pull 会引入网络延迟并与会话产生目录竞争
INPUT=$(cat) || exit 0
dac_codex_create_pre_snapshot "$INPUT" >/dev/null 2>&1 || true
exit 0
