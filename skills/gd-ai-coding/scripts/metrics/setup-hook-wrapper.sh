#!/usr/bin/env bash
# =============================================================================
# setup-hook-wrapper.sh — 在当前 git repo 安装 DAC post-commit hook 包装层
# =============================================================================
#
# 背景：
#   我们需要在每次 git commit 时把工作流追踪数据写入 git notes（refs/notes/dac-trace），
#   以便数据随 git push 持久化，后端可以通过 git notes 读取。
#
#   git-ai 也使用 post-commit hook（位于 .git/ai/hooks/post-commit）写入
#   refs/notes/ai（AI 代码归因数据）。两者都需要在 commit 后执行。
#
# 方案：
#   创建 .git/dac-hooks/ 目录，将其设为 git 的 hooksPath（覆盖默认的 .git/hooks/）。
#   其中的 post-commit 脚本先写 DAC trace notes，再转发给 git-ai 的 hook。
#   其他 hook 类型（pre-commit、pre-push 等）分两遍转发：先 .git/hooks/ 中已有的，
#   再 .git/ai/hooks/ 中 git-ai 独有的，保证两方的 hook 都能执行。
#
#   数据流：
#     git commit
#       → .git/dac-hooks/post-commit（我们的包装层）
#           → 写 refs/notes/dac-trace（追踪数据落入 git 历史）
#           → 转发 .git/ai/hooks/post-commit（git-ai 写 refs/notes/ai）
#
# 幂等性：
#   已配置且 post-commit 内容包含 MARKER 则跳过，重复执行安全。
#
# 调用时机：
#   init-dac.sh 的 _setup_hooks()，每次 init 或 --resume 时执行。
#   git ai checkpoint 可能会重置 core.hooksPath，--resume 会重新注册。
# =============================================================================

set -euo pipefail

# source lib.sh 复用代码白名单单一来源（生成 post-commit hook 时展开 numstat pathspec）
_SETUP_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$_SETUP_SCRIPTS_DIR/lib.sh"

# post-commit 内容中的标识符，用于幂等检查
MARKER="# DAC: write trace to git notes"
# 提交后「清零 write_lines_added」逻辑的标识符——旧版 hook 缺失此段，据此强制重装，
# 否则后端 write_lines_added 永不清零，与 commit 链路 lines_added 叠加导致行数虚高
RESET_MARKER="提交后清零本地实时写入行数"
# 行数统计「代码白名单口径」标识符——旧版 hook（含旧的纯 exclude 黑名单口径）缺此段则强制重装，
# 使存量仓库自愈升级到「仅统计代码文件」的新口径，否则 .md/配置/数据等非代码改动继续计入 lines_added
INCLUDE_MARKER="DAC: code-include-whitelist"
# owner 归属闸门标识符——旧版 hook 缺此段则强制重装：别人把 .dac/ 提交进主分支并被本地合并后，
# 其 state.json（owner_committer 记原作者）会占据本地 .dac/state.json，旧 hook 不校验 owner
# 会把本人提交误记到别人的 req_name 名下上报
OWNER_MARKER="DAC: skip-foreign-owner"
# 个人总量(vibe coding)提交后校正标识符——旧版 hook 缺此段则强制重装：个人总量管道的实时估算
# (Write 按整份文件全行计)只加不减、提交后从不回落，导致 vibe coding 行数虚高；新 hook 提交后
# 用精确 numstat 累加 committed_total 并清零实时估算，使行数回落精确值
PERSONAL_MARKER="DAC: personal-reconcile"
# 个人总量 Write 全文重复计数修复标识符——旧版 hook 提交后只清零 total、不清空按文件记录的高
# 水位线 files，跨提交周期残留会让下一轮去重基准出错；此标识符触发存量仓库自愈重装
WRITE_DEDUP_MARKER="DAC: write-dedup-reset"
# 前端组件/样式白名单标识符——post-commit hook 的 numstat pathspec 在生成期展开为字面串，
# 存量 hook 缺 vue/svelte/astro/css/scss/sass/less，会把前端仓库的组件与样式改动整体漏计；
# 此标识符触发存量仓库自愈重装，使新白名单对「提交后精确 diff」口径生效
FRONTEND_MARKER="DAC: code-include-frontend"
# 未走流程行（unused_workflow_lines）提交后原样上报标识符——旧 hook 校正段只报
# total/count，第三参缺省会使服务端看不到该字段（保留原值，但新机首次只走 post-commit
# 时永远不上报 unused）。缺此段则强制重装。
UNUSED_MARKER="DAC: unused-workflow-lines"
# 运行时 bootstrap 标识符——post-commit 由 Git 直接拉起，不能假设继承客户端环境变量。
RUNTIME_MARKER="DAC: runtime-bootstrap"

# 确认当前在 git repo 内
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null) || { echo "not a git repo, skipped"; exit 0; }

# git-ai 的 hook 目录（转发目标）
GITAI_HOOKS="$GIT_DIR/ai/hooks"
# 我们的包装层 hook 目录
DAC_HOOKS="$GIT_DIR/dac-hooks"

# 幂等检查：core.hooksPath 已指向包装层 且 post-commit 含 MARKER 且 pre-push 存在，说明已配置
if [[ "$(git config core.hooksPath 2>/dev/null || true)" == "$DAC_HOOKS" ]] && \
   grep -q "$MARKER" "$DAC_HOOKS/post-commit" 2>/dev/null && \
   grep -q "$RESET_MARKER" "$DAC_HOOKS/post-commit" 2>/dev/null && \
   grep -q "$INCLUDE_MARKER" "$DAC_HOOKS/post-commit" 2>/dev/null && \
   grep -q "$OWNER_MARKER" "$DAC_HOOKS/post-commit" 2>/dev/null && \
   grep -q "$PERSONAL_MARKER" "$DAC_HOOKS/post-commit" 2>/dev/null && \
   grep -q "$WRITE_DEDUP_MARKER" "$DAC_HOOKS/post-commit" 2>/dev/null && \
   grep -q "$FRONTEND_MARKER" "$DAC_HOOKS/post-commit" 2>/dev/null && \
   grep -q "$UNUSED_MARKER" "$DAC_HOOKS/post-commit" 2>/dev/null && \
   grep -q "$RUNTIME_MARKER" "$DAC_HOOKS/post-commit" 2>/dev/null && \
   [[ -x "$DAC_HOOKS/pre-push" ]]; then
  echo "already configured, skipped"
  exit 0
fi

mkdir -p "$DAC_HOOKS"

# -----------------------------------------------------------------------------
# post-commit 包装脚本
# 用 heredoc 写入，单引号 'HOOK' 避免变量展开（脚本运行时才展开）
# -----------------------------------------------------------------------------
cat > "$DAC_HOOKS/post-commit" << 'HOOK'
#!/usr/bin/env bash
# DAC: write trace to git notes
# DAC: runtime-bootstrap
# Git 直接执行 hook 时不保证继承 Claude/Codex 的 shell 环境；使用安装时写入的
# runtime.sh 解析当前客户端根目录。解析失败时保留原 hook 转发能力，并静默跳过 DAC 路径。
DAC_SKILL_HOME="${DAC_SKILL_HOME:-}"
DAC_STATE_HOME="${DAC_STATE_HOME:-}"
DAC_CONFIG_HOME="${DAC_CONFIG_HOME:-}"
_DAC_RUNTIME_SCRIPT=@@DAC_RUNTIME_SCRIPT@@
if [[ -f "$_DAC_RUNTIME_SCRIPT" ]]; then
  # shellcheck source=/dev/null
  source "$_DAC_RUNTIME_SCRIPT" 2>/dev/null && dac_resolve_runtime 2>/dev/null || true
fi
: "${DAC_SKILL_HOME:=/dev/null}"
: "${DAC_STATE_HOME:=/dev/null}"
: "${DAC_CONFIG_HOME:=/dev/null}"
export DAC_SKILL_HOME DAC_STATE_HOME DAC_CONFIG_HOME
#
# req_name 查找优先级：
#   1. .dac/state.json（完整 DAC 工作流，最高优先级）
#   2. .dac/req-bind（轻量绑定，含分支一致性校验，jq 不可用时静默跳过）
#   3. 当前分支名中的 T-IBT-XXXXXX 模式，未命中回退 R-IBG-XXXXXX（零配置兜底，任务优先）
# 三者均无结果时静默退出，不写 notes。

# 补全常见 jq 安装路径（macOS brew 或 CI 环境中，IDE 触发的 hook 可能不继承完整 PATH）
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

_req=""
_dac=""
_lightweight=0

# ── 优先级 1：.dac/state.json（完整工作流）────────────────────────────────────
# 查找 .dac/：优先当前目录（git 根），其次往上一级
# 兼容 workspace 根下多 git repo 的结构（如 driver/ 下的各业务仓库）
if [ -f ".dac/state.json" ]; then
  _dac=".dac"
elif [ -f "../.dac/state.json" ]; then
  _dac="../.dac"
fi

if [ -n "$_dac" ]; then
  _req=$(jq -r '.req_name // empty' "$_dac/state.json" 2>/dev/null)
fi

# ── owner 归属闸门（DAC: skip-foreign-owner）：只处理本人拥有的 state.json ──────
# 别人把 .dac/ 提交进主分支、被本地合并后，其 state.json（owner_committer 记原作者）会占据
# 本地 .dac/state.json；若不校验，本人的提交会被误记到「别人的 req_name」名下上报。与
# write-trace-hook.sh 的实时编辑归属闸门对齐：owner 为空视为本人（向后兼容旧数据 / 自动认领），
# owner 非空且 != 当前 git 身份则弃用该 state.json，回退到 req-bind / 分支名兜底。
if [ -n "$_req" ] && [ -n "$_dac" ]; then
  _owner=$(jq -r '.owner_committer // ""' "$_dac/state.json" 2>/dev/null)
  _me=$(git config user.email 2>/dev/null || echo "")
  if [ -n "$_owner" ] && [ "$_owner" != "$_me" ]; then
    _req=""
    _dac=""
  fi
fi

# ── 优先级 2：.dac/req-bind（轻量绑定 + 分支一致性 + owner 一致性校验）────────
# jq 不可用时静默跳过，降级到优先级 3。committer 校验同 state.json：req-bind 未被 gitignore，
# 同样可能随主分支合并进本地成为「别人的数据」，committer 为空视为本人（向后兼容）。
if [ -z "$_req" ] && [ -f ".dac/req-bind" ] && command -v jq >/dev/null 2>&1; then
  _bind_req=$(jq -r '.req // empty' ".dac/req-bind" 2>/dev/null)
  _bind_branch=$(jq -r '.branch // empty' ".dac/req-bind" 2>/dev/null)
  _bind_committer=$(jq -r '.committer // empty' ".dac/req-bind" 2>/dev/null)
  _cur_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
  _me=$(git config user.email 2>/dev/null || echo "")
  if [ -n "$_bind_req" ] && [ "$_bind_branch" = "$_cur_branch" ] \
     && { [ -z "$_bind_committer" ] || [ "$_bind_committer" = "$_me" ]; }; then
    _req="$_bind_req"
    _lightweight=1
  fi
fi

# ── 优先级 3：从分支名提取 T-IBT-XXXXXX，未命中回退 R-IBG-XXXXXX（零配置兜底，任务优先）──
if [ -z "$_req" ]; then
  _branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
  _req=$(printf '%s' "$_branch" | grep -oE 'T-IBT-[0-9]+' | head -1 2>/dev/null || true)
  if [ -z "$_req" ]; then
    _req=$(printf '%s' "$_branch" | grep -oE 'R-IBG-[0-9]+' | head -1 2>/dev/null || true)
  fi
  [ -n "$_req" ] && _lightweight=1
fi

# ── DAC: personal-reconcile — 提交后把个人总量(vibe coding)回落到精确 diff ────────
# 个人总量管道(write-trace-hook.sh 无条件分支)的 .total 是实时估算(Write 按整份文件全行计,偏高)
# 且只加不减；此处无条件执行(与需求维度是否存在无关)用本次 commit 的精确 numstat 累加进
# committed_total、清零实时估算 total,报 committed_total,使 vibe coding 行数回落到精确值(与下方
# 需求维度 write_lines_added 清零同构;清零确保历史遗留虚高值下次提交即自愈)。故置于「无 req_name
# 静默退出」之前,保证无 req 也执行。按 HEAD 去重防同一提交 hook 重复触发造成 committed_total 重复累加。
_pr_lib="${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/report-trace-backend.sh"
_pr_libatomic="${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/lib.sh"
if [ -f "$_pr_lib" ] && [ -f "$_pr_libatomic" ] && command -v jq >/dev/null 2>&1; then
  . "$_pr_lib"
  _pr_committer=$(git config user.email 2>/dev/null || echo "")
  _pr_repo=$(_dac_trace_repo_path 2>/dev/null || echo "")
  if [ -n "$_pr_committer" ] && [ -n "$_pr_repo" ]; then
    _pr_head=$(git rev-parse HEAD 2>/dev/null || echo "")
    _pr_numstat=$(git show --numstat --format="" HEAD -- @@DAC_NUMSTAT_PATHSPEC@@ 2>/dev/null)
    _pr_added=$(printf '%s\n' "$_pr_numstat" | awk '{if ($1 != "-") a+=$1} END {print (a+0)}')
    _pr_dir="${DAC_STATE_HOME:?DAC_STATE_HOME 未解析}/personal-trace"
    _pr_key="${_pr_committer}__${_pr_repo}"
    _pr_safe=$(printf '%s' "$_pr_key" | sed 's/[^A-Za-z0-9._-]/_/g')
    _pr_file="$_pr_dir/${_pr_safe}.json"
    mkdir -p "$_pr_dir" 2>/dev/null
    [ -f "$_pr_file" ] || echo '{"committed_total":0,"total":0,"count":0,"files":{}}' > "$_pr_file" 2>/dev/null
    # 带锁 atomic_jq(bash 复用 lib.sh,本 hook 为 #!/bin/sh):HEAD 与上次已校正一致则跳过累加、仅清零
    # 实时估算(及跨提交周期残留的 files 高水位线,DAC: write-dedup-reset);否则累加精确行到
    # committed_total、清零 total/files、记 last_commit。与并发 write-trace-hook 互斥。
    # 清零(而非扣减)确保历史遗留的虚高 total(旧 only-add bug 累积值)下次提交即回落到精确值;代价是多文件
    # 只提交其一时其余未提交文件估算被一并清零→暂时低估,由后续编辑重新累积自我修正(known limitation)。
    bash -c '. "$1" 2>/dev/null && atomic_jq "if (.last_commit // \"\") == \$h then . else .committed_total = ((.committed_total // 0) + \$a) end | .total = 0 | .files = {} | .last_commit = \$h" "$2" --argjson a "$3" --arg h "$4"' \
      _ "$_pr_libatomic" "$_pr_file" "$_pr_added" "$_pr_head" 2>/dev/null || true
    _pr_total=$(jq -r '.committed_total // 0' "$_pr_file" 2>/dev/null)
    _pr_count=$(jq -r '.count // 0' "$_pr_file" 2>/dev/null)
    # DAC: unused-workflow-lines — 提交校正不清零 unused_total（Write 当时的分类累计）
    _pr_unused=$(jq -r '.unused_total // 0' "$_pr_file" 2>/dev/null)
    _report_personal_trace "$_pr_total" "$_pr_count" "$_pr_unused" 2>/dev/null || true
  fi
fi

# ── 无 req_name：静默退出，转发其他 hook ──────────────────────────────────────
if [ -z "$_req" ]; then
  _orig="$(git rev-parse --git-dir)/hooks/post-commit"
  [ -x "$_orig" ] && "$_orig" "$@"
  _ai="$(git rev-parse --git-dir)/ai/hooks/post-commit"
  [ -x "$_ai" ] && exec "$_ai" "$@"
  exit 0
fi

_committer_email=$(git config user.email 2>/dev/null || echo "")
_committer_name=$(git config user.name 2>/dev/null || echo "")
_commit_ts_s=$(git log -1 --format="%ct" HEAD 2>/dev/null || echo "0")
_commit_ts_ms=$(( ${_commit_ts_s:-0} * 1000 ))

# ── 完整工作流路径：从 trace 文件写 notes（含 phases/features）───────────────
if [ "$_lightweight" -eq 0 ] && [ -n "$_dac" ]; then
  # 将需求名中的特殊字符替换为 "_"，与 record-trace.sh 的命名规则保持一致
  _sf=$(printf '%s' "$_req" | sed 's/[^A-Za-z0-9._-]/_/g')
  _trace="$_dac/trace/${_sf}.json"
  if [ -f "$_trace" ]; then
    # note_id = 追踪文件内容的 SHA hash 前 8 位
    # 同一追踪状态 → 同一 note_id → 后端不重复存储
    # 追踪内容变化（新 phase/feature）→ note_id 变化 → 后端识别为新版本
    _note_id=$(git hash-object "$_trace" | cut -c1-8)
    # 将 note_id + committer 信息注入 JSON，写入 git notes（-f 强制覆盖同一 commit 的旧 note）
    # committer 字段使多仓库聚合时无需 commit 对象即可归因
    _note_json=$(jq --arg nid "$_note_id" \
                   --arg ce "$_committer_email" \
                   --arg cn "$_committer_name" \
                   --argjson cts "$_commit_ts_ms" \
                   '. + {note_id: $nid, committer: $ce, committer_name: $cn, commit_ts: $cts}' \
                   "$_trace" 2>/dev/null)
    # 附加错误日志：如有写入失败记录，附到 trace_errors 字段供后端分析数据完整性
    # 写完后清空，保证每个 commit 只带本次提交前积累的错误，不跨 commit 累积
    _errlog="$_dac/logs/trace-errors.log"
    if [ -s "$_errlog" ]; then
      _errors=$(cat "$_errlog")
      _note_json=$(printf '%s' "$_note_json" | jq --arg e "$_errors" '. + {trace_errors: $e}' 2>/dev/null)
    fi
    # notes 写入成功后才清空错误日志，避免 notes 失败时丢失错误记录
    if git notes --ref=refs/notes/dac-trace add -f -m "$_note_json" HEAD 2>/dev/null; then
      : > "$_errlog"
    fi
  fi
else
  # ── 轻量路径：构建最简 note JSON（无 phases/features）────────────────────
  # 来自 req-bind 或分支名提取，无完整工作流 trace 文件
  if command -v jq >/dev/null 2>&1; then
    _note_json=$(jq -n \
      --arg r  "$_req" \
      --arg ce "$_committer_email" \
      --arg cn "$_committer_name" \
      --argjson cts "$_commit_ts_ms" \
      '{req_name:$r, workflow_session_ids:[], phases:[], features:[], committer:$ce, committer_name:$cn, commit_ts:$cts}')
    git notes --ref=refs/notes/dac-trace add -f -m "$_note_json" HEAD 2>/dev/null || true
  fi
fi

# ── 上报 commit 统计数据到后端（不影响本地 notes 写入结果，失败静默跳过）───────
_report_lib="${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/metrics/report-trace-backend.sh"
if [ -f "$_report_lib" ]; then
  . "$_report_lib"
  _commit_hash=$(git rev-parse HEAD 2>/dev/null)
  # DAC: code-include-whitelist — 仅统计代码文件（正向白名单 include）并排除生成/依赖锁/构建产物，
  # 使 .md 文档 / 配置 / 数据等非代码改动、以及 *.g.dart / pubspec.lock 等自动生成大文件均不计入
  # lines_added。白名单单一来源见 ~/.claude/skills/gd-ai-coding/scripts/lib.sh 的 DAC_CODE_EXTENSIONS，
  # 下方 pathspec 由 setup-hook-wrapper.sh 生成期展开写入（本 hook 为 #!/bin/sh，不 source 含 bashism 的 lib.sh）。
  # DAC: code-include-frontend — 白名单含前端组件(vue/svelte/astro)与样式(css/scss/sass/less)
  _numstat=$(git show --numstat --format="" HEAD -- @@DAC_NUMSTAT_PATHSPEC@@ 2>/dev/null)
  _cs_stats=$(printf '%s\n' "$_numstat" | awk '{if ($1 != "-") a+=$1; if ($2 != "-") d+=$2} END {print (a+0), (d+0)}')
  _lines_added=$(printf '%s' "$_cs_stats" | cut -d' ' -f1)
  _lines_deleted=$(printf '%s' "$_cs_stats" | cut -d' ' -f2)
  _report_commit_stats "$_req" "$_commit_hash" "$_commit_ts_ms" "$_lines_added" "$_lines_deleted"

  # ── 提交后清零本地实时写入行数并重报 write_lines_added=0 ──────────────────────
  # 单写者：write_lines_added 仅经 /report 写入，后端不设第二写者（避免丢失更新竞态）。
  # 本次提交的行已由 commit 链路精确计入 lines_added，清零并重报确保后端求和不重复计入。
  # 必须覆盖两条路径：_trace 变量只在完整工作流分支被赋值，dac-bind 轻量路径没有它，
  # 因此独立推导 trace 路径（write-trace-hook 对 bind 身份同样累加 .dac/trace/<req>.json）。
  # 清零经 bash 复用 lib.sh 的带锁 atomic_jq（本 hook 为 #!/bin/sh，不能直接调用含 bashism
  # 的 atomic_jq），与并发 write-trace-hook 写入互斥，不破坏 write_events。
  _reset_base=""
  if [ -n "$_dac" ]; then
    _reset_base="$_dac"
  elif [ -d ".dac/trace" ] || [ -f ".dac/req-bind" ]; then
    _reset_base=".dac"
  elif [ -d "../.dac/trace" ] || [ -f "../.dac/req-bind" ]; then
    _reset_base="../.dac"
  fi
  if [ -n "$_reset_base" ]; then
    _reset_sf=$(printf '%s' "$_req" | sed 's/[^A-Za-z0-9._-]/_/g')
    _reset_trace="$_reset_base/trace/${_reset_sf}.json"
    _reset_lib="${DAC_SKILL_HOME:?DAC_SKILL_HOME 未解析}/scripts/lib.sh"
    if [ -f "$_reset_trace" ] && [ -f "$_reset_lib" ]; then
      # getAndSet 语义：在同一个原子操作中读旧值并清零，避免与并发 write-trace-hook 竞态丢数据
      bash -c '. "$1" 2>/dev/null && atomic_jq ".write_lines_added as \$old | .write_lines_added = 0 | .write_lines_added_snapshot = \$old" "$2"' _ "$_reset_lib" "$_reset_trace" 2>/dev/null || true
      _report_progress "$_reset_trace" 2>/dev/null || true
      # 清理临时快照字段
      bash -c '. "$1" 2>/dev/null && atomic_jq "del(.write_lines_added_snapshot)" "$2"' _ "$_reset_lib" "$_reset_trace" 2>/dev/null || true
    fi
  fi
fi

# 转发给原始 .git/hooks/post-commit（如 dcc 代码统计）
# 必须用 call 而非 exec，否则后续转发不会执行
_orig="$(git rev-parse --git-dir)/hooks/post-commit"
[ -x "$_orig" ] && "$_orig" "$@"

# 最后转发给 git-ai 的 post-commit hook
# git-ai checkpoint 数据积累在 .git/ai/，commit 时通过此 hook 写入 refs/notes/ai
_ai="$(git rev-parse --git-dir)/ai/hooks/post-commit"
[ -x "$_ai" ] && exec "$_ai" "$@"
HOOK
# 生成期展开：将占位符替换为 lib.sh 单一来源的代码白名单 numstat pathspec 字面串
# （include '*.dart'… + exclude ':(exclude)*.g.dart'…）。用 perl + 环境变量插值避免
# pathspec 中 * ( ) : 等字符触发 sed 替换转义问题；替换后 hook 内为纯字面 pathspec，
# sh 运行期正确解析单引号，git 收到字面 *.dart 不被 shell glob 误展开。
DAC_NUMSTAT_PS="$(dac_numstat_pathspec_quoted)" \
DAC_RUNTIME_SCRIPT="$(printf '%q' "$_SETUP_SCRIPTS_DIR/runtime.sh")" \
  perl -i -pe 's/\@\@DAC_NUMSTAT_PATHSPEC\@\@/$ENV{DAC_NUMSTAT_PS}/g; s/\@\@DAC_RUNTIME_SCRIPT\@\@/$ENV{DAC_RUNTIME_SCRIPT}/g' "$DAC_HOOKS/post-commit"
chmod +x "$DAC_HOOKS/post-commit"

# -----------------------------------------------------------------------------
# pre-push：在每次 push 时把 dac-trace notes 也推到远端
# 不修改 remote.origin.push 配置（否则会覆盖 push.default，导致 branch 不推）
# 用 $1（运行时 remote 名）代替硬编码 origin，兼容任意 remote
# _DAC_NOTES_PUSH 防止 pre-push 触发内层 git push 再次进入本 hook（递归保护）
# -----------------------------------------------------------------------------
cat > "$DAC_HOOKS/pre-push" << 'HOOK'
#!/bin/sh
# DAC: push dac-trace notes alongside branch push
[ "${_DAC_NOTES_PUSH:-0}" = "1" ] && exit 0
_remote="$1"
_DAC_NOTES_PUSH=1 git push "$_remote" 'refs/notes/dac-trace:refs/notes/dac-trace' 2>/dev/null || true
_orig="$(git rev-parse --git-dir)/hooks/pre-push"
if [ -x "$_orig" ]; then "$_orig" "$@" || exit $?; fi
_ai="$(git rev-parse --git-dir)/ai/hooks/pre-push"
[ -x "$_ai" ] && exec "$_ai" "$@"
exit 0
HOOK
chmod +x "$DAC_HOOKS/pre-push"

# -----------------------------------------------------------------------------
# 其他 hook 类型：分两遍创建转发包装脚本，保证所有原有 hook 都能执行。
#
# 问题根因：core.hooksPath 会完全绕过 .git/hooks/，不只是 post-commit，
# pre-commit、pre-push 等也全部静默失效，必须在这里显式转发。
#
# 第一遍：.git/hooks/ 中已有的 hook
#   → 先转发到 .git/hooks/<name>（原有 hook，保持退出码传播），再到 .git/ai/hooks/<name>
# 第二遍：git-ai 独有的 hook（.git/hooks/ 里没有的）
#   → 只转发到 .git/ai/hooks/<name>
# -----------------------------------------------------------------------------
if [ -d "$GIT_DIR/hooks" ]; then
  for _f in "$GIT_DIR/hooks"/*; do
    [ -f "$_f" ] && [ -x "$_f" ] || continue
    _name=$(basename "$_f")
    [[ "$_name" == "post-commit" ]] && continue
    _wrapper="$DAC_HOOKS/$_name"
    [[ -f "$_wrapper" ]] && continue
    {
      echo '#!/bin/sh'
      echo "_orig=\"\$(git rev-parse --git-dir)/hooks/${_name}\""
      echo 'if [ -x "$_orig" ]; then "$_orig" "$@" || exit $?; fi'
      echo "_ai=\"\$(git rev-parse --git-dir)/ai/hooks/${_name}\""
      echo '[ -x "$_ai" ] && exec "$_ai" "$@"'
    } > "$_wrapper"
    chmod +x "$_wrapper"
  done
fi

if [ -d "$GITAI_HOOKS" ]; then
  for _f in "$GITAI_HOOKS"/*; do
    [ -f "$_f" ] && [ -x "$_f" ] || continue
    _name=$(basename "$_f")
    [[ "$_name" == "post-commit" ]] && continue
    _wrapper="$DAC_HOOKS/$_name"
    [[ -f "$_wrapper" ]] && continue
    {
      echo '#!/bin/sh'
      echo "_ai=\"\$(git rev-parse --git-dir)/ai/hooks/${_name}\""
      echo '[ -x "$_ai" ] && exec "$_ai" "$@"'
    } > "$_wrapper"
    chmod +x "$_wrapper"
  done
fi

# 将 core.hooksPath 指向包装层，使 git 使用我们的 hook 目录
git config core.hooksPath "$DAC_HOOKS"

# 清理历史遗留：旧方案曾用 git alias.commit 拦截提交，现已废弃
_old_alias=$(git config --local alias.commit 2>/dev/null || true)
if [[ "$_old_alias" == *"GIT_AI_CUSTOM_ATTRIBUTES"* ]]; then
  git config --local --unset alias.commit
  echo "removed stale alias.commit"
fi

echo "hook wrapper configured → $DAC_HOOKS"
