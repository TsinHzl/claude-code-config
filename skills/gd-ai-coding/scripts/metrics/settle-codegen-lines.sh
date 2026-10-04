#!/usr/bin/env bash
# =============================================================================
# settle-codegen-lines.sh — 把本 feature 相对 codegen checkpoint 的代码净增行
# 按 feat 取 max 写入 .dac/trace/<req>.json，再走既有 /report。
# =============================================================================
#
# 口径（代码比例「流程 · 自动生成」桶）：
#   git diff --numstat <base_commit> ∩ code-scope ∩ DAC_CODE_EXTENSIONS
#   + 同范围未跟踪新文件的行数（L2 通过时往往还没 git add）
#   每个 feat_id 取历史结算的 max（L2 通过一次、feature done 再一次，CR 修补算进去）
#   需求级 codegen_lines_added = sum(各 feat max)
#
# checkpoint 是 git 对象锚点，不是时间窗；成功后不删除。
# L2 失败 / feature failed 不要调本脚本。
#
# Usage: settle-codegen-lines.sh <feat_id>
# 任何失败都 exit 0，不阻断 codegen / state-update。
# =============================================================================

set -uo pipefail

FEAT_ID="${1:-}"
[[ -n "$FEAT_ID" ]] || exit 0

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPTS_DIR/runtime.sh" 2>/dev/null || exit 0
dac_resolve_runtime 2>/dev/null || exit 0
# shellcheck source=/dev/null
source "$SCRIPTS_DIR/lib.sh" 2>/dev/null || exit 0
# shellcheck source=/dev/null
source "$SCRIPTS_DIR/paths.sh" 2>/dev/null || exit 0
# shellcheck source=/dev/null
source "$SCRIPTS_DIR/metrics/report-trace-backend.sh" 2>/dev/null || true

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0
[[ -f .dac/state.json ]] || exit 0

FEAT_DIR="$(get_feat_dir "" "$FEAT_ID" 2>/dev/null)" || exit 0
CHECKPOINT="$FEAT_DIR/.codegen_checkpoint"
[[ -f "$CHECKPOINT" ]] || exit 0

BASE=$(jq -r '.base_commit // empty' "$CHECKPOINT" 2>/dev/null)
[[ -n "$BASE" ]] || exit 0
git rev-parse --verify "$BASE^{commit}" >/dev/null 2>&1 || exit 0

_req_name="$(jq -r '.req_name // "untitled"' .dac/state.json 2>/dev/null)"
_safe_req="${_req_name//[^A-Za-z0-9._-]/_}"
_trace_file=".dac/trace/${_safe_req}.json"
[[ -f "$_trace_file" ]] || exit 0

# 生成文件/依赖目录：与 numstat pathspec 同一份排除清单
_is_excluded() {
  local path="$1" base="${1##*/}" g d
  for g in $DAC_GENERATED_EXCLUDE; do
    case "$base" in $g) return 0 ;; esac
  done
  for d in $DAC_EXCLUDE_DIRS; do
    case "$path" in */"$d"/*|"$d"/*) return 0 ;; esac
  done
  case "$path" in */generated/*) return 0 ;; esac
  return 1
}

# code-scope 表格第二列；缺文件或抽不到路径时不过滤（skip_feature_plan 退化成全量代码 diff）
_SCOPE_FILE=$(mktemp 2>/dev/null) || exit 0
trap 'rm -f "$_SCOPE_FILE"' EXIT
_scope_empty=1
if [[ -f "$FEAT_DIR/code-scope.md" ]]; then
  awk -F'|' '
    /^\|/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      if ($2 != "" && $2 !~ /文件路径|----/) print $2
    }
  ' "$FEAT_DIR/code-scope.md" 2>/dev/null | sort -u > "$_SCOPE_FILE"
  if [[ -s "$_SCOPE_FILE" ]]; then
    _scope_empty=0
  fi
fi

_in_scope() {
  [[ "$_scope_empty" -eq 1 ]] && return 0
  grep -Fxq "$1" "$_SCOPE_FILE" 2>/dev/null
}

dac_build_numstat_pathspec

_added=0
# git diff 有差异时 exit 1，不能让 set -e 式调用方误杀；本脚本未开 -e，仍显式 || true
while IFS=$'\t' read -r add _del path; do
  [[ -n "$path" ]] || continue
  [[ "$add" != "-" ]] || continue
  _in_scope "$path" || continue
  dac_is_code_file "$path" || continue
  _is_excluded "$path" && continue
  _added=$((_added + add))
done < <(git diff --numstat "$BASE" -- "${DAC_NUMSTAT_PATHSPEC[@]}" 2>/dev/null || true)

# 未跟踪新文件不在 git diff 里（codegen Write 后常未 add）
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  _in_scope "$path" || continue
  dac_is_code_file "$path" || continue
  _is_excluded "$path" && continue
  # 已出现在 vs-base diff 里的路径不要再加（rename/拷贝边界）；未跟踪文件不会出现在 diff 中
  _lines=$(wc -l < "$path" 2>/dev/null | tr -d ' ')
  [[ "$_lines" =~ ^[0-9]+$ ]] || _lines=0
  _added=$((_added + _lines))
done < <(git ls-files --others --exclude-standard 2>/dev/null || true)

atomic_jq '
  .codegen_by_feature = (.codegen_by_feature // {}) |
  .codegen_by_feature[$fid] = (([.codegen_by_feature[$fid] // 0, $n] | max)) |
  .codegen_lines_added = (([.codegen_by_feature[]?] | add) // 0)
' "$_trace_file" --arg fid "$FEAT_ID" --argjson n "$_added" 2>/dev/null || exit 0

_report_progress "$_trace_file" 2>/dev/null || true
exit 0
