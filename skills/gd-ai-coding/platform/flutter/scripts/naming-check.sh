#!/usr/bin/env bash
# naming-check.sh [file_path...]
# 检查 Dart 文件的命名规范：
#   文件名：snake_case.dart
#   类名：PascalCase
# 支持批量输入：传入多个文件路径一次性检查
# 由 post-codegen-check.sh 内部调用

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法: naming-check.sh <file_path> [file_path...]" >&2
  exit 1
fi

PASS=true

for FILE in "$@"; do
  # 1. 文件名 snake_case 检查（允许字母、数字、下划线，不允许大写）
  BASENAME=$(basename "$FILE" .dart)
  if echo "$BASENAME" | grep -qE '[A-Z]'; then
    echo "❌ 文件名不符合 snake_case：$(basename "$FILE")"
    echo "   期望格式：my_feature_page.dart"
    PASS=false
  fi

  # 2. 类名 PascalCase 检查（每个 class/mixin/enum/extension 声明）
  # 私有类（以 _ 开头）是合法的 Flutter 模式，跳过检查
  while IFS= read -r line; do
    NAME=$(echo "$line" | grep -oE '(class|mixin|enum|extension) [A-Za-z_][A-Za-z0-9_]*' | awk '{print $2}')
    [[ -z "$NAME" ]] && continue
    [[ "$NAME" == _* ]] && continue  # 私有类跳过
    if ! echo "$NAME" | grep -qE '^[A-Z][a-zA-Z0-9]*$'; then
      echo "⚠️  类名不符合 PascalCase：${NAME}（在 ${FILE}）"
      PASS=false
    fi
  done < <(grep -E '^(class|mixin|enum|extension) ' "$FILE" 2>/dev/null || true)
done

if [[ "$PASS" == "false" ]]; then
  exit 1
fi
