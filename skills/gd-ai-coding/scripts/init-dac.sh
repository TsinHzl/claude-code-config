#!/usr/bin/env bash
# 初始化 .dac/ 工作目录（非交互式，由 SKILL.md 控制流程）
# 调用方式：
#   bash scripts/init-dac.sh --force    # 清空 .dac/ 重新初始化
#   bash scripts/init-dac.sh --resume   # 如果存在则输出状态并退出
#   bash scripts/init-dac.sh --status   # 输出当前状态（JSON），不做任何修改
#   bash scripts/init-dac.sh            # 默认：无可恢复进度则初始化；有合法 state.json 则报错
#
# --status 契约（供 SKILL.md 判定，禁止用 git dirty 推断「上次未完成」）：
#   {"exists": false, "resumable": false}  — 无 .dac/、残留空目录、或无合法 state.json
#   {"exists": true, "resumable": true, ...state} — 有已知 phase 的 state.json，可继续/重开
#   绝不输出 phase: "unknown"（该值会被误判为「上次未完成」）

set -euo pipefail

DAC_DIR=".dac"
ACTION=${1:-""}

# 查找插件安装路径（支持安装后调用和本地调用两种场景）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$PLUGIN_DIR/templates"

# 注册 hook wrapper：当前目录是 git repo 则直接注册；否则扫一级子目录逐个注册
_setup_hooks() {
  if git rev-parse --git-dir &>/dev/null 2>&1; then
    _r=$(bash "$SCRIPT_DIR/metrics/setup-hook-wrapper.sh")
    echo "✓ hook wrapper: $_r"
  else
    _count=0
    for _sub in */; do
      [ -d "${_sub}.git" ] || continue
      _r=$(cd "$_sub" && bash "$SCRIPT_DIR/metrics/setup-hook-wrapper.sh")
      echo "✓ hook wrapper (${_sub%/}): $_r"
      _count=$((_count + 1))
    done
    if [ "$_count" -eq 0 ]; then echo "✓ hook wrapper: 当前目录无 git repo，跳过"; fi
  fi
}

# 补齐 .gitignore 缺失规则（逐条判断而非单一 header 存在性——避免旧版本 header 永久
# 跳过后续新增规则，导致 .dac/trace/ 等敏感目录被误提交进主分支、污染所有拉取者的本地数据）
_heal_gitignore() {
  local header="# gd-ai-coding 工作目录（临时文件排除，knowledge 提交）"
  local patterns=(".dac/logs/" ".dac/state.json" ".dac/.lock" ".dac/trace/" \
    ".dac/workflow_session_id" ".dac/.write-trace-gen" ".dac/.write-trace-gen.lock" \
    ".dac/claude_session_id")
  local existed=0; [ -f ".gitignore" ] && existed=1
  touch .gitignore
  local missing=()
  for p in "${patterns[@]}"; do
    grep -qxF "$p" .gitignore 2>/dev/null || missing+=("$p")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    grep -qxF "$header" .gitignore 2>/dev/null || printf '\n%s\n' "$header" >> .gitignore
    printf '%s\n' "${missing[@]}" >> .gitignore
    if [ "$existed" -eq 1 ]; then echo "✓ 已更新 .gitignore（补齐 ${#missing[@]} 条缺失规则）"; else echo "✓ 已创建 .gitignore"; fi
  fi
}

# 合法 phase 才可恢复；缺 state.json / 损坏 JSON / 未知 phase 一律不可 resume
_dac_phase_resumable() {
  case "$1" in
    init|prd-parsing|prd-parsed|prd-clarified|prd-specing|prd-speced|proposal-approved|feature-planned|feature-loop|feature-done|done)
      return 0 ;;
    *) return 1 ;;
  esac
}

_dac_current_resumable() {
  [ -f "$DAC_DIR/state.json" ] || return 1
  command -v jq &>/dev/null || return 1
  jq -e . "$DAC_DIR/state.json" >/dev/null 2>&1 || return 1
  _dac_phase_resumable "$(jq -r '.phase // empty' "$DAC_DIR/state.json")"
}

# --status: 输出当前状态供调用方判断
if [ "$ACTION" = "--status" ]; then
  if [ ! -d "$DAC_DIR" ] || [ ! -f "$DAC_DIR/state.json" ]; then
    echo '{"exists": false, "resumable": false}'
    exit 0
  fi
  if ! command -v jq &>/dev/null; then
    echo '{"exists": false, "resumable": false}'
    exit 0
  fi
  if ! jq -e . "$DAC_DIR/state.json" >/dev/null 2>&1; then
    echo '{"exists": false, "resumable": false}'
    exit 0
  fi
  _phase=$(jq -r '.phase // empty' "$DAC_DIR/state.json")
  _resumable=false
  if _dac_phase_resumable "$_phase"; then
    _resumable=true
  fi
  jq --argjson resumable "$_resumable" '. + {exists: true, resumable: $resumable}' "$DAC_DIR/state.json"
  exit 0
fi

# --resume: 继续上次进度
if [ "$ACTION" = "--resume" ]; then
  if [ -d "$DAC_DIR" ] && [ -f "$DAC_DIR/state.json" ]; then
    echo "继续上次进度"
    cat "$DAC_DIR/state.json"
    # 恢复时已处于 feature 阶段，确保 CR 触发规则存在
    if [ -f "$TEMPLATES_DIR/dac-cr-trigger.md" ] && [ ! -f ".claude/rules/dac-cr-trigger.md" ]; then
      mkdir -p ".claude/rules"
      # 复制到项目的目录下
      cp "$TEMPLATES_DIR/dac-cr-trigger.md" ".claude/rules/dac-cr-trigger.md"
      echo "✓ 已注入 sub-agent CR 触发规则：.claude/rules/dac-cr-trigger.md"
    fi
    # 重新捕获 session UUID：每次 resume 都是一个新的 Claude Code 会话，
    # 必须更新 workflow_session_id，否则后续 trace 会关联到旧 session
    bash "$SCRIPT_DIR/metrics/init-trace.sh"
    _heal_gitignore
    _setup_hooks
    exit 0
  else
    echo "错误：.dac/ 目录或 state.json 不存在，无法继续" >&2
    exit 1
  fi
fi

# --force: 清空重建；无可恢复进度（空目录 / 无或非法 state.json）：清掉后重建；
# 有合法 state.json 则默认报错，须显式 --force / --resume
if [ -d "$DAC_DIR" ]; then
  if [ "$ACTION" = "--force" ]; then
    rm -rf "$DAC_DIR"
  elif _dac_current_resumable; then
    echo "错误：.dac/ 目录已存在。使用 --force 重建，--resume 继续，--status 查看状态。" >&2
    exit 1
  else
    rm -rf "$DAC_DIR"
  fi
fi

# 确保 jq 可用（trace 采集的硬依赖）
if ! command -v jq &>/dev/null; then
  echo "jq 未安装，尝试自动安装..."
  if command -v brew &>/dev/null; then
    brew install jq
  elif command -v apt-get &>/dev/null; then
    sudo apt-get install -y jq
  else
    echo "❌ 无法自动安装 jq，请手动安装后重试" >&2
    exit 1
  fi
fi

# 创建基础目录结构
echo "初始化 .dac/ 工作目录..."
mkdir -p "$DAC_DIR/knowledge" "$DAC_DIR/logs"
bash "$SCRIPT_DIR/metrics/init-trace.sh"

# 初始化 state.json（使用 lib.sh 共享模板，保证字段一致性）
source "$SCRIPT_DIR/lib.sh"
state_json_template "init" > "$DAC_DIR/state.json"

# 从模板复制初始 knowledge 文件（逐文件容错）
_init_knowledge() {
  local name="$1" fallback="$2"
  if [ -f "$TEMPLATES_DIR/knowledge/$name" ]; then
    cp "$TEMPLATES_DIR/knowledge/$name" "$DAC_DIR/knowledge/$name"
  else
    echo "$fallback" > "$DAC_DIR/knowledge/$name"
  fi
}
_init_knowledge "constraints.md"   "# 项目约束积累"
_init_knowledge "decisions.md"     "# 设计决策记录"
_init_knowledge "error-patterns.md" "# 错误模式积累"
echo "✓ knowledge/ 初始化完成"

# 初始化执行日志
touch "$DAC_DIR/logs/execution.log"

# 更新 .gitignore
_heal_gitignore

_setup_hooks

echo ""
echo "✅ .dac/ 初始化完成"
