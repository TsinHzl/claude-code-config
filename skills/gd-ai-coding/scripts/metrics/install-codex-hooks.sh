#!/usr/bin/env bash
# install-codex-hooks.sh — 无损安装 DAC 的 Codex apply_patch Hook
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

case "$SKILL_HOME" in
  *$'\n'*|*$'\r'*)
    printf '[DAC-CODEX-HOOK] ❌ Skill 路径包含不可安全执行的控制字符\n' >&2
    exit 1
    ;;
esac

CONFIG_DIR="$(dirname "$CONFIG_PATH")"
mkdir -p "$CONFIG_DIR"
printf -v PRE_COMMAND 'bash %q' "$SKILL_HOME/scripts/metrics/codex-pre-tool-use-hook.sh"
printf -v POST_COMMAND 'bash %q' "$SKILL_HOME/scripts/metrics/codex-post-tool-use-hook.sh"
INPUT_PATH=$(mktemp "$CONFIG_DIR/.hooks.json.dac-input.XXXXXX")
TMP_PATH=$(mktemp "$CONFIG_DIR/.hooks.json.dac-output.XXXXXX")
cleanup() { rm -f "$INPUT_PATH" "$TMP_PATH" "$BACKUP_PATH"; }
trap cleanup EXIT

if [[ -f "$CONFIG_PATH" ]]; then
  cp "$CONFIG_PATH" "$INPUT_PATH"
else
  printf '{"hooks":{}}\n' > "$INPUT_PATH"
fi
chmod 600 "$INPUT_PATH"

jq -e '. | type == "object" and ((.hooks // {}) | type == "object")' "$INPUT_PATH" >/dev/null || {
  printf '[DAC-CODEX-HOOK] ❌ Hook 配置不是合法的 {hooks:{...}} JSON：%s\n' "$CONFIG_PATH" >&2
  exit 1
}

BACKUP_PATH=$(mktemp "$CONFIG_DIR/hooks.json.dac-backup.XXXXXX")
cp "$INPUT_PATH" "$BACKUP_PATH"
chmod 600 "$BACKUP_PATH"

if ! jq -e \
  --arg pre_command "$PRE_COMMAND" \
  --arg post_command "$POST_COMMAND" '
    def desired($command): {
      _source: "gd-ai-coding",
      matcher: "apply_patch",
      hooks: [{type: "command", command: $command, timeout: 10, async: false}]
    };
    def valid($command):
      ._source == "gd-ai-coding" and
      .matcher == "apply_patch" and
      .hooks == [{type: "command", command: $command, timeout: 10, async: false}];
    def install($event; $command):
      (.hooks[$event] // []) as $groups |
      [$groups | to_entries[] | select(.value._source == "gd-ai-coding")] as $dac |
      if ($dac | length) > 1 or any($dac[]; (.value | valid($command) | not)) then
        error("检测到损坏或冲突的 gd-ai-coding Hook group")
      elif ($dac | length) == 1 then
        .hooks[$event] = ($groups | .[$dac[0].key] = desired($command))
      else
        .hooks[$event] = ($groups + [desired($command)])
      end;
    .hooks = (.hooks // {}) |
    install("PreToolUse"; $pre_command) |
    install("PostToolUse"; $post_command)
  ' "$INPUT_PATH" > "$TMP_PATH"; then
  printf '[DAC-CODEX-HOOK] ❌ Hook 配置合并失败，已保留原文件：%s\n' "$CONFIG_PATH" >&2
  exit 1
fi

jq -e '.hooks.PreToolUse and .hooks.PostToolUse' "$TMP_PATH" >/dev/null || {
  printf '[DAC-CODEX-HOOK] ❌ Hook 配置验证失败，已保留原文件：%s\n' "$CONFIG_PATH" >&2
  exit 1
}

chmod 600 "$TMP_PATH"
if [[ "${DAC_HOOKS_FAIL_AFTER_WRITE:-}" == "1" ]]; then
  printf '[DAC-CODEX-HOOK] ❌ 故障注入已保留安装前配置\n' >&2
  exit 1
fi
mv "$TMP_PATH" "$CONFIG_PATH"
printf '✓ Codex PreToolUse/PostToolUse apply_patch Hook 已安装：%s\n' "$CONFIG_PATH"
