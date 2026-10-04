#!/usr/bin/env bash
# env-checks.sh — 环境依赖检查（mcporter、openspec CLI、graphify-out[可选]）
# 在主 SKILL 初始化工作目录前调用，后续子 skill 不再重复检查。
#
# 用法：
#   bash env-checks.sh           # 检查全部项目

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPTS_DIR/runtime.sh"

MCPORTER_CFG="$HOME/.mcporter/mcporter.json"
ERRORS=()
JQ_AVAILABLE="false"

dac_resolve_runtime || { echo "❌ 无法解析 DAC 运行时；请设置 DAC_RUNTIME=claude 或 DAC_RUNTIME=codex"; exit 1; }

# ─────────────────────────────────────────────
# 0. 权限检查（由各客户端原生配置写入）
# ─────────────────────────────────────────────
case "${DAC_RUNTIME:-}" in
  claude)
    if [ ! -f "$HOME/.claude/settings.json" ]; then
      echo "⚠️  ~/.claude/settings.json 不存在，请先运行 install.sh 安装 skill"
    fi
    ;;
  codex)
    if [ ! -f "$HOME/.codex/hooks.json" ]; then
      echo "⚠️  ~/.codex/hooks.json 不存在，请先运行 install.sh 安装 Codex Hook"
    fi
    ;;
esac

# ─────────────────────────────────────────────
# 0.1 基础工具检查（jq + python3，多个脚本依赖）
# ─────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  ERRORS+=("jq 未安装（state-update.sh、recovery.sh 等脚本依赖）。请运行: brew install jq")
else
  JQ_AVAILABLE="true"
fi

if ! command -v python3 &>/dev/null; then
  ERRORS+=("python3 未安装（state-update.sh 原子状态更新、recovery.sh 状态诊断依赖）。请安装 Python 3")
fi

# ─────────────────────────────────────────────
# mcporter 中 Cooper 检查（pre-trim.sh 直接通过 mcporter 调用 Cooper）
# ─────────────────────────────────────────────
check_mcporter_cooper() {
  local cooper_exists
  cooper_exists=$(jq -r '.mcpServers["Cooper"] // empty' "$MCPORTER_CFG" 2>/dev/null)
  if [ -z "$cooper_exists" ] || [ "$cooper_exists" = "null" ]; then
    ERRORS+=("mcporter 中未配置 Cooper MCP，pre-trim.sh 需要此配置才能拉取文档。请运行: mcporter add Cooper --type http --url <Cooper_MCP_URL> -H 'Authorization: Bearer <KEY>'，或参考 https://cooper.didichuxing.com/knowledge/share/page/uRaZEPYXmPfm 获取 API-KEY")
  fi
}

# ─────────────────────────────────────────────
# mcporter 中 mastergo-proxy 检查
# ─────────────────────────────────────────────
check_mcporter_mastergo() {
  local mg_exists
  mg_exists=$(jq -r '.mcpServers["mastergo-proxy"] // empty' "$MCPORTER_CFG" 2>/dev/null)
  if [ -z "$mg_exists" ] || [ "$mg_exists" = "null" ]; then
    echo "⏳ mcporter 中未配置 mastergo-proxy，正在自动添加 ..."
    if jq '.mcpServers["mastergo-proxy"] = {
      "command": "npx",
      "args": ["-y", "@didi/mcp-proxy-generic"],
      "env": {
        "MCP_API_URL": "http://api-kylin-xg02.intra.xiaojukeji.com/code_cr_test",
        "MCP_RESPONSE_FORMAT": "errno"
      }
    }' "$MCPORTER_CFG" > "${MCPORTER_CFG}.tmp"; then
      mv "${MCPORTER_CFG}.tmp" "$MCPORTER_CFG"
      echo "✅ mastergo-proxy 已添加到 mcporter 配置"
    else
      rm -f "${MCPORTER_CFG}.tmp"
      ERRORS+=("mastergo-proxy 自动写入 mcporter 配置失败，请检查 $MCPORTER_CFG 是否为合法 JSON")
    fi
  fi
}

# ─────────────────────────────────────────────
# mcporter 中 DDP MCP 检查（警告级，不阻断）
# DDP MCP 仅供「DDP ID 入口」使用，缺失时工作流仍可走手动降级路径（req_name → PRD 地址），
# 因此硬阻断会误伤不用 DDP 入口的场景 —— 只做警告提示，不加入 ERRORS。
# ─────────────────────────────────────────────
check_mcporter_ddp() {
  # mcporter 聚合多来源配置（包括各客户端的 MCP 配置）并据此路由 `mcporter call ddp.*`。
  # 只 grep 单个 mcporter.json 会在 ddp 仅注册于客户端配置时误报"未配置"，而实际可用。改以 mcporter 自身识别的清单为准
  # （config list 不走网络探活）。严格区分「命令执行失败」与「确实未配置」：config list 非零
  # 退出时提示执行失败而非未配置。命中判定用 herestring 匹配（避免 `| grep -q` 在 pipefail 下
  # 因 grep 提前退出触发 SIGPIPE 误判失败）。本检查非阻断，任何分支均 return 0、不加入 ERRORS。
  local mcp_servers
  if ! mcp_servers=$(mcporter config list 2>&1); then
    echo "⚠️  mcporter config list 执行失败，无法确认 DDP MCP 配置状态（使用 DDP ID 入口时需要）"
    return 0
  fi
  if grep -Eqi '(^|[(, ])ddp([), ]|$)' <<<"$mcp_servers"; then
    return 0  # 任一来源已配置 ddp，静默通过
  fi
  echo "⚠️  mcporter 未识别到 DDP MCP（使用 DDP ID 入口时需要，缺失则降级为手动输入 PRD）"
  echo "   配置：在 ~/.mcporter/mcporter.json 或当前客户端的 MCP 配置中添加："
  echo "   \"ddp\": {\"url\":\"http://127.0.0.1:28582/v1/hub/ddp\",\"type\":\"http\",\"headers\":{\"Authorization\":\"Bearer <token>\"}}"
}

# ─────────────────────────────────────────────
# mcporter 中 mastergo_food 检查（streamable-http 模式）
# ─────────────────────────────────────────────
check_mcporter_mastergo_food() {
  local mg_food_exists
  mg_food_exists=$(jq -r '.mcpServers["mastergo_food"] // empty' "$MCPORTER_CFG" 2>/dev/null)
  if [ -z "$mg_food_exists" ] || [ "$mg_food_exists" = "null" ]; then
    echo "⏳ mcporter 中未配置 mastergo_food，正在自动添加 ..."
    if jq '.mcpServers["mastergo_food"] = {
      "url": "http://api-kylin-xg02.intra.xiaojukeji.com/mcp/mastergo",
      "type": "streamable-http"
    }' "$MCPORTER_CFG" > "${MCPORTER_CFG}.tmp"; then
      mv "${MCPORTER_CFG}.tmp" "$MCPORTER_CFG"
      echo "✅ mastergo_food 已添加到 mcporter 配置"
    else
      rm -f "${MCPORTER_CFG}.tmp"
      ERRORS+=("mastergo_food 自动写入 mcporter 配置失败，请检查 $MCPORTER_CFG 是否为合法 JSON")
    fi
  fi
}

# ─────────────────────────────────────────────
# 1. mcporter 配置检查
# 因为 需要在 sh 中 调用 mastergo mcp，所以使用mcporter
# ─────────────────────────────────────────────
check_mcporter() {
  if ! command -v mcporter &>/dev/null; then
    echo "⏳ mcporter CLI 未找到，正在自动安装 ..."
    if npm install -g mcporter 2>&1; then
      echo "✅ mcporter 安装成功"
    else
      ERRORS+=("mcporter CLI 自动安装失败，请手动运行: npm install -g mcporter")
      return
    fi
  fi

  if [ ! -f "$MCPORTER_CFG" ]; then
    mkdir -p "$HOME/.mcporter"
    echo '{"mcpServers":{}}' > "$MCPORTER_CFG"
    echo "⏳ 已创建 $MCPORTER_CFG"
  fi

  # jq 可用时才检查子配置
  if [ "$JQ_AVAILABLE" = "true" ]; then
    check_mcporter_mastergo
    check_mcporter_mastergo_food
    check_mcporter_cooper
    check_mcporter_ddp
  fi
}

# ─────────────────────────────────────────────
# 2. openspec CLI 检查
# ─────────────────────────────────────────────
check_openspec() {
  if ! command -v opsx &>/dev/null && ! command -v openspec &>/dev/null; then
    echo "⏳ openspec CLI 未找到，正在自动安装 @fission-ai/openspec ..."
    if npm install -g @fission-ai/openspec 2>&1; then
      echo "✅ @fission-ai/openspec 安装成功"
    else
      ERRORS+=("openspec CLI 自动安装失败，请手动运行: npm install -g @fission-ai/openspec")
      return
    fi
  fi

  # 验证版本可用
  local cmd
  if command -v opsx &>/dev/null; then
    cmd="opsx"
  else
    cmd="openspec"
  fi

  if ! "$cmd" --version &>/dev/null; then
    ERRORS+=("$cmd --version 执行失败，请检查安装是否完整")
  fi
}


# ─────────────────────────────────────────────
# 3. graphify-out 检查（可选，不阻断流程）
# ─────────────────────────────────────────────
GRAPHIFY_AVAILABLE="false"

check_graphify() {
  GRAPHIFY_SKILL="$(dirname "$DAC_SKILL_HOME")/graphify/SKILL.md"
  if [ ! -f "$GRAPHIFY_SKILL" ]; then
    echo "⚠️  graphify skill 未安装（$GRAPHIFY_SKILL 不存在）"
    echo "   安装参考：https://cooper.didichuxing.com/knowledge/2199952000607/2207853259276"
    return
  fi

  if ! command -v graphify &>/dev/null; then
    echo "⚠️  graphify CLI 未安装或不在 PATH"
    return
  fi

  if [ ! -d "graphify-out" ]; then
    echo "⚠️  graphify-out/ 目录不存在，可运行 /graphify 生成工程知识图谱"
    return
  fi

  if [ ! -f "graphify-out/graph.json" ]; then
    echo "⚠️  graphify-out/ 存在但缺少 graph.json，可重新运行 /graphify"
    return
  fi

  GRAPHIFY_AVAILABLE="true"
}

# ─────────────────────────────────────────────
# 执行检查
# ─────────────────────────────────────────────
check_mcporter
check_openspec
check_graphify

# ─────────────────────────────────────────────
# 输出结果
# ─────────────────────────────────────────────
if [ ${#ERRORS[@]} -gt 0 ]; then
  echo "❌ 环境检查失败（必须修复后才能继续）："
  for e in "${ERRORS[@]}"; do
    echo "   - $e"
  done
  exit 1
fi

echo "✅ 环境检查通过"

if [ "$GRAPHIFY_AVAILABLE" = "true" ]; then
  echo "GRAPHIFY_STATUS=available"
else
  echo "GRAPHIFY_STATUS=unavailable"
fi
