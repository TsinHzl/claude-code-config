#!/usr/bin/env bash
# recovery.sh [--diagnose | --reconcile | --resume]
# Sub-Agent 崩溃恢复：扫描产物存在性推断恢复点，或强制同步状态

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/lib.sh"
source "$SCRIPTS_DIR/paths.sh"

ACTION=${1:---diagnose}
STATE_FILE=".dac/state.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "[DAC-STATE-003] ❌ .dac/state.json 不存在，无法恢复"
  exit 1
fi

REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE" 2>/dev/null)
if [[ -z "$REQ_NAME" ]]; then
  echo "ℹ️  尚未开始需求分析（state.json 中无 req_name），无需恢复"
  exit 0
fi

PLAN_JSON="$(get_change_dir "$REQ_NAME")/feature-plan.json"

case "$ACTION" in
  --diagnose)
    echo "═══ DAC 恢复诊断 ═══"
    echo ""

    # 检查 lock 文件
    if [[ -f ".dac/.lock" ]]; then
      echo "⚠️  发现 lock 文件（存在未完成的状态转换）："
      cat .dac/.lock
      echo ""
    fi

    # 显示当前状态
    echo "当前 state.json："
    jq '{phase, current_feature_id, completed_features, skipped_features}' "$STATE_FILE"
    echo ""

    # 检查当前进行中的功能
    CURRENT=$(jq -r '.current_feature_id // empty' "$STATE_FILE")
    if [[ -n "$CURRENT" ]]; then
      echo "━━━ 进行中功能：$CURRENT ━━━"
      FEAT_DIR="$(get_feat_dir "$REQ_NAME" "$CURRENT")"

      echo "产物扫描："
      [[ -f "$FEAT_DIR/code-scope.md" ]] && echo "  ✓ code-scope.md" || echo "  ✗ code-scope.md"
      [[ -f "$FEAT_DIR/ui_dsl.json" ]] && echo "  ✓ ui_dsl.json + ui_tree.txt" || echo "  - ui_dsl.json（可选）"
      [[ -f "$FEAT_DIR/.design_skipped" ]] && echo "  ✓ .design_skipped（设计已跳过）"
      [[ -f "$FEAT_DIR/cr-report.md" ]] && echo "  ✓ cr-report.md" || echo "  ✗ cr-report.md"

      # 检查代码文件生成情况
      if [[ -f "$FEAT_DIR/code-scope.md" ]]; then
        TOTAL=0
        EXISTING=0
        while IFS= read -r filepath; do
          [[ -z "$filepath" ]] && continue
          TOTAL=$((TOTAL + 1))
          [[ -f "$filepath" ]] && EXISTING=$((EXISTING + 1))
        done < <(grep -E '^\| lib/' "$FEAT_DIR/code-scope.md" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 != "") print $2}')
        echo "  代码文件：$EXISTING/$TOTAL 已生成"
      fi

      # 检查 codegen checkpoint
      CHECKPOINT_FILE="$FEAT_DIR/.codegen_checkpoint"
      if [[ -f "$CHECKPOINT_FILE" ]]; then
        CHECKPOINT_BASE=$(jq -r '.base_commit // empty' "$CHECKPOINT_FILE" 2>/dev/null)
        CHECKPOINT_TIME=$(jq -r '.started_at // empty' "$CHECKPOINT_FILE" 2>/dev/null)
        echo "  ⚠️  存在 codegen checkpoint（启动于 $CHECKPOINT_TIME）"
        if [[ $EXISTING -gt 0 ]] && [[ $EXISTING -lt $TOTAL ]]; then
          echo "  → 代码生成不完整（$EXISTING/$TOTAL），建议回滚后重试"
          echo "  回滚命令："
          echo "    git checkout $CHECKPOINT_BASE -- \$(grep -E '^\| lib/' \"$FEAT_DIR/code-scope.md\" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+\$/, \"\", \$2); if (\$2 != \"\") print \$2}')"
        fi
      fi

      # 推断恢复点
      echo ""
      echo "推荐恢复点："
      if [[ -f "$FEAT_DIR/cr-report.md" ]]; then
        echo "  → 步骤 6（完成收尾）— CR 已完成"
        echo "  操作：Read ~/.claude/skills/gd-ai-coding/skills/feature-loop/SKILL.md 执行 ${CURRENT}（从步骤 6 继续）"
      elif [[ -f "$FEAT_DIR/code-scope.md" ]] && [[ $EXISTING -eq $TOTAL ]] && [[ $TOTAL -gt 0 ]]; then
        echo "  → 步骤 5（code-review）— codegen 产物完整"
        echo "  操作：Read ~/.claude/skills/gd-ai-coding/skills/feature-loop/SKILL.md 执行 ${CURRENT}（从步骤 5 继续）"
      elif [[ -f "$FEAT_DIR/code-scope.md" ]]; then
        if [[ -f "$CHECKPOINT_FILE" ]] && [[ $EXISTING -gt 0 ]] && [[ $EXISTING -lt $TOTAL ]]; then
          echo "  → 步骤 4（codegen）— 代码不完整，需先回滚再重试"
        else
          echo "  → 步骤 4（codegen）— code-scope 存在但代码不完整"
        fi
        echo "  操作：Read ~/.claude/skills/gd-ai-coding/skills/feature-loop/SKILL.md 执行 ${CURRENT}（从步骤 4 继续）"
      else
        echo "  → 步骤 2（code-scope）— 需从头开始"
        echo "  操作：Read ~/.claude/skills/gd-ai-coding/skills/feature-loop/SKILL.md 执行 $CURRENT"
      fi
    else
      echo "无进行中的功能"
    fi

    # 显示状态不一致（如有）
    if [[ -f "$PLAN_JSON" ]]; then
      echo ""
      if ! command -v python3 &>/dev/null; then
        echo "⚠️  python3 不可用，跳过一致性检查"
      else
        INCONSISTENT=$(DAC_STATE_FILE="$STATE_FILE" DAC_PLAN_JSON="$PLAN_JSON" python3 -c "
import json, os
state = json.load(open(os.environ['DAC_STATE_FILE']))
data = json.load(open(os.environ['DAC_PLAN_JSON']))
plan = data.get('features', data) if isinstance(data, dict) else data
completed = set(state.get('completed_features', []))
skipped = set(state.get('skipped_features', []))
current = state.get('current_feature_id')
issues = []
for feat in plan:
    fid = feat['id']
    # skipped_features 中同时包含 failed 和 skipped，需保留 feature-plan.json 中的原始状态区分二者
    if fid in completed:
        expected = 'done'
    elif fid in skipped:
        actual_status = feat.get('status', 'pending')
        expected = actual_status if actual_status in ('failed', 'skipped') else 'failed'
    elif fid == current:
        expected = 'in_progress'
    else:
        expected = 'pending'
    actual = feat.get('status', 'pending')
    if expected != actual:
        issues.append(f'  {fid}: state.json 期望 {expected}，feature-plan.json 实际 {actual}')
if issues:
    print('[DAC-STATE-002] 状态不一致：')
    for i in issues:
        print(i)
else:
    print('OK')
" 2>/dev/null || echo "PYTHON_ERROR")
        if [[ "$INCONSISTENT" == "PYTHON_ERROR" ]]; then
          echo "⚠️  一致性检查执行失败，跳过"
        elif [[ "$INCONSISTENT" != "OK" ]]; then
          echo "$INCONSISTENT"
          echo ""
          echo "运行 scripts/recovery.sh --reconcile 修复"
        else
          echo "状态一致性：✅ state.json 与 feature-plan.json 一致"
        fi
      fi
    fi
    ;;

  --reconcile)
    echo "正在从 state.json 同步 feature-plan.json..."

    if [[ ! -f "$PLAN_JSON" ]]; then
      echo "❌ feature-plan.json 不存在：$PLAN_JSON"
      exit 1
    fi

    # 协作模式前置：若 collab.json 存在，先从 features/*/status.json 回填
    # state.json 的 completed_features / skipped_features（跨人权威 → 本机权威）
    COLLAB_JSON="$(get_change_dir "$REQ_NAME")/collab.json"
    FEATURES_DIR="$(get_features_dir "$REQ_NAME")"
    if [[ -f "$COLLAB_JSON" && -d "$FEATURES_DIR" ]]; then
      _completed=$(find "$FEATURES_DIR" -mindepth 2 -maxdepth 2 -name status.json \
        -exec sh -c 'jq -r "if .status==\"done\" or .status==\"done_with_issues\" then (.feature_id // \"\") else empty end" "$1" 2>/dev/null' _ {} \; 2>/dev/null \
        | sort -u | jq -R -s -c 'split("\n") | map(select(length > 0))')
      _skipped=$(find "$FEATURES_DIR" -mindepth 2 -maxdepth 2 -name status.json \
        -exec sh -c 'jq -r "if .status==\"skipped\" or .status==\"failed\" then (.feature_id // \"\") else empty end" "$1" 2>/dev/null' _ {} \; 2>/dev/null \
        | sort -u | jq -R -s -c 'split("\n") | map(select(length > 0))')
      [[ -z "$_completed" ]] && _completed="[]"
      [[ -z "$_skipped" ]] && _skipped="[]"
      atomic_jq --compact '
        .completed_features = ((.completed_features // []) + $c | unique) |
        .skipped_features = ((.skipped_features // []) + $s | unique)
      ' "$STATE_FILE" --argjson c "$_completed" --argjson s "$_skipped"
      echo "  ↳ 协作模式：已从 features/*/status.json 回填 completed/skipped"
    fi

    DAC_STATE_FILE="$STATE_FILE" DAC_PLAN_JSON="$PLAN_JSON" python3 -c "
import json, os

state = json.load(open(os.environ['DAC_STATE_FILE']))
data = json.load(open(os.environ['DAC_PLAN_JSON']))
is_wrapped = isinstance(data, dict)
plan = data.get('features', []) if is_wrapped else data

completed = set(state.get('completed_features', []))
skipped = set(state.get('skipped_features', []))
issues = set(state.get('issues_features', []))
current = state.get('current_feature_id')

changes = 0
for feat in plan:
    fid = feat['id']
    old_status = feat.get('status', 'pending')
    if fid in completed:
        new_status = 'done_with_issues' if fid in issues else 'done'
    elif fid in skipped:
        # 保留原始状态区分：若已是 skipped 或 failed 则不变，否则默认 failed
        new_status = old_status if old_status in ('failed', 'skipped') else 'failed'
    elif fid == current:
        new_status = 'in_progress'
    else:
        new_status = 'pending'

    if old_status != new_status:
        feat['status'] = new_status
        changes += 1
        print(f'  {fid}: {old_status} → {new_status}')

# 写回时保持原始格式
output = data if is_wrapped else plan
if is_wrapped:
    data['features'] = plan
with open(os.environ['DAC_PLAN_JSON'], 'w') as f:
    json.dump(output, f, indent=2, ensure_ascii=False)

if changes:
    print(f'✅ 已同步 {changes} 个功能的状态')
else:
    print('✅ 无需同步（状态已一致）')
"

    # 清理 lock 文件
    if [[ -f ".dac/.lock" ]]; then
      rm -f .dac/.lock
      echo "✅ 已清理 lock 文件"
    fi
    ;;

  --resume|--suggest)
    bash "$0" --diagnose
    echo ""
    echo "━━━ 推荐恢复操作（可直接复制执行） ━━━"
    echo ""

    # 生成可执行命令
    if [[ -f ".dac/.lock" ]]; then
      echo "# 步骤 1：清理 lock + 同步状态"
      echo "bash ~/.claude/skills/gd-ai-coding/scripts/recovery.sh --reconcile"
      echo ""
    fi

    CURRENT=$(jq -r '.current_feature_id // empty' "$STATE_FILE")
    if [[ -n "$CURRENT" ]]; then
      FEAT_DIR="$(get_feat_dir "$REQ_NAME" "$CURRENT")"
      CHECKPOINT_FILE="$FEAT_DIR/.codegen_checkpoint"

      if [[ -f "$CHECKPOINT_FILE" ]]; then
        TOTAL=0; EXISTING=0
        if [[ -f "$FEAT_DIR/code-scope.md" ]]; then
          while IFS= read -r fp; do
            [[ -z "$fp" ]] && continue; TOTAL=$((TOTAL+1))
            [[ -f "$fp" ]] && EXISTING=$((EXISTING+1))
          done < <(grep -E '^\| lib/' "$FEAT_DIR/code-scope.md" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 != "") print $2}')
        fi
        if [[ $EXISTING -gt 0 && $EXISTING -lt $TOTAL ]]; then
          CODEGEN_BASE=$(jq -r '.base_commit // empty' "$CHECKPOINT_FILE" 2>/dev/null)
          echo "# 步骤 2：回滚不完整的 codegen 产物"
          echo "git checkout $CODEGEN_BASE -- \$(grep -E '^\| lib/' \"$FEAT_DIR/code-scope.md\" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+\$/, \"\", \$2); if (\$2 != \"\") print \$2}')"
          echo ""
        fi
      fi

      echo "# 步骤 3：继续开发"
      echo "Read ~/.claude/skills/gd-ai-coding/skills/feature-loop/SKILL.md（执行 $CURRENT）"
    else
      PHASE=$(jq -r '.phase // "init"' "$STATE_FILE")
      echo "# 继续流程（当前阶段：$PHASE）"
      case "$PHASE" in
        init|prd-parsing|prd-parsed|prd-clarified) echo "/gd-ai-coding" ;;
        prd-specing) echo "/gd-ai-coding" ;;
        prd-speced|proposal-approved) echo "/gd-ai-coding（进入 feature-plan 流程）" ;;
        feature-planned|feature-loop) echo "/gd-ai-coding" ;;
        feature-done) echo "# 功能开发已完成，运行 /opsx:archive 归档变更，或 /gd-ai-coding 处理" ;;
        done) echo "# 上一次流程已完成，运行 /gd-ai-coding 开始新任务" ;;
      esac
    fi
    ;;

  --rollback-to)
    TARGET_PHASE=${2:?"用法: recovery.sh --rollback-to <phase>"}

    # phase_to_order 来自 lib.sh

    TARGET_ORDER=$(phase_to_order "$TARGET_PHASE")
    if [[ "$TARGET_ORDER" -eq -1 ]]; then
      echo "❌ 无效的目标阶段：$TARGET_PHASE"
      echo "   有效取值：init | prd-parsing | prd-parsed | prd-clarified | prd-specing | prd-speced | proposal-approved | feature-planned | feature-loop | feature-done | done"
      exit 1
    fi

    CURRENT_PHASE=$(jq -r '.phase // "unknown"' "$STATE_FILE")
    CURRENT_ORDER=$(phase_to_order "$CURRENT_PHASE")
    [[ "$CURRENT_ORDER" -eq -1 ]] && CURRENT_ORDER=99

    if [[ $TARGET_ORDER -ge $CURRENT_ORDER ]]; then
      echo "❌ 目标阶段 ($TARGET_PHASE) 不早于当前阶段 ($CURRENT_PHASE)，无需回退"
      exit 1
    fi

    echo "═══ 阶段回退：$CURRENT_PHASE → $TARGET_PHASE ═══"
    echo ""

    CHANGE_DIR="$(get_change_dir "$REQ_NAME")"

    # 按倒序清理各阶段产物
    if [[ $TARGET_ORDER -lt 8 ]]; then
      # 清理 feature-loop 产物（各功能子目录中的运行时产物）
      FEATURES_DIR="$(get_features_dir "$REQ_NAME")"
      if [[ -d "$FEATURES_DIR" ]]; then
        for feat_dir in "$FEATURES_DIR"/*/; do
          [[ -d "$feat_dir" ]] || continue
          rm -f "$feat_dir/cr-report.md"
          rm -f "$feat_dir/code-scope.md"
          rm -f "$feat_dir/ui_dsl.json"
          rm -f "$feat_dir/ui_tree.txt"
          rm -f "$feat_dir/.design_skipped"
          rm -f "$feat_dir/.codegen_checkpoint"
          echo "  ✓ 清理功能目录：$(basename "$feat_dir")"
        done
      fi
      # 重置 state.json 中的 feature-loop 相关字段
      atomic_jq --compact '.current_feature_id = null | .completed_features = [] | .skipped_features = [] | .issues_features = []' "$STATE_FILE"
      echo "  ✓ 重置 feature-loop 状态"
    fi

    if [[ $TARGET_ORDER -lt 7 ]]; then
      # 清理 feature-planned 产物
      rm -f "$CHANGE_DIR/feature-plan.json"
      echo "  ✓ 删除 feature-plan.json"
    fi

    if [[ $TARGET_ORDER -lt 6 ]]; then
      # 清理 proposal-approved 产物（openspec 原生 artifacts）
      rm -f "$CHANGE_DIR/proposal.md"
      rm -f "$CHANGE_DIR/design.md"
      rm -f "$CHANGE_DIR/tasks.md"
      rm -rf "$CHANGE_DIR/specs"
      echo "  ✓ 删除 openspec artifacts (proposal/specs/design/tasks)"
    fi

    if [[ $TARGET_ORDER -lt 5 ]]; then
      # 清理 prd-speced 产物
      rm -f "$CHANGE_DIR/prd/prd-spec.md"
      echo "  ✓ 删除 prd-spec.md"
    fi

    if [[ $TARGET_ORDER -lt 3 ]]; then
      # 清理 prd-clarified 产物
      rm -f "$CHANGE_DIR/prd/prd-clarify.md"
      echo "  ✓ 删除 prd-clarify.md"
    fi

    if [[ $TARGET_ORDER -lt 2 ]]; then
      # 清理 prd-parsed 产物（含 prd-parsing 阶段获取的 ui/）
      rm -f "$CHANGE_DIR/prd/prd-parse.md"
      rm -rf "$CHANGE_DIR/ui"
      echo "  ✓ 删除 prd-parse.md 和 ui/"
    fi

    # 更新 phase（--force 绕过前进校验）
    bash "$SCRIPTS_DIR/state-update.sh" --phase "$TARGET_PHASE" --force

    # 清理 lock 文件
    rm -f .dac/.lock

    echo ""
    echo "✅ 已回退到阶段：$TARGET_PHASE"
    echo "   下一步操作："
    case "$TARGET_PHASE" in
      init|prd-parsing) echo "   → /gd-ai-coding（从阶段 1 继续）" ;;
      prd-parsed|prd-clarified) echo "   → /gd-ai-coding（从需求澄清/spec 生成继续）" ;;
      prd-specing|prd-speced) echo "   → /gd-ai-coding（进入 feature-plan 流程）" ;;
      proposal-approved)   echo "   → /gd-ai-coding（feature-plan 流程，从步骤 3 继续拆分功能）" ;;
      feature-planned)  echo "   → /gd-ai-coding（进入阶段 3 执行开发循环）" ;;
      feature-loop)     echo "   → /gd-ai-coding（Read feature-loop/SKILL.md 执行 <feat_id>）" ;;
      feature-done)     echo "   → /opsx:archive 归档变更，或 /gd-ai-coding 处理" ;;
      done)             echo "   → /gd-ai-coding 开始新任务" ;;
    esac
    ;;

  *)
    echo "用法: recovery.sh [--diagnose | --reconcile | --resume | --suggest | --rollback-to <phase>]"
    echo ""
    echo "  --diagnose          扫描产物，推断恢复点"
    echo "  --reconcile         从 state.json 强制同步 feature-plan.json"
    echo "  --resume/--suggest  综合诊断 + 输出可直接复制执行的恢复命令"
    echo "  --rollback-to <p>   回退到指定阶段，清理后续产物"
    echo ""
    echo "  有效阶段：init | prd-parsing | prd-parsed | prd-clarified | prd-specing | prd-speced | proposal-approved | feature-planned | feature-loop | feature-done | done"
    exit 1
    ;;
esac
