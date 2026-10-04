#!/usr/bin/env bash
# gen-dep-catalog.sh — Generate external component dependency catalog.
#
# Scans graphify-out/graph.json (preferred) or project lib/ (fallback) to build
# a compact reference of commonly-used external components: import path + usage example.
# Output: .dac/knowledge/dep-catalog.md
#
# Called by snapshot-knowledge.sh during feature loop init. The catalog is injected
# into codegen prompt ZONE B so sub-agents never need to scan outside the project.
#
# Usage: gen-dep-catalog.sh
# Exit codes: 0=success (catalog written), 0=also when lib/ not found (no-op)
set -euo pipefail

KNOWLEDGE_DIR=".dac/knowledge"
CATALOG_FILE="$KNOWLEDGE_DIR/dep-catalog.md"
GRAPH_FILE="graphify-out/graph.json"
TOP_N=25

if [[ ! -d "lib" ]]; then
  echo "SKIP: lib/ not found, not a Flutter project root" >&2
  exit 0
fi

mkdir -p "$KNOWLEDGE_DIR"

# Detect current package name from pubspec.yaml
CURRENT_PKG=""
if [[ -f "pubspec.yaml" ]]; then
  CURRENT_PKG=$(grep -m1 '^name:' pubspec.yaml | sed 's/^name:[[:space:]]*//' | tr -d "'" | tr -d '"')
fi

# ── Strategy 1: graphify-based extraction ────────────────────────────────────
#
# graph.json edges with context "import" or relation "references" encode which
# project files reference which external components. We find the source files,
# then grep those files for the actual import statements.

extract_via_graphify() {
  if [[ ! -f "$GRAPH_FILE" ]]; then
    return 1
  fi

  if ! command -v jq &>/dev/null; then
    echo "WARN: jq not available, falling back to grep" >&2
    return 1
  fi

  # Find source files from graph nodes that participate in import/reference edges
  local SOURCE_FILES
  SOURCE_FILES=$(jq -r '
    [.links[] | select(.context == "import" or .relation == "references")] as $edges |
    [.nodes[] | select(.file_type == "code")] as $nodes |
    [$edges[].source] | unique | . as $src_ids |
    [$nodes[] | select(.id as $id | $src_ids | index($id)) | .source_file] | unique[]
  ' "$GRAPH_FILE" 2>/dev/null) || return 1

  if [[ -z "$SOURCE_FILES" ]]; then
    return 1
  fi

  # From those files, extract external package imports
  local IMPORTS=""
  while IFS= read -r src_file; do
    [[ -f "$src_file" ]] || continue
    local file_imports
    file_imports=$(grep -h "^import 'package:" "$src_file" 2>/dev/null || true)
    [[ -n "$file_imports" ]] && IMPORTS+="$file_imports"$'\n'
  done <<< "$SOURCE_FILES"

  if [[ -z "$IMPORTS" ]]; then
    return 1
  fi

  echo "$IMPORTS"
  return 0
}

# ── Strategy 2: grep-based fallback ──────────────────────────────────────────

extract_via_grep() {
  grep -rh "^import 'package:" lib/ --include="*.dart" 2>/dev/null || true
}

# ── Main: collect imports → rank → generate catalog ─────────────────────────

RAW_IMPORTS=""
if ! RAW_IMPORTS=$(extract_via_graphify); then
  RAW_IMPORTS=$(extract_via_grep)
fi

if [[ -z "$RAW_IMPORTS" ]]; then
  echo "SKIP: no external imports found" >&2
  exit 0
fi

# Filter out current package imports, deduplicate, count frequency, take top-N
RANKED_IMPORTS=$(echo "$RAW_IMPORTS" \
  | grep -v "^$" \
  | { [[ -n "$CURRENT_PKG" ]] && grep -v "package:${CURRENT_PKG}/" || cat; } \
  | sort | uniq -c | sort -rn | head -n "$TOP_N" \
  | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')

if [[ -z "$RANKED_IMPORTS" ]]; then
  echo "SKIP: no external imports after filtering" >&2
  exit 0
fi

# For each import line, find class usages and build catalog entries
TMP_CATALOG=$(mktemp)
SEEN_FILE=$(mktemp)
trap 'rm -f "$TMP_CATALOG" "$SEEN_FILE"' EXIT

while IFS= read -r import_line; do
  [[ -z "$import_line" ]] && continue

  # Dedup via file (bash 3.2 has no associative arrays)
  if grep -qxF "$import_line" "$SEEN_FILE" 2>/dev/null; then
    continue
  fi
  echo "$import_line" >> "$SEEN_FILE"

  # Find files that import this package
  USING_FILES=$(grep -rln "$import_line" lib/ --include="*.dart" 2>/dev/null | head -5)
  [[ -z "$USING_FILES" ]] && continue

  # Collect PascalCase constructor calls from those files (likely component classes)
  CLASSES=""
  while IFS= read -r use_file; do
    [[ -f "$use_file" ]] || continue
    file_classes=$(grep -oE '\b[A-Z][a-zA-Z0-9]+\(' "$use_file" 2>/dev/null \
      | sed 's/($//' | sort -u \
      | grep -vE '^(Widget|State|Key|Text|Column|Row|Container|Center|Padding|Scaffold|SizedBox|EdgeInsets|Color|Colors|BoxDecoration|Border|BorderRadius|BuildContext|StatelessWidget|StatefulWidget|Map|List|Set|Future|Stream|Icon|Icons|Alignment|MainAxisAlignment|CrossAxisAlignment|TextStyle|FontWeight|Size|Offset|Rect|Duration|Timer|RegExp|Exception|Error|Navigator|MaterialApp|GetBuilder|GetView|Obx|Assert|Override|String|Function|Object|Type|Null)$' \
      || true)
    [[ -n "$file_classes" ]] && CLASSES+="$file_classes"$'\n'
  done <<< "$USING_FILES"

  [[ -z "$CLASSES" ]] && continue

  # Top classes by frequency
  UNIQUE_CLASSES=$(echo "$CLASSES" | grep -v "^$" | sort | uniq -c | sort -rn | head -5 | awk '{print $2}')

  while IFS= read -r cls; do
    [[ -z "$cls" ]] && continue

    # One usage example (constructor call with args, trimmed)
    USAGE=$(grep -rn "${cls}(" lib/ --include="*.dart" -m 1 2>/dev/null \
      | head -1 | sed 's/^[^:]*:[0-9]*://' | sed 's/^[[:space:]]*//' | cut -c1-120)

    if [[ -n "$USAGE" ]]; then
      echo "### $cls" >> "$TMP_CATALOG"
      echo "- import: \`$import_line\`" >> "$TMP_CATALOG"
      echo "- usage: \`$USAGE\`" >> "$TMP_CATALOG"
      echo "" >> "$TMP_CATALOG"
    fi
  done <<< "$UNIQUE_CLASSES"
done <<< "$RANKED_IMPORTS"

if [[ ! -s "$TMP_CATALOG" ]]; then
  echo "SKIP: no component references found" >&2
  exit 0
fi

# Write final catalog (deduplicated by class name, keep first = highest frequency)
{
  echo "<!-- Auto-generated by gen-dep-catalog.sh — do not edit manually -->"
  echo ""
  awk '/^### /{name=$2; if(seen[name]++){skip=1}else{skip=0}} !skip' "$TMP_CATALOG"
} > "$CATALOG_FILE"

ENTRY_COUNT=$(grep -c '^### ' "$CATALOG_FILE" 2>/dev/null || echo 0)
echo "✓ dep-catalog.md generated: $ENTRY_COUNT components"
