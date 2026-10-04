#!/usr/bin/env bash
# assemble-common.sh — Shared ZONE B assembly functions for codegen/CR prompt scripts.
# Source this file; do not execute directly.

# _has_content <file>
# Returns 0 if file exists and contains non-whitespace content beyond markdown headers.
_has_content() {
  [[ -f "$1" ]] && grep -vE '^[[:space:]]*(#.*)?$' "$1" 2>/dev/null | grep -q .
}

# emit_zone_b_constraints <knowledge_dir>
# Outputs constraints block with snapshot fallback. Skips section entirely if no meaningful content.
emit_zone_b_constraints() {
  local knowledge_dir="$1"
  if _has_content "$knowledge_dir/constraints.snapshot.md"; then
    cat "$knowledge_dir/constraints.snapshot.md"
  elif _has_content "$knowledge_dir/constraints.md"; then
    cat "$knowledge_dir/constraints.md"
  else
    echo "（暂无约束记录）"
  fi
}

# emit_zone_b_error_patterns <knowledge_dir>
# Outputs error-patterns block with snapshot fallback. Skips section entirely if no meaningful content.
emit_zone_b_error_patterns() {
  local knowledge_dir="$1"
  if _has_content "$knowledge_dir/error-patterns.snapshot.md"; then
    cat "$knowledge_dir/error-patterns.snapshot.md"
  elif _has_content "$knowledge_dir/error-patterns.md"; then
    cat "$knowledge_dir/error-patterns.md"
  fi
  # No placeholder when empty — section header in caller is sufficient signal
}

# emit_zone_b_dep_catalog <knowledge_dir>
# Outputs component dependency catalog (import paths + usage). Skips if empty/missing.
emit_zone_b_dep_catalog() {
  local knowledge_dir="$1"
  if _has_content "$knowledge_dir/dep-catalog.md"; then
    cat "$knowledge_dir/dep-catalog.md"
  fi
}
