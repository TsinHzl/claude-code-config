#!/usr/bin/env bash
# =============================================================================
# backfill-commit-stats-from-history.sh
#   从 git 历史回填 hook 安装前丢失的 commit 行数到后端 /commit-stats
# =============================================================================
#
# 背景：
#   post-commit hook（setup-hook-wrapper.sh）只在「安装之后」的提交才写 git
#   notes + 调 /commit-stats。若成员先完成了需求开发、之后才安装/更新 hook，
#   仅最近一次提交被记录，之前所有历史提交的行数全部丢失（看板显示行数远低于
#   实际）。backfill-trace-to-backend.sh 走 /backfill 端点，记录已存在即整条
#   skip，且读 git notes（历史提交无 note），无法补这类数据。
#
#   本脚本从 git 历史逐提交重算行数，走 /commit-stats（存在则累加、按
#   last_commit 去重），等价于「hook 当时就在」。
#
# 幂等（关键）：
#   后端 /commit-stats 去重只比对当前存储的单个 last_commit，不记全量提交集合，
#   重复累加风险高。本脚本改用「该提交是否已有 refs/notes/dac-trace note」作为
#   去重键：已有 note 的提交跳过（含 hook 已处理的最近提交，避免其行数被重复
#   计入）。对无 note 的提交，先 /commit-stats 上报成功、再补写 note，保证
#   「有 note ⟺ 已成功上报」不变式，网络失败的提交下次重跑会重试。
#
# 触发方式：
#   ① 手动运行（见下方用法）；② 由 write-trace-hook.sh（全局 PostToolUse hook）在装了
#      hook 的仓库每次 Write/Edit 时检测，用 .git/.dac-backfill-done 标记保证每仓库后台
#      静默自动回填一次（仅本脚本 exit 0 才建标记，失败下次编辑重试）——覆盖「先开发、
#      后装 hook」的存量仓库，无需人工干预。
#
# 用法：
#   backfill-commit-stats-from-history.sh [--base <ref>] [--branch <ref>] [--dry-run]
#     --base   <ref>   历史提交范围基线（默认自动取与 origin/main 等默认分支的
#                      merge-base；推导不出时报错要求显式指定，绝不默认全历史）
#     --branch <ref>   范围终点，默认 HEAD（在需求分支上运行）
#     --dry-run        只预览将补报的提交与行数，不写 note、不上报
#
# committer 固定取当前 git 身份（user.email）：回填须由本人在本人仓库运行。
# req_name 推导优先级同 post-commit hook：state.json → req-bind → 分支名 T-IBT（未命中回退 R-IBG）。
# =============================================================================

set -euo pipefail

# source lib.sh 复用代码白名单单一来源（numstat pathspec 与 post-commit hook 同口径）
_BF_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$_BF_SCRIPTS_DIR/runtime.sh"
dac_resolve_runtime || { echo "[backfill-history] ❌ 无法解析 DAC 运行时" >&2; exit 1; }
source "$_BF_SCRIPTS_DIR/lib.sh"

BACKEND_CONFIG="$DAC_CONFIG_HOME/backend-config.json"

BASE_REF=""
TIP_REF="HEAD"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)   BASE_REF="${2:?--base 缺少值}"; shift 2 ;;
    --branch) TIP_REF="${2:?--branch 缺少值}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "[backfill-history] ❌ 未知参数: $1" >&2; exit 1 ;;
  esac
done

command -v jq   >/dev/null 2>&1 || { echo "[backfill-history] ❌ jq 未安装" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "[backfill-history] ❌ curl 未安装" >&2; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "[backfill-history] ❌ 当前目录不是 git repo" >&2; exit 1; }

# ── 后端配置 ────────────────────────────────────────────────────────────────
[[ -f "$BACKEND_CONFIG" ]] || { echo "[backfill-history] ❌ 未配置后端: $BACKEND_CONFIG" >&2; exit 1; }
BASE_URL=$(jq -r '.base_url // empty' "$BACKEND_CONFIG")
TOKEN=$(jq -r '.token // empty' "$BACKEND_CONFIG")
[[ -n "$BASE_URL" && -n "$TOKEN" ]] || { echo "[backfill-history] ❌ backend-config.json 缺 base_url/token" >&2; exit 1; }

# ── 当前 git 身份（committer 与 log 过滤同源，保证一致）─────────────────────
EMAIL=$(git config user.email 2>/dev/null || true)
NAME=$(git config user.name 2>/dev/null || true)
[[ -n "$EMAIL" ]] || { echo "[backfill-history] ❌ 未配置 git user.email" >&2; exit 1; }

# ── repo_path 推导（与 report-trace-backend.sh 保持一致）────────────────────
_remote_url=$(git remote get-url origin 2>/dev/null || true)
if [[ -n "$_remote_url" ]]; then
  REPO_PATH=$(printf '%s' "$_remote_url" | sed -E 's#^[a-zA-Z]+://[^/]+/##; s#^[^@]+@[^:]+:##; s#\.git$##')
else
  REPO_PATH="local:$(pwd)"
fi

# ── req_name 推导（优先级同 hook）───────────────────────────────────────────
REQ=""
_state_file=""
_owner=""
if [[ -f ".dac/state.json" ]]; then
  _state_file=".dac/state.json"
elif [[ -f "../.dac/state.json" ]]; then
  _state_file="../.dac/state.json"
fi
if [[ -n "$_state_file" ]]; then
  # 归属闸门（同 write-trace-hook.sh）：owner 为空（未认领）或等于本人才采纳，
  # 防止他人 .dac/state.json 随主分支误合并进本地后，把本人历史提交记到别人 req_name 下
  _owner=$(jq -r '.owner_committer // empty' "$_state_file" 2>/dev/null || true)
  [[ -z "$_owner" || "$_owner" == "$EMAIL" ]] && REQ=$(jq -r '.req_name // empty' "$_state_file" 2>/dev/null || true)
fi
if [[ -z "$REQ" && -f ".dac/req-bind" ]]; then
  _bind_req=$(jq -r '.req // empty' ".dac/req-bind" 2>/dev/null || true)
  _bind_branch=$(jq -r '.branch // empty' ".dac/req-bind" 2>/dev/null || true)
  _bind_committer=$(jq -r '.committer // empty' ".dac/req-bind" 2>/dev/null || true)
  _cur_branch=$(git symbolic-ref --short HEAD 2>/dev/null || true)
  if [[ -n "$_bind_req" && "$_bind_branch" == "$_cur_branch" && ( -z "$_bind_committer" || "$_bind_committer" == "$EMAIL" ) ]]; then
    REQ="$_bind_req"
  fi
fi
if [[ -z "$REQ" ]]; then
  _branch=$(git symbolic-ref --short HEAD 2>/dev/null || true)
  REQ=$(printf '%s' "$_branch" | grep -oE 'T-IBT-[0-9]+' | head -1 || true)
  [[ -z "$REQ" ]] && REQ=$(printf '%s' "$_branch" | grep -oE 'R-IBG-[0-9]+' | head -1 || true)
fi
[[ -n "$REQ" ]] || { echo "[backfill-history] ❌ 无法推导 req_name（state.json / req-bind / 分支名均未命中）" >&2; exit 1; }

# ── 提交归属时间下界（根因修复）─────────────────────────────────────────────
# merge-base 在 develop/master 等长期共享分支上会回溯到最初分叉点（可能数年前），
# 把大量与本需求无关的历史提交误算进来。需求「绑定/创建之前」的提交必不属于它，
# 故以绑定时间为 --since 下界：state.json.created_at → req-bind.bound_at → req-bind mtime。
SINCE_TS=""
# 归属闸门（同上方 REQ 推导）：非本人拥有的 state.json 不采纳其时间基线，
# 否则即便 REQ 已回退到分支名兜底，SINCE_TS 仍可能沿用外来仓库文件的时间，
# 导致该（正确的）REQ 下的历史提交范围被污染。
if [[ -n "$_state_file" && ( -z "$_owner" || "$_owner" == "$EMAIL" ) ]]; then
  SINCE_TS=$(jq -r '.created_at // empty' "$_state_file" 2>/dev/null || true)
fi
if [[ -z "$SINCE_TS" ]]; then
  _cur_branch=$(git symbolic-ref --short HEAD 2>/dev/null || true)
  for _bf in ".dac/req-bind" "../.dac/req-bind"; do
    [[ -f "$_bf" ]] || continue
    # 与 REQ 推导（上方）一致：branch 不匹配说明已切换分支、req-bind 残留失效，
    # 不能用其时间基线，跳过（否则会把不相关需求的绑定时间当作本 REQ 下界）。
    _sb_branch=$(jq -r '.branch // empty' "$_bf" 2>/dev/null || true)
    [[ -n "$_sb_branch" && "$_sb_branch" == "$_cur_branch" ]] || continue
    _sb_committer=$(jq -r '.committer // empty' "$_bf" 2>/dev/null || true)
    [[ -z "$_sb_committer" || "$_sb_committer" == "$EMAIL" ]] || continue
    SINCE_TS=$(jq -r '.bound_at // empty' "$_bf" 2>/dev/null || true)
    # 旧版 req-bind 无 bound_at，退回文件 mtime（BSD/GNU stat 均兼容）
    [[ -z "$SINCE_TS" ]] && SINCE_TS=$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S' "$_bf" 2>/dev/null || stat -c '%y' "$_bf" 2>/dev/null || true)
    [[ -n "$SINCE_TS" ]] && break
  done
fi
_since_args=()
if [[ -n "$SINCE_TS" ]]; then
  _since_args=(--since="$SINCE_TS")
  echo "[backfill-history] 提交归属时间下界 --since=${SINCE_TS}（早于此的历史提交不计入本需求）" >&2
fi

# ── base 推导：显式 --base 优先，否则取与默认分支的 merge-base ───────────────
if [[ -z "$BASE_REF" ]]; then
  for _b in origin/main origin/master main master; do
    if git rev-parse --verify -q "$_b" >/dev/null 2>&1; then
      BASE_REF=$(git merge-base "$TIP_REF" "$_b" 2>/dev/null || true)
      [[ -n "$BASE_REF" ]] && break
    fi
  done
fi
[[ -n "$BASE_REF" ]] || { echo "[backfill-history] ❌ 无法推导 base，请用 --base <ref> 指定需求分支起点（拒绝默认全历史）" >&2; exit 1; }

echo "[backfill-history] req_name=$REQ committer=$EMAIL repo_path=$REPO_PATH" >&2
echo "[backfill-history] 范围 ${BASE_REF}..${TIP_REF}（--no-merges，仅本人提交）" >&2
[[ "$DRY_RUN" -eq 1 ]] && echo "[backfill-history] ⚠️  DRY-RUN：不写 note、不上报" >&2

# ── 遍历历史提交（升序，跳过已有 note 者）──────────────────────────────────
# 先校验 range 合法：区分「范围内无新提交」（正常）与「base/branch 是无效 ref」（错误），
# 避免无效 range 被 git log 静默降级为空历史后误报「补报 0 个提交」成功完成。
git rev-list "${BASE_REF}..${TIP_REF}" >/dev/null 2>&1 \
  || { echo "[backfill-history] ❌ 无效的提交范围 ${BASE_REF}..${TIP_REF}（检查 --base/--branch）" >&2; exit 1; }

_reported=0; _skipped=0; _failed=0; _sum_add=0; _sum_del=0

# 代码白名单 numstat pathspec 构造一次（循环内各提交复用，数组不随提交变化）
dac_build_numstat_pathspec

while read -r _commit _ts_s; do
  [[ -n "$_commit" ]] || continue
  # 去重键：已有 dac-trace note → 已被 hook 处理或已回填过，跳过（含那次已计入的最近提交）
  if git notes --ref=refs/notes/dac-trace list "$_commit" >/dev/null 2>&1; then
    _skipped=$(( _skipped + 1 )); continue
  fi

  # 仅统计代码文件（正向白名单 include + 排除生成/依赖锁/构建产物），与 setup-hook-wrapper.sh
  # post-commit hook 同口径，白名单单一来源见 lib.sh 的 DAC_CODE_EXTENSIONS/DAC_GENERATED_EXCLUDE
  # （DAC_NUMSTAT_PATHSPEC 已在循环外构造）。数组元素带引号扩展，git 收到字面 *.dart 不被 shell glob 误展开。
  _stats=$(git show --numstat --format="" "$_commit" -- "${DAC_NUMSTAT_PATHSPEC[@]}" 2>/dev/null \
    | awk '{if ($1 != "-") a+=$1; if ($2 != "-") d+=$2} END {print (a+0), (d+0)}')
  _la=$(printf '%s' "$_stats" | cut -d' ' -f1); _la=${_la:-0}
  _ld=$(printf '%s' "$_stats" | cut -d' ' -f2); _ld=${_ld:-0}
  _ts_ms=$(( ${_ts_s:-0} * 1000 ))

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] ${_commit:0:8} +${_la}/-${_ld}" >&2
    _reported=$(( _reported + 1 )); _sum_add=$(( _sum_add + _la )); _sum_del=$(( _sum_del + _ld )); continue
  fi

  _body=$(jq -cn --arg c "$EMAIL" --arg r "$REQ" --arg rp "$REPO_PATH" --arg lc "$_commit" \
    --argjson lts "$_ts_ms" --argjson la "$_la" --argjson ld "$_ld" \
    '{committer:$c, req_name:$r, repo_path:$rp, last_commit:$lc, last_commit_ts:$lts, lines_added:$la, lines_deleted:$ld, source:"history-backfill"}')

  # 先上报成功、再写 note，保证「有 note ⟺ 已上报」；失败不写 note，下次重跑重试
  if curl --max-time 10 --silent --fail -X POST "$BASE_URL/api/v1/trace/commit-stats" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "$_body" >/dev/null 2>&1; then
    _note=$(jq -cn --arg r "$REQ" --arg ce "$EMAIL" --arg cn "$NAME" \
      --argjson cts "$_ts_ms" --arg nid "${_commit:0:8}" \
      '{req_name:$r, workflow_session_ids:["dac-history-backfill"], phases:[], features:[], committer:$ce, committer_name:$cn, commit_ts:$cts, note_id:$nid, source:"history-backfill"}')
    if git notes --ref=refs/notes/dac-trace add -f -m "$_note" "$_commit" 2>/dev/null; then
      echo "  ✓ ${_commit:0:8} +${_la}/-${_ld}" >&2
      _reported=$(( _reported + 1 )); _sum_add=$(( _sum_add + _la )); _sum_del=$(( _sum_del + _ld ))
    else
      # 上报成功但 note 写入失败：不算成功。否则下次重跑因该提交无 note 而再次上报，
      # 破坏「有 note ⟺ 已上报」不变式并导致后端重复累加。显式告警促人工排查（权限/锁冲突）。
      echo "  ⚠️  ${_commit:0:8} 已上报但 note 写入失败（下次重跑会再次上报导致重复累加，请排查 git notes 写入权限/锁冲突）" >&2
      _failed=$(( _failed + 1 ))
    fi
  else
    echo "  ✗ ${_commit:0:8} 上报失败（下次重跑重试）" >&2
    _failed=$(( _failed + 1 ))
  fi
# 空数组用 ${a[@]+"${a[@]}"} 安全展开：macOS 默认 bash 3.2 下 set -u 直接展开空数组会报 unbound variable
done < <(git log --no-merges --reverse --fixed-strings --committer="$EMAIL" "${_since_args[@]+"${_since_args[@]}"}" --format="%H %ct" "${BASE_REF}..${TIP_REF}")

echo "[backfill-history] 完成：补报 ${_reported} 个提交（+${_sum_add}/-${_sum_del} 行），跳过 ${_skipped} 个（已有 note），失败 ${_failed} 个" >&2
if [[ "$DRY_RUN" -eq 0 && "$_reported" -gt 0 ]]; then
  echo "[backfill-history] 提示：新写入的 notes 会在下次 git push 时由 pre-push hook 自动带上远端；" >&2
  echo "[backfill-history]       或手动 git push <remote> refs/notes/dac-trace:refs/notes/dac-trace" >&2
fi

# 存在失败提交时以非 0 退出，供 CI/自动化据此判断需要重跑（0=全部成功，2=有失败）
[[ "$_failed" -eq 0 ]] || exit 2
