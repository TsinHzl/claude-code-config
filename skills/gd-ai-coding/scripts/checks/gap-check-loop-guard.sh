#!/usr/bin/env bash
# gap-check-loop-guard.sh <increment|reset|is_exceeded>
# 需求查漏补缺（feature-plan 步骤 2.3.5）轮次计数器，持久化到 .dac/state.json 的
# gap_check.attempt_count 字段，跨会话续跑不丢失。写入统一经 state-update.sh，
# 禁止本脚本直接 jq 改写 state.json（遵循 CLAUDE.md "状态变更必须通过
# scripts/state-update.sh" 的既有硬约束）。
#
# exit code 语义与本仓库其他 harness 脚本一致：0=pass, 2=retry_exceeded

set -euo pipefail

LIMIT=5
STATE_FILE=".dac/state.json"

if [[ $# -lt 1 ]]; then
  echo "用法: gap-check-loop-guard.sh <increment|reset|is_exceeded>" >&2
  exit 1
fi

ACTION=$1

if [[ ! -f "$STATE_FILE" ]]; then
  echo "[DAC-STATE-003] ❌ .dac/state.json 不存在" >&2
  exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

current_count() {
  jq -r '.gap_check.attempt_count // 0' "$STATE_FILE"
}

case "$ACTION" in
  increment)
    count=$(current_count)
    new_count=$((count + 1))
    bash "$SCRIPTS_DIR/state-update.sh" --set-json gap_check "{\"attempt_count\": $new_count}" >/dev/null
    echo "$new_count"
    if [[ "$new_count" -gt "$LIMIT" ]]; then
      exit 2
    fi
    exit 0
    ;;
  reset)
    bash "$SCRIPTS_DIR/state-update.sh" --set-json gap_check '{"attempt_count": 0}' >/dev/null
    echo "0"
    exit 0
    ;;
  is_exceeded)
    count=$(current_count)
    if [[ "$count" -gt "$LIMIT" ]]; then
      echo "exceeded (count=$count, limit=$LIMIT)"
      exit 2
    fi
    echo "not exceeded (count=$count, limit=$LIMIT)"
    exit 0
    ;;
  *)
    echo "用法: gap-check-loop-guard.sh <increment|reset|is_exceeded>" >&2
    exit 1
    ;;
esac
