#!/usr/bin/env bash
# permission/skill-postuse.sh
# Skill 工具 PostToolUse 回流提醒脚本
# 作为 Claude Code PostToolUse hook（matcher: "Skill"）配置使用
#
# 行为：opsx:propose 返回后，主动向主会话注入"继续 feature-plan 后续步骤"的强提示，
# 避免 LLM 把 opsx:propose 的下一步建议（/opsx:apply）误当作 feature-plan 的下一步。
#
# Hook stdin: {"tool_name": "Skill", "tool_input": {"skill": "...", ...}, "tool_response": ...}

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)
SKILL_NAME=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('skill',''))" 2>/dev/null || true)

# 解析失败或非 Skill 工具 → 静默放行
[[ -z "$TOOL_NAME" || "$TOOL_NAME" != "Skill" ]] && exit 0

# 仅在 opsx:propose 返回后注入提醒
# 注意：PostToolUse hook 的 stdout 在 exit 0 时仅进入 transcript 日志，不会回灌给 LLM。
# 必须用 exit 2 + stderr，才能让 reminder 真正被主会话看到。
case "$SKILL_NAME" in
  opsx:propose | opsx-propose | openspec-propose)
    cat >&2 <<'EOF'
[harness reminder] opsx:propose 已返回（仅子 skill 完成，不等于 feature-plan 流程完成）。
当前流程位置：feature-plan 流程步骤 2.2 之后。
下一步：**立即继续步骤 2.3（验证 4 个 openspec 产物）**，然后 2.4/2.5/3/4/5。
禁止：
  - end-of-turn 把控制权交还用户
  - 把 opsx:propose 的下一步建议（如 "run /opsx:apply"）当作 feature-plan 的下一步
  - 仅以文本形式描述"接下来运行 X"（必须真正通过 Skill/Bash 工具调用）
直到 state.json 的 phase 更新为 feature-planned，feature-plan 才算完成。
EOF
    exit 2
    ;;
  opsx:archive | opsx-archive | openspec-archive-change)
    STATE_FILE=".dac/state.json"
    if [[ -f "$STATE_FILE" ]]; then
      CURRENT_PHASE=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('phase',''))" 2>/dev/null || true)
      if [[ "$CURRENT_PHASE" == "feature-done" ]]; then
        SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        bash "$SCRIPTS_DIR/state-update.sh" --phase done --force
        echo "✅ archive 完成，phase 已自动更新：feature-done → done" >&2
      fi
    fi
    exit 0
    ;;
esac

exit 0
