#!/usr/bin/env bash
# test-cross-platform-install.sh — 校验 install.sh 跨平台安装与 uninstall.sh 清理逻辑
set -uo pipefail
PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (期望 [$3] 实际 [$2])"; fi }
file_mode() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

TMP_HOME=$(mktemp -d)
trap 'rm -rf "$TMP_HOME"' EXIT

# 构造假 HOME：含 .codex / .dsh（模拟两平台已存在）与 .claude
mkdir -p "$TMP_HOME/.codex/skills/gd-ai-coding/state" "$TMP_HOME/.dsh" "$TMP_HOME/.claude/skills/gd-ai-coding/state"
printf 'codex-state\n' > "$TMP_HOME/.codex/skills/gd-ai-coding/state/runtime.txt"
printf 'claude-state\n' > "$TMP_HOME/.claude/skills/gd-ai-coding/state/runtime.txt"
printf '# DSH AGENTS\n用户已有内容\n' > "$TMP_HOME/.dsh/AGENTS.md"

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

# 用 HOME 覆盖跑 install.sh（jq/python3 等依赖真实系统，仅隔离 HOME）
HOME="$TMP_HOME" bash "$REPO/install.sh" > "$TMP_HOME/install.log" 2>&1
INSTALL_RC=$?
check "install.sh 在隔离 HOME 下成功" "$INSTALL_RC" "0"

check "codex skill 已安装" "$([ -f "$TMP_HOME/.codex/skills/gd-ai-coding/SKILL.md" ] && echo yes)" "yes"
check "codex 子 skill 已收编" "$([ -d "$TMP_HOME/.codex/skills/gd-ai-coding/skills/feature-plan" ] && echo yes)" "yes"
check "codex 独立角色定义已安装" "$([ -f "$TMP_HOME/.codex/skills/gd-ai-coding/codex-agents/code-reviewer/agents/openai.yaml" ] && echo yes)" "yes"
check "codex 降级规则已随装" "$([ -f "$TMP_HOME/.codex/skills/gd-ai-coding/rules/interaction-degradation.md" ] && echo yes)" "yes"
check "codex 状态独立保留" "$(cat "$TMP_HOME/.codex/skills/gd-ai-coding/state/runtime.txt")" "codex-state"
check "codex source marker 已保留" "$([ -f "$TMP_HOME/.codex/skills/gd-ai-coding/.source-repo-path" ] && echo yes)" "yes"
check "codex 不复制 Claude 状态" "$([ "$(cat "$TMP_HOME/.codex/skills/gd-ai-coding/state/runtime.txt")" != "$(cat "$TMP_HOME/.claude/skills/gd-ai-coding/state/runtime.txt")" ] && echo yes)" "yes"
check "codex dashboard 仓库配置已安装" "$([ -f "$TMP_HOME/.codex/skills/dashboard/repos.json" ] && echo yes)" "yes"
check "codex dashboard 后端配置已安装" "$([ -f "$TMP_HOME/.codex/skills/dashboard/backend-config.json" ] && echo yes)" "yes"
check "codex dashboard 后端配置权限为 0600" "$(file_mode "$TMP_HOME/.codex/skills/dashboard/backend-config.json")" "600"
check "全局 dashboard 命令不硬编码 Claude" "$(! grep -qF 'exec \"$HOME/.claude' "$TMP_HOME/.local/bin/dashboard" && echo yes)" "yes"
check "dsh skill 已安装" "$([ -f "$TMP_HOME/.dsh/skills/gd-ai-coding/SKILL.md" ] && echo yes)" "yes"
check "dsh AGENTS.md 引导段已追加" "$(grep -c 'gd-ai-coding guidance' "$TMP_HOME/.dsh/AGENTS.md" | tr -d ' ')" "1"
check "dsh AGENTS.md 用户内容保留" "$(grep -c '用户已有内容' "$TMP_HOME/.dsh/AGENTS.md" | tr -d ' ')" "1"

# 幂等：重跑安装，引导段不重复
HOME="$TMP_HOME" bash "$REPO/install.sh" > "$TMP_HOME/install2.log" 2>&1
check "重跑安装仍成功" "$?" "0"
check "引导段幂等（不重复追加）" "$(grep -c 'gd-ai-coding guidance' "$TMP_HOME/.dsh/AGENTS.md" | tr -d ' ')" "1"

# 卸载
HOME="$TMP_HOME" bash "$REPO/uninstall.sh" > "$TMP_HOME/uninstall.log" 2>&1
check "uninstall.sh 成功" "$?" "0"
check "codex skill 已清理" "$([ -d "$TMP_HOME/.codex/skills/gd-ai-coding" ] && echo yes || echo no)" "no"
check "dsh skill 已清理" "$([ -d "$TMP_HOME/.dsh/skills/gd-ai-coding" ] && echo yes || echo no)" "no"
check "dsh AGENTS.md 引导段已移除" "$(grep -c 'gd-ai-coding guidance' "$TMP_HOME/.dsh/AGENTS.md" | tr -d ' ')" "0"
check "dsh AGENTS.md 用户内容仍保留" "$(grep -c '用户已有内容' "$TMP_HOME/.dsh/AGENTS.md" | tr -d ' ')" "1"

echo ""
echo "通过 $PASS / $((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
