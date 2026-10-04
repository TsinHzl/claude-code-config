#!/usr/bin/env bash
# post-codegen-check.sh [feat_id]
# Layer 2 门禁：codegen 完成后运行
# 检查内容：新增文件全部存在、dart format、dart analyze、命名规范
#
# Exit codes:
#   0 — 全部通过
#   1 — 硬性失败（文件缺失 / dart analyze error / 命名违规），需 codegen 重试
#   2 — 重试次数超限，需人工介入
#   3 — 仅有可自动修复的问题（format / import 顺序），已原地修复，无需 codegen 重试

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法: post-codegen-check.sh <feat_id> [--check-retry-count]" >&2
  exit 1
fi

FEAT_ID=$1
CHECK_RETRY=false
[[ "${2:-}" == "--check-retry-count" ]] && CHECK_RETRY=true

STATE_FILE=".dac/state.json"
REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE" 2>/dev/null)
if [[ -z "$REQ_NAME" ]]; then
  echo "❌ post-codegen-check：state.json 中缺少 req_name" >&2
  exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/../paths.sh"
source "$SCRIPTS_DIR/../platform.sh"
FEAT_DIR="$(get_feat_dir "$REQ_NAME" "$FEAT_ID")"
HARD_FAIL=false
AUTO_FIXED=false

PLATFORM="${PLATFORM:-flutter}"
PLATFORM_SRC_ROOT=$(load_platform_config "$PLATFORM" 2>/dev/null | jq -r '.src_root // "lib/"')

# 重试次数硬限制检查（Harness 层保证不超过 3 次）
if [[ "$CHECK_RETRY" == "true" ]]; then
  PLAN_JSON="$(get_change_dir "$REQ_NAME")/feature-plan.json"
  if [[ -f "$PLAN_JSON" ]]; then
    RETRY_COUNT=$(jq -r --arg fid "$FEAT_ID" '
      (if type == "array" then . else .features end)
      | map(select(.id == $fid)) | .[0].error_log // []
      | map(select(.step == "step:validating" and .resolved != true)) | length
    ' "$PLAN_JSON" 2>/dev/null || echo "0")
    if [[ "$RETRY_COUNT" -ge 3 ]]; then
      echo "[DAC-GEN-009] ❌ Layer 2 重试次数已达上限（${RETRY_COUNT}/3），需人工介入"
      echo "   功能 $FEAT_ID 的 codegen 验证已失败 $RETRY_COUNT 次，Harness 层硬性阻断"
      exit 2
    fi
  fi
fi

echo "▶ Layer 2 检查（feat: ${FEAT_ID}）"

# 收集本次涉及的所有文件路径
CHANGED_FILES=()
if [[ -f "$FEAT_DIR/code-scope.md" ]]; then
  while IFS= read -r filepath; do
    [[ -z "$filepath" ]] && continue
    CHANGED_FILES+=("$filepath")
  done < <(grep -E "^\| ${PLATFORM_SRC_ROOT}" "$FEAT_DIR/code-scope.md" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 != "") print $2}')
fi

# 1. code-scope.md 中列出的所有新增文件是否全部已生成 [硬性]
echo "  [1/5] 检查新增文件完整性..."
if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
  echo "  ⚠️  未从 code-scope.md 中解析到任何文件路径（src_root=${PLATFORM_SRC_ROOT}），请检查 code-scope.md 格式或 PLATFORM 配置"
fi
MISSING=""
for filepath in "${CHANGED_FILES[@]}"; do
  if [[ ! -f "$filepath" ]]; then
    MISSING="${MISSING}\n   - $filepath"
  fi
done
if [[ -n "$MISSING" ]]; then
  echo -e "[DAC-GEN-008] ❌ 以下文件未生成：$MISSING"
  HARD_FAIL=true
else
  echo "  ✓ 文件全部存在"
fi

# 2. 检查 modified_files 是否实际被修改（对比 codegen checkpoint 基准）[非阻断，仅警告]
echo "  [2/5] 检查 modified_files 是否实际修改..."
if [[ -f "$FEAT_DIR/code-scope.md" ]]; then
  MODIFIED_FILES=()
  IN_MODIFIED_SECTION=false
  while IFS= read -r line; do
    if echo "$line" | grep -qiE '^###\s*修改文件|^###\s*modified'; then
      IN_MODIFIED_SECTION=true
      continue
    fi
    if [[ "$IN_MODIFIED_SECTION" == "true" ]] && echo "$line" | grep -qE '^#{1,4}\s'; then
      break
    fi
    if [[ "$IN_MODIFIED_SECTION" == "true" ]] && echo "$line" | grep -qE "^\| ${PLATFORM_SRC_ROOT}"; then
      filepath=$(echo "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')
      [[ -n "$filepath" ]] && MODIFIED_FILES+=("$filepath")
    fi
  done < "$FEAT_DIR/code-scope.md"

  if [[ ${#MODIFIED_FILES[@]} -gt 0 ]]; then
    CHECKPOINT_FILE="$FEAT_DIR/.codegen_checkpoint"
    CODEGEN_BASE=""
    if [[ -f "$CHECKPOINT_FILE" ]]; then
      CODEGEN_BASE=$(jq -r '.base_commit // empty' "$CHECKPOINT_FILE" 2>/dev/null)
    fi

    if [[ -n "$CODEGEN_BASE" ]]; then
      ALL_CHANGED=$(git diff --name-only "$CODEGEN_BASE" 2>/dev/null || true)
    else
      GIT_CHANGED=$(git diff --name-only 2>/dev/null || true)
      GIT_STAGED=$(git diff --cached --name-only 2>/dev/null || true)
      ALL_CHANGED=$(printf '%s\n%s' "$GIT_CHANGED" "$GIT_STAGED" | sort -u)
    fi

    UNMODIFIED=""
    for mf in "${MODIFIED_FILES[@]}"; do
      if ! echo "$ALL_CHANGED" | grep -qxF "$mf"; then
        UNMODIFIED="${UNMODIFIED}\n   - $mf"
      fi
    done
    if [[ -n "$UNMODIFIED" ]]; then
      echo -e "[DAC-GEN-004] ⚠️  以下 modified_files 未被实际修改（非阻断）：$UNMODIFIED"
      echo "   这些文件相对 codegen 基准无变更，可能 codegen 判定无需修改"
    else
      echo "  ✓ 所有 modified_files 均已实际修改"
    fi
  else
    echo "  ✓ 无 modified_files 需验证"
  fi
else
  echo "  ⚠️  code-scope.md 不存在，跳过 modified_files 检查"
fi

# 3-5. Platform post-check dispatch
echo "  [3/5] Platform post-check..."
PLATFORM_SCRIPT=$(resolve_platform_script "$PLATFORM" "post-check.sh")

if [[ -n "$PLATFORM_SCRIPT" ]]; then
  EXISTING_FILES=()
  for filepath in "${CHANGED_FILES[@]}"; do
    [[ -f "$filepath" ]] && EXISTING_FILES+=("$filepath")
  done

  if [[ ${#EXISTING_FILES[@]} -gt 0 ]]; then
    PLATFORM_EXIT=0
    bash "$PLATFORM_SCRIPT" "$FEAT_ID" "${EXISTING_FILES[@]}" || PLATFORM_EXIT=$?
    case $PLATFORM_EXIT in
      0) ;;
      1) HARD_FAIL=true ;;
      3) AUTO_FIXED=true ;;
      *) echo "  ⚠️ platform post-check 返回未知退出码 $PLATFORM_EXIT，视为硬性失败"; HARD_FAIL=true ;;
    esac
  else
    echo "  ✓ 无文件需检查"
  fi
else
  echo "  ⚠️ platform '${PLATFORM}' 无 post-check 实现，跳过"
fi

# 结果判定
if [[ "$HARD_FAIL" == "true" ]]; then
  echo "❌ Layer 2 未通过（硬性失败），需 codegen 重试"
  exit 1
fi

if [[ "$AUTO_FIXED" == "true" ]]; then
  echo "✅ Layer 2 通过（已自动修复 format 问题，无需 codegen 重试）"
  exit 3
fi

echo "✅ Layer 2 通过"
