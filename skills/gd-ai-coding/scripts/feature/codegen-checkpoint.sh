#!/usr/bin/env bash
# codegen-checkpoint.sh — 写入 .codegen_checkpoint（codegen 回滚/结算锚点）
# 由 feature-harness.sh pre-codegen 在门禁通过后 source 调用。
# 已存在则跳过：重跑 pre-codegen 不能把基准漂到 codegen 之后的 HEAD。
# 任何失败都 return 0，不阻断主流程。

write_codegen_checkpoint() {
  local feat_dir="${1:-}"
  local checkpoint="${feat_dir%/}/.codegen_checkpoint"
  [[ -n "$feat_dir" ]] || return 0
  [[ -f "$checkpoint" ]] && return 0
  command -v git >/dev/null 2>&1 || return 0
  local base
  base=$(git rev-parse HEAD 2>/dev/null) || return 0
  [[ -n "$base" ]] || return 0
  mkdir -p "$feat_dir" 2>/dev/null || return 0
  printf '%s\n' "{\"base_commit\":\"$base\",\"started_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
    > "$checkpoint" 2>/dev/null || true
  return 0
}
