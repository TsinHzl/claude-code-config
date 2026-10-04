#!/usr/bin/env bash
# inject-runtime-env.sh — 为 Claude Code/Codex 的 shell 工具注入 DAC 运行时路径
set -euo pipefail

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CODEX_CONFIG="$HOME/.codex/config.toml"

inject_claude_env() {
  [[ -d "$HOME/.claude" ]] || return 0
  mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
  [[ -f "$CLAUDE_SETTINGS" ]] || printf '{}\n' > "$CLAUDE_SETTINGS"
  jq empty "$CLAUDE_SETTINGS" >/dev/null

  local tmp
  tmp=$(mktemp "${CLAUDE_SETTINGS}.tmp.XXXXXX")
  jq \
    --arg runtime claude \
    --arg skill "$HOME/.claude/skills/gd-ai-coding" \
    --arg state "$HOME/.claude/skills/gd-ai-coding/state" \
    --arg config "$HOME/.claude/skills/dashboard" \
    '.env = (.env // {}) + {
      DAC_RUNTIME: $runtime,
      DAC_SKILL_HOME: $skill,
      DAC_STATE_HOME: $state,
      DAC_CONFIG_HOME: $config
    }' "$CLAUDE_SETTINGS" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$CLAUDE_SETTINGS"
}

inject_codex_env() {
  [[ -d "$HOME/.codex" ]] || return 0
  [[ -f "$CODEX_CONFIG" ]] || : > "$CODEX_CONFIG"

  local expected_runtime='DAC_RUNTIME = "codex"'
  local expected_skill="DAC_SKILL_HOME = \"$HOME/.codex/skills/gd-ai-coding\""
  local expected_state="DAC_STATE_HOME = \"$HOME/.codex/skills/gd-ai-coding/state\""
  local expected_config="DAC_CONFIG_HOME = \"$HOME/.codex/skills/dashboard\""
  if grep -Eq '^DAC_(RUNTIME|SKILL_HOME|STATE_HOME|CONFIG_HOME)\s*=' "$CODEX_CONFIG"; then
    if grep -qFx "$expected_runtime" "$CODEX_CONFIG" && grep -qFx "$expected_skill" "$CODEX_CONFIG" && grep -qFx "$expected_state" "$CODEX_CONFIG" && grep -qFx "$expected_config" "$CODEX_CONFIG"; then
      return 0
    fi
    printf '[DAC-RUNTIME] ❌ %s 已包含冲突的 DAC runtime 环境键，拒绝覆盖既有值\n' "$CODEX_CONFIG" >&2
    return 1
  fi

  if grep -q '^\[shell_environment_policy\]$' "$CODEX_CONFIG"; then
    if grep -q '^\s*set\s*=' "$CODEX_CONFIG"; then
      printf '[DAC-RUNTIME] ❌ %s 使用 inline shell_environment_policy.set，拒绝破坏现有 TOML；请先迁移为 [shell_environment_policy.set] 表\n' "$CODEX_CONFIG" >&2
      return 1
    fi
  else
    cat >> "$CODEX_CONFIG" <<EOF

[shell_environment_policy]
inherit = "all"
ignore_default_excludes = true
EOF
  fi

  if ! grep -q '^\[shell_environment_policy\.set\]\s*$' "$CODEX_CONFIG"; then
    cat >> "$CODEX_CONFIG" <<EOF

[shell_environment_policy.set]
EOF
  fi

  local tmp
  tmp=$(mktemp "${CODEX_CONFIG}.tmp.XXXXXX")
  awk \
    -v runtime='DAC_RUNTIME = "codex"' \
    -v skill="DAC_SKILL_HOME = \"$HOME/.codex/skills/gd-ai-coding\"" \
    -v state="DAC_STATE_HOME = \"$HOME/.codex/skills/gd-ai-coding/state\"" \
    -v config="DAC_CONFIG_HOME = \"$HOME/.codex/skills/dashboard\"" '
      /^\[/ && in_set { print runtime; print skill; print state; print config; in_set=0; inserted=1 }
      /^\[shell_environment_policy\.set\]$/ { in_set=1 }
      { print }
      END { if (in_set && !inserted) { print runtime; print skill; print state; print config } }
    ' "$CODEX_CONFIG" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$CODEX_CONFIG"

  # 追加后做最小结构校验：四个 DAC 键必须已存在且无重复段头，防止注入产生不可解析的 TOML
  local key
  for key in DAC_RUNTIME DAC_SKILL_HOME DAC_STATE_HOME DAC_CONFIG_HOME; do
    if ! grep -Eq "^${key}\s*=" "$CODEX_CONFIG"; then
      printf '[DAC-RUNTIME] ❌ 注入后未找到 %s，TOML 注入异常：%s\n' "$key" "$CODEX_CONFIG" >&2
      return 1
    fi
  done
  if [[ "$(grep -c '^\[shell_environment_policy\.set\]' "$CODEX_CONFIG")" -ne 1 ]]; then
    printf '[DAC-RUNTIME] ❌ [shell_environment_policy.set] 段头缺失或重复，TOML 可能不可解析：%s\n' "$CODEX_CONFIG" >&2
    return 1
  fi
}

inject_claude_env
inject_codex_env
printf '✓ DAC runtime shell 环境已注入\n'
