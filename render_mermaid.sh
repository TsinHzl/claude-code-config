#!/usr/bin/env bash
# Mermaid 渲染管道：.mmd/.md 中的 mermaid 代码 → SVG/PNG
# 用法:
#   render_mermaid.sh input.mmd [output.svg]         # 单文件渲染
#   render_mermaid.sh input.mmd output.png           # 渲染为 PNG
#   render_mermaid.sh --inline "graph TD; A-->B"     # 内联代码渲染
#   render_mermaid.sh --batch dir/                   # 批量渲染目录下所有 .mmd

set -euo pipefail

MMDC="mmdc"
CHROME_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
export PUPPETEER_EXECUTABLE_PATH="$CHROME_PATH"
DEFAULT_THEME="default"
DEFAULT_BG="white"
DEFAULT_WIDTH=1200
DEFAULT_SCALE=2

render_single() {
  local input="$1"
  local output="${2:-${input%.mmd}.svg}"
  local ext="${output##*.}"

  $MMDC -i "$input" -o "$output" \
    --theme "$DEFAULT_THEME" \
    --backgroundColor "$DEFAULT_BG" \
    --width "$DEFAULT_WIDTH" \
    --scale "$DEFAULT_SCALE" 2>&1

  echo "✓ $output"
}

render_inline() {
  local code="$1"
  local output="${2:-/tmp/mermaid_output.svg}"
  local tmpdir
  tmpdir=$(mktemp -d)
  local tmpfile="$tmpdir/input.mmd"
  echo "$code" > "$tmpfile"
  render_single "$tmpfile" "$output"
  rm -rf "$tmpdir"
}

render_batch() {
  local dir="$1"
  find "$dir" -name "*.mmd" -type f | while read -r f; do
    render_single "$f"
  done
}

case "${1:-}" in
  --inline)
    shift
    render_inline "$1" "${2:-/tmp/mermaid_output.svg}"
    ;;
  --batch)
    shift
    render_batch "${1:-.}"
    ;;
  --help|-h)
    echo "用法: render_mermaid.sh [--inline CODE | --batch DIR | INPUT [OUTPUT]]"
    echo "支持输出格式: .svg (默认), .png, .pdf"
    ;;
  *)
    if [ -z "${1:-}" ]; then
      echo "错误: 需要输入文件" >&2; exit 1
    fi
    render_single "$1" "${2:-}"
    ;;
esac
