#!/usr/bin/env bash
# uninstall-codex-hooks.sh — 无损移除 DAC 的 Codex apply_patch Hook
set -euo pipefail

CONFIG_PATH="${HOME}/.codex/hooks.json"
SKILL_HOME="${HOME}/.codex/skills/gd-ai-coding"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_PATH="$2"; shift 2 ;;
    --skill-home) SKILL_HOME="$2"; shift 2 ;;
    *) printf '[DAC-CODEX-HOOK] ❌ 未知参数：%s\n' "$1" >&2; exit 1 ;;
  esac
done

[[ -f "$CONFIG_PATH" ]] || exit 0
case "$SKILL_HOME" in
  *$'\n'*|*$'\r'*)
    printf '[DAC-CODEX-HOOK] ❌ Skill 路径包含不可安全执行的控制字符\n' >&2
    exit 1
    ;;
esac

CONFIG_DIR="$(dirname "$CONFIG_PATH")"
printf -v PRE_COMMAND 'bash %q' "$SKILL_HOME/scripts/metrics/codex-pre-tool-use-hook.sh"
printf -v POST_COMMAND 'bash %q' "$SKILL_HOME/scripts/metrics/codex-post-tool-use-hook.sh"
jq -e '. | type == "object" and ((.hooks // {}) | type == "object")' "$CONFIG_PATH" >/dev/null || {
  printf '[DAC-CODEX-HOOK] ❌ Hook 配置不是合法的 {hooks:{...}} JSON：%s\n' "$CONFIG_PATH" >&2
  exit 1
}

jq -e '[(.hooks.PreToolUse // [])[], (.hooks.PostToolUse // [])[] | select(._source == "gd-ai-coding")] | length > 0' "$CONFIG_PATH" >/dev/null || exit 0

BACKUP_PATH=$(mktemp "$CONFIG_DIR/hooks.json.dac-backup.XXXXXX")
TMP_PATH=$(mktemp "$CONFIG_DIR/.hooks.json.dac-uninstall.XXXXXX")
cleanup() { rm -f "$TMP_PATH"; }
trap cleanup EXIT
cp "$CONFIG_PATH" "$BACKUP_PATH"
chmod 600 "$BACKUP_PATH"

if ! jq -e \
  --arg pre_command "$PRE_COMMAND" \
  --arg post_command "$POST_COMMAND" '
    def desired($command): {
      _source: "gd-ai-coding",
      matcher: "apply_patch",
      hooks: [{type: "command", command: $command, timeout: 10, async: false}]
    };
    def remove($event; $command):
      if (.hooks | has($event) | not) then .
      else
        .hooks[$event] as $groups |
        [$groups[] | select(._source == "gd-ai-coding")] as $dac |
        if any($dac[]; . != desired($command)) then
          error("检测到损坏或冲突的 gd-ai-coding Hook group")
        else
          .hooks[$event] = [$groups[] | select(._source != "gd-ai-coding")]
        end
      end;
    .hooks = (.hooks // {}) |
    remove("PreToolUse"; $pre_command) |
    remove("PostToolUse"; $post_command)
  ' "$CONFIG_PATH" > "$TMP_PATH"; then
  printf '[DAC-CODEX-HOOK] ❌ Hook 卸载失败，已保留原文件：%s\n' "$CONFIG_PATH" >&2
  exit 1
fi

chmod 600 "$TMP_PATH"
if [[ "${DAC_HOOKS_FAIL_AFTER_WRITE:-}" == "1" ]]; then
  printf '[DAC-CODEX-HOOK] ❌ 故障注入已保留卸载前配置\n' >&2
  exit 1
fi
mv "$TMP_PATH" "$CONFIG_PATH"
# 卸载成功后备份已无用途；失败路径保留备份供人工恢复
rm -f "$BACKUP_PATH"
printf '✓ Codex DAC apply_patch Hook 已卸载：%s\n' "$CONFIG_PATH"
