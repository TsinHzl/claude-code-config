#!/usr/bin/env bash
# permission/skill-guard.sh
# Skill 工具 PreToolUse 拦截脚本
# 作为 Claude Code PreToolUse hook（matcher: "Skill"）配置使用
#
# 拦截规则：
# - 禁止在本流程中通过 Skill 工具调用 opsx:apply（codegen 由 feature-loop 自有管线完成）
#
# Hook stdin: {"tool_name": "Skill", "tool_input": {"skill": "...", "args": "..."}}

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)
SKILL_NAME=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('skill',''))" 2>/dev/null || true)

# JSON 解析失败 → 拒绝执行（与 guard.sh 策略一致，防 bypass）
if [[ -z "$TOOL_NAME" ]]; then
  echo "🚫 permission/skill-guard：无法解析 hook 输入，已拒绝执行" >&2
  exit 1
fi

# 非 Skill 工具不处理
[[ "$TOOL_NAME" != "Skill" ]] && exit 0

# 拦截 opsx:apply（含可能的别名 openspec-apply-change / opsx-apply）
case "$SKILL_NAME" in
  opsx:apply | opsx-apply | openspec-apply-change)
    echo "🚫 gd-ai-coding 流程禁止调用 ${SKILL_NAME}：" >&2
    echo "   本项目的代码实现由 feature-loop 自有 codegen 管线完成（pre/post-codegen-check + sub-agent CR），" >&2
    echo "   不走 openspec 的 apply 阶段。请继续 feature-plan / feature-loop 流程的剩余步骤。" >&2
    exit 2
    ;;
esac

exit 0
