#!/usr/bin/env bash
# extract-constraints.sh [feat_id]
# 从 cr-report.md 提取 🔴 和 🟡 问题，格式化后追加到 .dac/knowledge/constraints.md
# 由 dac-code-review 步骤 5 完成后自动调用

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法: extract-constraints.sh <feat_id>" >&2
  exit 1
fi

FEAT_ID=$1
STATE_FILE=".dac/state.json"
REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE" 2>/dev/null)
if [[ -z "$REQ_NAME" ]]; then
  echo "❌ extract-constraints：state.json 中缺少 req_name" >&2
  exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPTS_DIR/paths.sh"
REPORT="$(get_feat_dir "$REQ_NAME" "$FEAT_ID")/cr-report.md"
CONSTRAINTS=".dac/knowledge/constraints.md"
DATE=$(date +%Y-%m-%d)

# 协作模式：openspec/changes/{req}/collab.json 存在时，把 constraints 副本写到
# openspec/changes/{req}/knowledge/constraints.md，随规划一起入库，供对方 git pull
COLLAB_JSON="$(get_change_dir "$REQ_NAME")/collab.json"
COLLAB_CONSTRAINTS=""
if [[ -f "$COLLAB_JSON" ]]; then
  COLLAB_CONSTRAINTS="$(get_change_dir "$REQ_NAME")/knowledge/constraints.md"
  mkdir -p "$(dirname "$COLLAB_CONSTRAINTS")"
  [[ -f "$COLLAB_CONSTRAINTS" ]] || : > "$COLLAB_CONSTRAINTS"
fi

if [[ ! -f "$REPORT" ]]; then
  echo "❌ cr-report.md 不存在：$REPORT"
  exit 1
fi

if [[ ! -f "$CONSTRAINTS" ]]; then
  echo "❌ constraints.md 不存在，请先运行 scripts/init-dac.sh"
  exit 1
fi

# 提取所有严重/一般问题块（从 🔴/🟡 行开始到下一个 ### 头部为止）
TMP_ISSUES=$(mktemp)
trap 'rm -f "$TMP_ISSUES"' EXIT

awk '
  /^### 🔴|^### 🟡/ { found=1; next }
  /^### /            { found=0; next }
  found              { print }
' "$REPORT" \
  > "$TMP_ISSUES"

if [[ -s "$TMP_ISSUES" ]]; then
  # 去重检查 1：同日同功能是否已提取过
  if grep -qF "## [$DATE] $FEAT_ID" "$CONSTRAINTS" 2>/dev/null; then
    echo "ℹ️  约束已存在（$FEAT_ID, ${DATE}），跳过重复追加"
    exit 0
  fi

  # 跨平台 md5 计算（macOS: md5 -qs, Linux: md5sum）
  compute_hash() {
    if command -v md5 &>/dev/null; then
      md5 -qs "$1"
    elif command -v md5sum &>/dev/null; then
      printf '%s' "$1" | md5sum | cut -c1-32
    else
      printf '%s' "$1" | python3 -c "import sys,hashlib; print(hashlib.md5(sys.stdin.buffer.read()).hexdigest())"
    fi
  }

  # 去重检查 2：基于 hash 精确去重
  ALREADY_EXISTS=0
  TOTAL_LINES=0
  NEW_HASHES=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    TOTAL_LINES=$((TOTAL_LINES + 1))
    # 构建去重 key：[维度标签] + 文件路径
    DIMENSION=$(echo "$line" | grep -oE '\[[^]]+\]' | head -1)
    FILE_PATH=$(echo "$line" | grep -oE '`[^`]+\.(dart|yaml|json)[^`]*`' | head -1)
    if [[ -n "$DIMENSION" && -n "$FILE_PATH" ]]; then
      DEDUP_KEY="${DIMENSION}${FILE_PATH}"
    elif [[ -n "$DIMENSION" ]]; then
      DEDUP_KEY="${DIMENSION}$(echo "$line" | head -c 80)"
    else
      DEDUP_KEY=$(echo "$line" | head -c 80)
    fi
    HASH=$(compute_hash "$DEDUP_KEY" | cut -c1-16)
    NEW_HASHES+=("$HASH")
    if grep -qF "$HASH" "$CONSTRAINTS" 2>/dev/null; then
      ALREADY_EXISTS=$((ALREADY_EXISTS + 1))
    fi
  done < <(grep -E '^[0-9]+\.|^[-*] ' "$TMP_ISSUES")

  if [[ $TOTAL_LINES -gt 0 ]] && [[ $((ALREADY_EXISTS * 100 / TOTAL_LINES)) -ge 80 ]]; then
    echo "ℹ️  约束内容 80%+ 已存在，跳过重复追加（$ALREADY_EXISTS/$TOTAL_LINES 条已有）"
    exit 0
  fi

  # 追加新约束（带来源追溯 + hash 去重标记）
  HASH_LIST=$(IFS=,; echo "${NEW_HASHES[*]}")
  echo "" >> "$CONSTRAINTS"
  echo "## [$DATE] $FEAT_ID" >> "$CONSTRAINTS"
  echo "<!-- source: $FEAT_ID | extracted: $DATE | dedup-keys: $HASH_LIST -->" >> "$CONSTRAINTS"
  cat "$TMP_ISSUES" >> "$CONSTRAINTS"
  COUNT=$(grep -cE '^[0-9]+\.|^[-*] ' "$TMP_ISSUES" 2>/dev/null || echo "0")
  echo "✅ 已提取 $COUNT 条约束到 constraints.md（来源：$FEAT_ID CR）"

  # 协作模式：镜像写到 openspec 副本（幂等：同日同 feat 已有则跳过）
  if [[ -n "$COLLAB_CONSTRAINTS" ]]; then
    if grep -qF "## [$DATE] $FEAT_ID" "$COLLAB_CONSTRAINTS" 2>/dev/null; then
      echo "ℹ️  openspec 副本已含 [$DATE] $FEAT_ID，跳过双写"
    else
      echo "" >> "$COLLAB_CONSTRAINTS"
      echo "## [$DATE] $FEAT_ID" >> "$COLLAB_CONSTRAINTS"
      echo "<!-- source: $FEAT_ID | extracted: $DATE | dedup-keys: $HASH_LIST -->" >> "$COLLAB_CONSTRAINTS"
      cat "$TMP_ISSUES" >> "$COLLAB_CONSTRAINTS"
      echo "✅ 已镜像到 openspec 副本：$COLLAB_CONSTRAINTS"
    fi
  fi
else
  echo "ℹ️  无需提取约束（CR 无严重/一般问题）"
fi
