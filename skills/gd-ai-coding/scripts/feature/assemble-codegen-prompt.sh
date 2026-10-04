#!/usr/bin/env bash
# assemble-codegen-prompt.sh — Assemble codegen sub-agent prompt with stable prefix for API cache.
# Usage: assemble-codegen-prompt.sh <feat_id> [--retry]
#   --retry: Trim ZONE C for retry (reads .retry_context.json for error info)
# Output: Complete prompt to stdout. Redirect to a file in the target repo, e.g.
#   mkdir -p .dac/tmp && …/assemble-codegen-prompt.sh "$FEAT_ID" > ".dac/tmp/codegen-prompt-${FEAT_ID}.txt"
# Do NOT capture via CODEGEN_PROMPT=$(...) in the orchestrator session — the blob
# belongs in the codegen sub-agent, not the main-session tool_result.
# Exit codes: 0=success, 1=missing prerequisites
set -euo pipefail

FEAT_ID="${1:?Usage: assemble-codegen-prompt.sh <feat_id> [--retry]}"
RETRY_MODE=false
[[ "${2:-}" == "--retry" ]] && RETRY_MODE=true

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/runtime.sh"
dac_resolve_runtime || { echo "ERROR: 无法解析 DAC 运行时" >&2; exit 1; }
source "$SCRIPT_DIR/paths.sh"
source "$SCRIPT_DIR/platform.sh"
source "$(dirname "$0")/assemble-common.sh"

CHANGE_DIR="$(get_change_dir)"
FEAT_DIR="$(get_feat_dir "" "$FEAT_ID")"
PLAN_FILE="$CHANGE_DIR/feature-plan.json"
RULES_DIR="$DAC_SKILL_HOME/rules"
KNOWLEDGE_DIR=".dac/knowledge"

PLATFORM="${PLATFORM:-flutter}"
PLATFORM_RULES_DIR=$(resolve_platform_rules_dir "$PLATFORM")

SKIP_SCAFFOLD=$(jq -r '.flow_profile.skip_scaffold // false' .dac/state.json 2>/dev/null)

# Validate prerequisites
if [[ ! -f "$PLAN_FILE" ]]; then
  echo "ERROR: $PLAN_FILE not found" >&2
  exit 1
fi
SKIP_FEATURE_PLAN=$(jq -r '.flow_profile.skip_feature_plan // false' .dac/state.json 2>/dev/null)
if [[ ! -f "$FEAT_DIR/code-scope.md" && "$SKIP_FEATURE_PLAN" != "true" ]]; then
  echo "ERROR: $FEAT_DIR/code-scope.md not found" >&2
  exit 1
fi

# Resolve feature type
FEAT_TYPE=$(jq -r --arg id "$FEAT_ID" \
  '(if type == "array" then . else .features end) | map(select(.id == $id)) | .[0].type // "page"' \
  "$PLAN_FILE")

# Derive feature directory path for batch dart format (need at least 3 segments like lib/features/xxx/file.dart)
_raw_first_file=$(jq -r --arg id "$FEAT_ID" \
  '(if type == "array" then . else .features end) | map(select(.id == $id)) | .[0].proposal_scope.new_files[0] // ""' \
  "$PLAN_FILE")
_segment_count=$(echo "$_raw_first_file" | tr '/' '\n' | wc -l | tr -d ' ')
if [[ $_segment_count -ge 3 ]]; then
  FEATURE_DIR_PATH=$(echo "$_raw_first_file" | sed 's|/[^/]*$||' | sed 's|/[^/]*$||')
else
  FEATURE_DIR_PATH=$(echo "$_raw_first_file" | sed 's|/[^/]*$||')
fi
[[ -z "$FEATURE_DIR_PATH" || "$FEATURE_DIR_PATH" == "." ]] && FEATURE_DIR_PATH="${PLATFORM_SRC_ROOT%/}"

# Retry mode: load context and determine trimming strategy
NEEDS_FULL_CONTEXT=false
RETRY_CONTEXT_FILE="$FEAT_DIR/.retry_context.json"
if [[ "$RETRY_MODE" == "true" ]]; then
  if [[ ! -f "$RETRY_CONTEXT_FILE" ]]; then
    echo "ERROR: --retry requires $RETRY_CONTEXT_FILE (run build-retry-context.sh first)" >&2
    exit 1
  fi
  NEEDS_FULL_CONTEXT=$(jq -r '.needs_full_context // false' "$RETRY_CONTEXT_FILE")
fi

# ═══════════════════════════════════════════════════════════════════════════════
# ZONE A — Static rules (stable prefix → API cache hit)
# ═══════════════════════════════════════════════════════════════════════════════

_PLAT_CFG=$(load_platform_config "$PLATFORM" 2>/dev/null || echo '{}')
PLATFORM_LANGUAGE=$(echo "$_PLAT_CFG" | jq -r '.language // "dart"')
FORMAT_CMD=$(echo "$_PLAT_CFG" | jq -r '.format_cmd // "dart format"')
PLATFORM_SRC_ROOT=$(echo "$_PLAT_CFG" | jq -r '.src_root // "lib/"')
PLATFORM_FILE_EXT=$(echo "$_PLAT_CFG" | jq -r '.file_ext[0] // ".dart"')

cat <<HEADER
你是 ${PLATFORM} (${PLATFORM_LANGUAGE}) 代码生成器。严格遵循以下编码规范生成代码，不得偏离。

## 输出行为约束（最高优先级）
- 禁止输出解释性文本，直接执行工具调用
- 文件之间不插入分析或过渡语句
- 最终摘要：单行 \`✓ {N} files done\`

# ═══════════════════════════════════════════════════════
# ZONE A — 编码规范（固定）
# ═══════════════════════════════════════════════════════

## 架构规范

HEADER

# Load platform-specific rules (fallback to global RULES_DIR for backward compatibility)
emit_rule_file() {
  local name="$1"
  if [[ -f "$PLATFORM_RULES_DIR/$name" ]]; then
    cat "$PLATFORM_RULES_DIR/$name"
  elif [[ -f "$RULES_DIR/$name" ]]; then
    cat "$RULES_DIR/$name"
  fi
}

# Dynamically load all platform rules (architecture first, then others by name)
RULES_LOADED=false
if [[ -d "$PLATFORM_RULES_DIR" ]]; then
  for rule_file in "$PLATFORM_RULES_DIR"/*-architecture.md; do
    [[ -f "$rule_file" ]] && { cat "$rule_file"; RULES_LOADED=true; }
  done
  printf '\n## 代码风格规范\n\n'
  for rule_file in "$PLATFORM_RULES_DIR"/*-style.md; do
    [[ -f "$rule_file" ]] && cat "$rule_file"
  done
  if [[ "$FEAT_TYPE" == "page" || "$FEAT_TYPE" == "component" ]]; then
    for rule_file in "$PLATFORM_RULES_DIR"/*-performance.md; do
      [[ -f "$rule_file" ]] && { printf '\n## 性能规范\n\n'; cat "$rule_file"; }
    done
    for rule_file in "$PLATFORM_RULES_DIR"/*-widgets.md; do
      [[ -f "$rule_file" ]] && { printf '\n## Widget/组件规范\n\n'; cat "$rule_file"; }
    done
  fi
fi
if [[ "$RULES_LOADED" != "true" ]]; then
  emit_rule_file "flutter-architecture.md"
  printf '\n## 代码风格规范\n\n'
  emit_rule_file "flutter-style.md"
  if [[ "$FEAT_TYPE" == "page" || "$FEAT_TYPE" == "component" ]]; then
    printf '\n## 性能规范\n\n'
    emit_rule_file "flutter-performance.md"
    printf '\n## Widget 规范\n\n'
    emit_rule_file "flutter-widgets.md"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# ZONE B — Project constraints (stable within one loop iteration)
# ═══════════════════════════════════════════════════════════════════════════════

cat <<'DIVIDER'

# ═══════════════════════════════════════════════════════
# ZONE B — 项目约束（同一轮次内稳定）
# ═══════════════════════════════════════════════════════

## 已知约束（CR 积累，优先级最高）

DIVIDER

emit_zone_b_constraints "$KNOWLEDGE_DIR"

printf '\n## 已知错误模式（避免重犯）\n\n'

emit_zone_b_error_patterns "$KNOWLEDGE_DIR"

printf '\n## 组件依赖参考（import 路径 + 用法，禁止自行搜索项目外目录）\n\n'

emit_zone_b_dep_catalog "$KNOWLEDGE_DIR"

# ═══════════════════════════════════════════════════════════════════════════════
# ZONE C — Feature-specific inputs (changes every feature)
# ═══════════════════════════════════════════════════════════════════════════════

cat <<'DIVIDER'

# ═══════════════════════════════════════════════════════
# ZONE C — 当前功能输入
# ═══════════════════════════════════════════════════════

## 代码改动范围

DIVIDER

cat "$FEAT_DIR/code-scope.md"

# Graphify 知识图谱：注入与当前 feature 相关的现有组件信息（帮助定位已有代码）
if [[ -f "$FEAT_DIR/graphify-context.md" ]]; then
  printf '\n## 现有组件参考（项目知识图谱）\n\n'
  cat "$FEAT_DIR/graphify-context.md"
fi

# Channel 规范：仅当本次改动涉及 UniNative/UniFlutter 通信时注入（属于 feature-specific，放 ZONE C）
if [[ -f "$FEAT_DIR/code-scope.md" ]] && grep -qE '(UniNative|UniFlutter|@UniModel|driver_uni_business/interface/|driver_uni_foundation/interface/)' "$FEAT_DIR/code-scope.md"; then
  printf '\n## Channel 通信规范\n\n'
  emit_rule_file "flutter-channel.md"
  printf '\n'
fi

# In retry mode with non-full-context errors, skip spec/design/DSL to save tokens
if [[ "$RETRY_MODE" == "true" && "$NEEDS_FULL_CONTEXT" == "false" ]]; then
  printf '\n## 需求规格\n\n（重试模式：省略，参见首次生成）\n'
  printf '\n## 技术设计决策\n\n（重试模式：省略）\n'
else
  printf '\n## 需求规格（当前功能相关章节）\n\n'

  if [[ -f "$FEAT_DIR/spec-slice.md" ]]; then
    cat "$FEAT_DIR/spec-slice.md"
  else
    echo "（无关联需求章节）"
  fi

  printf '\n## 技术设计决策\n\n'

  if [[ -f "$FEAT_DIR/design-slice.md" ]]; then
    cat "$FEAT_DIR/design-slice.md"
  elif [[ -f "$CHANGE_DIR/design.md" ]]; then
    cat "$CHANGE_DIR/design.md"
  else
    echo "（无技术设计文档）"
  fi

  # Design assets (only for page/component with existing files)
  if [[ "$FEAT_TYPE" == "page" || "$FEAT_TYPE" == "component" ]]; then
    if [[ -f "$FEAT_DIR/ui_tree.txt" ]]; then
      printf '\n## 设计稿\n\n### UI 层级结构\n\n'
      cat "$FEAT_DIR/ui_tree.txt"

      if [[ -f "$FEAT_DIR/ui_dsl.json" ]]; then
        printf '\n### UI 详细规格\n\n'
        cat "$FEAT_DIR/ui_dsl.json"
      fi
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Execution instructions
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$RETRY_MODE" == "true" ]]; then
  # Retry mode: Edit-based fix (minimize output tokens)
  cat <<INSTRUCTIONS

# ═══════════════════════════════════════════════════════
# 执行指令（重试修复模式）
# ═══════════════════════════════════════════════════════

本次为重试修复。使用 Edit 修复下方列出的具体错误，不要重写整个文件。

1. Read 出错文件 → 定位错误位置 → Edit 修复具体行
2. 全部修复后：\`dart format $FEATURE_DIR_PATH/\`
3. 输出 \`✓ fixed {N} files\`

约束优先级：constraints.md > 架构规范 > 默认

## 项目边界（硬性）
- 禁止 grep/find 项目根目录以外的任何路径（父目录、sibling 仓库、.pub-cache）
- import 路径和组件用法通过 grep 项目内已有 .dart 文件推断
INSTRUCTIONS

  # Append error context from .retry_context.json
  printf '\n# ═══════════════════════════════════════════════════════\n'
  printf '# 错误上下文\n'
  printf '# ═══════════════════════════════════════════════════════\n\n'

  printf '## 错误信息\n\n```\n'
  jq -r '.error_message' "$RETRY_CONTEXT_FILE"
  printf '```\n\n'

  printf '## 需要重新生成的文件\n\n'
  jq -r '.error_files[]' "$RETRY_CONTEXT_FILE" | while IFS= read -r f; do
    echo "- \`$f\`"
  done

  # Embed related passing files as reference (imports, types)
  ERROR_FILES_LIST=$(jq -r '.error_files[]' "$RETRY_CONTEXT_FILE")
  ALL_FILES=$(grep -oE "${PLATFORM_SRC_ROOT}[^ |]+\\${PLATFORM_FILE_EXT}" "$FEAT_DIR/code-scope.md" 2>/dev/null | sort -u || true)

  REF_FILES=""
  if [[ -n "$ALL_FILES" && -n "$ERROR_FILES_LIST" ]]; then
    REF_FILES=$(comm -23 <(echo "$ALL_FILES") <(echo "$ERROR_FILES_LIST" | sort) | head -5)
  fi

  if [[ -n "$REF_FILES" ]]; then
    printf '\n## 参考文件（已通过验证，供 import/类型参考，不要修改）\n\n'
    while IFS= read -r filepath; do
      if [[ -f "$filepath" ]]; then
        printf '### `%s`\n\n```dart\n' "$filepath"
        cat "$filepath"
        printf '\n```\n\n'
      fi
    done <<< "$REF_FILES"
  fi

elif [[ "$FEAT_TYPE" == "page" || "$FEAT_TYPE" == "component" ]]; then
  if [[ "$SKIP_SCAFFOLD" == "true" ]]; then
    cat <<INSTRUCTIONS

# ═══════════════════════════════════════════════════════
# 执行指令
# ═══════════════════════════════════════════════════════

无骨架文件（skip_scaffold=true）。你的任务：

1. **新增文件**：按 code-scope.md 中的文件列表，用 Write 从零创建完整 .${PLATFORM_LANGUAGE} 文件
   - 包含完整类声明、import、DI 注册、生命周期方法
2. **修改文件**：Read → Edit 最小改动
3. **设计稿还原**：按 ui_tree/ui_dsl 填充 View 的 build 方法体
4. 全部完成后：\`$FORMAT_CMD $FEATURE_DIR_PATH/\`
5. 输出 \`✓ {N} files done\`

约束优先级：constraints.md > 架构规范 > 设计稿 > 默认

## 项目边界（硬性）
- 禁止 grep/find 项目根目录以外的任何路径（父目录、sibling 仓库、.pub-cache）
- import 路径和组件用法通过 grep 项目内已有源文件推断
INSTRUCTIONS
  else
    cat <<INSTRUCTIONS

# ═══════════════════════════════════════════════════════
# 执行指令
# ═══════════════════════════════════════════════════════

骨架文件已预生成（含类声明、生命周期壳、DI 注册、part of）。你的任务：

1. 对每个骨架文件：Read → 找到 \`// TODO:\` 占位 → Edit 填充业务逻辑
2. **修改文件**（非骨架）：Read → Edit 最小改动
3. **设计稿还原**：按 ui_tree/ui_dsl 填充 View 的 build 方法体
4. 全部完成后：\`$FORMAT_CMD $FEATURE_DIR_PATH/\`
5. 输出 \`✓ {N} files done\`

约束优先级：constraints.md > 架构规范 > 设计稿 > 默认

## 项目边界（硬性）
- 禁止 grep/find 项目根目录以外的任何路径（父目录、sibling 仓库、.pub-cache）
- import 路径和组件用法通过 grep 项目内已有 .dart 文件推断
INSTRUCTIONS
  fi
else
  if [[ "$SKIP_SCAFFOLD" == "true" ]]; then
    cat <<INSTRUCTIONS

# ═══════════════════════════════════════════════════════
# 执行指令
# ═══════════════════════════════════════════════════════

无骨架文件（skip_scaffold=true）。你的任务：

1. **新增文件**：按 code-scope.md 中的文件列表，用 Write 从零创建完整 .${PLATFORM_LANGUAGE} 文件
2. **修改文件**：Read → Edit 最小改动
3. 全部完成后：\`$FORMAT_CMD $FEATURE_DIR_PATH/\`
4. 输出 \`✓ {N} files done\`

约束优先级：constraints.md > 架构规范 > 默认

## 项目边界（硬性）
- 禁止 grep/find 项目根目录以外的任何路径（父目录、sibling 仓库、.pub-cache）
- import 路径和组件用法通过 grep 项目内已有源文件推断
INSTRUCTIONS
  else
    cat <<INSTRUCTIONS

# ═══════════════════════════════════════════════════════
# 执行指令
# ═══════════════════════════════════════════════════════

骨架文件已预生成（含类声明、生命周期壳）。你的任务：

1. 对每个骨架文件：Read → 找到 \`// TODO:\` 占位 → Edit 填充业务逻辑
2. **修改文件**（非骨架）：Read → Edit 最小改动
3. 全部完成后：\`$FORMAT_CMD $FEATURE_DIR_PATH/\`
4. 输出 \`✓ {N} files done\`

约束优先级：constraints.md > 架构规范 > 默认

## 项目边界（硬性）
- 禁止 grep/find 项目根目录以外的任何路径（父目录、sibling 仓库、.pub-cache）
- import 路径和组件用法通过 grep 项目内已有源文件推断
INSTRUCTIONS
  fi
fi
