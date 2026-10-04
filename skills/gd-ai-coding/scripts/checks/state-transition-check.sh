#!/usr/bin/env bash
# state-transition-check.sh [feat_id] [--up-to=<step>]
# 按步骤顺序验证产物完整性，遇到 --up-to 指定的步骤后停止
# step 取值：ui-spec | codegen | code-review

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法: state-transition-check.sh <feat_id> [--up-to=<step>]" >&2
  exit 1
fi

FEAT_ID=$1
RAW_ARG="${2:-}"
if [[ -n "$RAW_ARG" ]]; then
  UP_TO="${RAW_ARG#--up-to=}"
else
  UP_TO=""
fi

STATE_FILE=".dac/state.json"
REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE" 2>/dev/null)
if [[ -z "$REQ_NAME" ]]; then
  echo "❌ state-transition-check：state.json 中缺少 req_name" >&2
  exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/../paths.sh"
FEAT_DIR="$(get_feat_dir "$REQ_NAME" "$FEAT_ID")"

# 校验 --up-to 参数合法性（空值表示全量检查）
VALID_STEPS=(ui-spec codegen code-review)
if [[ -n "$UP_TO" ]] && ! printf '%s\n' "${VALID_STEPS[@]}" | grep -qx "$UP_TO"; then
  echo "❌ 无效的 --up-to 参数：$UP_TO"
  echo "   有效取值：ui-spec | codegen | code-review（不传则全量检查）"
  exit 1
fi

check_artifact() {
  local desc=$1; local file=$2
  if [[ ! -s "$file" ]]; then
    return 1
  fi
  return 0
}

# ── 全量检查时先诊断当前进度，防止提前调用 ──────────────
if [[ -z "$UP_TO" ]]; then
  CURRENT_STEP=$(jq -r --arg id "$FEAT_ID" '
    (if type == "array" then . else .features end)
    | map(select(.id == $id)) | .[0].current_step // "unknown"
  ' "$(get_change_dir "$REQ_NAME")/feature-plan.json" 2>/dev/null) || CURRENT_STEP="unknown"

  if [[ "$CURRENT_STEP" != "done" && "$CURRENT_STEP" != "code-review" ]]; then
    # 检查 code-review 是否真的执行过
    if [[ ! -f "$FEAT_DIR/cr-report.md" ]]; then
      echo "❌ 终态门禁被提前调用"
      echo "   当前步骤：${CURRENT_STEP}"
      echo "   code-review 尚未执行（cr-report.md 不存在）"
      echo ""
      echo "   请按流程顺序执行：codegen → code-review → 终态门禁"
      echo "   如需单步验证，请使用：state-transition-check.sh $FEAT_ID --up-to=codegen"
      exit 1
    fi
  fi
fi

# ── 按流程顺序逐步检查 ──

ERRORS=()

# 1. code-scope.md（步骤 2 产物，始终必须存在）
if ! check_artifact "code-scope" "$FEAT_DIR/code-scope.md"; then
  ERRORS+=("code-scope.md 不存在或为空：$FEAT_DIR/code-scope.md")
fi

# 2. ui_dsl.json + ui_tree.txt（步骤 3 产物，用户决定是否提供；有 .design_skipped 标记时跳过）
if [[ ! -f "$FEAT_DIR/.design_skipped" ]] && [[ -f "$FEAT_DIR/ui_dsl.json" ]]; then
  echo "  ✓ ui_dsl.json + ui_tree.txt 存在"
elif [[ -f "$FEAT_DIR/.design_skipped" ]]; then
  echo "  ✓ 设计稿已标记跳过"
fi
[[ "$UP_TO" == "ui-spec" ]] && { [[ ${#ERRORS[@]} -eq 0 ]] && echo "✅ 验证通过（up-to: ui-spec）" && exit 0 || true; }

# 3. codegen 验证：code-scope.md 中列出的文件是否全部存在于工程
MISSING=0
while IFS= read -r filepath; do
  [[ -z "$filepath" ]] && continue
  if [[ ! -f "$filepath" ]]; then
    ERRORS+=("codegen 未生成：$filepath")
    MISSING=$((MISSING + 1))
  fi
done < <(grep -E '^\| lib/' "$FEAT_DIR/code-scope.md" 2>/dev/null | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 != "") print $2}')

if [[ "$UP_TO" == "codegen" ]]; then
  if [[ ${#ERRORS[@]} -eq 0 ]]; then
    echo "✅ 验证通过（up-to: codegen）"
    exit 0
  else
    echo "❌ 验证失败（up-to: codegen）："
    for e in "${ERRORS[@]}"; do echo "   - $e"; done
    exit 1
  fi
fi

# 4. code-review 验证：cr-report.md 存在
if ! check_artifact "code-review" "$FEAT_DIR/cr-report.md"; then
  ERRORS+=("code-review 未完成：$FEAT_DIR/cr-report.md 不存在")
fi

if [[ "$UP_TO" == "code-review" ]]; then
  if [[ ${#ERRORS[@]} -eq 0 ]]; then
    echo "✅ 验证通过（up-to: code-review）"
    exit 0
  else
    echo "❌ 验证失败（up-to: code-review）："
    for e in "${ERRORS[@]}"; do echo "   - $e"; done
    exit 1
  fi
fi

# 全量结果
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "❌ 终态门禁未通过（${#ERRORS[@]} 项失败）："
  for e in "${ERRORS[@]}"; do echo "   - $e"; done
  exit 1
fi

echo "✅ 终态门禁通过：所有步骤产物验证完整（code-scope + codegen + cr-report）"
