#!/usr/bin/env bash
# import-order-check.sh [file_path...]
# 检查 Dart import 顺序：
#   1. dart: 内置库
#   2. package:flutter
#   3. package:第三方
#   4. 项目内部（相对路径 ../  ./）
# 支持批量输入：传入多个文件路径一次性检查
# 由 post-codegen-check.sh 内部调用

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法: import-order-check.sh <file_path> [file_path...]" >&2
  exit 1
fi

PASS=true

for FILE in "$@"; do
  # 提取各类 import 的首次出现行号（无则为 0）
  DART_LINE=$(grep -n "^import 'dart:" "$FILE" 2>/dev/null | head -1 | cut -d: -f1 || echo 0)
  FLUTTER_LINE=$(grep -n "^import 'package:flutter" "$FILE" 2>/dev/null | head -1 | cut -d: -f1 || echo 0)
  THIRD_LINE=$(grep -n "^import 'package:" "$FILE" 2>/dev/null | grep -v "^[0-9]*:import 'package:flutter" | head -1 | cut -d: -f1 || echo 0)
  RELATIVE_LINE=$(grep -n "^import '\.\." "$FILE" 2>/dev/null | head -1 | cut -d: -f1 || echo 0)
  RELATIVE_LINE2=$(grep -n "^import '\." "$FILE" 2>/dev/null | grep -v "^[0-9]*:import '\.\." | head -1 | cut -d: -f1 || echo 0)
  # 取相对路径最小行号
  LOCAL_LINE=0
  [[ "$RELATIVE_LINE" -gt 0 ]] && LOCAL_LINE=$RELATIVE_LINE
  [[ "$RELATIVE_LINE2" -gt 0 ]] && [[ "$LOCAL_LINE" -eq 0 || "$RELATIVE_LINE2" -lt "$LOCAL_LINE" ]] && LOCAL_LINE=$RELATIVE_LINE2

  # 规则 1：dart: 必须在 package: 之前
  if [[ "$DART_LINE" -gt 0 && "$FLUTTER_LINE" -gt 0 && "$FLUTTER_LINE" -lt "$DART_LINE" ]]; then
    echo "⚠️  import 顺序异常：package:flutter（行 ${FLUTTER_LINE}）在 dart:（行 ${DART_LINE}）之前 — $FILE"
    PASS=false
  fi
  if [[ "$DART_LINE" -gt 0 && "$THIRD_LINE" -gt 0 && "$THIRD_LINE" -lt "$DART_LINE" ]]; then
    echo "⚠️  import 顺序异常：第三方 package:（行 ${THIRD_LINE}）在 dart:（行 ${DART_LINE}）之前 — $FILE"
    PASS=false
  fi

  # 规则 2：package:flutter 必须在第三方 package: 之前
  if [[ "$FLUTTER_LINE" -gt 0 && "$THIRD_LINE" -gt 0 && "$THIRD_LINE" -lt "$FLUTTER_LINE" ]]; then
    echo "⚠️  import 顺序异常：第三方 package:（行 ${THIRD_LINE}）在 package:flutter（行 ${FLUTTER_LINE}）之前 — $FILE"
    PASS=false
  fi

  # 规则 3：项目内部相对路径必须在所有 package: 之后
  LAST_PKG=0
  [[ "$FLUTTER_LINE" -gt "$LAST_PKG" ]] && LAST_PKG=$FLUTTER_LINE
  [[ "$THIRD_LINE" -gt "$LAST_PKG" ]] && LAST_PKG=$THIRD_LINE
  if [[ "$LOCAL_LINE" -gt 0 && "$LAST_PKG" -gt 0 && "$LOCAL_LINE" -lt "$LAST_PKG" ]]; then
    echo "⚠️  import 顺序异常：相对路径 import（行 ${LOCAL_LINE}）在 package:（行 ${LAST_PKG}）之前 — $FILE"
    PASS=false
  fi
done

if [[ "$PASS" == "false" ]]; then
  exit 1
fi
