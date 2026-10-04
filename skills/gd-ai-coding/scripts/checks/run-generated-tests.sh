#!/usr/bin/env bash
# run-generated-tests.sh <feat_id>
# Layer 2.5 步骤 4.5.2：对 test-case-generator.md 产出的逻辑/数据类测试文件逐一执行
# `flutter test <path>`，汇总退出码。UI/交互类场景清单不在本脚本处理范围（由步骤 4.5.3
# 独立 sub-agent 推理判断）。
#
# exit code 语义：0=pass（全部通过或无适用测试文件），1=hard_fail（存在失败用例）

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法: run-generated-tests.sh <feat_id>" >&2
  exit 1
fi

FEAT_ID=$1
PLATFORM="${PLATFORM:-flutter}"

if [[ "$PLATFORM" != "flutter" ]]; then
  echo "⏭ 非 flutter 平台（${PLATFORM}），本脚本仅支持 flutter test，跳过"
  exit 0
fi

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/../paths.sh"

STATE_FILE=".dac/state.json"
REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE" 2>/dev/null)
if [[ -z "$REQ_NAME" ]]; then
  echo "[DAC-STATE-003] ❌ state.json 中缺少 req_name" >&2
  exit 1
fi

FEAT_DIR="$(get_feat_dir "$REQ_NAME" "$FEAT_ID")"
TEST_CASES_FILE="$FEAT_DIR/test-cases.md"

if [[ ! -f "$TEST_CASES_FILE" ]]; then
  echo "[DAC-GEN-013] ❌ ${TEST_CASES_FILE} 不存在，无法获取逻辑/数据类测试文件清单（feat: ${FEAT_ID}）" >&2
  exit 1
fi

# 提取「## 生成的逻辑/数据类测试文件」章节下反引号包裹的 .dart 测试文件路径
TEST_FILES=()
while IFS= read -r path; do
  [[ -n "$path" ]] && TEST_FILES+=("$path")
done < <(awk '
  /^## 生成的逻辑\/数据类测试文件/ { in_section=1; next }
  /^## / { in_section=0 }
  in_section { print }
' "$TEST_CASES_FILE" | grep -oE '`[^`]+\.dart`' | tr -d '`')

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
  echo "⏭ 无逻辑/数据类测试文件（feat: ${FEAT_ID}），跳过"
  exit 0
fi

echo "▶ 逻辑/数据类测试执行（feat: ${FEAT_ID}，共 ${#TEST_FILES[@]} 个文件）"

FAILED=()
for f in "${TEST_FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "[DAC-GEN-013] ❌ 测试文件不存在：$f" >&2
    FAILED+=("${f}｜文件不存在")
    continue
  fi
  echo "  ▶ flutter test $f"
  OUTPUT=$(flutter test "$f" 2>&1)
  CODE=$?
  echo "$OUTPUT" | sed 's/^/    /'
  if [[ $CODE -ne 0 ]]; then
    FAILED+=("${f}｜exit ${CODE}")
  fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo ""
  echo "[DAC-GEN-013] ❌ 存在失败用例（${#FAILED[@]}/${#TEST_FILES[@]}）：" >&2
  for item in "${FAILED[@]}"; do
    echo "   - $item" >&2
  done
  exit 1
fi

echo "✅ 全部 ${#TEST_FILES[@]} 个逻辑/数据类测试文件通过"
