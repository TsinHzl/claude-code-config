#!/bin/bash
set -euo pipefail

# gen-index.sh — 扫描 ui/ 子目录，生成 index.json
#
# 用法：
#   gen-index.sh --ui-dir <目录> --links "<原始链接文本>"
#
# 输出：<ui-dir>/index.json

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

UI_DIR=""
LINKS_RAW=""

usage() {
  cat <<'EOF'
用法：
  gen-index.sh --ui-dir <目录> [--links "<原始链接文本>"]

参数：
  --ui-dir   设计稿输出目录（包含 001/ 002/ ... 子目录）
  --links    可选，用户原始输入的设计稿链接文本（fallback，优先读取子目录中的 .source_link 文件）

输出：
  <ui-dir>/index.json
EOF
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --ui-dir)  UI_DIR="$2"; shift 2 ;;
    --links)   LINKS_RAW="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "❌ 未知参数：$1" >&2; usage ;;
  esac
done

[ -z "$UI_DIR" ] && { echo "❌ 必须指定 --ui-dir" >&2; usage; }

if [ ! -d "$UI_DIR" ]; then
  echo "❌ 目录不存在：$UI_DIR" >&2
  exit 1
fi

# filter-dsl 产出是 {nodes:[...]}，没有顶层 name。空字符串也不走 jq //。
# 顺序：顶层 name/nodeName → nodes[0].name → ui_tree.txt 第一行 [TYPE] 名。
extract_node_name() {
  local dir="$1"
  local name=""
  if [ -f "$dir/ui_dsl.json" ]; then
    name=$(jq -r '
      def nonempty: if . == null or . == "" then empty else . end;
      (.name | nonempty) // (.nodeName | nonempty) // (.nodes[0].name | nonempty) // ""
    ' "$dir/ui_dsl.json" 2>/dev/null || true)
  fi
  if [ -z "$name" ] && [ -f "$dir/ui_tree.txt" ]; then
    name=$(sed -n '1{s/^[^]]*\][[:space:]]*//; s/[[:space:]]*(.*//; p;}' "$dir/ui_tree.txt")
  fi
  printf '%s' "$name"
}

# 提取 fallback 链接列表（按顺序对应 001, 002, ...）
# bash 3.2 compatible — no mapfile
FALLBACK_LINKS=()
if [ -n "$LINKS_RAW" ]; then
  while IFS= read -r _line; do
    [ -n "$_line" ] && FALLBACK_LINKS+=("$_line")
  done < <(echo "$LINKS_RAW" | grep -oE 'https?://[^[:space:],，]+' | sed 's/[,，]*$//')
fi

# 扫描数字子目录
# bash 3.2 compatible — no mapfile
DIRS=()
while IFS= read -r _line; do
  [ -n "$_line" ] && DIRS+=("$_line")
done < <(find "$UI_DIR" -maxdepth 1 -type d -regex '.*/[0-9][0-9][0-9]' | sort)

if [ ${#DIRS[@]} -eq 0 ]; then
  # 单链接模式：ui_dsl.json 直接在 ui/ 根目录，无编号子目录
  if [ -f "$UI_DIR/ui_dsl.json" ] || find "$UI_DIR" -maxdepth 1 -name "*.html" -print -quit 2>/dev/null | grep -q .; then
    STATUS="failed"
    if [ -f "$UI_DIR/ui_dsl.json" ]; then
      STATUS="ok"
    elif find "$UI_DIR" -maxdepth 1 -name "*.html" -print -quit 2>/dev/null | grep -q .; then
      STATUS="ok"
    fi

    NODE_NAME=$(extract_node_name "$UI_DIR")

    SOURCE_LINK=""
    if [ -f "$UI_DIR/.source_link" ]; then
      SOURCE_LINK=$(cat "$UI_DIR/.source_link")
    elif [ -n "$LINKS_RAW" ] && [ ${#FALLBACK_LINKS[@]} -gt 0 ]; then
      SOURCE_LINK="${FALLBACK_LINKS[0]}"
    fi

    ENTRY=$(jq -n \
      --arg id "ds_001" \
      --arg source_link "$SOURCE_LINK" \
      --arg node_name "$NODE_NAME" \
      --arg status "$STATUS" \
      '{
        id: $id,
        source_link: $source_link,
        sections: [],
        features: [],
        node_name: $node_name,
        dir: ".",
        status: $status,
        mapping: "pending"
      }')

    echo "[$ENTRY]" | jq '.' > "$UI_DIR/index.json"
    echo "✅ index.json 已生成（单设计稿模式）：$UI_DIR/index.json" >&2
  else
    echo "⚠️  未找到子目录且无设计稿文件，生成空 index.json" >&2
    echo "[]" > "$UI_DIR/index.json"
  fi
  exit 0
fi

JSON="[]"
for DIR in "${DIRS[@]}"; do
  DIR_NAME=$(basename "$DIR")
  INDEX=$((10#$DIR_NAME))
  ID="ds_$(printf "%03d" "$INDEX")"

  # 关联 source_link（优先从 .source_link 文件读取）
  SOURCE_LINK=""
  if [ -f "$DIR/.source_link" ]; then
    SOURCE_LINK=$(cat "$DIR/.source_link")
  else
    LINK_IDX=$((INDEX - 1))
    if [ $LINK_IDX -ge 0 ] && [ $LINK_IDX -lt ${#FALLBACK_LINKS[@]} ]; then
      SOURCE_LINK="${FALLBACK_LINKS[$LINK_IDX]}"
    fi
  fi

  # 判定 status
  STATUS="failed"
  if [ -f "$DIR/ui_dsl.json" ]; then
    STATUS="ok"
  elif find "$DIR" -name "*.html" -print -quit 2>/dev/null | grep -q .; then
    STATUS="ok"
  elif [ -f "$DIR/.skipped" ]; then
    STATUS="skipped"
  fi

  NODE_NAME=$(extract_node_name "$DIR")

  # 构建条目
  ENTRY=$(jq -n \
    --arg id "$ID" \
    --arg source_link "$SOURCE_LINK" \
    --arg node_name "$NODE_NAME" \
    --arg dir "$DIR_NAME" \
    --arg status "$STATUS" \
    '{
      id: $id,
      source_link: $source_link,
      sections: [],
      features: [],
      node_name: $node_name,
      dir: $dir,
      status: $status,
      mapping: "pending"
    }')

  JSON=$(echo "$JSON" | jq --argjson entry "$ENTRY" '. + [$entry]')
done

echo "$JSON" | jq '.' > "$UI_DIR/index.json"

OK_COUNT=$(echo "$JSON" | jq '[.[] | select(.status == "ok")] | length')
TOTAL=${#DIRS[@]}
echo "✅ index.json 已生成：$UI_DIR/index.json（$OK_COUNT/$TOTAL 有效）" >&2
