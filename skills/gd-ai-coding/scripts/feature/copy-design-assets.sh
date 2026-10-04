#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# copy-design-assets.sh
# 从 ui/index.json 中查找与指定 feature 关联的设计稿目录，将 ui_dsl.json 和
# ui_tree.txt 复制（或合并）到对应的 features/<feat_id>/ 目录。
#
# 用法:
#   bash copy-design-assets.sh <feat_id>
#
# 行为:
#   - 单设计稿匹配: 直接 cp
#   - 多设计稿匹配: 合并 JSON nodes 数组 + 拼接 tree 文本（每段加 Page 分隔）
#
# 退出码:
#   0 — 成功复制/合并
#   1 — 参数错误或运行时异常
#   2 — 无关联设计稿（非错误，允许无设计开发）
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../paths.sh"

FEAT_ID="${1:?Usage: copy-design-assets.sh <feat_id>}"
CHANGE_DIR="$(get_change_dir)"
FEAT_DIR="$(get_feat_dir "" "$FEAT_ID")"
UI_DIR="$CHANGE_DIR/ui"
INDEX_FILE="$UI_DIR/index.json"

mkdir -p "$FEAT_DIR"

if [[ ! -f "$INDEX_FILE" ]]; then
  echo "NO_DESIGN: index.json not found"
  exit 2
fi

# Find directories matching this feature
# bash 3.2 compatible — no mapfile
DIR_ARRAY=()
while IFS= read -r _line; do
  [ -n "$_line" ] && DIR_ARRAY+=("$_line")
done < <(jq -r --arg fid "$FEAT_ID" \
  '.[] | select(.features[]? == $fid) | .dir' "$INDEX_FILE" 2>/dev/null)

if [[ ${#DIR_ARRAY[@]} -eq 0 ]]; then
  # skip_feature_plan 可能没回填 features[]。单 feature + 全部未关联 → 视为都属于该 feat。
  PLAN_JSON="$CHANGE_DIR/feature-plan.json"
  PLAN_LEN=0
  PLAN_ID=""
  if [[ -f "$PLAN_JSON" ]]; then
    PLAN_LEN=$(jq 'if type == "array" then length else (.features | length) end' "$PLAN_JSON" 2>/dev/null || echo 0)
    PLAN_ID=$(jq -r 'if type == "array" then .[0].id // "" else .features[0].id // "" end' "$PLAN_JSON" 2>/dev/null || true)
  fi
  UNLINKED=$(jq '[.[] | select((.features // []) | length == 0)] | length' "$INDEX_FILE" 2>/dev/null || echo 0)
  TOTAL=$(jq 'length' "$INDEX_FILE" 2>/dev/null || echo 0)
  if [[ "$PLAN_LEN" == "1" && "$PLAN_ID" == "$FEAT_ID" && "$TOTAL" -gt 0 && "$UNLINKED" == "$TOTAL" ]]; then
    echo "WARN: index.json features[] empty; single feature $FEAT_ID — using all designs"
    TMP=$(mktemp)
    jq --arg fid "$FEAT_ID" \
      'map(if ((.features // []) | length) == 0 then .features = [$fid] | .mapping = "auto" else . end)' \
      "$INDEX_FILE" > "$TMP" && mv "$TMP" "$INDEX_FILE"
    while IFS= read -r _line; do
      [ -n "$_line" ] && DIR_ARRAY+=("$_line")
    done < <(jq -r --arg fid "$FEAT_ID" \
      '.[] | select(.features[]? == $fid) | .dir' "$INDEX_FILE" 2>/dev/null)
  fi
fi

if [[ ${#DIR_ARRAY[@]} -eq 0 ]]; then
  echo "NO_DESIGN: no design linked to $FEAT_ID"
  exit 2
fi

if [[ ${#DIR_ARRAY[@]} -eq 1 ]]; then
  # Single design: direct copy
  SRC_DIR="$UI_DIR/${DIR_ARRAY[0]}"
  [[ -f "$SRC_DIR/ui_dsl.json" ]] && cp "$SRC_DIR/ui_dsl.json" "$FEAT_DIR/ui_dsl.json"
  [[ -f "$SRC_DIR/ui_tree.txt" ]] && cp "$SRC_DIR/ui_tree.txt" "$FEAT_DIR/ui_tree.txt"
else
  # Multiple designs: merge
  MERGED_NODES="[]"
  HAS_DSL=false
  > "$FEAT_DIR/ui_tree.txt"

  for DIR in "${DIR_ARRAY[@]}"; do
    SRC_DIR="$UI_DIR/$DIR"

    if [[ -f "$SRC_DIR/ui_dsl.json" ]]; then
      NODES=$(jq '.nodes // []' "$SRC_DIR/ui_dsl.json" 2>/dev/null || echo "[]")
      MERGED_NODES=$(jq --argjson new "$NODES" '. + $new' <<< "$MERGED_NODES")
      HAS_DSL=true
    fi

    if [[ -f "$SRC_DIR/ui_tree.txt" ]]; then
      NODE_NAME=$(jq -r '.node_name // "unknown"' "$SRC_DIR/ui_dsl.json" 2>/dev/null || echo "$DIR")
      [[ -s "$FEAT_DIR/ui_tree.txt" ]] && echo "" >> "$FEAT_DIR/ui_tree.txt"
      echo "--- Page: $NODE_NAME ---" >> "$FEAT_DIR/ui_tree.txt"
      cat "$SRC_DIR/ui_tree.txt" >> "$FEAT_DIR/ui_tree.txt"
    fi
  done

  # Write merged DSL only if at least one source had ui_dsl.json
  if [[ "$HAS_DSL" == "true" ]]; then
    FIRST_DIR="${DIR_ARRAY[0]}"
    jq --argjson nodes "$MERGED_NODES" '.nodes = $nodes' \
      "$UI_DIR/$FIRST_DIR/ui_dsl.json" > "$FEAT_DIR/ui_dsl.json"
  fi

  # Remove empty tree file if nothing was written
  [[ ! -s "$FEAT_DIR/ui_tree.txt" ]] && rm -f "$FEAT_DIR/ui_tree.txt"
fi

echo "OK: design assets copied to $FEAT_DIR"
exit 0
