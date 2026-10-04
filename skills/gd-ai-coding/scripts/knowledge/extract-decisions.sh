#!/usr/bin/env bash
# extract-decisions.sh
# Extract key technical decisions from design.md → .dac/knowledge/decisions.md
# Called by feature-plan step 2.5 after proposal approval.
# Idempotent: same req_name won't produce duplicate entries.

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPTS_DIR/paths.sh"

STATE_FILE=".dac/state.json"
REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE" 2>/dev/null)
if [[ -z "$REQ_NAME" ]]; then
  echo "❌ extract-decisions：state.json 中缺少 req_name" >&2
  exit 1
fi

CHANGE_DIR="$(get_change_dir "$REQ_NAME")"
DESIGN_FILE="$CHANGE_DIR/design.md"
DECISIONS_FILE=".dac/knowledge/decisions.md"
DATE=$(date +%Y-%m-%d)

if [[ ! -f "$DESIGN_FILE" ]]; then
  echo "ℹ️  design.md 不存在，跳过决策提取"
  exit 0
fi

if [[ ! -f "$DECISIONS_FILE" ]]; then
  echo "❌ decisions.md 不存在，请先运行 scripts/init-dac.sh" >&2
  exit 1
fi

# Dedup check: already extracted for this req_name
if grep -qF "## [$DATE] $REQ_NAME" "$DECISIONS_FILE" 2>/dev/null; then
  echo "ℹ️  决策已存在（$REQ_NAME, $DATE），跳过重复追加"
  exit 0
fi

# Extract decision blocks from design.md
# Supports formats:
#   ### Decision: Title
#   **Decision:** content
#   ## N. Section with decision content
TMP_DECISIONS=$(mktemp)
trap 'rm -f "$TMP_DECISIONS"' EXIT

awk '
  /^###? *(Decision|决策)/ { found=1; print; next }
  /^\*\*(Decision|决策)[：:]/ { found=1; print; next }
  found && /^#{1,3} / { found=0; next }
  found { print }
' "$DESIGN_FILE" > "$TMP_DECISIONS"

# Fallback: if no explicit Decision markers, extract section headings + first paragraph
if [[ ! -s "$TMP_DECISIONS" ]]; then
  awk '
    /^### / { title=$0; content=""; capturing=1; next }
    capturing && /^$/ && content != "" { print title; print content; print ""; capturing=0; next }
    capturing { content = content (content ? " " : "") $0 }
  ' "$DESIGN_FILE" | head -40 > "$TMP_DECISIONS"
fi

if [[ -s "$TMP_DECISIONS" ]]; then
  {
    echo ""
    echo "## [$DATE] $REQ_NAME"
    echo ""
    cat "$TMP_DECISIONS"
  } >> "$DECISIONS_FILE"
  COUNT=$(grep -cE '^###|^\*\*Decision|^\*\*决策' "$TMP_DECISIONS" 2>/dev/null || echo "1")
  echo "✅ 已提取 $COUNT 条决策到 decisions.md（来源：$REQ_NAME design.md）"
else
  echo "ℹ️  design.md 中未识别到结构化决策条目，跳过"
fi
