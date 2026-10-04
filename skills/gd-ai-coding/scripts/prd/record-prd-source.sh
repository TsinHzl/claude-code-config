#!/usr/bin/env bash
# record-prd-source.sh — 把「有没有标准 PRD」的结论写入 state.json
#
# AskUserQuestion 仍由 LLM 弹出；本脚本是 Harness 落盘。ingest-prd.sh --url
# 在 .dac/state.json 存在时必须先有这份记录，否则拒绝下载（禁止拿 DDP.prd 偷跑）。
#
# 用法:
#   record-prd-source.sh --kind standard --url "<Cooper knowledge URL>"
#   record-prd-source.sh --kind legacy --url "<Cooper knowledge URL>"
#   record-prd-source.sh --kind none
#   record-prd-source.sh --check
#
# --check: kind 为 standard|legacy|none → exit 0 并打印 PRD_SOURCE_KIND / PRD_SOURCE_URL
#          缺失 → [DAC-SPEC-005] exit 1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_UPDATE="$SCRIPT_DIR/../state-update.sh"
STATE_FILE=".dac/state.json"

KIND=""
URL=""
CHECK=false

usage() {
  echo "用法: record-prd-source.sh --kind standard|legacy --url <Cooper knowledge URL>" >&2
  echo "      record-prd-source.sh --kind none" >&2
  echo "      record-prd-source.sh --check" >&2
  exit 1
}

first_token() {
  echo "$1" | awk '{print $1}'
}

is_knowledge_url() {
  echo "$1" | grep -q '/knowledge/'
}

print_source() {
  local kind="$1" url="${2:-}"
  echo "PRD_SOURCE_KIND=$kind"
  echo "PRD_SOURCE_URL=$url"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --kind) [ $# -lt 2 ] && usage; KIND="$2"; shift 2 ;;
    --url)  [ $# -lt 2 ] && usage; URL="$2"; shift 2 ;;
    --check) CHECK=true; shift ;;
    -h|--help) usage ;;
    *) echo "[DAC-SPEC-005] ❌ 未知参数: $1" >&2; usage ;;
  esac
done

if [ "$CHECK" = true ]; then
  if [ ! -f "$STATE_FILE" ]; then
    echo "[DAC-SPEC-005] ❌ 尚未确认标准 PRD（.dac/state.json 不存在）。先完成 1.2，再 record-prd-source.sh --kind …" >&2
    exit 1
  fi
  KIND=$(jq -r '.prd_source.kind // empty' "$STATE_FILE")
  URL=$(jq -r '.prd_source.url // empty' "$STATE_FILE")
  case "$KIND" in
    standard|legacy|none)
      print_source "$KIND" "$URL"
      exit 0
      ;;
    *)
      echo "[DAC-SPEC-005] ❌ 尚未确认标准 PRD。先 AskUserQuestion「有没有标准 PRD」，再：" >&2
      echo "   bash ~/.claude/skills/gd-ai-coding/scripts/prd/record-prd-source.sh --kind standard|legacy --url <知识库链接>" >&2
      echo "   或 --kind none。禁止用 DDP 返回的产品文档链接直接 ingest。" >&2
      exit 1
      ;;
  esac
fi

[ -z "$KIND" ] && usage
case "$KIND" in
  standard|legacy|none) ;;
  *)
    echo "[DAC-SPEC-005] ❌ --kind 必须是 standard、legacy 或 none，收到：$KIND" >&2
    exit 1
    ;;
esac

if [ ! -f "$STATE_FILE" ]; then
  echo "[DAC-STATE-003] ❌ .dac/state.json 不存在，先完成 1.2 初始化再记录 PRD 来源" >&2
  exit 1
fi

if [ "$KIND" = "none" ]; then
  URL=""
else
  URL=$(first_token "$URL")
  if [ -z "$URL" ]; then
    echo "[DAC-SPEC-007] ❌ --kind $KIND 必须提供 --url（Cooper 知识库链接）" >&2
    exit 1
  fi
  if ! is_knowledge_url "$URL"; then
    echo "[DAC-SPEC-007] ❌ PRD 链接必须是带 knowledge 的知识库地址：$URL" >&2
    exit 1
  fi
fi

JSON=$(jq -n --arg k "$KIND" --arg u "$URL" '{kind:$k, url:$u}')
bash "$STATE_UPDATE" --set-json prd_source "$JSON"
print_source "$KIND" "$URL"
