#!/usr/bin/env bash
# runtime.sh — Claude Code / Codex 的统一安装、状态和配置路径解析

_dac_runtime_error() {
  printf '[DAC-RUNTIME] %s\n' "$1" >&2
  return 1
}

_dac_runtime_path_signal() {
  local path="$1"
  case "/$path/" in
    */./*|*/../*) return 1 ;;
  esac
  case "$path" in
    "$HOME"/.claude/*) printf 'claude\n' ;;
    "$HOME"/.codex/*) printf 'codex\n' ;;
    *) return 0 ;;
  esac
}

dac_resolve_runtime() {
  local explicit_runtime="${DAC_RUNTIME:-}"
  local skill_home="${DAC_SKILL_HOME:-}"
  local state_home="${DAC_STATE_HOME:-}"
  local config_home="${DAC_CONFIG_HOME:-}"
  local signals=()
  local signal runtime=""
  local path runtime_script

  if [[ -n "$explicit_runtime" ]]; then
    case "$explicit_runtime" in
      claude|codex) signals+=("$explicit_runtime") ;;
      *) _dac_runtime_error "不支持的 DAC_RUNTIME: $explicit_runtime"; return 1 ;;
    esac
  fi

  for path in "$skill_home" "$state_home" "$config_home"; do
    if [[ -n "$path" ]]; then
      [[ "$path" == /* ]] || { _dac_runtime_error "路径必须为绝对路径: $path"; return 1; }
      signal=$(_dac_runtime_path_signal "$path") || { _dac_runtime_error "路径不得包含 . 或 .. 段: $path"; return 1; }
      [[ -z "$signal" ]] || signals+=("$signal")
    fi
  done

  runtime_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/$(basename "${BASH_SOURCE[0]}")"
  signal=$(_dac_runtime_path_signal "$runtime_script")
  [[ -z "$signal" ]] || signals+=("$signal")

  if [[ ${#signals[@]} -eq 0 ]]; then
    for path in "$HOME"/.*; do
      [[ -d "$path/skills/gd-ai-coding" ]] || continue
      case "${path##*/}" in
        .claude) signals+=(claude) ;;
        .codex) signals+=(codex) ;;
      esac
    done
  fi
  [[ ${#signals[@]} -gt 0 ]] || { _dac_runtime_error '无法推断 runtime；请设置 DAC_RUNTIME'; return 1; }

  runtime="${signals[0]}"
  for signal in "${signals[@]}"; do
    [[ "$signal" == "$runtime" ]] || { _dac_runtime_error '检测到跨客户端 runtime/path conflict'; return 1; }
  done

  case "$runtime" in
    claude)
      : "${skill_home:=$HOME/.claude/skills/gd-ai-coding}"
      : "${state_home:=$HOME/.claude/skills/gd-ai-coding/state}"
      : "${config_home:=$HOME/.claude/skills/dashboard}"
      ;;
    codex)
      : "${skill_home:=$HOME/.codex/skills/gd-ai-coding}"
      : "${state_home:=$HOME/.codex/skills/gd-ai-coding/state}"
      : "${config_home:=$HOME/.codex/skills/dashboard}"
      ;;
  esac

  DAC_RUNTIME="$runtime"
  DAC_SKILL_HOME="$skill_home"
  DAC_STATE_HOME="$state_home"
  DAC_CONFIG_HOME="$config_home"
  export DAC_RUNTIME DAC_SKILL_HOME DAC_STATE_HOME DAC_CONFIG_HOME
}
