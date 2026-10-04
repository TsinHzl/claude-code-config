#!/usr/bin/env bash
# pre-trim.sh — PRD 文档预裁剪（章节级粗过滤）
# 按关键词对 Markdown 文档做确定性裁剪，减少传给 LLM 的体积。
#
# 用法：
#   模式 A（本地文件）：
#     bash pre-trim.sh --input <原始文档> --keywords <关键词> --output <输出文件>
#
#   模式 B（从 Cooper 直接拉取，手动指定参数）：
#     bash pre-trim.sh --cooper <resourceId> --app-id <appId> --keywords <关键词> --output <输出文件> [--raw <原始文件保存路径>]
#
#   模式 C（从 URL 自动解析，推荐）：
#     bash pre-trim.sh --url "<Cooper URL> [关键词]" --output <输出文件> [--raw <原始文件保存路径>]
#     bash pre-trim.sh --url "<Cooper URL>" --output <raw.md> --raw <raw.md> --skip-trim   # 只下载不裁剪
#
# 示例：
#   bash pre-trim.sh --input raw-prd.md --keywords "司机" --output trimmed.md
#   bash pre-trim.sh --cooper 2207083621002 --app-id 4 --keywords "司机" --output trimmed.md --raw raw-prd.md
#   bash pre-trim.sh --url "https://cooper.didichuxing.com/knowledge/12345/67890 司机" --output trimmed.md

set -euo pipefail

# ─────────────────────────────────────────────
# 工具函数
# ─────────────────────────────────────────────
file_size() { stat -f%z "$1" 2>/dev/null || stat --format=%s "$1" 2>/dev/null || echo 0; }

# 统一临时文件清理
_TMPFILES=()
mktmp() { local f; f=$(mktemp); _TMPFILES+=("$f"); echo "$f"; }
cleanup_tmp() { [ ${#_TMPFILES[@]} -gt 0 ] && rm -f "${_TMPFILES[@]}" 2>/dev/null; return 0; }
trap cleanup_tmp EXIT

# ─────────────────────────────────────────────
# 参数解析
# ─────────────────────────────────────────────
INPUT=""
KEYWORDS=""
OUTPUT=""
COOPER_RESOURCE=""
COOPER_APP_ID=""
RAW_OUTPUT=""
URL_INPUT=""
SKIP_TRIM=false

while [ $# -gt 0 ]; do
  case "$1" in
    --input)  [ $# -lt 2 ] && { echo "❌ --input 需要一个参数"; exit 1; }; INPUT="$2"; shift 2 ;;
    --url)    [ $# -lt 2 ] && { echo "❌ --url 需要一个参数"; exit 1; }; URL_INPUT="$2"; shift 2 ;;
    --cooper) [ $# -lt 2 ] && { echo "❌ --cooper 需要一个参数"; exit 1; }; COOPER_RESOURCE="$2"; shift 2 ;;
    --skip-trim) SKIP_TRIM=true; shift ;;
    --app-id) [ $# -lt 2 ] && { echo "❌ --app-id 需要一个参数"; exit 1; }; COOPER_APP_ID="$2"; shift 2 ;;
    --raw)    [ $# -lt 2 ] && { echo "❌ --raw 需要一个参数"; exit 1; }; RAW_OUTPUT="$2"; shift 2 ;;
    --keywords) [ $# -lt 2 ] && { echo "❌ --keywords 需要一个参数"; exit 1; }; KEYWORDS="$2"; shift 2 ;;
    --output) [ $# -lt 2 ] && { echo "❌ --output 需要一个参数"; exit 1; }; OUTPUT="$2"; shift 2 ;;
    --min-hits) shift 2 ;;  # 已废弃，忽略该参数
    *) echo "❌ 未知参数: $1"; exit 1 ;;
  esac
done

# ─────────────────────────────────────────────
# --url 模式：从用户输入解析 resourceId、appId、keywords
# 格式：<Cooper URL> [关键词]（关键词可选，默认"司机端"）
# ─────────────────────────────────────────────
if [ -n "$URL_INPUT" ]; then
  # 分离 URL 和关键词（URL 为第一段，其余为关键词）
  URL_PART=$(echo "$URL_INPUT" | awk '{print $1}')
  KW_PART=$(echo "$URL_INPUT" | awk '{$1=""; print}' | sed 's/^ *//')

  # 解析 appId：路径含 /knowledge/ 则为知识库
  if echo "$URL_PART" | grep -q '/knowledge/'; then
    COOPER_APP_ID=4
  else
    COOPER_APP_ID=2
  fi

  # 解析 resourceId：URL 路径中最后一段数字
  COOPER_RESOURCE=$(echo "$URL_PART" | grep -oE '[0-9]+' | tail -1)

  if [ -z "$COOPER_RESOURCE" ]; then
    echo "❌ 无法从 URL 中解析 resourceId：$URL_PART"
    exit 1
  fi

  # 关键词：用户未提供则默认"司机端"
  if [ -n "$KW_PART" ]; then
    KEYWORDS="$KW_PART"
  elif [ -z "$KEYWORDS" ]; then
    KEYWORDS="司机端"
  fi
fi

# ─────────────────────────────────────────────
# Cooper 模式：通过 mcporter 直接拉取文档
# ─────────────────────────────────────────────
if [ -n "$COOPER_RESOURCE" ]; then
  [ -z "$COOPER_APP_ID" ] && COOPER_APP_ID=4
  if [ "$SKIP_TRIM" != true ]; then
    [ -z "$KEYWORDS" ] && { echo "❌ --cooper 模式需要 --keywords 参数"; exit 1; }
  fi
  [ -z "$OUTPUT" ] && { echo "❌ --cooper 模式需要 --output 参数"; exit 1; }

  echo "📥 从 Cooper 获取文档（resourceId=${COOPER_RESOURCE}, appId=${COOPER_APP_ID}）..."

  # 通过 mcporter 获取文档内容（返回 JSON，需提取 text 字段并还原换行）
  _COOPER_RAW_TMP=$(mktmp)
  _COOPER_TMP=$(mktmp)
  if ! mcporter call Cooper.readContent resourceId="$COOPER_RESOURCE" appId="$COOPER_APP_ID" range="" --output json > "$_COOPER_RAW_TMP" 2>/dev/null; then
    echo "❌ mcporter 调用失败，请检查 mcporter 配置和 Cooper 权限"
    exit 1
  fi

  # mcporter --output json 返回 JSON 编码的字符串（\n 为转义换行），用 jq -r 解码
  if command -v jq &>/dev/null; then
    jq -r 'if type == "object" then (.content[0].text // .text // tostring) else . end' "$_COOPER_RAW_TMP" > "$_COOPER_TMP" 2>/dev/null || cp "$_COOPER_RAW_TMP" "$_COOPER_TMP"
  elif command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
with open('$_COOPER_RAW_TMP') as f:
    data = json.load(f)
if isinstance(data, str):
    sys.stdout.write(data)
elif isinstance(data, dict):
    text = data.get('content', [{}])[0].get('text', '') if 'content' in data else data.get('text', '')
    sys.stdout.write(text or json.dumps(data))
else:
    sys.stdout.write(str(data))
" > "$_COOPER_TMP"
  else
    cp "$_COOPER_RAW_TMP" "$_COOPER_TMP"
  fi
  # 检查内容是否有效
  if [ ! -s "$_COOPER_TMP" ]; then
    echo "❌ Cooper 返回内容为空，请检查 resourceId 是否正确"
    exit 1
  fi

  # 检查是否为有效 Markdown（非 HTML 错误页）
  if grep -qiE '<html|<!DOCTYPE' "$_COOPER_TMP"; then
    echo "❌ Cooper 返回内容疑似 HTML 错误页（非 Markdown），请检查网络或权限"
    exit 1
  fi
  if ! grep -qE '^#{1,6} ' "$_COOPER_TMP"; then
    echo "⚠️  警告：Cooper 返回内容中未发现 Markdown 标题，裁剪效果可能不佳"
  fi

  # 修复表格列数偏移：Cooper 导出 rowspan 合并单元格时会丢弃该列，导致数据行列数少于 header
  _FIXED_TMP=$(mktmp)
  LC_ALL=en_US.UTF-8 awk '
  BEGIN { in_table = 0; header_pipes = 0 }
  !/^\|/ {
    in_table = 0
    header_pipes = 0
    print
    next
  }
  /^\|/ {
    line = $0
    tmp = line
    current_pipes = gsub(/\|/, "|", tmp)
    if (!in_table) {
      in_table = 1
      header_pipes = current_pipes
      print line
      next
    }
    if (current_pipes < header_pipes) {
      deficit = header_pipes - current_pipes
      padding = ""
      for (i = 1; i <= deficit; i++) padding = padding " |"
      sub(/^\|/, "|" padding, line)
    }
    print line
  }' "$_COOPER_TMP" > "$_FIXED_TMP" && mv "$_FIXED_TMP" "$_COOPER_TMP"

  INPUT="$_COOPER_TMP"

  # 如果指定了 --raw，保存一份原始文件
  if [ -n "$RAW_OUTPUT" ]; then
    mkdir -p "$(dirname "$RAW_OUTPUT")"
    cp "$_COOPER_TMP" "$RAW_OUTPUT"
    echo "   原始文档已保存：$RAW_OUTPUT"
  fi

  if [ "$SKIP_TRIM" = true ]; then
    mkdir -p "$(dirname "$OUTPUT")"
    cp "$_COOPER_TMP" "$OUTPUT"
    echo "⏭ 跳过预裁剪（--skip-trim），已写出 $OUTPUT"
    exit 0
  fi

elif [ -z "$INPUT" ] || [ -z "$OUTPUT" ]; then
  echo "❌ 缺少必要参数"
  echo "用法 A: pre-trim.sh --input <文件> --keywords <关键词> --output <输出>"
  echo "用法 B: pre-trim.sh --cooper <resourceId> --app-id <appId> --keywords <关键词> --output <输出>"
  echo "      仅下载不裁剪: 追加 --skip-trim（--keywords 可省略）"
  exit 1
elif [ "$SKIP_TRIM" != true ] && [ -z "$KEYWORDS" ]; then
  echo "❌ 缺少必要参数"
  echo "用法 A: pre-trim.sh --input <文件> --keywords <关键词> --output <输出>"
  echo "用法 B: pre-trim.sh --cooper <resourceId> --app-id <appId> --keywords <关键词> --output <输出>"
  exit 1
elif [ ! -f "$INPUT" ]; then
  echo "❌ 输入文件不存在: $INPUT"
  exit 1
fi

if [ "$SKIP_TRIM" = true ]; then
  mkdir -p "$(dirname "$OUTPUT")"
  cp "$INPUT" "$OUTPUT"
  echo "⏭ 跳过预裁剪（--skip-trim），已写出 $OUTPUT"
  exit 0
fi

# ─────────────────────────────────────────────
# 关键词变体扩展
# ─────────────────────────────────────────────
expand_keyword() {
  local kw="$1"
  # 归一化：去掉尾部的"端/侧/方"后缀再匹配
  local base="${kw%端}"
  base="${base%侧}"
  base="${base%方}"
  case "$base" in
    司机)   echo "司机|司机端|司机侧|Driver|driver端|D端|骑手|骑手端" ;;
    乘客)   echo "乘客|乘客端|乘客侧|Passenger|P端|用户端" ;;
    后端|后) echo "后端|服务端|Server|API|接口" ;;
    前端|前) echo "前端|H5|Web|小程序" ;;
    iOS)    echo "iOS|苹果|Apple" ;;
    Android) echo "Android|安卓" ;;
    *)      echo "${base}|${base}端|${base}侧|${base}方" ;;
  esac
}

# 转义 awk 正则元字符
escape_regex() {
  printf '%s' "$1" | sed 's/[][(){}.*+?^$\\|]/\\&/g'
}

# 构建完整正则（支持逗号分隔的多个关键词）
REGEX_PARTS=()
KEYWORD_LABELS=()
IFS=',' read -ra KW_ARRAY <<< "$KEYWORDS"
for kw in "${KW_ARRAY[@]}"; do
  kw="${kw#"${kw%%[![:space:]]*}"}"
  kw="${kw%"${kw##*[![:space:]]}"}"
  [ -z "$kw" ] && continue
  KEYWORD_LABELS+=("$kw")
  expanded=$(expand_keyword "$kw")
  # 对非预定义的通配展开结果做转义
  escaped=""
  IFS='|' read -ra VARIANTS <<< "$expanded"
  for v in "${VARIANTS[@]}"; do
    [ -n "$escaped" ] && escaped="${escaped}|"
    escaped="${escaped}$(escape_regex "$v")"
  done
  REGEX_PARTS+=("$escaped")
done

PATTERN=$(IFS='|'; echo "${REGEX_PARTS[*]}")

# 占位文案：多关键词用逗号连接（避免特殊字符传入 awk 时编码问题）
if [ ${#KEYWORD_LABELS[@]} -eq 1 ]; then
  KEYWORD_LABEL="${KEYWORD_LABELS[0]}"
elif [ ${#KEYWORD_LABELS[@]} -gt 1 ]; then
  KEYWORD_LABEL="${KEYWORD_LABELS[0]}"
  for ((i = 1; i < ${#KEYWORD_LABELS[@]}; i++)); do
    KEYWORD_LABEL+=", ${KEYWORD_LABELS[$i]}"
  done
else
  KEYWORD_LABEL="$KEYWORDS"
fi

format_size() {
  local bytes=$1
  if [ "$bytes" -ge 1048576 ]; then
    echo "$(( bytes / 1048576 )).$(( bytes % 1048576 * 10 / 1048576 )) MB"
  elif [ "$bytes" -ge 1024 ]; then
    echo "$(( bytes / 1024 )).$(( bytes % 1024 * 10 / 1024 )) KB"
  else
    echo "${bytes} B"
  fi
}

# 全局章节正则（无条件保留）
GLOBAL_PATTERN="排期|里程碑|名词解释|术语表|时间表|Timeline"

# ─────────────────────────────────────────────
# 按标题切分并过滤
# ─────────────────────────────────────────────
ORIG_LINES_TOTAL=$(wc -l < "$INPUT" | tr -d ' ')
ORIG_SIZE_TOTAL=$(file_size "$INPUT")

echo ""
echo "⏳ 开始预裁剪..."
echo "   输入文件：$INPUT"
echo "   文件大小：$(format_size "$ORIG_SIZE_TOTAL")（${ORIG_LINES_TOTAL} 行）"
echo "   关键词：${KEYWORD_LABEL}"
echo "   策略：标题或内容命中关键词 → 章节全保留；否则裁剪"

_AWK_STATS_FILE=$(mktmp)
export _AWK_STATS_FILE

echo "   [1/3] 解析章节结构..."
LC_ALL=en_US.UTF-8 awk -v pattern="$PATTERN" -v global_pattern="$GLOBAL_PATTERN" -v keyword="$KEYWORD_LABEL" '
BEGIN {
  section_title = ""
  section_body = ""
  section_level = 0
  is_first_h1 = 1
  kept_sections = 0
  trimmed_sections = 0
  lc_pattern = tolower(pattern)
  # 预拆分关键词变体供 quick_has_keyword 使用
  kw_count = split(lc_pattern, kw_variants, "|")
}

# 剥离图片/链接URL，只保留可读文本（图片URL不可能含中文关键词，但占行长80%+）
function strip_urls(text,    tmp) {
  tmp = text
  # 移除 ![alt](url) 图片标记
  gsub(/!\[[^\]]*\]\([^)]*\)/, "", tmp)
  # 移除 [text](url) 中的 URL 部分，保留 text
  gsub(/\]\(https?:\/\/[^)]*\)/, "]", tmp)
  # 移除裸 URL
  gsub(/https?:\/\/[^ \t|<>)\]]+/, "", tmp)
  return tmp
}

# 快速检查：文本小写后是否包含任一关键词（纯 index 调用，无正则开销）
function quick_has_keyword(text,    tmp, j) {
  tmp = tolower(strip_urls(text))
  for (j = 1; j <= kw_count; j++) {
    if (index(tmp, kw_variants[j]) > 0) return 1
  }
  return 0
}


function flush_section() {
  if (section_title == "") return

  # 一级标题（文档名称）无条件保留
  if (section_level == 1 && is_first_h1) {
    printf "%s\n%s", section_title, section_body
    is_first_h1 = 0
    kept_sections++
    return
  }

  # 全局章节无条件保留
  if (match(section_title, global_pattern)) {
    printf "%s\n%s", section_title, section_body
    kept_sections++
    return
  }

  # 纯结构性标题（body 仅含空白）：直接保留标题，不加占位符
  body_trimmed = section_body
  gsub(/^[[:space:]]+$/, "", body_trimmed)
  if (body_trimmed == "" || body_trimmed == "\n") {
    printf "%s\n%s", section_title, section_body
    kept_sections++
    return
  }

  # 优先判断标题：标题含关键词 → 整个章节原样保留（不做表格行过滤）
  if (quick_has_keyword(section_title)) {
    printf "%s\n%s", section_title, section_body
    kept_sections++
    return
  }

  # 标题不含关键词 → 对内容做关键词匹配，有命中就保留
  if (!quick_has_keyword(section_body)) {
    printf "%s\n[非%s内容，已省略]\n\n", section_title, keyword
    trimmed_sections++
    return
  }

  # 内容含关键词 → 整个章节原样保留（表格精裁交给 LLM）
  printf "%s\n%s", section_title, section_body
  kept_sections++
}

/^#{1,6} / {
  flush_section()
  section_title = $0
  section_body = ""
  # 计算标题级别
  match($0, /^#+/)
  section_level = RLENGTH
  next
}

{
  section_body = section_body $0 "\n"
}

END {
  flush_section()
  # 统计写入临时文件，由外层 bash 读取后输出到 stdout
  printf "%d %d\n", kept_sections, trimmed_sections > ENVIRON["_AWK_STATS_FILE"]
}
' "$INPUT" > "$OUTPUT"

echo "   [2/3] 章节级粗裁完成，开始行级精裁..."

# ─────────────────────────────────────────────
# 第二阶段：行级精裁（原 prd-fine-trim.sh 逻辑）
# 对粗裁结果做表格行阈值过滤、删除线清理
# ─────────────────────────────────────────────
_FINE_TRIM_TMP=$(mktmp)
_FINE_TRIM_STATS=$(mktmp)
export _FINE_TRIM_STATS

LC_ALL=en_US.UTF-8 awk -v pattern="$PATTERN" -v threshold=2 '
BEGIN {
  lc_pattern = tolower(pattern)
  kw_count = split(lc_pattern, kw_variants, "|")
  in_table = 0
  table_header = ""
  table_sep = ""
  table_data_kept = 0
  table_buf = ""
  prev_row_kept = 1
  deleted_rows = 0
  deleted_paragraphs = 0
}

function strip_urls(text,    tmp) {
  tmp = text
  gsub(/!\[[^\]]*\]\([^)]*\)/, "", tmp)
  gsub(/\]\(https?:\/\/[^)]*\)/, "]", tmp)
  gsub(/https?:\/\/[^ \t|<>)\]]+/, "", tmp)
  gsub(/<!--[^>]*-->/, "", tmp)
  return tmp
}

function count_hits(text,    tmp, j, count, pos, idx) {
  tmp = tolower(strip_urls(text))
  count = 0
  for (j = 1; j <= kw_count; j++) {
    pos = 1
    while ((idx = index(substr(tmp, pos), kw_variants[j])) > 0) {
      count++
      pos = pos + idx + length(kw_variants[j]) - 1
    }
  }
  return count
}

function is_image_only_row(line,    tmp, n, i, cells, cell) {
  tmp = line
  gsub(/^\||\|$/, "", tmp)
  n = split(tmp, cells, "|")
  for (i = 1; i <= n; i++) {
    cell = cells[i]
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", cell)
    gsub(/!\[[^\]]*\]\([^)]*\)/, "", cell)
    gsub(/<br>/, "", cell)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", cell)
    if (cell != "" && cell != "/" && cell != "-") return 0
  }
  return 1
}

function is_strikethrough_row(line,    tmp, total_len, strike_len) {
  tmp = line
  gsub(/^\||\|$/, "", tmp)
  total_len = length(tmp)
  gsub(/~~[^~]*~~/, "", tmp)
  strike_len = total_len - length(tmp)
  return (strike_len > total_len * 0.5)
}

function flush_table() {
  if (table_header == "") return
  if (table_data_kept > 0) {
    printf "%s", table_buf
  } else {
    deleted_rows += 2
  }
  table_header = ""
  table_sep = ""
  table_buf = ""
  table_data_kept = 0
  in_table = 0
}

/^\|/ {
  if (!in_table) {
    in_table = 1
    table_header = $0
    table_sep = ""
    table_buf = $0 "\n"
    table_data_kept = 0
    prev_row_kept = 1
    next
  }
  if (table_sep == "" && $0 ~ /^\| *[-:]+/) {
    table_sep = $0
    table_buf = table_buf $0 "\n"
    next
  }
  if (is_strikethrough_row($0)) {
    deleted_rows++
    prev_row_kept = 0
    next
  }
  if (is_image_only_row($0)) {
    if (prev_row_kept) {
      table_buf = table_buf $0 "\n"
      table_data_kept++
    } else {
      deleted_rows++
    }
    next
  }
  hits = count_hits($0)
  if (hits >= threshold) {
    table_buf = table_buf $0 "\n"
    table_data_kept++
    prev_row_kept = 1
  } else {
    deleted_rows++
    prev_row_kept = 0
  }
  next
}

!/^\|/ {
  if (in_table) flush_table()
}

/^[[:space:]]*$/ { print; next }
/^#{1,6} / { print; next }
/\[.*已省略\]/ { print; next }
/^>/ { print; next }

{
  tmp = $0
  total_len = length(tmp)
  gsub(/~~[^~]*~~/, "", tmp)
  if (total_len > 10 && (total_len - length(tmp)) > total_len * 0.5) {
    deleted_paragraphs++
    next
  }
  print
}

END {
  if (in_table) flush_table()
  printf "%d %d\n", deleted_rows, deleted_paragraphs > ENVIRON["_FINE_TRIM_STATS"]
}
' "$OUTPUT" > "$_FINE_TRIM_TMP" || { echo "❌ 行级精裁 awk 执行失败"; exit 1; }

mv "$_FINE_TRIM_TMP" "$OUTPUT"

FINE_DEL_ROWS=0; FINE_DEL_PARAS=0
if [ -f "$_FINE_TRIM_STATS" ]; then
  read -r FINE_DEL_ROWS FINE_DEL_PARAS < "$_FINE_TRIM_STATS"
fi

echo "   [3/3] 生成统计报告..."

# ─────────────────────────────────────────────
# 统计输出（全部写 stdout，确保 Claude Code 可见）
# ─────────────────────────────────────────────
if [ -f "$_AWK_STATS_FILE" ]; then
  read -r KEPT TRIMMED < "$_AWK_STATS_FILE"
else
  KEPT=0; TRIMMED=0
fi

ORIG_LINES="$ORIG_LINES_TOTAL"
ORIG_CHARS=$(wc -m < "$INPUT" | tr -d ' ')
TRIMMED_LINES=$(wc -l < "$OUTPUT" | tr -d ' ')
TRIMMED_CHARS=$(wc -m < "$OUTPUT" | tr -d ' ')
ORIG_SIZE="$ORIG_SIZE_TOTAL"
TRIMMED_SIZE=$(file_size "$OUTPUT")

if [ "$ORIG_CHARS" -gt 0 ]; then
  REDUCE_PERCENT=$(( (ORIG_CHARS - TRIMMED_CHARS) * 100 / ORIG_CHARS ))
else
  REDUCE_PERCENT=0
fi

DIFF_CHARS=$(( ORIG_CHARS - TRIMMED_CHARS ))
DIFF_SIZE=$(( ORIG_SIZE - TRIMMED_SIZE ))
[ "$DIFF_CHARS" -lt 0 ] && DIFF_CHARS=0
[ "$DIFF_SIZE" -lt 0 ] && DIFF_SIZE=0

echo ""
echo "📊 预裁剪统计："
echo "   章节级：保留 ${KEPT} / 裁剪 ${TRIMMED}"
echo "   行级：删除表格行 ${FINE_DEL_ROWS} / 删除段落 ${FINE_DEL_PARAS}"
echo ""
echo "✅ 预裁剪完成"
echo "   原始：${ORIG_LINES} 行 / ${ORIG_CHARS} 字符 / $(format_size "$ORIG_SIZE")"
echo "   裁剪后：${TRIMMED_LINES} 行 / ${TRIMMED_CHARS} 字符 / $(format_size "$TRIMMED_SIZE")"
echo "   缩减：${REDUCE_PERCENT}%（减少 ${DIFF_CHARS} 字符 / $(format_size "$DIFF_SIZE")）"
echo "   输出文件：$OUTPUT"
