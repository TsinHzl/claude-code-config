#!/usr/bin/env bash
# sync-skipped-from-plan.sh — 把 feature-plan.json 里 status=skipped 的 id 写入 state.skipped_features
#
# 只改 skipped_features，不走 state-update.sh <id> skipped（那会记 feature-loop 终态、
# 并在「全部 skipped」时抢跑 feature-done，挡住随后的 --phase feature-planned）。
set -euo pipefail

STATE_FILE=".dac/state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "[DAC-STATE-003] ❌ .dac/state.json 不存在" >&2
  exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPTS_DIR/lib.sh"
# shellcheck source=../paths.sh
source "$SCRIPTS_DIR/paths.sh"

REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE")
if [[ -z "$REQ_NAME" ]]; then
  echo "[DAC-STATE-003] ❌ state.json 中缺少 req_name 字段" >&2
  exit 1
fi

PLAN_JSON="$(get_change_dir "$REQ_NAME")/feature-plan.json"
if [[ ! -f "$PLAN_JSON" ]]; then
  echo "[DAC-PLAN-007] ❌ feature-plan.json 不存在：$PLAN_JSON" >&2
  exit 1
fi

IDS_JSON=$(jq -c '
  (if type == "array" then . else .features end)
  | [ .[] | select(.status == "skipped") | .id ]
' "$PLAN_JSON")

if [[ "$IDS_JSON" == "[]" ]]; then
  echo "ℹ️  无 skipped feature，无需同步"
  exit 0
fi

atomic_jq --compact '
  .skipped_features = ((.skipped_features // []) + $ids | unique)
' "$STATE_FILE" --argjson ids "$IDS_JSON"

echo "✅ 已同步 skipped_features：$IDS_JSON"
