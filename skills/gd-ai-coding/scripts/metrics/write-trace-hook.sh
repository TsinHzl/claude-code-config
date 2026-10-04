#!/usr/bin/env bash
# =============================================================================
# write-trace-hook.sh — PostToolUse:Write|Edit|MultiEdit 触发的实时 trace 记录与后端上报
# =============================================================================
#
# 职责（两条并行管道，无分类判断，共用同一份 stdin 解析 + 净增行数计算）：
#   1. 个人总量管道（无条件，但仅统计代码文件改动）：任意目录、是否绑定 DDP 需求均无关，
#      只要 git 身份可用且改动文件为代码文件（扩展名白名单），即记录 (committer, repo_path)
#      维度的累计估算行数并异步上报；非代码文件（文档/配置/数据等）改动不计入。
#   2. 需求维度管道（现有逻辑，行为不变）：仅当当前 git 身份对 `.dac/state.json` 或
#      `.dac/req-bind` 拥有归属权时，追加 write_events 到 `.dac/trace/<req>.json` 并
#      异步上报；未认领 `.dac` 数据源的目录完全不触发自愈/回填/记录。
#   任一路径失败不影响另一路径，也不能阻塞或影响触发它的工具调用本身。
#
# 配置方式（由各客户端原生 Hook 配置注入；本机执行过一次 install.sh 后对所有本地
# 仓库生效，无需逐项目安装）：
#   Claude Code: PostToolUse matcher "Write|Edit|MultiEdit"
#   Codex: PostToolUse 的 apply_patch 适配器
#
# 身份归属（需求维度管道）：
#   - .dac/state.json.owner_committer / .dac/req-bind.committer 记录创建时的
#     git user.email；字段缺失或空串同等视为"未认领"，首次触发时自动认领
#   - git user.email 未配置（空串）时两条管道均直接跳过，避免"空串对空串"误匹配
#   - req-bind 额外校验 branch 字段与当前分支一致（复用 bind-req.sh 既有约定），
#     不一致（切换分支后残留）时忽略该数据源
#   - state.json 与 req-bind 均无归属权（或均不存在）时不创建任何 .dac 文件，
#     个人总量管道不受影响，照常执行
#
# 退出码：始终 0（不使用 set -e，各步骤自行 `|| true`/`2>/dev/null` 兜底）
# =============================================================================

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPTS_DIR/runtime.sh" 2>/dev/null
dac_resolve_runtime 2>/dev/null || exit 0
[[ "$DAC_RUNTIME" == claude ]] || exit 0
source "$SCRIPTS_DIR/lib.sh" 2>/dev/null
source "$SCRIPTS_DIR/metrics/report-trace-backend.sh" 2>/dev/null

STATE_FILE=".dac/state.json"
BIND_FILE=".dac/req-bind"

# === 公共前置逻辑：无条件执行，服务下方两条管道 ===================

command -v jq >/dev/null 2>&1 || exit 0

# --- 1. 解析 PostToolUse stdin ---
INPUT=$(cat 2>/dev/null)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

case "$TOOL_NAME" in
  Write|Edit|MultiEdit) ;;
  *) exit 0 ;;
esac

CUR_COMMITTER=$(git config user.email 2>/dev/null || echo "")
[[ -n "$CUR_COMMITTER" ]] || exit 0

# --- 2. 计算本次「仅新增行」（两条管道共用同一份计算结果）---
# 纯 jq 计算，避免 bash 处理多行代码内容；Edit/MultiEdit 用 new-old 净增（下限 0），
# Write 因 PostToolUse 在写入后触发、拿不到旧文件内容，统一按 content 全行计（实时估算）。
# 取不到对应字段（缺失/非字符串）时本次记 0，不影响主流程。
_added=$(printf '%s' "$INPUT" | jq -r '
  def lc: if (. // "") == "" then 0 else (tostring | split("\n") | length) end;
  def edit_added(o; n): (((n | lc) - (o | lc)) | if . > 0 then . else 0 end);
  .tool_input as $ti |
  ( if   .tool_name == "Edit"      then edit_added($ti.old_string; $ti.new_string)
    elif .tool_name == "MultiEdit" then ([ ($ti.edits // [])[] | edit_added(.old_string; .new_string) ] | add // 0)
    elif .tool_name == "Write"     then ($ti.content | lc)
    else 0 end )
' 2>/dev/null)
[[ "$_added" =~ ^[0-9]+$ ]] || _added=0

# 代码文件白名单判定改用 lib.sh 的 `dac_is_code_file`（单一来源），需求维度与个人总量
# 两条管道共用同一份扩展名清单，消除重复定义与口径漂移。

# === 个人总量管道：无条件执行一次，与 .dac 是否存在无关 =====================
# 本地维护 (committer, repo_path) 维度的累计估算总量——与需求维度管道
# `.dac/trace/*.json` 的 write_lines_added 同一语义（整份估算累计值，后端 SET 覆盖式
# 上报），但存放在 skill 自身状态目录下，不在用户项目目录里创建任何文件。
_personal_state_dir="$DAC_STATE_HOME/personal-trace"
mkdir -p "$_personal_state_dir" 2>/dev/null
_personal_repo=$(_dac_trace_repo_path 2>/dev/null)
if [[ -n "$_personal_repo" ]] && dac_is_code_file "$FILE_PATH"; then
  _personal_key="${CUR_COMMITTER}__${_personal_repo}"
  _personal_safe_key="${_personal_key//[^A-Za-z0-9._-]/_}"
  _personal_file="$_personal_state_dir/${_personal_safe_key}.json"
  [[ -f "$_personal_file" ]] || echo '{"committed_total":0,"total":0,"count":0,"unused_total":0,"files":{}}' > "$_personal_file" 2>/dev/null
  # 代码比例「未走流程」桶：以本次 Write 当时是否已有认领数据源为准（本管道在自动认领之前执行）。
  # 有 .dac/state.json 或 .dac/req-bind → 算流程内，不累加 unused_total；否则累加与 .total 相同的增量。
  _had_dac=0
  if [[ -f "$STATE_FILE" || -f "$BIND_FILE" ]]; then
    _had_dac=1
  fi
  # Write 拿不到旧内容，按整份文件全行计；同一文件在一次提交周期内被反复 Write 会被重复计入
  # 全文长度，导致 .total 远超真实新增行数。用 .files[路径] 记录本提交周期内出现过的最大估算
  # 长度作为高水位线，只把「超出高水位线」的部分计入 .total（Edit/MultiEdit 的 _added 本身已是
  # 净增 diff，不受影响，原样累加）。
  if [[ "$TOOL_NAME" == "Write" ]]; then
    atomic_jq '
      (.files[$fp] // 0) as $prev |
      (if $a > $prev then $a - $prev else 0 end) as $delta |
      .total = ((.total // 0) + $delta) |
      .unused_total = (if $dac == 1 then (.unused_total // 0) else ((.unused_total // 0) + $delta) end) |
      .files[$fp] = (if $a > $prev then $a else $prev end) |
      .count = ((.count // 0) + 1)
    ' "$_personal_file" --argjson a "$_added" --arg fp "$FILE_PATH" --argjson dac "$_had_dac" 2>/dev/null
  else
    atomic_jq '
      .total = ((.total // 0) + $a) |
      .unused_total = (if $dac == 1 then (.unused_total // 0) else ((.unused_total // 0) + $a) end) |
      .count = ((.count // 0) + 1)
    ' "$_personal_file" --argjson a "$_added" --argjson dac "$_had_dac" 2>/dev/null
  fi
  # 上报值 = committed_total（提交后精确 diff 累加，由 post-commit hook 维护）+ total（未提交实时估算）。
  # 旧 schema 无 committed_total 时按 0 计，上报值即旧 total，下次提交由 post-commit 校正回落精确值。
  _personal_committed=$(jq -r '.committed_total // 0' "$_personal_file" 2>/dev/null)
  [[ "$_personal_committed" =~ ^[0-9]+$ ]] || _personal_committed=0
  _personal_uncommitted=$(jq -r '.total // 0' "$_personal_file" 2>/dev/null)
  [[ "$_personal_uncommitted" =~ ^[0-9]+$ ]] || _personal_uncommitted=0
  _personal_total=$(( _personal_committed + _personal_uncommitted ))
  _personal_count=$(jq -r '.count // 0' "$_personal_file" 2>/dev/null)
  [[ "$_personal_count" =~ ^[0-9]+$ ]] || _personal_count=0
  _personal_unused=$(jq -r '.unused_total // 0' "$_personal_file" 2>/dev/null)
  [[ "$_personal_unused" =~ ^[0-9]+$ ]] || _personal_unused=0

  (
    _report_personal_trace "$_personal_total" "$_personal_count" "$_personal_unused" 2>/dev/null
  ) >/dev/null 2>&1 &
  disown 2>/dev/null
fi

# === 需求维度管道：仅当已认领 .dac 数据源时执行（现有逻辑，行为不变） =======
# 提取为函数并用早退 guard 代替外层双重 if 包裹，将嵌套深度压回 <=4 层（原两层
# `if STATE_FILE||BIND_FILE` + `if -n _use_source` 包裹会把内部自愈/回填的既有嵌套
# 顶到 5 层）；函数体本身逻辑与改动前完全一致，仅改变早退实现方式。
_run_requirement_dimension_pipeline() {
  [[ -f "$STATE_FILE" || -f "$BIND_FILE" ]] || return 0

  # --- 3. 身份校验（含空邮箱兜底与自动认领） ---
  _use_source=""

  if [[ -f "$STATE_FILE" ]]; then
    _owner=$(jq -r '.owner_committer // ""' "$STATE_FILE" 2>/dev/null)
    if [[ -z "$_owner" ]]; then
      atomic_jq '.owner_committer = $c' "$STATE_FILE" --arg c "$CUR_COMMITTER" 2>/dev/null
      _use_source="state"
    elif [[ "$_owner" == "$CUR_COMMITTER" ]]; then
      _use_source="state"
    fi
  fi

  if [[ -z "$_use_source" && -f "$BIND_FILE" ]]; then
    _bind_branch=$(jq -r '.branch // ""' "$BIND_FILE" 2>/dev/null)
    _cur_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
    # 分支一致性校验复用 setup-hook-wrapper.sh:96 的既有约定：直接字符串相等判断
    # "一致"，而非用 -n 短路判断"不一致"——避免 branch 为空串（detached HEAD 残留绑定）
    # 时被误判为"一致"从而无条件采纳该数据源
    if [[ "$_bind_branch" == "$_cur_branch" ]]; then
      _bind_committer=$(jq -r '.committer // ""' "$BIND_FILE" 2>/dev/null)
      if [[ -z "$_bind_committer" ]]; then
        atomic_jq '.committer = $c' "$BIND_FILE" --arg c "$CUR_COMMITTER" 2>/dev/null
        _use_source="bind"
      elif [[ "$_bind_committer" == "$CUR_COMMITTER" ]]; then
        _use_source="bind"
      fi
    fi
  fi

  [[ -n "$_use_source" ]] || return 0

  # --- 3.5 自愈：升级缺「提交后清零」/「owner 归属闸门」/「代码白名单口径」逻辑的旧版 post-commit hook ---
  # 旧版 hook（实时特性前安装）提交后不清零 write_lines_added，与 commit 链路 lines_added 叠加致行数偏高；
  # 更早的版本还缺 owner 归属闸门（别人的 .dac/ 随主分支合并进本地后会把本人提交误记到别人 req 名下）；
  # 本次新增「代码白名单口径」后，旧版 hook 的 numstat 仍把 .md/配置/数据等非代码改动计入 lines_added。
  # setup-hook-wrapper.sh 幂等检查已能识别并强制重装，但它仅在 init/--resume 被调，存量仓库无人手动重跑；
  # 故在此（全局最新、每次编辑都触发的 hook）自愈一次。mkdir 原子锁防并发重写；重装后新 hook 同时含
  # RESET_MARKER、OWNER_MARKER(skip-foreign-owner)、INCLUDE_MARKER(code-include-whitelist)、
  # PERSONAL_MARKER(personal-reconcile)、WRITE_DEDUP_MARKER(write-dedup-reset)、
  # FRONTEND_MARKER(code-include-frontend)、UNUSED_MARKER(unused-workflow-lines) 七者皆命中才跳过
  # （与 setup-hook-wrapper.sh 幂等检查的 marker 集合保持同步，任缺其一即重装；自限，只升一次；
  # 失败则锁释放，下次编辑自动重试）。
  _dac_git_dir="$(git rev-parse --git-dir 2>/dev/null)"
  _dac_hooks_dir="$_dac_git_dir/dac-hooks"
  if [[ -n "$_dac_git_dir" ]] \
     && [[ "$(git config core.hooksPath 2>/dev/null)" == "$_dac_hooks_dir" ]] \
     && [[ -f "$_dac_hooks_dir/post-commit" ]] \
     && ! { grep -q "提交后清零本地实时写入行数" "$_dac_hooks_dir/post-commit" 2>/dev/null \
            && grep -q "DAC: skip-foreign-owner" "$_dac_hooks_dir/post-commit" 2>/dev/null \
            && grep -q "DAC: code-include-whitelist" "$_dac_hooks_dir/post-commit" 2>/dev/null \
            && grep -q "DAC: personal-reconcile" "$_dac_hooks_dir/post-commit" 2>/dev/null \
            && grep -q "DAC: write-dedup-reset" "$_dac_hooks_dir/post-commit" 2>/dev/null \
            && grep -q "DAC: code-include-frontend" "$_dac_hooks_dir/post-commit" 2>/dev/null \
            && grep -q "DAC: unused-workflow-lines" "$_dac_hooks_dir/post-commit" 2>/dev/null; }; then
    _heal_wrapper="$DAC_SKILL_HOME/scripts/metrics/setup-hook-wrapper.sh"
    _heal_lock="$_dac_git_dir/.dac-hook-heal.lock"
    # 清理孤儿锁：后台进程异常终止（未 rmdir）会残留锁目录、永久禁用自愈；
    # 锁存活超过 1 分钟（重装实际 <1s）即视为孤儿，强制清理后重试
    if [[ -d "$_heal_lock" ]] && [[ -n "$(find "$_heal_lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]]; then
      rmdir "$_heal_lock" 2>/dev/null
    fi
    if [[ -f "$_heal_wrapper" ]] && mkdir "$_heal_lock" 2>/dev/null; then
      ( bash "$_heal_wrapper" >/dev/null 2>&1; rmdir "$_heal_lock" 2>/dev/null ) &
      disown 2>/dev/null
    fi
  fi

  # --- 3.6 一次性回填：补齐 hook 安装前丢失的历史提交行数（每仓库后台静默一次）---
  # write-trace-hook 是全局高频入口，覆盖所有装了 hook 的仓库；标记文件保证每仓库只自动
  # 回填一次（回填脚本自身按 git note 去重幂等，标记仅为省去每次编辑的 git log 遍历开销）。
  # 仅回填脚本 exit 0（成功）才建标记：暂无后端配置(exit 1)/网络部分失败(exit 2) 时不留
  # 标记，下次编辑自动重试。后台 disown 不阻塞工具调用。复用自愈段已求值的 _dac_git_dir。
  if [[ -n "$_dac_git_dir" ]]; then
    _backfill_sh="$DAC_SKILL_HOME/scripts/metrics/backfill-commit-stats-from-history.sh"
    _backfill_done="$_dac_git_dir/.dac-backfill-done"
    _backfill_lock="$_dac_git_dir/.dac-backfill.lock"
    _backfill_tw="$DAC_SKILL_HOME/scripts/timeout-wrapper.sh"
    if [[ -x "$_backfill_sh" ]] && [[ ! -f "$_backfill_done" ]]; then
      # 清理孤儿锁：回填含 curl 可能耗时，超 15 分钟未释放视为异常残留（> 下方 600s timeout 上限）
      if [[ -d "$_backfill_lock" ]] && [[ -n "$(find "$_backfill_lock" -maxdepth 0 -mmin +15 2>/dev/null)" ]]; then
        rmdir "$_backfill_lock" 2>/dev/null
      fi
      if mkdir "$_backfill_lock" 2>/dev/null; then
        # timeout-wrapper 封顶 600s，避免 curl 挂起使回填运行超孤儿锁阈值、被误判后并发多实例；
        # 顺序：先跑回填→无条件释放锁→仅 exit 0 才建标记（先释放锁保证锁必被清，最坏多回填
        # 一次而回填自身按 note 幂等；touch 失败也仅致下次重跑，不会残留永久锁）。
        (
          if [[ -x "$_backfill_tw" ]]; then
            bash "$_backfill_tw" 600 bash "$_backfill_sh"
          else
            bash "$_backfill_sh"
          fi
          _bf_rc=$?
          rmdir "$_backfill_lock" 2>/dev/null
          [[ "$_bf_rc" -eq 0 ]] && touch "$_backfill_done" 2>/dev/null
        ) </dev/null >/dev/null 2>&1 &
        disown 2>/dev/null
      fi
    fi
  fi

  # --- 4a. 文件类型门控：仅代码文件计入需求维度统计 ---
  # 复用 lib.sh 单一来源白名单（.md/配置/数据/图片等非代码编辑不累加 write_lines_added、
  # 不追加 write_events、不触发 /report）。置于 req_name 解析与 trace 文件创建之前，
  # 保证非代码编辑不会创建/改动 .dac/trace/<req>.json。自愈重装/历史回填已在上方执行，不受影响。
  dac_is_code_file "$FILE_PATH" || return 0

  # --- 4. req_name 解析（state.json 优先于 req-bind） ---
  if [[ "$_use_source" == "state" ]]; then
    _req_name=$(jq -r '.req_name // "untitled"' "$STATE_FILE" 2>/dev/null)
  else
    _req_name=$(jq -r '.req // "untitled"' "$BIND_FILE" 2>/dev/null)
  fi
  [[ -n "$_req_name" && "$_req_name" != "null" ]] || _req_name="untitled"
  _safe_req="${_req_name//[^A-Za-z0-9._-]/_}"
  _trace_file=".dac/trace/${_safe_req}.json"

  mkdir -p ".dac/trace" 2>/dev/null
  [[ -f "$_trace_file" ]] || echo '{}' > "$_trace_file" 2>/dev/null

  # --- 5. atomic_jq 一次性追加 write_events + 累加 write_lines_added（合并为单次加锁写入）---
  atomic_jq '.write_events = ((.write_events // []) + [{tool: $t, file: $f, ts: (now * 1000 | floor)}])
             | .write_lines_added = ((.write_lines_added // 0) + $a)' \
    "$_trace_file" --arg t "$TOOL_NAME" --arg f "$FILE_PATH" --argjson a "$_added" 2>/dev/null

  # --- 6. 立即异步上报：每次编辑后即时上报，不做防抖窗口 ---
  # 派生 disown 后台子进程立即调用 _report_progress，不阻塞触发它的工具调用。
  # write_lines_added 为累计总量，后端 /report 对其为覆盖（SET）语义，连续编辑重复
  # 上报幂等安全（每次上报都是"当前累计值"的全量覆盖，无重复计数）。
  (
    _report_progress "$_trace_file" 2>/dev/null
  ) >/dev/null 2>&1 &
  disown 2>/dev/null
}
_run_requirement_dimension_pipeline

exit 0
