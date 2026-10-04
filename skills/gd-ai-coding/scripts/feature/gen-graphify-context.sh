#!/usr/bin/env bash
# gen-graphify-context.sh — 从 graphify 知识图谱提取当前 feature 相关的现有组件上下文。
#
# 输入：feature-plan.json 中的 feat_id
# 输出：openspec/changes/{req_name}/features/{feat_id}/graphify-context.md
#
# 零 LLM token：纯 bash/jq 从 graph.json 中提取与 feature 涉及目录相关的节点和边。
# graphify-out/ 不存在时静默退出（exit 0），不阻断流程。
#
# Usage: gen-graphify-context.sh <feat_id>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../paths.sh"
source "$SCRIPT_DIR/../lib.sh"

FEAT_ID="${1:?Usage: gen-graphify-context.sh <feat_id>}"
CHANGE_DIR="$(get_change_dir)"
FEAT_DIR="$(get_feat_dir "" "$FEAT_ID")"
PLAN_FILE="$CHANGE_DIR/feature-plan.json"
GRAPH_FILE="graphify-out/graph.json"
OUTPUT_FILE="$FEAT_DIR/graphify-context.md"

MAX_NODES=30

# ── 前置检查 ──────────────────────────────────────────────────────────────────

if [[ ! -f "$GRAPH_FILE" ]]; then
  echo "[gen-graphify-context] ⏭ graphify-out/graph.json 不存在，跳过" >&2
  exit 0
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "[gen-graphify-context] ⏭ feature-plan.json 不存在，跳过" >&2
  exit 0
fi

mkdir -p "$FEAT_DIR"

# ── 提取目标目录（从 modified_files + new_files 的父目录去重） ─────────────────

TARGET_DIRS=$(jq -r --arg id "$FEAT_ID" '
  (if type == "array" then . else .features end)
  | map(select(.id == $id)) | .[0].proposal_scope // {}
  | ((.modified_files // []) + (.new_files // []))
  | map(split("/") | .[:-1] | join("/"))
  | unique | .[]
' "$PLAN_FILE" 2>/dev/null)

if [[ -z "$TARGET_DIRS" ]]; then
  echo "[gen-graphify-context] ⏭ feature $FEAT_ID 无 proposal_scope 文件路径，跳过" >&2
  exit 0
fi

# ── 从 graph.json 查询相关节点 ────────────────────────────────────────────────

# 构建 jq 过滤条件：source_file 以任一目标目录为前缀
DIR_FILTER=$(echo "$TARGET_DIRS" | while IFS= read -r dir; do
  [[ -z "$dir" ]] && continue
  printf 'startswith("%s/") or ' "$dir"
done)
DIR_FILTER="${DIR_FILTER% or }"

if [[ -z "$DIR_FILTER" ]]; then
  exit 0
fi

# 提取匹配节点（file_type=code 的文件级节点，即 label 以 .dart/.kt/.swift/.vue/.ts 结尾）
MATCHED_NODES=$(jq -r --argjson max "$MAX_NODES" "
  [.nodes[] | select(.source_file != null and (.source_file | ($DIR_FILTER)))]
  | [.[] | select(.label | test(\"\\\\.(dart|kt|swift|vue|ts|js)\$\"))]
  | unique_by(.source_file)
  | .[:$max]
" "$GRAPH_FILE" 2>/dev/null)

NODE_COUNT=$(echo "$MATCHED_NODES" | jq 'length' 2>/dev/null || echo "0")

if [[ "$NODE_COUNT" -eq 0 || "$NODE_COUNT" == "null" ]]; then
  echo "[gen-graphify-context] ⏭ 知识图谱中未找到相关节点，跳过" >&2
  exit 0
fi

# ── 提取关联边（imports/extends/implements/mixin_of） ─────────────────────────

# 收集匹配节点的 id 列表
NODE_IDS=$(echo "$MATCHED_NODES" | jq -r '.[].id')

# 从 links 中提取与这些节点关联的有意义边
RELATED_EDGES=$(echo "$NODE_IDS" | jq -Rs --argjson graph "$(cat "$GRAPH_FILE")" '
  split("\n") | map(select(. != "")) as $ids |
  [$graph.links[] | select(
    (.relation == "imports" or .relation == "extends" or .relation == "implements" or .relation == "mixin_of" or .relation == "uses") and
    ((.source as $s | $ids | any(. == $s)) or (.target as $t | $ids | any(. == $t)))
  )] | .[:100]
' 2>/dev/null || echo "[]")

# ── 生成 markdown 输出 ───────────────────────────────────────────────────────

{
  echo "以下是项目知识图谱中与当前功能涉及目录相关的现有组件："
  echo ""
  echo "### 现有文件"
  echo ""
  echo "| 文件路径 | 组件名 |"
  echo "|---------|--------|"

  echo "$MATCHED_NODES" | jq -r '.[] | "| \(.source_file) | \(.label) |"'

  # 输出关联关系
  EDGE_COUNT=$(echo "$RELATED_EDGES" | jq 'length' 2>/dev/null || echo "0")
  if [[ "$EDGE_COUNT" -gt 0 && "$EDGE_COUNT" != "null" ]]; then
    echo ""
    echo "### 关键依赖关系"
    echo ""
    echo "| 来源 | 关系 | 目标 |"
    echo "|------|------|------|"

    # 构建 id→label 映射用于可读化
    echo "$RELATED_EDGES" | jq -r --argjson nodes "$MATCHED_NODES" '
      ($nodes | map({(.id): .label}) | add // {}) as $labels |
      .[] | "\(.source)" as $s | "\(.target)" as $t |
      "| \($labels[$s] // $s | split("_") | .[-3:] | join("_")) | \(.relation) | \($labels[$t] // $t | split("_") | .[-3:] | join("_")) |"
    ' 2>/dev/null | head -30
  fi

  echo ""
  echo "> 以上信息来自 graphify 知识图谱静态分析，修改现有文件时请先 Read 确认当前实现。"
} > "$OUTPUT_FILE"

echo "✓ graphify-context.md 已生成（${NODE_COUNT} 个相关组件）"
