#!/usr/bin/env bash
# test-verify-loop-guard.sh <increment|reset|is_exceeded> <feat_id>
# Phase 3 测试用例验证（feature-loop 步骤 4.5）失败重试的独立计数器，与 Layer 2
# （post-codegen-check.sh 的 dart analyze/format 重试）计数完全隔离，避免混用
# 污染各自的 exit code 语义（design.md 决策3）。
#
# 计数持久化于 .dac/state.json 的 test_verify 字段（{"attempt_count", "feat_id"}），
# 写入统一经 state-update.sh，禁止本脚本直接 jq 改写 state.json。切换到不同 feat_id
# 时自动重置计数（串行处理模型下每次只有一个 feature 在跑该环节）。超限（≥3 次）后
# 调用 state-update.sh 将该 feature 状态置为 failed（复用现有失败语义，不新增状态值）。
#
# exit code 语义与本仓库其他 harness 脚本一致：0=pass, 2=retry_exceeded

set -euo pipefail

LIMIT=3
STATE_FILE=".dac/state.json"

if [[ $# -lt 2 ]]; then
  echo "用法: test-verify-loop-guard.sh <increment|reset|is_exceeded> <feat_id>" >&2
  exit 1
fi

ACTION=$1
FEAT_ID=$2

if [[ ! -f "$STATE_FILE" ]]; then
  echo "[DAC-STATE-003] ❌ .dac/state.json 不存在" >&2
  exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 读取当前计数：feat_id 与传入不一致时（切换到新 feature）视为 0
current_count() {
  jq -r --arg fid "$FEAT_ID" '
    if (.test_verify.feat_id // "") == $fid then (.test_verify.attempt_count // 0) else 0 end
  ' "$STATE_FILE"
}

write_count() {
  local n=$1
  bash "$SCRIPTS_DIR/state-update.sh" --set-json test_verify \
    "{\"attempt_count\": $n, \"feat_id\": \"$FEAT_ID\"}" >/dev/null
}

case "$ACTION" in
  increment)
    count=$(current_count)
    new_count=$((count + 1))
    write_count "$new_count"
    echo "$new_count"
    if [[ "$new_count" -ge "$LIMIT" ]]; then
      bash "$SCRIPTS_DIR/state-update.sh" "$FEAT_ID" failed \
        --audit "test-verify 重试超限（>${LIMIT}次）" >/dev/null
      exit 2
    fi
    exit 0
    ;;
  reset)
    write_count 0
    echo "0"
    exit 0
    ;;
  is_exceeded)
    count=$(current_count)
    if [[ "$count" -ge "$LIMIT" ]]; then
      echo "exceeded (count=$count, limit=$LIMIT)"
      exit 2
    fi
    echo "not exceeded (count=$count, limit=$LIMIT)"
    exit 0
    ;;
  *)
    echo "用法: test-verify-loop-guard.sh <increment|reset|is_exceeded> <feat_id>" >&2
    exit 1
    ;;
esac
