#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scaffold-feature.sh — Platform dispatcher for scaffold generation
# ─────────────────────────────────────────────────────────────────────────────
#
# 调用时机：feature/feature-harness.sh pre-codegen 阶段，codegen sub-agent 启动前
# 作用：根据 platform 参数路由到对应 platform/{name}/scripts/scaffold.sh
#
# 输入：
#   $1 — feat_id（必填）
#   PLATFORM 环境变量 — 目标平台（默认 flutter）
#
# 退出码：0=成功生成, 1=错误, 2=无 new_files/不支持
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

FEAT_ID="${1:?Usage: scaffold-feature.sh <feat_id>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../platform.sh"

PLATFORM="${PLATFORM:-flutter}"

# Check platform config for scaffold support
PLATFORM_CONFIG=$(load_platform_config "$PLATFORM" 2>/dev/null) || {
  echo "ERROR: platform '$PLATFORM' config not found" >&2
  exit 1
}

SCAFFOLD_ENABLED=$(echo "$PLATFORM_CONFIG" | jq -r '.scaffold_enabled // false')
if [[ "$SCAFFOLD_ENABLED" != "true" ]]; then
  echo "⏭ 骨架生成已跳过（platform '${PLATFORM}' 不支持）"
  exit 0
fi

PLATFORM_SCAFFOLD=$(resolve_platform_script "$PLATFORM" "scaffold.sh")
if [[ -z "$PLATFORM_SCAFFOLD" ]]; then
  echo "⏭ 骨架生成已跳过（platform '${PLATFORM}' 无 scaffold.sh）"
  exit 0
fi

exec bash "$PLATFORM_SCAFFOLD" "$FEAT_ID"