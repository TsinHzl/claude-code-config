#!/usr/bin/env bash
# test-pre-trim.sh — 从 Cooper 拉取文档并验证 pre-trim.sh 裁剪逻辑
#
# 用法：
#   bash test-pre-trim.sh <Cooper URL> [关键词]
#
# 示例：
#   bash test-pre-trim.sh https://cooper.didichuxing.com/knowledge/2204291401492/2207251345848
#   bash test-pre-trim.sh https://cooper.didichuxing.com/knowledge/2204291401492/2207251345848 "乘客,前端"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRE_TRIM="$SCRIPT_DIR/pre-trim.sh"

if [ ! -f "$PRE_TRIM" ]; then
  echo "❌ 找不到 pre-trim.sh: $PRE_TRIM"
  exit 1
fi

# mcporter 路径检测
MCPORTER=""
if command -v mcporter &>/dev/null; then
  MCPORTER="mcporter"
elif [ -x "$(npm prefix -g 2>/dev/null)/bin/mcporter" ]; then
  MCPORTER="$(npm prefix -g)/bin/mcporter"
else
  echo "❌ mcporter 未安装，请运行: npm install -g mcporter"
  exit 1
fi

# ─────────────────────────────────────────────
# 参数解析
# ─────────────────────────────────────────────
if [ $# -lt 1 ]; then
  echo "❌ 用法: test-pre-trim.sh <Cooper URL> [关键词]"
  echo "   关键词默认为 '司机端'，支持逗号分隔多个"
  exit 1
fi

URL="$1"
KEYWORDS="${2:-司机端}"

# ─────────────────────────────────────────────
# URL 解析：提取 appId / spaceId / resourceId
# ─────────────────────────────────────────────
APP_ID=""
SPACE_ID=""
RESOURCE_ID=""

if echo "$URL" | grep -q "knowledge"; then
  APP_ID=4
fi

# 提取路径中的数字段
NUMBERS=($(echo "$URL" | grep -oE '[0-9]{10,}'))

if [ ${#NUMBERS[@]} -ge 2 ]; then
  SPACE_ID="${NUMBERS[0]}"
  RESOURCE_ID="${NUMBERS[1]}"
elif [ ${#NUMBERS[@]} -eq 1 ]; then
  RESOURCE_ID="${NUMBERS[0]}"
fi

if [ -z "$APP_ID" ]; then
  echo "❌ 无法从 URL 识别 appId（URL 需包含 'knowledge'）"
  exit 1
fi

if [ -z "$SPACE_ID" ] || [ -z "$RESOURCE_ID" ]; then
  echo "❌ 无法从 URL 解析出 spaceId 和 resourceId"
  echo "   URL: $URL"
  echo "   解析到的数字段: ${NUMBERS[*]:-无}"
  exit 1
fi

echo "📎 解析结果：appId=$APP_ID, spaceId=$SPACE_ID, resourceId=$RESOURCE_ID"
echo "📎 提取关键词：$KEYWORDS"
echo ""

# ─────────────────────────────────────────────
# 调用 mcporter 获取文档内容
# ─────────────────────────────────────────────
echo "⏳ 正在从 Cooper 获取文档..."
echo "   命令：$MCPORTER call Cooper.readContent spaceId=\"$SPACE_ID\" resourceId=\"$RESOURCE_ID\" appId=$APP_ID range=\"\" --output json"

set +e
RESPONSE=$("$MCPORTER" call Cooper.readContent \
  spaceId="$SPACE_ID" \
  resourceId="$RESOURCE_ID" \
  appId="$APP_ID" \
  range="" \
  --output json 2>&1)
MC_EXIT=$?
set -e

if [ $MC_EXIT -ne 0 ]; then
  echo "❌ mcporter 调用失败（exit code: $MC_EXIT）："
  echo "$RESPONSE"
  exit 1
fi

# 提取内容：mcporter 返回可能是 JSON 字符串或 JSON 对象
JSON_TYPE=$(echo "$RESPONSE" | jq -r 'type' 2>/dev/null || echo "unknown")

if [ "$JSON_TYPE" = "string" ]; then
  CONTENT=$(echo "$RESPONSE" | jq -r '.')
elif [ "$JSON_TYPE" = "object" ]; then
  CONTENT=$(echo "$RESPONSE" | jq -r '.content // .result // .data // empty')
else
  CONTENT="$RESPONSE"
fi

if [ -z "$CONTENT" ] || [ "$CONTENT" = "null" ]; then
  echo "❌ 获取文档内容为空，mcporter 原始返回："
  echo "$RESPONSE" | head -50
  exit 1
fi

TMP_DIR=$(mktemp -d)
RAW_FILE="$TMP_DIR/raw-prd.md"
TRIMMED_FILE="$TMP_DIR/trimmed-prd.md"

echo "$CONTENT" > "$RAW_FILE"
read -r RAW_LINES RAW_CHARS <<< "$(wc -lm < "$RAW_FILE" | xargs)"
echo "✅ 文档获取成功：$RAW_LINES 行 / $RAW_CHARS 字符"
echo ""

# ─────────────────────────────────────────────
# 调用 pre-trim.sh 执行裁剪
# ─────────────────────────────────────────────
echo "⏳ 正在执行预裁剪..."
echo "─────────────────────────────────────────────"
bash "$PRE_TRIM" --input "$RAW_FILE" --keywords "$KEYWORDS" --output "$TRIMMED_FILE"
echo "─────────────────────────────────────────────"
echo ""
echo "🔍 裁剪结果预览（前 30 行）："
echo "─────────────────────────────────────────────"
head -30 "$TRIMMED_FILE"
echo ""
echo "─────────────────────────────────────────────"
echo ""
echo "📁 临时文件保留在：$TMP_DIR"
echo "   原始文档：$RAW_FILE"
echo "   裁剪结果：$TRIMMED_FILE"
