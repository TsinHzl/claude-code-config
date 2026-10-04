#!/usr/bin/env bash
# inject-permissions.sh — 注入项目级权限配置到 .claude/settings.json
# 由 install.sh 调用，确保 skill 脚本执行不需要用户手动确认

set -euo pipefail

mkdir -p ".claude"
CLAUDE_SETTINGS="$(pwd)/.claude/settings.json"

REQUIRED_ALLOWS=(
  # --- skill 脚本执行（前缀锚定到安装根目录；scripts/* 同时覆盖主 scripts/
  #     与收编后子 skill 自带的 skills/<name>/scripts/，避免其执行触发权限确认）---
  "Bash(bash ~/.claude/skills/gd-ai-coding/scripts/*)"
  "Bash(bash ~/.claude/skills/gd-ai-coding/skills/*/scripts/*)"
  "Bash(bash -* ~/.claude/skills/gd-ai-coding/scripts/*)"
  "Bash(bash -* ~/.claude/skills/gd-ai-coding/skills/*/scripts/*)"
  # --- 外部工具 ---
  "Bash(mcporter call *)"
  "Bash(openspec init*)"
  "Bash(openspec new*)"
  "Bash(openspec validate*)"
  "Bash(openspec status*)"
  "Bash(opsx new*)"
  "Bash(opsx status*)"
  # --- 文件复制（PRD 临时文件 → 产物目录）---
  "Bash(cp */dac-prd.*/trimmed-prd.md *openspec/*)"
  # --- 目录创建（仅限产物目录）---
  "Bash(mkdir -p .dac*)"
  "Bash(mkdir -p openspec*)"
  # --- JSON 读写（路径限定）---
  "Bash(jq * .dac/*)"
  "Bash(jq * openspec/*)"
  # --- 文件读取（前缀锚定；Claude Code Bash 权限规则为前缀匹配语义，
  #     不支持 ** 通配符 —— 统一收敛为明确前缀，深层子路径由前缀天然覆盖）---
  "Read(~/.claude/skills/gd-ai-coding/references/*)"
  "Read(~/.claude/skills/gd-ai-coding/prompts/*)"
  "Read(~/.claude/skills/gd-ai-coding/skills/**)"
  "Read(~/.claude/skills/gd-ai-coding/templates/*)"
  "Read(~/.claude/skills/gd-ai-coding/rules/*)"
  "Bash(cat openspec/*)"
  "Bash(cat .dac/*)"
  "Bash(cat ~/.claude/skills/gd-ai-coding/*)"
  "Bash(cat ~/.claude/skills/gd-ai-coding/scripts/*)"
  "Bash(cat ~/.claude/skills/gd-ai-coding/references/*)"
  "Bash(cat ~/.claude/skills/gd-ai-coding/prompts/*)"
  "Bash(cat ~/.claude/skills/gd-ai-coding/skills/*)"
  "Bash(cat ~/.claude/skills/gd-ai-coding/skills/*/scripts/*)"
  "Bash(cat ~/.claude/skills/gd-ai-coding/skills/*/references/*)"
  "Bash(cat ~/.claude/skills/gd-ai-coding/templates/*)"
  "Bash(cat ~/.claude/skills/gd-ai-coding/rules/*)"
  # --- 文件搜索（前缀锚定，** 通配符同上收敛）---
  "Bash(grep * openspec/*)"
  "Bash(grep * .dac/*)"
  "Bash(grep * ~/.claude/skills/gd-ai-coding/scripts/*)"
  "Bash(grep * ~/.claude/skills/gd-ai-coding/references/*)"
  "Bash(grep * ~/.claude/skills/gd-ai-coding/prompts/*)"
  "Bash(grep * ~/.claude/skills/gd-ai-coding/rules/*)"
  "Bash(grep * ~/.claude/skills/gd-ai-coding/skills/*)"
  "Bash(grep * ~/.claude/skills/gd-ai-coding/skills/*/scripts/*)"
  "Bash(grep * ~/.claude/skills/gd-ai-coding/skills/*/references/*)"
  "Bash(find openspec/*)"
  "Bash(find .dac/*)"
  "Bash(find ~/.claude/skills/gd-ai-coding/scripts/*)"
  "Bash(find ~/.claude/skills/gd-ai-coding/references/*)"
  "Bash(find ~/.claude/skills/gd-ai-coding/prompts/*)"
  "Bash(find ~/.claude/skills/gd-ai-coding/rules/*)"
  "Bash(find ~/.claude/skills/gd-ai-coding/skills/*)"
  "Bash(find ~/.claude/skills/gd-ai-coding/skills/*/scripts/*)"
  "Bash(find ~/.claude/skills/gd-ai-coding/skills/*/references/*)"
  "Bash(ls openspec*)"
  "Bash(ls .dac*)"
  "Bash(ls ~/.claude/skills/gd-ai-coding/scripts/*)"
  "Bash(ls ~/.claude/skills/gd-ai-coding/references/*)"
  "Bash(ls ~/.claude/skills/gd-ai-coding/prompts/*)"
  "Bash(ls ~/.claude/skills/gd-ai-coding/rules/*)"
  "Bash(ls ~/.claude/skills/gd-ai-coding/skills/*)"
  "Bash(ls ~/.claude/skills/gd-ai-coding/skills/*/scripts/*)"
  "Bash(ls ~/.claude/skills/gd-ai-coding/skills/*/references/*)"
  # --- 只读工具（前缀锚定）---
  "Bash(wc * openspec/*)"
  "Bash(wc * .dac/*)"
  "Bash(head * openspec/*)"
  "Bash(head * .dac/*)"
  "Bash(tail * openspec/*)"
  "Bash(tail * .dac/*)"
  "Bash(date +*)"
  "Bash(date)"
)

REQUIRED_DENYS=(
  "Bash(rm -rf .dac*)"
  "Bash(git push --force*)"
)

# permission/guard hook 配置
# - PreToolUse:Bash        → guard.sh           （Level 2/3 bash 命令拦截）
# - PreToolUse:Skill       → skill-guard.sh      （禁止 opsx:apply 等不相干 skill）
# - PostToolUse:Skill      → skill-postuse.sh    （opsx:propose 返回后注入回流提醒）
# - write-trace-hook.sh 已改为由全局 inject-global-hook.sh 注入 PostToolUse，不再在此处项目级注册
BASH_GUARD_CMD="bash ~/.claude/skills/gd-ai-coding/scripts/permission/guard.sh"
SKILL_GUARD_CMD="bash ~/.claude/skills/gd-ai-coding/scripts/permission/skill-guard.sh"
SKILL_POST_CMD="bash ~/.claude/skills/gd-ai-coding/scripts/permission/skill-postuse.sh"
HOOK_JSON=$(jq -n \
  --arg bash_cmd  "$BASH_GUARD_CMD" \
  --arg sg_cmd    "$SKILL_GUARD_CMD" \
  --arg sp_cmd    "$SKILL_POST_CMD" \
  '{
    "hooks": {
      "PreToolUse": [
        { "matcher": "Bash",  "hooks": [{"type": "command", "command": $bash_cmd}] },
        { "matcher": "Skill", "hooks": [{"type": "command", "command": $sg_cmd}] }
      ],
      "PostToolUse": [
        { "matcher": "Skill",       "hooks": [{"type": "command", "command": $sp_cmd}] }
      ]
    }
  }')

ALLOWS_JSON=$(printf '%s\n' "${REQUIRED_ALLOWS[@]}" | jq -R . | jq -s .)
DENYS_JSON=$(printf '%s\n' "${REQUIRED_DENYS[@]}" | jq -R . | jq -s .)

if [ ! -f "$CLAUDE_SETTINGS" ]; then
  jq -n --argjson allows "$ALLOWS_JSON" --argjson denys "$DENYS_JSON" --argjson hooks "$HOOK_JSON" \
    '$hooks + {"permissions": {"allow": $allows, "deny": $denys}}' > "$CLAUDE_SETTINGS"
else
  TMPFILE=$(mktemp)
  # hooks 合并策略：
  # - 不与用户既有的、非本插件管理的 hook 项冲突（保留 matcher 不在 [Bash, Skill] 的用户 hook）
  # - 本插件管理的 matcher（PreToolUse:Bash, PreToolUse:Skill, PostToolUse:Skill）始终以本次注入为准
  # - write-trace-hook.sh 已迁移到全局注册，此处顺带清理历史遗留的项目级 Write|Edit /
  #   Write|Edit|MultiEdit matcher 残留条目，避免与全局条目重复触发
  # - 幂等：重复运行不会重复堆叠
  jq --argjson req_allows "$ALLOWS_JSON" --argjson req_denys "$DENYS_JSON" --argjson hooks "$HOOK_JSON" '
    .permissions.allow = ((.permissions.allow // []) + ($req_allows - (.permissions.allow // []))) |
    .permissions.deny = ((.permissions.deny // []) + ($req_denys - (.permissions.deny // []))) |
    .hooks = (.hooks // {}) |
    .hooks.PreToolUse =
      (((.hooks.PreToolUse // []) | map(select(.matcher != "Bash" and .matcher != "Skill")))
        + $hooks.hooks.PreToolUse) |
    .hooks.PostToolUse =
      (((.hooks.PostToolUse // []) | map(select(.matcher != "Skill" and .matcher != "Write|Edit" and .matcher != "Write|Edit|MultiEdit")))
        + $hooks.hooks.PostToolUse)
  ' "$CLAUDE_SETTINGS" > "$TMPFILE" && mv "$TMPFILE" "$CLAUDE_SETTINGS"
fi

echo "✓ 项目级权限 + hooks 配置：.claude/settings.json"
