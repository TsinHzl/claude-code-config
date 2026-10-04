#!/usr/bin/env bash
# assemble-cr-prompt.sh — Assemble CR sub-agent prompt with stable prefix for API cache.
# Usage: assemble-cr-prompt.sh <feat_id>
# Output: Complete prompt to stdout (pipe to Agent tool's prompt parameter)
# Exit codes: 0=success, 1=missing prerequisites
set -euo pipefail

FEAT_ID="${1:?Usage: assemble-cr-prompt.sh <feat_id>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../runtime.sh"
dac_resolve_runtime || { echo "ERROR: 无法解析 DAC 运行时" >&2; exit 1; }
source "$SCRIPT_DIR/../paths.sh"
source "$SCRIPT_DIR/assemble-common.sh"

CHANGE_DIR="$(get_change_dir)"
FEAT_DIR="$(get_feat_dir "" "$FEAT_ID")"
PLAN_FILE="$CHANGE_DIR/feature-plan.json"
RULES_DIR="$DAC_SKILL_HOME/rules"
KNOWLEDGE_DIR=".dac/knowledge"

# Validate prerequisites
if [[ ! -f "$FEAT_DIR/code-scope.md" ]]; then
  echo "ERROR: $FEAT_DIR/code-scope.md not found" >&2
  exit 1
fi

# CR 开始：与 L2 一样先打 started，结果由 report-cr-verdict.sh 根据 cr-report.md 上报
bash "$SCRIPT_DIR/../metrics/report-cr-verdict.sh" "$FEAT_ID" started >/dev/null 2>&1 || true

# Resolve feature info
FEAT_NAME=""
FEAT_TYPE="page"
if [[ -f "$PLAN_FILE" ]]; then
  FEAT_NAME=$(jq -r --arg id "$FEAT_ID" \
    '(if type == "array" then . else .features end) | map(select(.id == $id)) | .[0].name // ""' \
    "$PLAN_FILE")
  FEAT_TYPE=$(jq -r --arg id "$FEAT_ID" \
    '(if type == "array" then . else .features end) | map(select(.id == $id)) | .[0].type // "page"' \
    "$PLAN_FILE")
fi

# ── 项目语言探测（决定 CR 专家角色 / 源文件后缀 / 代码块语言标签）───────────
# 以项目根目录（cwd）的标志文件为准，命中即停；未命中回退通用角色。
# 注意：本 skill 主体面向 Flutter，此处仅让 CR prompt 随实际项目语言自适应，
# 不改变 codegen / post-codegen 等其余环节。
PROJ_LANG=""          # 语言名词，空 → 通用
SRC_EXT_RE=""         # 源文件后缀 ERE 集合（用于从 code-scope.md 提取代码文件）
if [[ -f pubspec.yaml ]]; then
  PROJ_LANG="Flutter"; SRC_EXT_RE="dart"
elif [[ -f pom.xml || -f build.gradle || -f build.gradle.kts || -f settings.gradle || -f settings.gradle.kts ]]; then
  PROJ_LANG="Java"; SRC_EXT_RE="java|kt|kts"
elif [[ -f go.mod ]]; then
  PROJ_LANG="Go"; SRC_EXT_RE="go"
elif [[ -f tsconfig.json ]]; then
  PROJ_LANG="TypeScript"; SRC_EXT_RE="ts|tsx|js|jsx|mjs|cjs"
elif [[ -f package.json ]]; then
  PROJ_LANG="JavaScript"; SRC_EXT_RE="ts|tsx|js|jsx|mjs|cjs"
elif [[ -f Cargo.toml ]]; then
  PROJ_LANG="Rust"; SRC_EXT_RE="rs"
elif [[ -f pyproject.toml || -f setup.py || -f requirements.txt ]]; then
  PROJ_LANG="Python"; SRC_EXT_RE="py"
fi
# 探测全落空时（脚本非在项目根运行、或语言/构建体系未覆盖）：角色退回通用，
# 后缀集合也须同步退回全语言，避免文件提取被静默限定为 dart 而漏检非 Flutter 代码。
if [[ -z "$SRC_EXT_RE" ]]; then
  SRC_EXT_RE="dart|java|kt|kts|go|ts|tsx|js|jsx|mjs|cjs|rs|py"
fi
if [[ -n "$PROJ_LANG" ]]; then
  CR_ROLE="$PROJ_LANG 代码审查专家"
else
  CR_ROLE="资深代码审查专家"
fi

# 代码块语言标签：按单文件后缀映射，混合语言项目也逐文件正确高亮
fence_for() {
  case "${1##*.}" in
    dart) echo dart ;; java) echo java ;; kt|kts) echo kotlin ;;
    ts) echo typescript ;; tsx) echo tsx ;; jsx) echo jsx ;;
    js|mjs|cjs) echo javascript ;; go) echo go ;; rs) echo rust ;;
    py) echo python ;; *) echo "" ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# ZONE A — CR checklist (stable prefix → API cache hit across features)
# ═══════════════════════════════════════════════════════════════════════════════

printf '你是 %s。对以下功能代码进行需求符合性 Code Review。\n' "$CR_ROLE"
cat <<'HEADER'
严格按检查清单逐维度检查，只输出不通过的项，通过的不列举。

# ═══════════════════════════════════════════════════════
# ZONE A — CR 检查规范（固定）
# ═══════════════════════════════════════════════════════

## 取数约束（最高优先级，覆盖你自身的默认探索行为）

本 prompt 的 ZONE C 已内联本次审查所需的全部输入：需求章节、代码改动范围、设计稿规格、
新增文件全文、修改文件 diff（含 10 行上下文）。因此：

- 禁止执行任何 git 命令（`git diff` / `git log` / `git status` / `git show` / `git blame` 等）
- 禁止 Grep / Glob 全仓检索，禁止 Read ZONE C 未列出的文件
- 仅当跨调用点一致性判断确实必要时，可 Read **ZONE C 已列出的改动文件**的当前完整内容，
  上限 **3 个文件**
- 允许 Write：写入下方「输出指令」指定的 cr-report.md；正常情况仅需 1 次，
  若该次 Write 失败（路径/权限异常）允许重试一次，总工具调用上限不变
- **总工具调用数 ≤ 8 次**；触及上限立即基于已有信息出结论，不再取数

检查清单中任何一项若因 ZONE C 未提供对应输入而无法判断，直接跳过该项，不得为此额外取数。

HEADER

cat "$RULES_DIR/cr-checklist.md"

# ═══════════════════════════════════════════════════════════════════════════════
# ZONE B — Project constraints (stable within one loop iteration)
# ═══════════════════════════════════════════════════════════════════════════════

cat <<'DIVIDER'

# ═══════════════════════════════════════════════════════
# ZONE B — 项目约束（同一轮次内稳定）
# ═══════════════════════════════════════════════════════

## 已知约束（CR 积累，审查时需对照）

DIVIDER

emit_zone_b_constraints "$KNOWLEDGE_DIR"

printf '\n## 已知错误模式（审查时需关注是否重犯）\n\n'

emit_zone_b_error_patterns "$KNOWLEDGE_DIR"

# ═══════════════════════════════════════════════════════════════════════════════
# ZONE C — Feature-specific inputs (changes every feature)
# ═══════════════════════════════════════════════════════════════════════════════

cat <<'DIVIDER'

# ═══════════════════════════════════════════════════════
# ZONE C — 当前功能输入
# ═══════════════════════════════════════════════════════

## 需求文档（当前功能相关章节）

DIVIDER

if [[ -f "$FEAT_DIR/spec-slice.md" ]]; then
  cat "$FEAT_DIR/spec-slice.md"
else
  # Fallback: extract only related sections from prd-spec.md (NOT full file)
  PRD_SPEC="$CHANGE_DIR/prd/prd-spec.md"
  if [[ -f "$PRD_SPEC" && -f "$PLAN_FILE" ]]; then
    RELATED=$(jq -r --arg id "$FEAT_ID" \
      '(if type == "array" then . else .features end) | map(select(.id == $id)) | .[0].related_requirements // [] | .[]' \
      "$PLAN_FILE" 2>/dev/null || true)
    if [[ -n "$RELATED" ]]; then
      echo "（从 prd-spec.md 提取关联章节）"
      echo ""
      SPEC_TOTAL=$(wc -l < "$PRD_SPEC")
      while IFS= read -r section; do
        [[ -z "$section" ]] && continue
        NUM=$(echo "$section" | sed 's/^§//')
        ESCAPED_NUM=$(printf '%s' "$NUM" | sed 's/\./\\./g')
        SEC_START=$(grep -n "^#\\{2,4\\} *${ESCAPED_NUM}[. ]" "$PRD_SPEC" | head -1 | cut -d: -f1) || true
        [[ -z "$SEC_START" ]] && continue
        HEADING_LEVEL=$(sed -n "${SEC_START}p" "$PRD_SPEC" | grep -o "^#*" | wc -c)
        HEADING_LEVEL=$((HEADING_LEVEL - 1))
        LEVEL_PATTERN="^#\\{2,${HEADING_LEVEL}\\} "
        SEC_END=$(tail -n +"$((SEC_START + 1))" "$PRD_SPEC" | grep -n "$LEVEL_PATTERN" | head -1 | cut -d: -f1) || true
        if [[ -n "$SEC_END" ]]; then
          SEC_END=$((SEC_START + SEC_END - 1))
        else
          SEC_END=$SPEC_TOTAL
        fi
        sed -n "${SEC_START},${SEC_END}p" "$PRD_SPEC"
        echo ""
        echo "---"
        echo ""
      done <<< "$RELATED"
    else
      echo "（无关联需求章节）"
    fi
  else
    echo "（无关联需求章节）"
  fi
fi

printf '\n## 代码改动范围\n\n'
cat "$FEAT_DIR/code-scope.md"

# Design assets
printf '\n## 设计稿\n\n'

if [[ -f "$FEAT_DIR/.design_skipped" ]]; then
  SKIP_REASON=$(jq -r '.reason // "用户选择跳过"' "$FEAT_DIR/.design_skipped" 2>/dev/null || echo "用户选择跳过")
  echo "设计稿已标记跳过（reason: ${SKIP_REASON}）。3.3/3.5 节检查跳过。"
elif [[ -f "$FEAT_DIR/ui_tree.txt" ]]; then
  printf '### UI 层级结构\n\n'
  cat "$FEAT_DIR/ui_tree.txt"
  if [[ -f "$FEAT_DIR/ui_dsl.json" ]]; then
    printf '\n### UI 详细规格（用于 3.5 节设计稿-代码结构一致性检查）\n\n'
    cat "$FEAT_DIR/ui_dsl.json"
  fi
else
  echo "无设计稿。3.3/3.5 节检查跳过。"
fi

# Actual code files — new files: full content; modified files: diff only
printf '\n## 实际代码文件\n\n'

# Parse code-scope.md to separate new vs modified files
NEW_FILES=""
MODIFIED_FILES=""
if [[ -f "$FEAT_DIR/code-scope.md" ]]; then
  IN_NEW=false
  IN_MOD=false
  while IFS= read -r line; do
    if echo "$line" | grep -qiE '^###\s*新增|^###\s*new'; then
      IN_NEW=true; IN_MOD=false; continue
    fi
    if echo "$line" | grep -qiE '^###\s*修改|^###\s*modified'; then
      IN_MOD=true; IN_NEW=false; continue
    fi
    if echo "$line" | grep -qE '^#{1,3}\s'; then
      if [[ "$IN_NEW" == "true" || "$IN_MOD" == "true" ]]; then
        IN_NEW=false; IN_MOD=false
      fi
      continue
    fi
    filepath=$(echo "$line" | grep -oE "[A-Za-z0-9_./-]+\.($SRC_EXT_RE)" || true)
    [[ -z "$filepath" ]] && continue
    if [[ "$IN_NEW" == "true" ]]; then
      NEW_FILES+="$filepath"$'\n'
    elif [[ "$IN_MOD" == "true" ]]; then
      MODIFIED_FILES+="$filepath"$'\n'
    fi
  done < "$FEAT_DIR/code-scope.md"
fi

# New files: full content injection
if [[ -n "$NEW_FILES" ]]; then
  while IFS= read -r filepath; do
    [[ -z "$filepath" ]] && continue
    if [[ -f "$filepath" ]]; then
      printf '### `%s` (new)\n\n```%s\n' "$filepath" "$(fence_for "$filepath")"
      cat "$filepath"
      printf '\n```\n\n'
    else
      printf '### `%s`\n\n（文件不存在，可能尚未生成）\n\n' "$filepath"
    fi
  done <<< "$NEW_FILES"
fi

# Modified files: diff with 10 lines of context (saves 50-90% vs full content)
CODEGEN_BASE=""
if [[ -f "$FEAT_DIR/.codegen_checkpoint" ]]; then
  CODEGEN_BASE=$(jq -r '.base_commit // empty' "$FEAT_DIR/.codegen_checkpoint" 2>/dev/null)
fi

if [[ -n "$MODIFIED_FILES" ]]; then
  while IFS= read -r filepath; do
    [[ -z "$filepath" ]] && continue
    [[ ! -f "$filepath" ]] && continue

    DIFF_OUTPUT=""
    if [[ -n "$CODEGEN_BASE" ]]; then
      DIFF_OUTPUT=$(git diff -U10 "$CODEGEN_BASE" -- "$filepath" 2>/dev/null || true)
    fi

    if [[ -n "$DIFF_OUTPUT" ]]; then
      printf '### `%s` (modified - diff)\n\n```diff\n' "$filepath"
      echo "$DIFF_OUTPUT"
      printf '\n```\n\n'
    else
      # Fallback: full content when checkpoint unavailable or no diff
      printf '### `%s` (modified)\n\n```%s\n' "$filepath" "$(fence_for "$filepath")"
      cat "$filepath"
      printf '\n```\n\n'
    fi
  done <<< "$MODIFIED_FILES"
fi

if [[ -z "$NEW_FILES" && -z "$MODIFIED_FILES" ]]; then
  echo "（未从 code-scope.md 解析到代码文件路径）"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Output instructions
# ═══════════════════════════════════════════════════════════════════════════════

cat <<INSTRUCTIONS

# ═══════════════════════════════════════════════════════
# 输出指令
# ═══════════════════════════════════════════════════════

按 cr-checklist.md 的 6 个维度检查。只输出不通过的项，通过的不列举。

生成 CR 报告写入：$FEAT_DIR/cr-report.md

全部通过时报告只写 "verdict: clean"，不要列通过项摘要。

返回：
- verdict: clean 或 with_issues
- issues_summary: 仅当 with_issues 时列出 🔴/🟡 问题（clean 时此字段省略）
INSTRUCTIONS
