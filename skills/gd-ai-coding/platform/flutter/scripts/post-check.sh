#!/usr/bin/env bash
# platform/flutter/scripts/post-check.sh
# Flutter 平台 post-codegen 检查：dart format + dart analyze + naming + import order
#
# 输入：
#   $1 — feat_id
#   环境变量 CHANGED_FILES_JSON — JSON 数组格式的文件列表（如 ["lib/a.dart","lib/b.dart"]）
#   或通过参数传入文件路径列表（从 $2 开始）
#
# Exit codes:
#   0 — 全部通过
#   1 — 硬性失败（dart analyze error / 命名违规）
#   3 — 仅有可自动修复的问题（format），已原地修复

set -euo pipefail

FEAT_ID="${1:-}"
shift || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARD_FAIL=false
AUTO_FIXED=false

# Collect dart files from args or CHANGED_FILES_JSON
DART_FILES=()
if [[ $# -gt 0 ]]; then
  for f in "$@"; do
    [[ -f "$f" && "$f" == *.dart ]] && DART_FILES+=("$f")
  done
elif [[ -n "${CHANGED_FILES_JSON:-}" ]]; then
  while IFS= read -r f; do
    [[ -f "$f" && "$f" == *.dart ]] && DART_FILES+=("$f")
  done < <(echo "$CHANGED_FILES_JSON" | jq -r '.[]')
fi

if [[ ${#DART_FILES[@]} -eq 0 ]]; then
  echo "  ✓ 无 .dart 文件需检查"
  exit 0
fi

# 1. dart format [可自动修复]
echo "  [1/3] dart format 检查..."
if command -v dart &>/dev/null; then
  if ! dart format --output=none --set-exit-if-changed "${DART_FILES[@]}" 2>/dev/null; then
    echo "  ⟳ dart format 发现格式问题，自动修复中..."
    dart format "${DART_FILES[@]}" >/dev/null 2>&1
    AUTO_FIXED=true
    echo "  ✓ dart format 已自动修复"
  else
    echo "  ✓ dart format 通过"
  fi
else
  echo "  ⚠️  dart 命令不可用，跳过 format 检查"
fi

# 2. dart analyze [硬性]
echo "  [2/3] dart analyze..."
if command -v dart &>/dev/null; then
  ANALYZE_EXIT=0
  ANALYZE_OUTPUT=$(dart analyze "${DART_FILES[@]}" 2>&1) || ANALYZE_EXIT=$?
  if [[ $ANALYZE_EXIT -ne 0 ]]; then
    ERROR_LINES=$(echo "$ANALYZE_OUTPUT" | grep -iE 'error' | head -10)
    if [[ -n "$ERROR_LINES" ]]; then
      echo "[DAC-GEN-006] ❌ dart analyze 发现 error："
      echo "$ERROR_LINES"
      HARD_FAIL=true
    else
      echo "  ✓ dart analyze 无 error（有 warning/info）"
    fi
  else
    echo "  ✓ dart analyze 通过"
  fi
else
  echo "  ⚠️  dart 命令不可用，跳过 analyze 检查"
fi

# 3. naming-check + import-order-check [硬性 / 警告级]
echo "  [3/3] 命名规范 + import 顺序检查..."
NAMING_SCRIPT="$SCRIPT_DIR/naming-check.sh"
IMPORT_SCRIPT="$SCRIPT_DIR/import-order-check.sh"

if [[ -x "$NAMING_SCRIPT" ]]; then
  if ! bash "$NAMING_SCRIPT" "${DART_FILES[@]}"; then
    HARD_FAIL=true
  fi
fi

if [[ -x "$IMPORT_SCRIPT" ]]; then
  if ! bash "$IMPORT_SCRIPT" "${DART_FILES[@]}"; then
    echo "  ⚠️  import 顺序不规范（非阻断，记录供后续修复）"
  fi
fi

# 结果判定
if [[ "$HARD_FAIL" == "true" ]]; then
  echo "❌ Flutter post-check 未通过（硬性失败）"
  exit 1
fi

if [[ "$AUTO_FIXED" == "true" ]]; then
  echo "✅ Flutter post-check 通过（已自动修复 format 问题）"
  exit 3
fi

echo "✅ Flutter post-check 通过"