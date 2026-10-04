#!/bin/bash
set -euo pipefail

# get-dsl.sh — 通过 mcporter 调用 mastergo-proxy MCP 获取设计稿
#
# 策略：D2C 优先（生成 HTML），失败回退到 DSL → getMeta → getComponentLink
# 所有中间数据保留在内存，最终由 filter-dsl.sh 生成 ui_dsl.json + ui_tree.txt
#
# 用法：
#   get-dsl.sh <URL>
#   get-dsl.sh <fileId> [layerId]
#   get-dsl.sh --short-link <shortLink>
#
# 示例：
#   get-dsl.sh https://mastergo.com/goto/TgBrnRPC?page_id=2:12334&layer_id=334:06986&file=190015246063124
#   get-dsl.sh https://mastergo.com/file/190015246063124?page_id=2%3A12334
#   get-dsl.sh 190015246063124 334:06986

OUT_DIR="./mg_dsl"

usage() {
  cat <<'EOF'
用法：
  get-dsl.sh [--out-dir <目录>] <URL 或多个链接的原文>
  get-dsl.sh [--out-dir <目录>] <fileId> [layerId]
  get-dsl.sh [--out-dir <目录>] --short-link <shortLink>
  get-dsl.sh [--out-dir <目录>] --d2c <contentId>
  get-dsl.sh [--out-dir <目录>] mastergo://getd2c/<contentId>

参数：
  --out-dir    可选，指定输出目录（默认 ./mg_dsl）
  URL/原文     支持单个或多个链接，自动从输入中提取 http/https 链接
               多链接时自动并行获取，输出到 001/ 002/ ... 子目录
  fileId       MasterGo 文件 ID（URL 中 file/ 后的数字）
  layerId      可选，图层 ID（URL 中 layer_id/page_id 参数值）
  --short-link 使用 MasterGo 短链接获取
  --d2c        传入 D2C contentId，优先生成 HTML（失败回退到 DSL）

示例：
  # 单链接
  get-dsl.sh https://mastergo.com/goto/TgBrnRPC?page_id=2:12334&layer_id=334:06986&file=190015246063124
  get-dsl.sh --out-dir .dac/my-feature https://mastergo.com/file/190015246063124?layer_id=123:456

  # 多链接（自动并行）
  get-dsl.sh --out-dir ./ui "https://mastergo.com/file/111 https://mastergo.com/file/222"
  get-dsl.sh --out-dir ./ui "链接1, 链接2, 链接3"

  # 其他格式
  get-dsl.sh 190015246063124 334:06986
  get-dsl.sh --d2c 176452330285910-2-2845
EOF
  exit 1
}

# 处理 --out-dir
if [ "${1:-}" = "--out-dir" ]; then
  [ $# -lt 2 ] && usage
  OUT_DIR="$2"
  shift 2
fi

if [ $# -lt 1 ]; then
  usage
fi

# ---------- 多链接自动检测 ----------
# 将所有剩余参数合并，提取 http/https 链接
_ALL_INPUT="$*"
# bash 3.2 compatible — no mapfile
_LINKS=()
while IFS= read -r _line; do
  [ -n "$_line" ] && _LINKS+=("$_line")
done < <(echo "$_ALL_INPUT" | grep -oE 'https?://[^[:space:],，]+' | sed 's/[,，]*$//')

if [ ${#_LINKS[@]} -eq 0 ]; then
  # 非 URL 输入（可能是 fileId 或 --short-link），走原有单链接逻辑
  if [[ "$1" =~ ^[0-9]+$ ]] || [[ "$1" == "--short-link" ]] || [[ "$1" == "--d2c" ]] || [[ "$1" =~ ^mastergo:// ]]; then
    : # 继续执行原有逻辑
  else
    echo "❌ 未检测到有效链接（需包含 http:// 或 https://）" >&2
    echo "   收到的输入：$_ALL_INPUT" >&2
    echo "" >&2
    echo "   支持的格式：" >&2
    echo "     • MasterGo 完整链接（https://mastergo.com/...）" >&2
    echo "     • 多个链接用空格/逗号/换行分隔" >&2
    echo "     • fileId（纯数字）" >&2
    echo "     • --short-link <短链接>" >&2
    exit 1
  fi
elif [ ${#_LINKS[@]} -gt 1 ]; then
  # 多链接模式：自动并行
  echo "🚀 检测到 ${#_LINKS[@]} 个设计稿链接，并行获取 ..." >&2
  echo "" >&2

  SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  MAX_JOBS=3
  PIDS=()
  DIRS=()
  INDEX=1

  for LINK in "${_LINKS[@]}"; do
    DIR=$(printf "%03d" $INDEX)
    mkdir -p "$OUT_DIR/$DIR"
    DIRS+=("$OUT_DIR/$DIR")

    echo "   [$DIR] $LINK" >&2
    echo "$LINK" > "$OUT_DIR/$DIR/.source_link"
    bash "$SELF" --out-dir "$OUT_DIR/$DIR" "$LINK" > "$OUT_DIR/$DIR/.fetch.log" 2>&1 &
    PIDS+=($!)
    INDEX=$((INDEX + 1))

    # 并发限流
    if [ ${#PIDS[@]} -ge $MAX_JOBS ]; then
      wait "${PIDS[0]}" 2>/dev/null || true
      PIDS=("${PIDS[@]:1}")
    fi
  done

  # 等待剩余任务
  for PID in "${PIDS[@]}"; do
    wait "$PID" 2>/dev/null || true
  done

  # 汇总结果
  echo "" >&2
  FAIL_COUNT=0
  for DIR in "${DIRS[@]}"; do
    if [ -f "$DIR/ui_dsl.json" ] || find "$DIR" -name "*.html" -print -quit 2>/dev/null | grep -q .; then
      echo "   ✅ $(basename "$DIR") 成功" >&2
    else
      echo "   ❌ $(basename "$DIR") 失败（详见 $DIR/.fetch.log）" >&2
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  done

  echo "" >&2
  echo "✅ 并行获取完成：$((${#DIRS[@]} - FAIL_COUNT))/${#DIRS[@]} 成功" >&2
  if [ "$FAIL_COUNT" -eq "${#DIRS[@]}" ]; then
    echo "❌ 全部设计稿获取失败" >&2
    exit 1
  fi
  if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "⚠️  部分失败（$FAIL_COUNT），已有 ui_dsl.json 的目录可继续写 spec / codegen" >&2
  fi
  exit 0
fi

# ---------- 单链接模式（原有逻辑）----------
# 如果从多链接检测中提取到恰好 1 个 URL，规范化参数
if [ ${#_LINKS[@]} -eq 1 ]; then
  set -- "${_LINKS[0]}"
fi

# ---------- 参数解析 ----------
FILE_ID=""
LAYER_ID=""
SHORT_LINK=""
D2C_CONTENT_ID=""

# 从 contentId 推导 fileId 和 layerId（用于 DSL 回退）
parse_content_id() {
  D2C_CONTENT_ID="$1"
  FILE_ID=$(echo "$D2C_CONTENT_ID" | cut -d'-' -f1)
  _seg2=$(echo "$D2C_CONTENT_ID" | cut -d'-' -f2)
  _seg3=$(echo "$D2C_CONTENT_ID" | cut -d'-' -f3)
  [ -n "$_seg2" ] && [ -n "$_seg3" ] && LAYER_ID="${_seg2}:${_seg3}"
}

# 处理 --d2c 标志
if [ "$1" = "--d2c" ]; then
  [ $# -lt 2 ] && usage
  parse_content_id "$2"
  shift 2
fi

if [ -z "$D2C_CONTENT_ID" ] && [ $# -lt 1 ]; then
  usage
fi

if [ -n "$D2C_CONTENT_ID" ]; then
  : # 已解析
elif [[ "$1" =~ ^mastergo://getd2c/ ]]; then
  parse_content_id "$(echo "$1" | sed 's|mastergo://getd2c/||')"
elif [ "$1" = "--short-link" ]; then
  [ $# -lt 2 ] && usage
  SHORT_LINK="$2"
elif [[ "$1" =~ ^https?:// ]]; then
  URL="$1"
  DECODED_URL=$(echo "$URL" | sed 's/%3[Aa]/:/g')
  PARAM_FILE_ID=$(echo "$DECODED_URL" | grep -oE '[?&]file=[0-9]+' | grep -oE '[0-9]+' | head -1 || true)
  PATH_FILE_ID=$(echo "$DECODED_URL" | grep -oE 'file/[0-9]+' | grep -oE '[0-9]+' | head -1 || true)
  LAYER_ID=$(echo "$DECODED_URL" | grep -oE 'layer_id=[^&]+' | head -1 | cut -d= -f2 || true)
  [ -z "$LAYER_ID" ] && LAYER_ID=$(echo "$DECODED_URL" | grep -oE 'page_id=[^&]+' | head -1 | cut -d= -f2 || true)

  if [ -n "$PARAM_FILE_ID" ]; then
    FILE_ID="$PARAM_FILE_ID"
  elif [ -n "$PATH_FILE_ID" ]; then
    FILE_ID="$PATH_FILE_ID"
  elif [[ "$URL" =~ /goto/ ]]; then
    SHORT_LINK="$URL"
  else
    echo "❌ 无法从 URL 提取 fileId：$URL"
    exit 1
  fi
else
  FILE_ID="$1"
  LAYER_ID="${2:-}"
fi

mkdir -p "$OUT_DIR"

# ---------- 辅助函数 ----------

# mcporter 调用单服务器（带重试）
_call_mcp_server() {
  local SERVER="$1"
  local TOOL="$2"
  shift 2
  local MAX_RETRIES=2
  local RETRY=0
  local OUTPUT=""
  local EXIT_CODE=0

  while [ $RETRY -le $MAX_RETRIES ]; do
    if [ $RETRY -gt 0 ]; then
      echo "   🔄 重试 ($RETRY/$MAX_RETRIES) ..." >&2
      sleep "$RETRY"
    fi

    EXIT_CODE=0
    OUTPUT=$(mcporter call "${SERVER}.${TOOL}" "$@" 2>&1) || EXIT_CODE=$?

    if echo "$OUTPUT" | grep -q "status: 504\|Gateway Time-out\|ETIMEDOUT\|ECONNRESET"; then
      RETRY=$((RETRY + 1))
      if [ $RETRY -gt $MAX_RETRIES ]; then
        echo "$OUTPUT" >&2
        return 1
      fi
      echo "   ⚠️  服务端超时..." >&2
    elif [ $EXIT_CODE -ne 0 ]; then
      echo "$OUTPUT" >&2
      return 1
    elif echo "$OUTPUT" | grep -qi "error\|failed\|Cannot read\|not found\|ECONNREFUSED"; then
      echo "$OUTPUT" >&2
      return 1
    else
      echo "$OUTPUT"
      return 0
    fi
  done
}

# mcporter 调用（mastergo-proxy 优先，失败回退 mastergo_food）
call_mcp() {
  local TOOL="$1"
  shift

  local OUTPUT=""
  OUTPUT=$(_call_mcp_server "mastergo-proxy" "$TOOL" "$@" 2>/dev/null) && {
    echo "$OUTPUT"
    return 0
  }

  echo "   ⚠️  mastergo-proxy 获取失败，尝试 mastergo_food ..." >&2
  _call_mcp_server "mastergo_food" "$TOOL" "$@"
}

# 从 mcporter 输出中提取纯 JSON（跳过非 JSON 行，取第一个 {/[ 起始块）
extract_json() {
  awk '/^[{\[]/{ found=1 } found{ print }'
}

# 解包 MCP content wrapper：{content:[{text:"..."}]} → 内层 JSON
unwrap_mcp() {
  jq '
    if .content and (.content | type) == "array" and (.content | length) > 0 and (.content[0].text? != null)
    then (.content[0].text | if type == "string" then fromjson else . end)
    else . end
  '
}

# ---------- 策略 1：D2C（生成 HTML） ----------

try_d2c() {
  if [ -z "$D2C_CONTENT_ID" ]; then
    return 1
  fi

  local DOC_ID
  DOC_ID=$(echo "$D2C_CONTENT_ID" | cut -d'-' -f1)
  local D2C_OUT_DIR="$OUT_DIR/d2c_${D2C_CONTENT_ID//[-:]/_}"

  mkdir -p "$D2C_OUT_DIR"

  echo "🎨 [策略 1] D2C 生成 HTML ..." >&2
  echo "   contentId=$D2C_CONTENT_ID, documentId=$DOC_ID" >&2

  local RAW
  RAW=$(call_mcp mcp__getD2c contentId="$D2C_CONTENT_ID" documentId="$DOC_ID" outDir="$D2C_OUT_DIR") || {
    echo "   ❌ D2C 调用失败，回退到 DSL" >&2
    return 1
  }

  if echo "$RAW" | grep -qi "error\|failed\|Cannot read\|not found\|undefined"; then
    echo "   ❌ D2C 返回错误，回退到 DSL" >&2
    return 1
  fi

  local HTML_FILES
  HTML_FILES=$(find "$D2C_OUT_DIR" -name "*.html" 2>/dev/null | head -5)
  if [ -z "$HTML_FILES" ]; then
    echo "   ❌ D2C 未生成 HTML 文件，回退到 DSL" >&2
    return 1
  fi

  echo "" >&2
  echo "✅ D2C 完成！" >&2
  echo "   输出目录：$D2C_OUT_DIR" >&2
  echo "   HTML 文件：" >&2
  find "$D2C_OUT_DIR" -name "*.html" -exec echo "     {}" \; >&2
  return 0
}

# ---------- 策略 2：DSL → getMeta → getComponentLink ----------

try_dsl() {
  echo "📋 [策略 2] DSL 获取 ..." >&2

  local CALL_ARGS=()
  if [ -n "$SHORT_LINK" ]; then
    CALL_ARGS=(shortLink="$SHORT_LINK")
    echo "   🔗 shortLink=$SHORT_LINK" >&2
  elif [ -n "$LAYER_ID" ]; then
    CALL_ARGS=(fileId="$FILE_ID" layerId="$LAYER_ID")
    echo "   📐 fileId=$FILE_ID, layerId=$LAYER_ID" >&2
  else
    CALL_ARGS=(fileId="$FILE_ID")
    echo "   📄 fileId=$FILE_ID" >&2
  fi

  # 获取 DSL
  local RAW
  RAW=$(call_mcp mcp__getDsl "${CALL_ARGS[@]}") || {
    echo "   ❌ getDsl 持续超时" >&2
    exit 1
  }

  DSL_JSON=$(echo "$RAW" | extract_json | unwrap_mcp)

  if ! echo "$DSL_JSON" | jq empty 2>/dev/null; then
    echo "   ❌ getDsl 返回非 JSON" >&2
    exit 1
  fi

  if echo "$DSL_JSON" | jq -e '.error // .isError // empty' &>/dev/null; then
    echo "   ❌ getDsl 返回错误响应" >&2
    exit 1
  fi

  echo "   ✓ DSL 获取成功" >&2
  GOT_DATA=true

  # getMeta（需要 fileId + layerId）
  if [ -n "$FILE_ID" ] && [ -n "$LAYER_ID" ]; then
    echo "   📊 获取 Meta ..." >&2
    local META_RAW
    META_RAW=$(call_mcp mcp__getMeta fileId="$FILE_ID" layerId="$LAYER_ID") || true
    local META_JSON
    META_JSON=$(echo "$META_RAW" | extract_json)

    _meta_ok=false
    if echo "$META_JSON" | jq -e 'type == "object" or type == "array"' >/dev/null 2>&1; then
      _meta_tmp=$(mktemp)
      printf '%s' "$META_JSON" > "$_meta_tmp"
      if _merged=$(echo "$DSL_JSON" | jq --slurpfile meta "$_meta_tmp" '. + {meta: $meta[0]}' 2>/dev/null); then
        DSL_JSON="$_merged"
        _meta_ok=true
        echo "   ✓ Meta 已合并" >&2
      fi
      rm -f "$_meta_tmp"
    fi
    if [ "$_meta_ok" != true ]; then
      echo "   ⚠️  getMeta 失败，跳过（DSL 已保留）" >&2
    fi
  fi

  # getComponentLink（从 DSL 中提取 componentDocumentLinks）
  local COMP_LINKS
  COMP_LINKS=$(echo "$DSL_JSON" | jq -r '.componentDocumentLinks // [] | .[]' 2>/dev/null || true)

  if [ -n "$COMP_LINKS" ]; then
    echo "   🔗 获取组件文档 ..." >&2
    local COMP_ARRAY="[]"
    while IFS= read -r LINK; do
      [ -z "$LINK" ] && continue
      local COMP_RAW
      COMP_RAW=$(call_mcp mcp__getComponentLink url="$LINK") || true
      local COMP_JSON
      COMP_JSON=$(echo "$COMP_RAW" | extract_json)
      if echo "$COMP_JSON" | jq -e 'type == "object" or type == "array"' >/dev/null 2>&1; then
        _c_tmp=$(mktemp)
        printf '%s' "$COMP_JSON" > "$_c_tmp"
        if _carr=$(echo "$COMP_ARRAY" | jq --slurpfile c "$_c_tmp" '. + $c' 2>/dev/null); then
          COMP_ARRAY="$_carr"
          echo "   ✓ 组件已获取" >&2
        fi
        rm -f "$_c_tmp"
      fi
    done <<< "$COMP_LINKS"

    if [ "$(echo "$COMP_ARRAY" | jq 'length')" -gt 0 ]; then
      _comp_tmp=$(mktemp)
      printf '%s' "$COMP_ARRAY" > "$_comp_tmp"
      if _d2=$(echo "$DSL_JSON" | jq --slurpfile comps "$_comp_tmp" '. + {components: $comps[0]}' 2>/dev/null); then
        DSL_JSON="$_d2"
        echo "   ✓ 组件文档已合并" >&2
      else
        echo "   ⚠️  组件文档合并失败，跳过（DSL 已保留）" >&2
      fi
      rm -f "$_comp_tmp"
    fi
  fi
}

# ---------- 主流程 ----------

echo "🚀 MasterGo 设计稿获取" >&2
echo "   fileId=${FILE_ID:-N/A} layerId=${LAYER_ID:-N/A} shortLink=${SHORT_LINK:-N/A}" >&2
echo "" >&2

DSL_JSON=""
GOT_DATA=false

if try_d2c; then
  exit 0
fi

try_dsl

if [ "$GOT_DATA" != "true" ]; then
  echo "❌ 未获取到任何设计稿数据" >&2
  exit 1
fi

# 通过 filter-dsl.sh 过滤并生成最终产物
FILTER_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/filter-dsl.sh"
if [ -f "$FILTER_SCRIPT" ]; then
  echo "   🔧 过滤 DSL ..." >&2
  if ! bash "$FILTER_SCRIPT" --input <(echo "$DSL_JSON") --output "$OUT_DIR"; then
    echo "   ⚠️  filter-dsl.sh 解析失败，降级写入原始 DSL" >&2
    echo "$DSL_JSON" > "$OUT_DIR/ui_dsl.json"
  fi
else
  echo "   ⚠️  filter-dsl.sh 不存在，直接写入原始数据" >&2
  echo "$DSL_JSON" > "$OUT_DIR/ui_dsl.json"
fi

echo "" >&2
echo "✅ 完成！输出目录：$OUT_DIR" >&2
[ -f "$OUT_DIR/ui_dsl.json" ] && echo "   DSL：$OUT_DIR/ui_dsl.json" >&2
[ -f "$OUT_DIR/ui_tree.txt" ] && echo "   Tree：$OUT_DIR/ui_tree.txt" >&2
