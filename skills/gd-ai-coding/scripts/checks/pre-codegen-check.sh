#!/usr/bin/env bash
# pre-codegen-check.sh [feat_id]
# Layer 1 门禁：codegen 启动前的架构约束检查
# 检查内容：产物完整性、修改文件存在性、knowledge 目录、架构目录结构

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法: pre-codegen-check.sh <feat_id>" >&2
  exit 1
fi

FEAT_ID=$1
STATE_FILE=".dac/state.json"
REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE" 2>/dev/null)
if [[ -z "$REQ_NAME" ]]; then
  echo "❌ pre-codegen-check：state.json 中缺少 req_name" >&2
  exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/../runtime.sh"
dac_resolve_runtime || { echo "❌ pre-codegen-check：无法解析 DAC 运行时" >&2; exit 1; }
source "$SCRIPTS_DIR/../paths.sh"
source "$SCRIPTS_DIR/../platform.sh"
FEAT_DIR="$(get_feat_dir "$REQ_NAME" "$FEAT_ID")"
PASS=true

PLATFORM="${PLATFORM:-flutter}"
PLATFORM_SRC_ROOT=$(load_platform_config "$PLATFORM" 2>/dev/null | jq -r '.src_root // "lib/"')

# flow_profile 感知：读取跳过标记，产物缺失时降级为 warning
SKIP_FEATURE_PLAN=$(jq -r '.flow_profile.skip_feature_plan // false' "$STATE_FILE" 2>/dev/null)


echo "▶ Layer 1 检查（feat: ${FEAT_ID}）"

# 1. code-scope.md 存在且非空（skip_feature_plan 时降级为 warning）
if [[ ! -s "$FEAT_DIR/code-scope.md" ]]; then
  if [[ "$SKIP_FEATURE_PLAN" == "true" ]]; then
    echo "⚠️ 已跳过功能拆分，code-scope.md 缺失不检查"
  else
    echo "❌ code-scope.md 不存在或为空：$FEAT_DIR/code-scope.md"
    PASS=false
  fi
fi

# 2. code-scope.md 中「修改文件」section 内的文件是否实际存在于工程
if [[ -f "$FEAT_DIR/code-scope.md" ]]; then
  MODIFIED_FILES=()
  IN_MODIFIED_SECTION=false
  while IFS= read -r line; do
    if echo "$line" | grep -qiE '^###\s*修改文件|^###\s*modified'; then
      IN_MODIFIED_SECTION=true
      continue
    fi
    if [[ "$IN_MODIFIED_SECTION" == "true" ]] && echo "$line" | grep -qE '^#{1,4}\s'; then
      break
    fi
    if [[ "$IN_MODIFIED_SECTION" == "true" ]] && echo "$line" | grep -qE "^\| ${PLATFORM_SRC_ROOT}"; then
      filepath=$(echo "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')
      [[ -n "$filepath" ]] && MODIFIED_FILES+=("$filepath")
    fi
  done < "$FEAT_DIR/code-scope.md"

  if [[ ${#MODIFIED_FILES[@]} -gt 0 ]]; then
    for filepath in "${MODIFIED_FILES[@]}"; do
      if [[ ! -f "$filepath" ]]; then
        echo "❌ code-scope.md 中「修改文件」在工程中不存在：$filepath"
        PASS=false
      fi
    done
  fi
fi

# 3. constraints.md 存在（skip_prd_parse 模式下降级为警告）
if [[ ! -f ".dac/knowledge/constraints.md" ]]; then
  SKIP_PRD=$(jq -r '.flow_profile.skip_prd_parse // false' .dac/state.json 2>/dev/null)
  if [[ "$SKIP_PRD" == "true" ]]; then
    echo "⚠️  .dac/knowledge/constraints.md 不存在（skip_prd_parse 模式，降级为警告）"
  else
    echo "❌ .dac/knowledge/constraints.md 不存在（请先运行 scripts/init-dac.sh）"
    PASS=false
  fi
fi

# 4. 核心规范文件是否存在（动态检查 platform rules 目录内至少有一个规则文件）
RULES_DIR="$DAC_SKILL_HOME/rules"
PLATFORM_RULES_DIR="$DAC_SKILL_HOME/platform/${PLATFORM}/rules"
RULE_COUNT=0
if [[ -d "$PLATFORM_RULES_DIR" ]]; then
  RULE_COUNT=$(find "$PLATFORM_RULES_DIR" -name "*.md" -not -name "codegen-subagent-rules.md" -not -name "zone-prompt-structure.md" | wc -l | tr -d ' ')
fi
if [[ "$RULE_COUNT" -eq 0 ]]; then
  # Fallback: check global rules dir for legacy flutter files
  if [[ ! -f "$RULES_DIR/flutter-architecture.md" ]]; then
    echo "❌ platform '${PLATFORM}' 规范文件缺失（$PLATFORM_RULES_DIR 下无 .md 文件，请重新运行 install.sh）"
    PASS=false
  fi
fi

# 5. 格式化工具可用性
_CHECK_CMD=$(load_platform_config "$PLATFORM" 2>/dev/null | jq -r '.check_cmd // ""')
_FORMAT_CMD=$(load_platform_config "$PLATFORM" 2>/dev/null | jq -r '.format_cmd // ""')
if [[ -n "$_FORMAT_CMD" ]]; then
  _FORMAT_BIN="${_FORMAT_CMD%% *}"
  if ! command -v "$_FORMAT_BIN" &>/dev/null; then
    echo "❌ ${_FORMAT_BIN} 命令不可用（codegen 内需执行 ${_FORMAT_CMD}），请确认已安装并在 PATH 中"
    PASS=false
  fi
fi

# 6. src_root 目录结构检查（警告，不阻断）
if [[ "$PLATFORM" == "flutter" ]]; then
  if [[ -d "${PLATFORM_SRC_ROOT%/}" ]] && [[ ! -d "${PLATFORM_SRC_ROOT}features" ]]; then
    echo "⚠️  警告：${PLATFORM_SRC_ROOT}features/ 目录不存在，请确认项目采用 Feature-first 架构"
  fi
fi

if [[ "$PASS" == "false" ]]; then
  echo "❌ Layer 1 未通过，codegen 已阻断"
  exit 1
fi

echo "✅ Layer 1 通过"
