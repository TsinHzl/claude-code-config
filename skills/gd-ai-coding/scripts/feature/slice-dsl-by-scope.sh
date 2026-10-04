#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# slice-dsl-by-scope.sh — 按功能范围裁剪 MasterGo DSL，减少 codegen 输入 token。
#
# 作用：从完整页面 DSL (ui_dsl.json) 中仅保留当前 feature 相关的设计节点子树，
#       裁剪后覆写 features/{feat_id}/ui_dsl.json 并重新生成 ui_tree.txt。
#       典型节省幅度 40-60%。
#
# 三级匹配策略：
#   1. Primary: feature-plan.json → design_nodes[] (LLM 显式标注)
#   2. Fallback: ui_tree.txt 根节点名 (copy-design-assets 已预过滤)
#   3. Fallback: code-scope.md → widget 文件名 → PascalCase → 模糊匹配
#   4. 全部未命中: 保留完整 DSL (安全兜底)
#
# 用法: slice-dsl-by-scope.sh <feat_id>
# 退出码: 0=已裁剪, 1=错误, 2=无 DSL 文件(跳过), 3=未命中(保留全量)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

FEAT_ID="${1:?Usage: slice-dsl-by-scope.sh <feat_id>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../paths.sh"

CHANGE_DIR="$(get_change_dir)"
FEAT_DIR="$(get_feat_dir "" "$FEAT_ID")"
PLAN_FILE="$CHANGE_DIR/feature-plan.json"
DSL_FILE="$FEAT_DIR/ui_dsl.json"

if [[ ! -f "$DSL_FILE" ]]; then
  echo "SKIP: no ui_dsl.json for $FEAT_ID"
  exit 2
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "WARN: feature-plan.json not found, keeping full DSL" >&2
  exit 3
fi

# ── Step 1: Resolve target node names ─────────────────────────────────────────

TARGET_NAMES=""

# Strategy 1: design_nodes from feature-plan.json
DESIGN_NODES=$(jq -r --arg id "$FEAT_ID" \
  '(if type == "array" then . else .features end) | map(select(.id == $id)) | .[0].design_nodes // [] | .[]' \
  "$PLAN_FILE" 2>/dev/null || true)

if [[ -n "$DESIGN_NODES" ]]; then
  TARGET_NAMES="$DESIGN_NODES"
  echo "  策略: design_nodes 显式标注"
else
  # Strategy 2: Extract root node names from local ui_tree.txt (already filtered by copy-design-assets)
  TREE_FILE="$FEAT_DIR/ui_tree.txt"
  if [[ -f "$TREE_FILE" ]]; then
    ROOT_NAMES=$(grep -E '^[├└]' "$TREE_FILE" | sed -E 's/^[├└]── \[[^]]+\] ([^ ]+) .*/\1/' | grep -v '^$' || true)
    if [[ -n "$ROOT_NAMES" ]]; then
      TARGET_NAMES="$ROOT_NAMES"
      echo "  策略: ui_tree.txt 根节点提取"
    fi
  fi

  # Strategy 3: Fallback - derive from code-scope.md widget file names
  if [[ -z "$TARGET_NAMES" ]]; then
    SCOPE_FILE="$FEAT_DIR/code-scope.md"
    if [[ -f "$SCOPE_FILE" ]]; then
      # Extract dart file names from presentation/widgets paths, convert to PascalCase
      WIDGET_FILES=$(grep -oE 'lib/[^ |]+/presentation/[^ |]+\.dart' "$SCOPE_FILE" 2>/dev/null \
        | grep -v '_page\.dart$' \
        | sed 's|.*/||; s|\.dart$||' || true)

      if [[ -n "$WIDGET_FILES" ]]; then
        # Convert snake_case to PascalCase: login_form → LoginForm
        TARGET_NAMES=$(echo "$WIDGET_FILES" | while IFS= read -r name; do
          echo "$name" | sed -E 's/(^|_)([a-z])/\U\2/g'
        done)
        echo "  策略: code-scope 文件名推导"
      fi
    fi
  fi
fi

if [[ -z "$TARGET_NAMES" ]]; then
  echo "NO_MATCH: no target nodes resolved, keeping full DSL"
  exit 3
fi

echo "  目标节点: $(echo "$TARGET_NAMES" | tr '\n' ', ' | sed 's/,$//')"

# ── Step 2: Build jq match pattern ───────────────────────────────────────────

# Convert target names to a JSON array for jq
TARGETS_JSON=$(echo "$TARGET_NAMES" | jq -R -s 'split("\n") | map(select(length > 0))')

# ── Step 3: Slice DSL - keep matching subtrees + ancestors ───────────────────

ORIG_SIZE=$(wc -c < "$DSL_FILE")
ORIG_NODES=$(jq '.nodes | length' "$DSL_FILE" 2>/dev/null || echo "0")

SLICED=$(jq --argjson targets "$TARGETS_JSON" '
  # Check if a node name fuzzy-matches any target
  # Matching rules:
  #   - Exact match (case-insensitive)
  #   - Node name contains target as substring
  #   - Target contains node name as substring (for short design names)
  def matches_target:
    . as $name
    | ($name | ascii_downcase) as $lower
    | any($targets[]; . as $t |
        ($t | ascii_downcase) as $tl |
        ($lower == $tl) or ($lower | contains($tl)) or ($tl | contains($lower))
      );

  # Recursively check if a node or any descendant matches
  def has_match:
    (.name // "" | matches_target)
    or any(.children // []; . | has_match);

  # Slice: keep node if it matches or has matching descendants
  # For matching nodes: keep full subtree (all children)
  # For ancestor nodes: keep only structure + matching child branches
  def slice_node:
    if (.name // "" | matches_target) then
      .  # Full subtree preserved
    elif any(.children // []; . | has_match) then
      .children = [.children[] | select(has_match) | slice_node]
    else
      empty
    end;

  .nodes = [.nodes[] | select(has_match) | slice_node]
' "$DSL_FILE" 2>/dev/null)

if [[ -z "$SLICED" ]] || ! echo "$SLICED" | jq empty 2>/dev/null; then
  echo "WARN: jq slicing failed, keeping full DSL" >&2
  exit 3
fi

SLICED_NODES=$(echo "$SLICED" | jq '.nodes | length')

# If slicing removed everything or kept everything, skip overwrite
if [[ "$SLICED_NODES" -eq 0 ]]; then
  echo "NO_MATCH: slicing matched 0 nodes, keeping full DSL"
  exit 3
fi

if [[ "$SLICED_NODES" -eq "$ORIG_NODES" ]]; then
  echo "  全部节点已匹配（${ORIG_NODES}），无需裁剪"
  exit 0
fi

# ── Step 4: Overwrite DSL + regenerate tree ──────────────────────────────────

echo "$SLICED" | jq -c '.' > "$DSL_FILE"

# Regenerate ui_tree.txt from sliced DSL
jq -r '
  def truncate30: if length > 30 then .[0:30] + "…" else . end;

  def node_attrs:
    []
    | if .flex then . + ["flex:\(.flex)"] else . end
    | if .fill then . + ["fill:\(.fill)"] else . end
    | if .content then . + ["\"\(.content | truncate30)\""] else . end
    | if .font then . + ["font:\(.font.size)sp"] else . end;

  def tree_lines($prefix):
    . as $nodes
    | reduce range(0; $nodes | length) as $i ("";
        ($nodes[$i]) as $node
        | ($i == ($nodes | length - 1)) as $is_last
        | (if $is_last then "└── " else "├── " end) as $conn
        | (if $is_last then "    " else "│   " end) as $child_prefix
        | ($node.layout // {}) as $l
        | ($node | node_attrs) as $attrs
        | . + $prefix + $conn + "[\($node.type // "")] \($node.name // "") (\($l.w // 0)×\($l.h // 0))\(if ($attrs|length)>0 then " [\($attrs|join(", "))]" else "" end)\n"
        | if ($node.children // [] | length) > 0
          then . + ($node.children | tree_lines($prefix + $child_prefix))
          else . end
      );

  .nodes | tree_lines("")
' "$DSL_FILE" > "$FEAT_DIR/ui_tree.txt"

SLICED_SIZE=$(wc -c < "$DSL_FILE")

echo "✅ DSL 裁剪完成: $ORIG_NODES → $SLICED_NODES 节点 (${ORIG_SIZE}B → ${SLICED_SIZE}B)"
