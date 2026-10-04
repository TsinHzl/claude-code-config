#!/usr/bin/env bash
# =============================================================================
# init-trace.sh — 初始化本次工作流的归因追踪
# =============================================================================
#
# 职责：
#   1. 创建 .dac/trace/ 目录（存放本次需求的追踪 JSON 文件）
#   2. 捕获当前 Claude Code 的 session UUID，写入 .dac/workflow_session_id
#
# 为什么需要 session UUID？
#   git-ai 会把 AI 写代码的归因数据写入 refs/notes/ai，其中包含 Claude
#   session UUID（agent_id.id）。我们自己采集的 refs/notes/dac-trace 里
#   也记录同一个 UUID（workflow_session_id），后端通过这个字段把两条 notes
#   关联起来，从而知道"这行代码是 AI 写的，且属于哪个工作流需求"。
#
# session UUID 从哪里读？
#   Claude Code 把每个会话的对话记录存为 ~/.claude/projects/<project-key>/<uuid>.jsonl
#   project-key 是工作目录路径，将 "/" 和 "_" 全部替换为 "-" 得到。
#   脚本从当前目录往上逐级查找匹配的目录，取最新 .jsonl 文件名作为 UUID。
#
#   逐级向上是为了兼容"从 workspace 根打开 Claude Code，但 init 在子目录运行"
#   的多仓库工作区场景（如 driver/ 下有多个 Flutter repo）。
#
# 调用时机：
#   init-dac.sh 的初始化阶段，每次 init 或 --resume 时执行一次。
#
# 产物：
#   .dac/trace/          （目录，后续 record-trace.sh 在此创建追踪 JSON）
#   .dac/workflow_session_id  （文件，存放 Claude session UUID 字符串）
# =============================================================================

set -euo pipefail

DAC_DIR=".dac"
mkdir -p "$DAC_DIR/trace"

# 从当前目录往上逐级查找 Claude Code 的 projects 目录
# Claude Code 的 project-key 规则：路径中 "/" 和 "_" 均替换为 "-"
# 例：/Users/didi/project/driver/driver_biz_main → -Users-didi-project-driver-driver-biz-main
_session_id="unknown"
_check="$(pwd)"
while [[ -n "$_check" && "$_check" != "/" ]]; do
  # 将路径转换为 Claude projects 目录的 key 格式
  _key="${_check//\//-}"   # "/" → "-"
  _key="${_key//_/-}"      # "_" → "-"
  _dir="$HOME/.claude/projects/${_key}"

  if [[ -d "$_dir" ]]; then
    # 取最新的 .jsonl 文件，文件名即为 session UUID
    _latest=$(ls -t "$_dir"/*.jsonl 2>/dev/null | head -1)
    if [[ -n "$_latest" ]]; then
      _session_id=$(basename "$_latest" .jsonl)
      break
    fi
  fi
  # 未找到则继续向上一级
  _check="$(dirname "$_check")"
done

# 写入 session UUID 供后续 record-trace.sh 使用
# "unknown" 表示当前未在 Claude Code session 中运行，归因链会断开但不影响流程继续
echo "$_session_id" > "$DAC_DIR/workflow_session_id"
echo "✓ session UUID: $_session_id"
