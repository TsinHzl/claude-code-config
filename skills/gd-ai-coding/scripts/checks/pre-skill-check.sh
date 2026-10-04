#!/usr/bin/env bash
# pre-skill-check.sh [skill_name] [feat_id]
# 每个 skill 在步骤 0 调用，检查自身所需的前置产物是否存在
# skill_name 取值：feature-plan | feature-loop | codegen | code-review

set -euo pipefail

SKILL_NAME=${1:?"用法: pre-skill-check.sh <skill_name> [feat_id]"}
FEAT_ID=${2:-""}
VALIDATORS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ALLOWED_SKILLS=(feature-plan feature-loop codegen code-review)
if ! printf '%s\n' "${ALLOWED_SKILLS[@]}" | grep -qx "$SKILL_NAME"; then
  echo "❌ pre-skill-check：未知 skill 名称：$SKILL_NAME"
  echo "   有效取值：feature-plan | feature-loop | codegen | code-review"
  exit 1
fi

# 引入路径库
source "$VALIDATORS_DIR/../paths.sh"

# 从 state.json 获取 req_name（多个 case 需要）
STATE_FILE=".dac/state.json"
REQ_NAME=""
if [ -f "$STATE_FILE" ]; then
  REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE" 2>/dev/null)
fi

case "$SKILL_NAME" in
  feature-plan)
    # 环境依赖已由 env-checks.sh 在主 SKILL 初始化前完成（graphify 为可选），此处检查流程前置条件
    STATE_FILE=".dac/state.json"
    if [ ! -f "$STATE_FILE" ]; then
      echo "❌ pre-skill-check[feature-plan]：.dac/state.json 不存在，请先完成阶段 1（需求分析）"
      exit 1
    fi
    PHASE=$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null)
    if [ "$PHASE" != "prd-speced" ]; then
      echo "❌ pre-skill-check[feature-plan]：当前 phase 为 '$PHASE'，需要 'prd-speced'，请先完成阶段 1（需求分析）"
      exit 1
    fi
    REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE" 2>/dev/null)
    if [ -z "$REQ_NAME" ]; then
      echo "❌ pre-skill-check[feature-plan]：state.json 中缺少 req_name 字段"
      exit 1
    fi
    SKIP_PRD_PARSE=$(jq -r '.flow_profile.skip_prd_parse // false' "$STATE_FILE" 2>/dev/null)
    SPEC_FILE="$(get_prd_dir "$REQ_NAME")/prd-spec.md"
    if [ ! -f "$SPEC_FILE" ]; then
      if [ "$SKIP_PRD_PARSE" == "true" ]; then
        echo "⚠️ pre-skill-check[feature-plan]：已跳过 PRD 解析，prd-spec.md 缺失不阻断"
      else
        echo "❌ pre-skill-check[feature-plan]：$SPEC_FILE 不存在，请先完成阶段 1（需求分析）"
        exit 1
      fi
    fi
    echo "✅ pre-skill-check[feature-plan]：前置条件满足（req_name=${REQ_NAME}）"
    ;;
  feature-loop)
    # Schema 校验 feature-plan.json + proposal.md 存在性
    if [ -z "$REQ_NAME" ]; then
      echo "[DAC-STATE-003] ❌ pre-skill-check[feature-loop]：state.json 中缺少 req_name"
      exit 1
    fi
    PROPOSAL_FILE="$(get_change_dir "$REQ_NAME")/proposal.md"
    if [ ! -f "$PROPOSAL_FILE" ]; then
      echo "[DAC-GEN-003] ❌ pre-skill-check[feature-loop]：$PROPOSAL_FILE 不存在"
      echo "   skip_feature_plan 只跳过拆分，仍须先完成 opsx:propose 生成 proposal.md"
      exit 1
    fi
    bash "$VALIDATORS_DIR/feature-plan-schema-check.sh"
    echo "✅ pre-skill-check[feature-loop]：前置条件满足"
    ;;
  codegen)
    # 需要 code-scope.md 存在（ui_dsl.json 由用户在 feature-loop 步骤 3 决定是否提供）
    # 注：proposal.md 已由 feature-loop pre-check 保证，此处不重复检查
    if [ -z "$FEAT_ID" ]; then
      echo "[DAC-GEN-001] ❌ pre-skill-check[codegen]：未提供 feat_id"
      exit 1
    fi
    if [ -z "$REQ_NAME" ]; then
      echo "[DAC-STATE-003] ❌ pre-skill-check[codegen]：state.json 中缺少 req_name"
      exit 1
    fi
    SKIP_FEATURE_PLAN=$(jq -r '.flow_profile.skip_feature_plan // false' "$STATE_FILE" 2>/dev/null)
    FEAT_SCOPE="$(get_feat_dir "$REQ_NAME" "$FEAT_ID")/code-scope.md"
    if [ ! -f "$FEAT_SCOPE" ]; then
      if [ "$SKIP_FEATURE_PLAN" == "true" ]; then
        echo "⚠️ pre-skill-check[codegen]：已跳过功能拆分，code-scope.md 缺失不阻断"
      else
        echo "[DAC-GEN-001] ❌ pre-skill-check[codegen]：$FEAT_SCOPE 不存在"
        exit 1
      fi
    fi
    INDEX_JSON="$(get_design_dir "$REQ_NAME")/index.json"
    if [[ -f "$INDEX_JSON" ]]; then
      MATCHED=$(jq -e "[.[] | select(.features[]? == \"$FEAT_ID\")] | length" "$INDEX_JSON" 2>/dev/null || echo "0")
      if [[ "$MATCHED" -gt 0 ]]; then
        for dir in $(jq -r ".[] | select(.features[]? == \"$FEAT_ID\") | .dir" "$INDEX_JSON" 2>/dev/null); do
          DS_DIR="$(get_design_dir "$REQ_NAME")/$dir"
          if [[ ! -d "$DS_DIR" ]]; then
            echo "[DAC-GEN-002] ❌ pre-skill-check[codegen]：index.json 引用的设计稿目录不存在：$DS_DIR"
            exit 1
          fi
        done
      fi
    fi
    echo "✅ pre-skill-check[codegen]：前置条件满足"
    ;;
  code-review)
    # 需要 codegen 已完成（所有新增文件存在）
    if [ -z "$FEAT_ID" ]; then
      echo "❌ pre-skill-check[code-review]：未提供 feat_id"
      exit 1
    fi
    bash "$VALIDATORS_DIR/state-transition-check.sh" "$FEAT_ID" --up-to=codegen
    ;;
esac
