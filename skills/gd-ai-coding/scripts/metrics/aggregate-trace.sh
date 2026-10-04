#!/usr/bin/env bash
# =============================================================================
# aggregate-trace.sh — 拉取并聚合所有 refs/notes/dac-trace 数据
# =============================================================================
#
# 用法：aggregate-trace.sh [--remote <name>]
#   --remote <name>  fetch 的 remote 名称，默认 origin
#
# stdout: 按 committer 聚合的 JSON 数组（供后端/其他脚本 pipe 消费）
# stderr: 进度/警告信息（不污染 stdout）
# exit 0: 正常（fetch 失败时降级用本地已有数据，仍输出）
# exit 1: jq 不可用 或 当前目录不是 git repo
#
# 输出结构：
#   [
#     {
#       "committer": "alice@example.com",
#       "committer_name": "Alice",
#       "requirements": [
#         {
#           "req_name": "driver-side",
#           "workflow_session_ids": [...],
#           "phases": [...],
#           "features": [...],
#           "last_note_id": "96265626",
#           "last_commit": "abc1234f",
#           "last_commit_ts": 1783246254000
#         }
#       ]
#     }
#   ]
#
# 同一 committer 下同一 req_name 可能出现在多个 commit（每次 phase/feature 变更都提交），
# 脚本取该 req_name 最新一次 commit 上的 note（phases/features 最完整）作为最终状态。
# =============================================================================

set -euo pipefail

# source lib.sh 复用代码白名单单一来源（numstat pathspec 与 post-commit hook / backfill 同口径）
_AGG_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$_AGG_SCRIPTS_DIR/lib.sh"

REMOTE="origin"

# 解析参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote)
      if [[ -z "${2-}" ]]; then
        echo "[aggregate-trace] ❌ --remote 缺少值" >&2; exit 1
      fi
      REMOTE="$2"; shift 2 ;;
    *) echo "[aggregate-trace] ❌ 未知参数: $1" >&2; exit 1 ;;
  esac
done

# 前置检查
command -v jq >/dev/null 2>&1 || { echo "[aggregate-trace] ❌ jq 未安装" >&2; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "[aggregate-trace] ❌ 当前目录不是 git repo" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Step 1: fetch refs/notes/dac-trace（失败降级，不中断）
# -----------------------------------------------------------------------------
echo "[aggregate-trace] fetch $REMOTE refs/notes/dac-trace ..." >&2
if git fetch "$REMOTE" "refs/notes/dac-trace:refs/notes/dac-trace" 2>/dev/null; then
  echo "[aggregate-trace] fetch 成功" >&2
else
  echo "[aggregate-trace] ⚠️  fetch 失败（网络/权限/remote 不存在），使用本地已有 notes" >&2
fi

# -----------------------------------------------------------------------------
# Step 2: 先用 git notes list 获取所有有 note 的 commit 列表
# 避免对每个 commit 都调用 git notes show（O(所有commit) → O(有note的commit)）
# -----------------------------------------------------------------------------
echo "[aggregate-trace] 获取有效 note 列表 ..." >&2

TMP_NDJSON=$(mktemp)
trap 'rm -f "$TMP_NDJSON"' EXIT

# git notes list 输出格式: <note_object> <annotated_commit>
# 只取 commit hash，再批量查 committer 信息 + note 内容
NOTE_COMMITS=()
while read -r _note_obj _commit; do
  [[ -n "$_commit" ]] && NOTE_COMMITS+=("$_commit")
done < <(git notes --ref=refs/notes/dac-trace list 2>/dev/null || true)

NOTE_COUNT="${#NOTE_COMMITS[@]}"
echo "[aggregate-trace] 找到 $NOTE_COUNT 个有 note 的 commit" >&2

if [[ $NOTE_COUNT -eq 0 ]]; then
  echo "[aggregate-trace] ⚠️  本地无 dac-trace notes，尝试文件证明兜底..." >&2
fi

# -----------------------------------------------------------------------------
# Step 3: 对每个有 note 的 commit，拉取 committer 信息 + note 内容
# 序列化为一行 JSON 写入 TMP_NDJSON（规避 note 含换行导致的分隔符协议问题）
# -----------------------------------------------------------------------------
# 代码白名单 numstat pathspec 构造一次（各 commit 复用，数组不随 commit 变化）
dac_build_numstat_pathspec

for _commit in "${NOTE_COMMITS[@]+"${NOTE_COMMITS[@]}"}"; do
  # 获取 note 内容（整体作为字符串，可能含换行）
  _note=$(git notes --ref=refs/notes/dac-trace show "$_commit" 2>/dev/null) || continue

  # 校验是否合法 JSON 且含 req_name
  _req=$(printf '%s' "$_note" | jq -r '.req_name // empty' 2>/dev/null) || continue
  [[ -z "$_req" ]] && continue

  # 优先从 note 读取 committer（支持 bare repo / 无 commit 对象场景）
  _email=$(printf '%s' "$_note" | jq -r '.committer // empty' 2>/dev/null)
  if [[ -n "$_email" ]]; then
    _name=$(printf '%s' "$_note" | jq -r '.committer_name // ""' 2>/dev/null)
    _ts_ms=$(printf '%s' "$_note" | jq -r '(.commit_ts // 0)' 2>/dev/null || echo "0")
  else
    # 降级：从 commit 对象读取（需要本地有 commit 对象，bare repo 下跳过此 note）
    # 用 tab（%x09）分隔：$() 只剥离尾部换行，不剥离 tab，IFS=$'\t' 可正确拆分三字段
    _meta=$(git log -1 --format="%ce%x09%cn%x09%ct" "$_commit" 2>/dev/null) || continue
    IFS=$'\t' read -r _email _name _ts <<< "$_meta"
    [[ -z "$_email" ]] && continue
    _ts_ms=$(( ${_ts:-0} * 1000 ))
  fi

  # 提取本次 commit 的「仅代码文件」改动行数：白名单 include + 排除生成/锁/构建产物，
  # 与 post-commit hook / backfill 完全同口径（原 git show --stat 自算含文档且连生成文件都未排除）。
  # numstat/pathspec 在 bare repo 下同样可用，DAC_NUMSTAT_PATHSPEC 已在循环外构造一次。
  _lines_added=0
  _lines_deleted=0
  _stats=$(git show --numstat --format="" "$_commit" -- "${DAC_NUMSTAT_PATHSPEC[@]}" 2>/dev/null \
    | awk '{if ($1 != "-") a+=$1; if ($2 != "-") d+=$2} END {print (a+0), (d+0)}')
  if [[ -n "$_stats" ]]; then
    _lines_added=$(printf '%s' "$_stats" | cut -d' ' -f1); _lines_added=${_lines_added:-0}
    _lines_deleted=$(printf '%s' "$_stats" | cut -d' ' -f2); _lines_deleted=${_lines_deleted:-0}
  fi

  # 将所有字段序列化为一行 JSON，note 整体作为 --argjson 传入（保留其 JSON 结构）
  printf '%s' "$_note" | jq -c \
    --arg    commit "$_commit"       \
    --arg    email  "$_email"        \
    --arg    name   "$_name"         \
    --arg    ts_ms  "$_ts_ms"        \
    --argjson la    "$_lines_added"  \
    --argjson ld    "$_lines_deleted" \
    '{
      committer:            $email,
      committer_name:       $name,
      req_name:             (.req_name // "unknown"),
      workflow_session_ids: (.workflow_session_ids // []),
      phases:               (.phases   // []),
      features:             (.features // []),
      last_note_id:         (.note_id  // null),
      last_commit:          $commit,
      last_commit_ts:       ($ts_ms | tonumber),
      lines_added:          $la,
      lines_deleted:        $ld
    }' 2>/dev/null >> "$TMP_NDJSON" || true
done

NDJSON_COUNT=$(wc -l < "$TMP_NDJSON" | tr -d ' ')
echo "[aggregate-trace] 成功解析 $NDJSON_COUNT 条 notes 记录" >&2

# -----------------------------------------------------------------------------
# Step 3.5: 文件证明兜底 — 提交了 gd-ai-coding 标记文件也算使用 DAC
# 扫描路径：openspec/changes/*/proposal.md  .dac/state.json
#           .dac/knowledge/*  .dac/trace/*.json
# 合成条目的 workflow_session_ids=["dac-file-proof"]，jq 聚合时与 notes 数据合并，
# 若同一 (committer, req_name) 已有 notes 条目则 notes 优先（last_commit_ts 更大）。
# -----------------------------------------------------------------------------
echo "[aggregate-trace] 文件证明扫描 (openspec/ + .dac/)..." >&2
_fp_count=0
while IFS= read -r _fpc; do
  [[ -z "$_fpc" ]] && continue
  _fp_meta=$(git log -1 --format="%ce%x09%cn%x09%ct" "$_fpc" 2>/dev/null) || continue
  IFS=$'\t' read -r _fp_email _fp_name _fp_ts <<< "$_fp_meta"
  [[ -z "$_fp_email" ]] && continue
  _fp_ts_num=${_fp_ts:-0}
  _fp_ts_ms=$(( _fp_ts_num * 1000 ))
  while IFS= read -r _fp_path; do
    [[ -z "$_fp_path" ]] && continue
    _fp_req="__dac_file_proof__"
    if [[ "$_fp_path" =~ ^openspec/changes/([^/]+)/proposal\.md$ ]]; then
      _fp_req="${BASH_REMATCH[1]}"
    fi
    jq -cn \
      --arg    email    "$_fp_email"   \
      --arg    name     "$_fp_name"    \
      --argjson ts      "$_fp_ts_ms"  \
      --arg    req_name "$_fp_req"    \
      '{
        committer:            $email,
        committer_name:       $name,
        req_name:             $req_name,
        workflow_session_ids: ["dac-file-proof"],
        phases:               [],
        features:             [],
        last_note_id:         null,
        last_commit:          null,
        last_commit_ts:       $ts,
        lines_added:          0,
        lines_deleted:        0
      }' 2>/dev/null >> "$TMP_NDJSON" || true
    _fp_count=$(( _fp_count + 1 ))
  done < <(git diff-tree --no-commit-id -r --name-only --diff-filter=A "$_fpc" 2>/dev/null \
    | grep -E '^(openspec/changes/[^/]+/proposal\.md|\.dac/state\.json|\.dac/knowledge/.+|\.dac/trace/.+\.json)$' \
    || true)
done < <(git log --all --format="%H" --diff-filter=A -- \
  'openspec/changes/*/proposal.md' '.dac/state.json' '.dac/knowledge/*' '.dac/trace/*.json' \
  2>/dev/null || true)
echo "[aggregate-trace] 文件证明：${_fp_count} 条记录" >&2

NDJSON_COUNT=$(wc -l < "$TMP_NDJSON" | tr -d ' ')
if [[ "$NDJSON_COUNT" -eq 0 ]]; then
  echo "[aggregate-trace] ⚠️  notes + 文件证明均无数据，输出空数组" >&2
  echo "[]"
  exit 0
fi

# -----------------------------------------------------------------------------
# Step 4: jq -s 聚合：按 (committer, req_name) 分组，取 last_commit_ts 最大的 note
# committer_name 取同一 committer 最新 commit 上的名称（避免历史改名问题）
# -----------------------------------------------------------------------------
jq -s '
  group_by(.committer)
  | map(
      . as $group |
      {
        committer:      ($group | sort_by(.last_commit_ts) | last | .committer),
        committer_name: ($group | sort_by(.last_commit_ts) | last | .committer_name),
        requirements: (
          $group
          | group_by(.req_name)
          | map(
              (length) as $cnt
              | (map(.lines_added // 0) | add // 0) as $la
              | (map(.lines_deleted // 0) | add // 0) as $ld
              | sort_by(.last_commit_ts) | last
              | {
                  req_name,
                  workflow_session_ids,
                  phases,
                  features,
                  last_note_id,
                  last_commit,
                  last_commit_ts,
                  commit_count: $cnt,
                  lines_added:  $la,
                  lines_deleted: $ld
                }
            )
        )
      }
    )
  | sort_by(.committer)
' "$TMP_NDJSON"
