#!/usr/bin/env bash
# inject-global-hook.sh — 幂等注入全局 SessionStart 静默更新 hook 到 ~/.claude/settings.json
# 由 install.sh 调用。全局文件承载用户其他工具的配置（iTerm 状态栏、openspec 提示等），
# 合并前必须校验现有内容合法且保留备份，任何一步失败都中止、不覆盖原文件。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

SETTINGS_FILE="$HOME/.claude/settings.json"
BACKUP_DIR="$HOME/.claude/skills/.dac-settings-backup"
BACKUP_RETENTION=3
SILENT_UPDATE_CMD="bash ~/.claude/skills/gd-ai-coding/scripts/maintenance/silent-update.sh >/dev/null 2>&1 || true"
WRITE_TRACE_CMD="bash ~/.claude/skills/gd-ai-coding/scripts/metrics/write-trace-hook.sh"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  echo '{}' > "$SETTINGS_FILE"
fi

if ! validate_json "$SETTINGS_FILE"; then
  echo "[DAC-PERM] ❌ $SETTINGS_FILE 内容非合法 JSON，已中止注入（不覆盖原文件）" >&2
  exit 1
fi

# 写入前备份（仅保留最近 N 份，写入新备份前清理更旧的）
mkdir -p "$BACKUP_DIR"
cp "$SETTINGS_FILE" "$BACKUP_DIR/settings.json.$(date +%Y%m%d%H%M%S).bak"
ls -1t "$BACKUP_DIR"/settings.json.*.bak 2>/dev/null | tail -n +$((BACKUP_RETENTION + 1)) | while IFS= read -r old; do
  rm -f "$old"
done

# 幂等合并：按 command 字符串精确匹配替换本插件自身条目，保留其他已有 SessionStart 条目
if ! atomic_jq '
  .hooks = (.hooks // {}) |
  .hooks.SessionStart = (
    ((.hooks.SessionStart // []) | map(select((.hooks[0].command // "") != $cmd)))
    + [{"hooks": [{"type": "command", "command": $cmd}]}]
  )
' "$SETTINGS_FILE" --arg cmd "$SILENT_UPDATE_CMD"; then
  echo "[DAC-PERM] ❌ 全局 hook 合并写入失败：$SETTINGS_FILE" >&2
  exit 1
fi

# 幂等合并：按 command 字符串精确匹配替换本插件自身的实时 write-trace 条目，
# 保留全局配置中其他工具已有的 PostToolUse 条目不受影响
if ! atomic_jq '
  .hooks = (.hooks // {}) |
  .hooks.PostToolUse = (
    ((.hooks.PostToolUse // []) | map(select((.hooks[0].command // "") != $cmd)))
    + [{"matcher": "Write|Edit|MultiEdit", "hooks": [{"type": "command", "command": $cmd}]}]
  )
' "$SETTINGS_FILE" --arg cmd "$WRITE_TRACE_CMD"; then
  echo "[DAC-PERM] ❌ 全局 hook 合并写入失败：$SETTINGS_FILE" >&2
  exit 1
fi

echo "✓ 全局 SessionStart + PostToolUse(write-trace) hook：$SETTINGS_FILE"
