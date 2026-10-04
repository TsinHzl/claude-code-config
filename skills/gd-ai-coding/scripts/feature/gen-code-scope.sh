#!/usr/bin/env bash
# gen-code-scope.sh — 从 feature-plan.json 为单个 feature 生成开发上下文切片（无需 LLM）。
#
# 输入：feature-plan.json 中的 feat_id
# 输出（写入 features/<feat_id>/）：
#   1. code-scope.md      — 新增/修改文件清单 + 用途说明（从 proposal 反查）
#   2. proposal-slice.md  — proposal.md 中该 feature 对应章节的原文切片
#   3. spec-slice.md      — prd-spec.md 中 related_requirements 对应章节的原文切片
#   4. design-slice.md    — design.md 中相关模块/文件的上下文切片（标题匹配 → 文件名 grep 兜底）
#
# 这些切片作为下游 codegen prompt 的精确上下文输入，避免注入整份文档。
#
# Usage: gen-code-scope.sh <feat_id>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../paths.sh"
source "$SCRIPT_DIR/../lib.sh"

FEAT_ID="${1:?Usage: gen-code-scope.sh <feat_id>}"
CHANGE_DIR="$(get_change_dir)"
FEAT_DIR="$(get_feat_dir "" "$FEAT_ID")"
PLAN_FILE="$CHANGE_DIR/feature-plan.json"

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "ERROR: $PLAN_FILE not found" >&2
  exit 1
fi

# ── Temp file management ────────────────────────────────────────────────────
_TMP_FILES=()
_cleanup_tmp() { [[ ${#_TMP_FILES[@]} -gt 0 ]] && rm -f "${_TMP_FILES[@]}" 2>/dev/null || true; }
trap '_cleanup_tmp' EXIT

_mktemp() {
  local f; f=$(mktemp)
  _TMP_FILES+=("$f")
  echo "$f"
}

# ── One-shot jq extraction (read JSON once, extract fields individually) ────
_FEAT_JSON_TMP=$(_mktemp)
read_features_jq "$PLAN_FILE" "map(select(.id == \"$FEAT_ID\")) | .[0] // empty" > "$_FEAT_JSON_TMP"

if [[ ! -s "$_FEAT_JSON_TMP" ]]; then
  echo "ERROR: feature $FEAT_ID not found in $PLAN_FILE" >&2
  exit 1
fi

_BULK_TMP=$(_mktemp)
jq -r '
  ( @sh "FEAT_NAME=\(.name)" ),
  ( @sh "SECTION_TITLE=\(.proposal_scope.proposal_section // "")" ),
  "---NEW_FILES---",
  ( (.proposal_scope.new_files[]?) // empty ),
  "---MODIFIED_FILES---",
  ( (.proposal_scope.modified_files[]?) // empty ),
  "---RELATED_REQS---",
  ( (.related_requirements[]?) // empty )
' "$_FEAT_JSON_TMP" > "$_BULK_TMP"

eval "$(sed -n '1p' "$_BULK_TMP")"
eval "$(sed -n '2p' "$_BULK_TMP")"
NEW_FILES=$(awk '/^---MODIFIED_FILES---$/{exit} f{print} /^---NEW_FILES---$/{f=1}' "$_BULK_TMP")
MODIFIED_FILES=$(awk '/^---RELATED_REQS---$/{exit} f{print} /^---MODIFIED_FILES---$/{f=1}' "$_BULK_TMP")
RELATED_REQS=$(awk 'f{print} /^---RELATED_REQS---$/{f=1}' "$_BULK_TMP")

mkdir -p "$FEAT_DIR"

# ── Helper: append chunk with separator to a named variable ────────────────
_append_chunk() {
  local varname="$1" chunk="$2" sep="${3-"---"}"
  local cur="${!varname}"
  if [[ -n "$cur" ]]; then
    if [[ -n "$sep" ]]; then
      printf -v "$varname" '%s\n%s\n%s' "$cur" "$sep" "$chunk"
    else
      printf -v "$varname" '%s\n%s' "$cur" "$chunk"
    fi
  else
    printf -v "$varname" '%s' "$chunk"
  fi
}

# ── Helper: count lines including incomplete final line ─────────────────────
_count_lines() {
  local n; n=$(wc -l < "$1" | tr -d ' ')
  [[ -n "$(tail -c 1 "$1")" ]] && n=$((n + 1))
  echo "$n"
}

# ── Helper: extract a markdown section by heading match ─────────────────────
_extract_section() {
  local file="$1" title="$2" max_level="${3:-2}"
  local total start_line="" fuzzy

  total=$(_count_lines "$file")

  start_line=$(grep -nF "$title" "$file" | head -1 | cut -d: -f1) || true

  if [[ -z "$start_line" ]]; then
    fuzzy=$(echo "$title" | sed -E 's/^#{1,4} *([0-9]+\.)? *//')
    if [[ -n "$fuzzy" ]]; then
      start_line=$(grep -niF "$fuzzy" "$file" | head -1 | cut -d: -f1) || true
    fi
  fi

  if [[ -z "$start_line" ]]; then
    return 1
  fi

  local actual_level
  actual_level=$(sed -n "${start_line}p" "$file" | sed 's/^\(#*\).*/\1/' | tr -cd '#' | wc -c | tr -d ' ')
  [[ $actual_level -lt 1 ]] && actual_level=$max_level

  local level_pattern="^#\\{2,${actual_level}\\} "
  local end_line=""
  end_line=$(tail -n +"$((start_line + 1))" "$file" | grep -n "$level_pattern" | head -1 | cut -d: -f1) || true

  if [[ -n "$end_line" ]]; then
    end_line=$((start_line + end_line - 1))
  else
    end_line=$total
  fi

  sed -n "${start_line},${end_line}p" "$file"
}

# ── Extract proposal sections ───────────────────────────────────────────────
PROPOSAL_FILE="$CHANGE_DIR/proposal.md"
PROPOSAL_SECTION=""

if [[ -n "$SECTION_TITLE" && -f "$PROPOSAL_FILE" ]]; then
  IFS='+' read -ra TITLES <<< "$SECTION_TITLE"
  for raw_title in "${TITLES[@]}"; do
    local_title=$(echo "$raw_title" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$local_title" ]] && continue
    chunk=$(_extract_section "$PROPOSAL_FILE" "$local_title" 2) || true
    [[ -n "$chunk" ]] && _append_chunk PROPOSAL_SECTION "$chunk" ""
  done
fi

# Write proposal section to temp file for fast grep in lookup_file_desc
_PROPOSAL_TMP=""
if [[ -n "$PROPOSAL_SECTION" ]]; then
  _PROPOSAL_TMP=$(_mktemp)
  printf '%s\n' "$PROPOSAL_SECTION" > "$_PROPOSAL_TMP"
fi

# ── Helper: lookup file description from proposal section ───────────────────
lookup_file_desc() {
  local filepath="$1"
  local basename
  basename=$(basename "$filepath")
  if [[ -n "$_PROPOSAL_TMP" ]]; then
    local desc
    desc=$(grep -F "$basename" "$_PROPOSAL_TMP" | head -1 \
      | sed -E 's/.*( — | - |：)//;s/\|[[:space:]]*$//;s/^[[:space:]]+|[[:space:]]+$//' \
      | head -c 80)
    [[ -n "$desc" && "$desc" != "$basename"* ]] && echo "$desc" && return
  fi
  echo ""
}

# ── 1. code-scope.md ────────────────────────────────────────────────────────
{
  echo "## 代码改动范围：$FEAT_NAME"
  echo ""
  echo "### 新增文件"
  echo "| 文件路径 | 用途 |"
  echo "|---------|------|"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    desc=$(lookup_file_desc "$f")
    echo "| $f | $desc |"
  done <<< "$NEW_FILES"
  echo ""
  echo "### 修改文件"
  echo "| 文件路径 | 修改说明 |"
  echo "|---------|--------|"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    desc=$(lookup_file_desc "$f")
    echo "| $f | $desc |"
  done <<< "$MODIFIED_FILES"
} > "$FEAT_DIR/code-scope.md"

echo "$FEAT_DIR/code-scope.md"

# ── 2. proposal-slice.md ────────────────────────────────────────────────────
if [[ -n "$PROPOSAL_SECTION" ]]; then
  printf '%s\n' "$PROPOSAL_SECTION" > "$FEAT_DIR/proposal-slice.md"
  echo "$FEAT_DIR/proposal-slice.md"
elif [[ -n "$SECTION_TITLE" ]]; then
  echo "WARN: proposal-slice.md not generated (section not matched)" >&2
fi

# ── 3. spec-slice.md ────────────────────────────────────────────────────────
SPEC_FILE="$CHANGE_DIR/prd/prd-spec.md"

if [[ -n "$RELATED_REQS" && -f "$SPEC_FILE" ]]; then
  SLICE_CONTENT=""

  while IFS= read -r section; do
    [[ -z "$section" ]] && continue
    NUM=$(echo "$section" | sed 's/^§//')
    ESCAPED_NUM=$(printf '%s' "$NUM" | sed 's/\./\\./g')

    SEC_START=$(grep -n "^#\\{2,4\\} *${ESCAPED_NUM}[. ]" "$SPEC_FILE" | head -1 | cut -d: -f1) || true
    if [[ -z "$SEC_START" ]]; then
      echo "WARN: spec section '$section' not found in $SPEC_FILE" >&2
      continue
    fi

    HEADING_TEXT=$(sed -n "${SEC_START}p" "$SPEC_FILE")
    CHUNK=$(_extract_section "$SPEC_FILE" "$HEADING_TEXT") || true

    [[ -n "$CHUNK" ]] && _append_chunk SLICE_CONTENT "$CHUNK"
  done <<< "$RELATED_REQS"

  if [[ -n "$SLICE_CONTENT" ]]; then
    printf '%s\n' "$SLICE_CONTENT" > "$FEAT_DIR/spec-slice.md"
    echo "$FEAT_DIR/spec-slice.md"
  fi
fi

# ── 4. design-slice.md ──────────────────────────────────────────────────────
DESIGN_FILE="$CHANGE_DIR/design.md"

if [[ -n "$SECTION_TITLE" && -f "$DESIGN_FILE" ]]; then
  DESIGN_TOTAL=$(_count_lines "$DESIGN_FILE")
  DESIGN_SLICE=""

  # Strategy 1: match module names from proposal_section titles
  IFS='+' read -ra D_TITLES <<< "$SECTION_TITLE"
  for raw_dt in "${D_TITLES[@]}"; do
    local_dt=$(echo "$raw_dt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    MODULE_NAME=$(echo "$local_dt" | sed -E 's/^#{1,4} *[0-9]+\. *//;s/^#{1,4} *//')
    [[ -z "$MODULE_NAME" ]] && continue
    CHUNK=$(_extract_section "$DESIGN_FILE" "$MODULE_NAME" 2) || true
    [[ -n "$CHUNK" ]] && _append_chunk DESIGN_SLICE "$CHUNK"
  done

  # Strategy 2: grep file paths, merge overlapping context windows
  if [[ -z "$DESIGN_SLICE" ]]; then
    LINES_TMP=$(_mktemp)
    ALL_FILES="${NEW_FILES}
${MODIFIED_FILES}"
    while IFS= read -r fp; do
      [[ -z "$fp" ]] && continue
      BN=$(basename "$fp" .dart)
      grep -nF "$BN" "$DESIGN_FILE" 2>/dev/null | head -2 | cut -d: -f1 >> "$LINES_TMP" || true
    done <<< "$ALL_FILES"

    if [[ -s "$LINES_TMP" ]]; then
      CTX_TMP=$(_mktemp)
      PREV_START=0 PREV_END=0
      while IFS= read -r lnum; do
        CTX_START=$((lnum > 5 ? lnum - 5 : 1))
        CTX_END=$((lnum + 10))
        [[ $CTX_END -gt $DESIGN_TOTAL ]] && CTX_END=$DESIGN_TOTAL

        if [[ $CTX_START -le $((PREV_END + 1)) && $PREV_END -gt 0 ]]; then
          PREV_END=$CTX_END
        else
          if [[ $PREV_END -gt 0 ]]; then
            sed -n "${PREV_START},${PREV_END}p" "$DESIGN_FILE" >> "$CTX_TMP"
            echo "---" >> "$CTX_TMP"
          fi
          PREV_START=$CTX_START
          PREV_END=$CTX_END
        fi
      done < <(sort -un "$LINES_TMP")
      if [[ $PREV_END -gt 0 ]]; then
        sed -n "${PREV_START},${PREV_END}p" "$DESIGN_FILE" >> "$CTX_TMP"
      fi

      DESIGN_SLICE=$(sed '$ { /^---$/d }' "$CTX_TMP")
    fi
  fi

  if [[ -n "$DESIGN_SLICE" ]]; then
    printf '%s\n' "$DESIGN_SLICE" > "$FEAT_DIR/design-slice.md"
    echo "$FEAT_DIR/design-slice.md"
  fi
fi
