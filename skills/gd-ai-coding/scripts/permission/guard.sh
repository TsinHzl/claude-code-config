#!/usr/bin/env bash
# permission/guard.sh
# Level 2/3 工具权限硬拦截脚本
# 作为 Claude Code PreToolUse hook 配置使用
#
# 配置方式（在项目根目录 .claude/settings.json）：
# {
#   "hooks": {
#     "PreToolUse": [
#       {
#         "matcher": "Bash",
#         "hooks": [{"type": "command", "command": "bash ~/.claude/skills/gd-ai-coding/scripts/permission/guard.sh"}]
#       },
#       {
#         "matcher": "Edit",
#         "hooks": [{"type": "command", "command": "bash ~/.claude/skills/gd-ai-coding/scripts/permission/guard.sh"}]
#       },
#       {
#         "matcher": "Write",
#         "hooks": [{"type": "command", "command": "bash ~/.claude/skills/gd-ai-coding/scripts/permission/guard.sh"}]
#       }
#     ]
#   }
# }
#
# Hook 执行时通过 stdin 接收 JSON：{"tool_name": "...", "tool_input": {"command": "..."}}

set -euo pipefail

# 读取 hook 输入（JSON from stdin）
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)
COMMAND=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)
FILE_PATH=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || true)

# JSON 解析失败时拒绝，防止 bypass
if [[ -z "$TOOL_NAME" ]]; then
  echo "🚫 permission/guard：无法解析 hook 输入，已拒绝执行"
  exit 1
fi

# --- Edit/Write 工具：核心文件保护 ---
if [[ "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "Write" ]]; then
  if [[ -n "$FILE_PATH" ]] && echo "$FILE_PATH" | grep -qE '(app_router|injection|di\.dart)'; then
    echo ""
    echo "⚠️  Level 2 操作：通过 ${TOOL_NAME} 修改核心文件（路由/依赖注入）"
    echo "文件：$FILE_PATH"
    read -r -p "确认修改核心文件？(yes/no): " confirm < /dev/tty
    if [[ "$confirm" != "yes" ]]; then
      echo "❌ 已取消"
      exit 1
    fi
  fi
  exit 0
fi

# 非 Bash 工具不需要命令级策略检查
[[ "$TOOL_NAME" != "Bash" ]] && exit 0

# --- Level 3：永久禁止（直接 exit 1）---

# 禁止删除 .dac/ 目录（兼容短选项 rm -rf、长选项 rm --recursive --force、混合变体）
if echo "$COMMAND" | grep -qE 'rm\s+.*\.dac/?(\s|$)' && echo "$COMMAND" | grep -qE 'rm\s+.*(--recursive|-[a-zA-Z]*r[a-zA-Z]*)'; then
  echo "🚫 Level 3 禁止：不允许删除 .dac/ 目录（包含项目知识和状态，请手动操作）"
  exit 1
fi

# 禁止写入覆盖 rules/ 文件（cp/mv 目标为 rules/，或 tee/重定向写入 rules/）
if echo "$COMMAND" | grep -qE '(cp|mv)\s+.+\s+.*rules/' || echo "$COMMAND" | grep -qE 'tee\s+.*rules/' || echo "$COMMAND" | grep -qE '>.*rules/'; then
  echo "🚫 Level 3 禁止：不允许覆盖 rules/ 规范文件"
  exit 1
fi

# 禁止销毁 Git 历史（reset --hard、rebase -i、filter-branch、push --force/-f）
if echo "$COMMAND" | grep -qE 'git\s+(-[a-zA-Z]\s+\S+\s+)*(\s+-c\s+\S+\s+)*(reset\s+--hard|rebase\s+-i|filter-branch)'; then
  echo "🚫 Level 3 禁止：不允许销毁 Git 历史，请联系人工处理"
  exit 1
fi
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*(--force|-f)(\s|$)'; then
  echo "🚫 Level 3 禁止：不允许 force push（会销毁远端历史），请联系人工处理"
  exit 1
fi

# --- Level 2：硬拦截 + 强确认（不可逆操作）---

# openspec apply
if echo "$COMMAND" | grep -qE 'opsx\s+apply|openspec\s+apply'; then
  FEAT_ID=$(python3 -c "
import json, sys
try:
    d = json.load(open('.dac/state.json'))
    print(d.get('current_feature_id') or '')
except:
    print('')
" 2>/dev/null || echo "")

  SCOPE="${FEAT_ID:+.dac/$FEAT_ID/code-scope.md}"

  echo ""
  echo "⚠️  Level 2 操作：openspec apply（不可逆代码写入）"
  echo "   超时保护：5 分钟（300s），超时后自动终止"
  echo "────────────────────────────────────"
  if [[ -n "$FEAT_ID" ]] && [[ -f "$SCOPE" ]]; then
    echo "功能：$FEAT_ID"
    echo "影响文件："
    grep -E '^\|' "$SCOPE" | grep -v '^| 文件\|^|---' | head -10 || true
  fi
  echo "────────────────────────────────────"
  read -r -p "确认执行 openspec apply？(yes/no): " confirm < /dev/tty
  if [[ "$confirm" != "yes" ]]; then
    echo "❌ 已取消 openspec apply"
    exit 1
  fi
  echo "✅ 用户已确认，继续执行"
fi

# 删除任意文件（排除 .dac/.lock 等内部临时文件；检测复合命令中的 rm/unlink）
if echo "$COMMAND" | grep -qE '(^|[;&|]\s*)(rm|unlink)\s'; then
  if echo "$COMMAND" | grep -qE '(^|[;&|]\s*)rm\s+(-f\s+)?\.dac/\.lock$'; then
    : # 内部 lock 文件清理，放行
  else
    echo ""
    echo "⚠️  Level 2 操作：删除文件"
    echo "命令：$COMMAND"
    read -r -p "确认执行删除操作？(yes/no): " confirm < /dev/tty
    if [[ "$confirm" != "yes" ]]; then
      echo "❌ 已取消删除操作"
      exit 1
    fi
  fi
fi

# 修改核心文件（router / injection）
if echo "$COMMAND" | grep -qE '(app_router|injection|di\.dart)' && echo "$COMMAND" | grep -qE '(write|edit|sed|awk|tee)'; then
  echo ""
  echo "⚠️  Level 2 操作：修改核心文件（路由/依赖注入）"
  echo "命令：$COMMAND"
  read -r -p "确认修改核心文件？(yes/no): " confirm < /dev/tty
  if [[ "$confirm" != "yes" ]]; then
    echo "❌ 已取消"
    exit 1
  fi
fi

# 通过：所有检查均未触发拦截
exit 0
