#!/usr/bin/env bash
# ingest-prd.sh — 下载 Cooper PRD，能抽出标准表则写 extract；否则 fallback 到 pre-trim
#
# 用法：
#   ingest-prd.sh --url "<Cooper URL> [关键词]" --output <摘要或 trimmed> --raw <raw.md> [--extract <json>] [--assets-dir <dir>] [--source standard|legacy]
#   ingest-prd.sh --input <本地 md> --output ... [--raw ...] [--extract ...] [--keywords 司机端]
#
# --url 门禁（Harness，不靠 LLM）：
#   .dac/state.json 存在时必须先有 prd_source（record-prd-source.sh）；kind=none 禁止下载。
#   --url 的第一段必须与已记录的 prd_source.url 一致，禁止改塞 DDP 产品文档链接。
#   无 state 时必须带 --source standard|legacy（单测 / 独立调用）。
# --input 不走该门禁（本地 fixture / 失败后改贴文件）。
#
# stdout 含：DAC_PRD_MODE=standard|legacy
# 同时写 <raw 同目录>/dac-prd-mode，供步骤 1.4 读取。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_PY="$SCRIPT_DIR/parse-standard-prd.py"
PRE_TRIM="$SCRIPT_DIR/pre-trim.sh"

URL_INPUT=""
INPUT=""
OUTPUT=""
RAW_OUTPUT=""
EXTRACT=""
ASSETS_DIR=""
KEYWORDS="司机端"
SOURCE_KIND=""
RECORD_PRD="$SCRIPT_DIR/record-prd-source.sh"

usage() {
  echo "用法: ingest-prd.sh --url \"<Cooper URL> [关键词]\" --output <file> --raw <file> [--extract <json>] [--assets-dir <dir>] [--source standard|legacy]"
  echo "      ingest-prd.sh --input <file> --output <file> [--raw <file>] [--extract <json>] [--keywords <kw>]"
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --url)        [ $# -lt 2 ] && usage; URL_INPUT="$2"; shift 2 ;;
    --input)      [ $# -lt 2 ] && usage; INPUT="$2"; shift 2 ;;
    --output)     [ $# -lt 2 ] && usage; OUTPUT="$2"; shift 2 ;;
    --raw)        [ $# -lt 2 ] && usage; RAW_OUTPUT="$2"; shift 2 ;;
    --extract)    [ $# -lt 2 ] && usage; EXTRACT="$2"; shift 2 ;;
    --assets-dir) [ $# -lt 2 ] && usage; ASSETS_DIR="$2"; shift 2 ;;
    --keywords)   [ $# -lt 2 ] && usage; KEYWORDS="$2"; shift 2 ;;
    --source)     [ $# -lt 2 ] && usage; SOURCE_KIND="$2"; shift 2 ;;
    *) echo "❌ 未知参数: $1"; usage ;;
  esac
done

[ -z "$OUTPUT" ] && usage
if [ -z "$URL_INPUT" ] && [ -z "$INPUT" ]; then
  echo "❌ 需要 --url 或 --input"
  exit 1
fi

# --url 必须先确认「有没有标准 PRD」。--input 是本地文件，不挡。
if [ -n "$URL_INPUT" ]; then
  STATE_FILE=".dac/state.json"
  RECORDED_KIND=""
  RECORDED_URL=""
  if [ -f "$STATE_FILE" ]; then
    if ! bash "$RECORD_PRD" --check >/dev/null; then
      exit 1
    fi
    RECORDED_KIND=$(jq -r '.prd_source.kind // empty' "$STATE_FILE")
    RECORDED_URL=$(jq -r '.prd_source.url // empty' "$STATE_FILE")
    if [ "$RECORDED_KIND" = "none" ]; then
      echo "[DAC-SPEC-006] ❌ 用户确认本次无 PRD，禁止下载 Cooper。不要用 DDP 产品文档链接。" >&2
      exit 1
    fi
  fi
  EFFECTIVE_KIND="${SOURCE_KIND:-$RECORDED_KIND}"
  if [ -z "$EFFECTIVE_KIND" ]; then
    echo "[DAC-SPEC-005] ❌ --url 下载前必须确认标准 PRD：" >&2
    echo "   先 AskUserQuestion，再 record-prd-source.sh --kind standard|legacy --url <知识库链接>" >&2
    echo "   （无 .dac 的独立调用可加 --source standard|legacy）" >&2
    exit 1
  fi
  if [ "$EFFECTIVE_KIND" != "standard" ] && [ "$EFFECTIVE_KIND" != "legacy" ]; then
    echo "[DAC-SPEC-006] ❌ 非法 PRD 来源：$EFFECTIVE_KIND（只接受 standard|legacy）" >&2
    exit 1
  fi
  if [ -n "$SOURCE_KIND" ] && [ -n "$RECORDED_KIND" ] && [ "$SOURCE_KIND" != "$RECORDED_KIND" ]; then
    echo "[DAC-SPEC-008] ❌ --source=$SOURCE_KIND 与已确认的 prd_source.kind=$RECORDED_KIND 不一致" >&2
    exit 1
  fi
  URL_PART=$(echo "$URL_INPUT" | awk '{print $1}')
  if [ -n "$RECORDED_URL" ] && [ "$URL_PART" != "$RECORDED_URL" ]; then
    echo "[DAC-SPEC-008] ❌ --url 与已确认的 prd_source.url 不一致，禁止改用 DDP 产品文档链接。" >&2
    echo "   已确认：$RECORDED_URL" >&2
    echo "   本次传入：$URL_PART" >&2
    exit 1
  fi
fi

mkdir -p "$(dirname "$OUTPUT")"

_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/dac-ingest.XXXXXX")
cleanup() { rm -rf "$_TMPDIR"; }
trap cleanup EXIT

RAW_TMP="$_TMPDIR/raw.md"
TRIM_TMP="$_TMPDIR/trimmed.md"

if [ -n "$URL_INPUT" ]; then
  echo "📥 ingest：从 Cooper 下载（先不裁剪）…"
  bash "$PRE_TRIM" \
    --url "$URL_INPUT" \
    --output "$RAW_TMP" \
    --raw "$RAW_TMP" \
    --skip-trim
  INPUT="$RAW_TMP"
else
  if [ ! -f "$INPUT" ]; then
    echo "❌ 输入文件不存在: $INPUT"
    exit 1
  fi
  cp "$INPUT" "$RAW_TMP"
  INPUT="$RAW_TMP"
fi

if [ -n "$RAW_OUTPUT" ]; then
  mkdir -p "$(dirname "$RAW_OUTPUT")"
  cp "$RAW_TMP" "$RAW_OUTPUT"
  echo "   原始文档已保存：$RAW_OUTPUT"
  MODE_DIR="$(cd "$(dirname "$RAW_OUTPUT")" && pwd)"
else
  MODE_DIR="$(cd "$(dirname "$OUTPUT")" && pwd)"
fi

if [ -z "$EXTRACT" ]; then
  EXTRACT="$MODE_DIR/prd-extract.json"
fi

PARSE_ARGS=(--input "$RAW_TMP" --out "$EXTRACT" --summary "$OUTPUT")
if [ -n "$ASSETS_DIR" ]; then
  PARSE_ARGS+=(--assets-dir "$ASSETS_DIR")
fi

set +e
python3 "$PARSE_PY" "${PARSE_ARGS[@]}"
PARSE_RC=$?
set -e

write_mode() {
  local mode="$1"
  printf '%s\n' "$mode" > "$MODE_DIR/dac-prd-mode"
  echo "DAC_PRD_MODE=$mode"
}

if [ "$PARSE_RC" -eq 0 ]; then
  write_mode standard
  echo "DAC_EXTRACT=$(cd "$(dirname "$EXTRACT")" && pwd)/$(basename "$EXTRACT")"
  echo "✅ 标准 PRD 已抽出：$EXTRACT"
  exit 0
fi

if [ "$PARSE_RC" -eq 2 ]; then
  echo "ℹ️  未识别标准需求列表，fallback 到 pre-trim"
  if [ ! -s "$TRIM_TMP" ]; then
    bash "$PRE_TRIM" \
      --input "$RAW_TMP" \
      --keywords "$KEYWORDS" \
      --output "$TRIM_TMP"
  fi
  mkdir -p "$(dirname "$OUTPUT")"
  cp "$TRIM_TMP" "$OUTPUT"
  rm -f "$EXTRACT"
  write_mode legacy
  echo "✅ 已裁剪：$OUTPUT"
  exit 0
fi

echo "❌ 标准 PRD 解析失败（exit $PARSE_RC）"
exit "$PARSE_RC"
