#!/usr/bin/env bash
# state-update.sh — 统一状态更新入口
#
# 用法：
#   state-update.sh --phase <phase_name>                                  # phase 级更新（prd 阶段）
#   state-update.sh --set-flag <key> <true|false>                         # 设置/清除顶层布尔标记
#   state-update.sh --set-field <key> <value>                             # 设置顶层任意字符串值
#   state-update.sh <feat_id> <status> [--step <name>] [--audit <msg>]    # feature 级更新（feature-loop 阶段）
#
# 所有 state.json 变更必须通过本脚本，skill 中不直接 jq 修改。

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/lib.sh"

# ─── Flag 模式：设置 state.json 顶层布尔标记（如 batch_confirmed） ───
if [[ "${1:-}" == "--set-flag" ]]; then
  FLAG_KEY=${2:?"用法: state-update.sh --set-flag <key> <true|false>"}
  FLAG_VAL=${3:?"用法: state-update.sh --set-flag <key> <true|false>"}
  STATE_FILE=".dac/state.json"
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "[DAC-STATE-003] ❌ .dac/state.json 不存在" >&2
    exit 1
  fi
  if [[ "$FLAG_VAL" == "true" ]]; then
    atomic_jq --compact '.[$k] = true' "$STATE_FILE" --arg k "$FLAG_KEY"
    echo "✅ flag 已设置：$FLAG_KEY=true"
  else
    atomic_jq --compact 'del(.[$k])' "$STATE_FILE" --arg k "$FLAG_KEY"
    echo "✅ flag 已清除：$FLAG_KEY"
  fi
  exit 0
fi

# ─── JSON 模式：设置 state.json 顶层 JSON 对象/数组值（如 flow_profile, available_platforms） ───
if [[ "${1:-}" == "--set-json" ]]; then
  JSON_KEY=${2:?"用法: state-update.sh --set-json <key> '<json_value>'"}
  JSON_VAL=${3:?"用法: state-update.sh --set-json <key> '<json_value>'"}
  STATE_FILE=".dac/state.json"
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "[DAC-STATE-003] ❌ .dac/state.json 不存在" >&2
    exit 1
  fi
  if ! echo "$JSON_VAL" | jq . >/dev/null 2>&1; then
    echo "[DAC-STATE-010] ❌ 无效 JSON 值：$JSON_VAL" >&2
    exit 1
  fi
  atomic_jq --compact '.[$k] = $v' "$STATE_FILE" --argjson v "$JSON_VAL" --arg k "$JSON_KEY"
  echo "✅ json field 已设置：$JSON_KEY"
  exit 0
fi

# ─── Field 模式：设置 state.json 顶层任意字符串值（如 graphify_decision） ───
if [[ "${1:-}" == "--set-field" ]]; then
  FIELD_KEY=${2:?"用法: state-update.sh --set-field <key> <value>"}
  FIELD_VAL=${3:?"用法: state-update.sh --set-field <key> <value>"}
  STATE_FILE=".dac/state.json"
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "[DAC-STATE-003] ❌ .dac/state.json 不存在" >&2
    exit 1
  fi
  atomic_jq --compact '.[$k] = $v' "$STATE_FILE" --arg k "$FIELD_KEY" --arg v "$FIELD_VAL"
  echo "✅ field 已设置：$FIELD_KEY=$FIELD_VAL"
  exit 0
fi

# ─── req-id 模式：写入 req_id 到 state.json 并同步追踪文件 ───
if [[ "${1:-}" == "--req-id" ]]; then
  REQ_ID_VAL="${2:?"用法: state-update.sh --req-id <id>"}"
  STATE_FILE=".dac/state.json"
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "[DAC-STATE-003] ❌ .dac/state.json 不存在" >&2
    exit 1
  fi
  # ① 写 state.json.req_id
  atomic_jq --compact '.req_id = $rid' "$STATE_FILE" --arg rid "$REQ_ID_VAL"
  # ② 读 req_name，若为空则跳过追踪文件同步
  _rn="$(jq -r '.req_name // empty' "$STATE_FILE")"
  if [[ -z "$_rn" ]]; then
    echo "[state-update] ⚠️  state.json.req_name 为空，跳过追踪文件同步" >&2
  else
    _safe_rn="${_rn//[^A-Za-z0-9._-]/_}"
    _tf=".dac/trace/${_safe_rn}.json"
    # ③ 同步追踪文件 req_id（文件不存在时静默跳过）
    if [[ -f "$_tf" ]]; then
      atomic_jq --compact '.req_id = $rid' "$_tf" --arg rid "$REQ_ID_VAL" || \
        echo "[state-update] ⚠️  追踪文件 req_id 同步失败：$_tf" >&2
    fi
  fi
  echo "✅ req_id 已设置：$REQ_ID_VAL"
  exit 0
fi

# ─── Phase 模式：更新 state.json 的 phase 字段（可选设置 req_name / req_id） ───
if [[ "${1:-}" == "--phase" ]]; then
  NEW_PHASE=${2:?"用法: state-update.sh --phase <phase_name> [--req-name <name>] [--req-id <id>] [--force]"}
  shift 2
  REQ_NAME_ARG=""
  REQ_ID_ARG=""
  FORCE=false
  DDP_ID_ARG=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --req-name) REQ_NAME_ARG="$2"; shift 2 ;;
      --req-id)   REQ_ID_ARG="$2"; shift 2 ;;
      --ddp-id)   DDP_ID_ARG="$2"; shift 2 ;;
      --force) FORCE=true; shift ;;
      --) shift; break ;;
      -*) echo "[DAC-STATE-011] ⚠️  未知参数：$1（忽略）" >&2; shift ;;
      *) shift ;;
    esac
  done

  # ddp_id 统一标准化为大写存储
  if [[ -n "$DDP_ID_ARG" ]]; then
    DDP_ID_ARG=$(normalize_ddp_id "$DDP_ID_ARG")
  fi

  STATE_FILE=".dac/state.json"
  OLD_PHASE=""

  if [[ ! -f "$STATE_FILE" ]]; then
    mkdir -p .dac
    state_json_template "$NEW_PHASE" "$REQ_NAME_ARG" > "$STATE_FILE"
    [[ -n "$DDP_ID_ARG" ]] && atomic_jq --compact '.ddp_id = $ddpid' "$STATE_FILE" --arg ddpid "$DDP_ID_ARG"
    echo "✅ phase 已初始化：→ $NEW_PHASE"
    for _i in 1 2 3; do bash "$SCRIPTS_DIR/metrics/record-trace.sh" --phase "$NEW_PHASE" && break || sleep 0.2; done || true
    exit 0
  fi

  OLD_PHASE=$(jq -r '.phase // "init"' "$STATE_FILE" 2>/dev/null)

  # 校验 phase 转换合法性（仅允许向前推进，回退需使用 recovery.sh --rollback-to）
  if [[ "$FORCE" == "false" ]]; then
    CURRENT_PHASE="$OLD_PHASE"
    CURRENT_ORDER=$(phase_to_order "$CURRENT_PHASE")
    NEW_ORDER=$(phase_to_order "$NEW_PHASE")
    if [[ "$NEW_ORDER" -eq -1 ]]; then
      echo "[DAC-STATE-005] ❌ 无效的目标 phase：$NEW_PHASE" >&2
      exit 1
    fi
    if [[ "$NEW_ORDER" -le "$CURRENT_ORDER" && "$CURRENT_ORDER" -ne -1 ]]; then
      echo "[DAC-STATE-005] ❌ phase 转换不合法：$CURRENT_PHASE → $NEW_PHASE（不允许回退或重复）" >&2
      echo "   如需回退，请使用：bash scripts/recovery.sh --rollback-to $NEW_PHASE" >&2
      exit 1
    fi
  fi

  NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  _JQ_EXPR='.phase = $phase | .updated_at = $ts'
  _JQ_ARGS=(--arg phase "$NEW_PHASE" --arg ts "$NOW_ISO")
  [[ -n "$REQ_NAME_ARG" ]] && { _JQ_EXPR+=' | .req_name = $rn';  _JQ_ARGS+=(--arg rn "$REQ_NAME_ARG"); }
  [[ -n "$REQ_ID_ARG"   ]] && { _JQ_EXPR+=' | .req_id = $rid';   _JQ_ARGS+=(--arg rid "$REQ_ID_ARG"); }
  [[ -n "$DDP_ID_ARG"   ]] && { _JQ_EXPR+=' | .ddp_id = $ddpid'; _JQ_ARGS+=(--arg ddpid "$DDP_ID_ARG"); }
  atomic_jq --compact "$_JQ_EXPR" "$STATE_FILE" "${_JQ_ARGS[@]}"

  for _i in 1 2 3; do bash "$SCRIPTS_DIR/metrics/record-trace.sh" --phase "$NEW_PHASE" && break || sleep 0.2; done || true

  # --req-id 同步：record-trace.sh 的 resume 分支不写 req_id，在此显式补全
  if [[ -n "$REQ_ID_ARG" ]]; then
    _rn_phase="$(jq -r '.req_name // empty' "$STATE_FILE")"
    if [[ -n "$_rn_phase" ]]; then
      _tf_phase=".dac/trace/${_rn_phase//[^A-Za-z0-9._-]/_}.json"
      [[ -f "$_tf_phase" ]] && \
        atomic_jq --compact '.req_id = $rid' "$_tf_phase" --arg rid "$REQ_ID_ARG" || true
    fi
  fi

  # token 汇总：feature-done 时打印本需求 token 消耗
  [[ "$NEW_PHASE" == "feature-done" ]] && bash "$SCRIPTS_DIR/metrics/cal-req-token-cost.sh" || true

  # 用户门「接受」：phase 真正推进到确认点时由 Harness 上报，skill 不要再报
  if [[ "$NEW_PHASE" != "$OLD_PHASE" ]]; then
    case "$NEW_PHASE" in
      prd-clarified)      bash "$SCRIPTS_DIR/metrics/report-user-gate.sh" clarify accepted || true ;;
      proposal-approved)  bash "$SCRIPTS_DIR/metrics/report-user-gate.sh" proposal accepted || true ;;
      feature-planned)    bash "$SCRIPTS_DIR/metrics/report-user-gate.sh" feature_plan accepted || true ;;
    esac
  fi

  echo "✅ phase 已更新：→ $NEW_PHASE"
  exit 0
fi

# ─── Feature 模式：更新 state.json + feature-plan.json ───
if [[ $# -lt 2 ]]; then
  echo "用法:" >&2
  echo "  state-update.sh --phase <phase_name>" >&2
  echo "  state-update.sh <feat_id> <status> [--step <step_name>]" >&2
  exit 1
fi

FEAT_ID=$1
NEW_STATUS=$2
STEP_NAME=""
AUDIT_MSG=""

# 校验 status 合法性（白名单）
ALLOWED_STATUSES="pending in_progress done done_with_issues failed skipped"
if ! echo "$ALLOWED_STATUSES" | grep -qw "$NEW_STATUS"; then
  echo "[DAC-STATE-013] ❌ 无效的 feature status：'$NEW_STATUS'" >&2
  echo "   允许值：$ALLOWED_STATUSES" >&2
  exit 1
fi

shift 2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --step) STEP_NAME="$2"; shift 2 ;;
    --audit) AUDIT_MSG="$2"; shift 2 ;;
    --) shift; break ;;
    -*) echo "[DAC-STATE-011] ⚠️  未知参数：$1（忽略）" >&2; shift ;;
    *) shift ;;
  esac
done

LOCK_FILE=".dac/.lock"
STATE_FILE=".dac/state.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "[DAC-STATE-003] ❌ .dac/state.json 不存在" >&2
  exit 1
fi

# 校验 state.json 格式合法性
if ! validate_json "$STATE_FILE"; then
  echo "[DAC-STATE-004] ❌ state.json JSON 格式损坏，无法更新状态" >&2
  echo "   运行 scripts/recovery.sh --reconcile 修复，或手动修正 .dac/state.json" >&2
  exit 1
fi

REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE" 2>/dev/null)
if [[ -z "$REQ_NAME" ]]; then
  echo "[DAC-STATE-003] ❌ state.json 中缺少 req_name 字段" >&2
  exit 1
fi

source "$SCRIPTS_DIR/paths.sh"
PLAN_JSON="$(get_change_dir "$REQ_NAME")/feature-plan.json"

# 0. 终态门禁：feature → done 时强制校验 cr-report.md 存在性（Harness 硬拦截）
if [[ "$NEW_STATUS" == "done" || "$NEW_STATUS" == "done_with_issues" ]]; then
  FEAT_DIR="$(get_feat_dir "$REQ_NAME" "$FEAT_ID")"
  if [[ ! -f "$FEAT_DIR/cr-report.md" ]]; then
    echo "[DAC-STATE-012] ❌ 终态门禁拦截：cr-report.md 不存在" >&2
    echo "   路径：$FEAT_DIR/cr-report.md" >&2
    echo "   feature 标记 done 前必须完成步骤 5（CR 校验）或合法跳过（净改动<10行）" >&2
    echo "" >&2
    echo "   修复方式：" >&2
    echo "     1. 补执行 CR：重新 Read 执行 feature-loop/SKILL.md（${FEAT_ID}，会从步骤 5 恢复）" >&2
    echo "     2. 合法跳过：echo 'verdict: skipped（手动确认跳过）' > \"${FEAT_DIR}/cr-report.md\"" >&2
    exit 1
  fi
fi

# 1. 检查 lock 文件（检测未完成的转换）
if [[ -f "$LOCK_FILE" ]]; then
  LOCK_TS=$(jq -r '.ts // empty' "$LOCK_FILE" 2>/dev/null)

  if [[ -n "$LOCK_TS" ]]; then
    LOCK_EPOCH=$(iso_to_epoch "$LOCK_TS")
    NOW_EPOCH=$(date +%s)
    AGE=$(( NOW_EPOCH - LOCK_EPOCH ))

    if [[ $AGE -le 300 ]]; then
      # 新鲜 lock：可能有并发操作正在进行，拒绝写入
      echo "[DAC-STATE-001] ❌ Lock 文件存在（${AGE}s 前创建），可能有状态转换正在进行"
      echo "   Lock 内容：$(cat "$LOCK_FILE")"
      echo "   若确认无并发操作，运行 scripts/recovery.sh --reconcile 清理"
      exit 1
    fi
    # 超时 lock（> 5min）：视为崩溃残留，安全清理
    echo "[DAC-STATE-001] ⚠️  清理超时 lock 文件（已存在 $((AGE/60)) 分钟，判定为崩溃残留）" >&2
  fi
  rm -f "$LOCK_FILE"
fi

# 2. 写入 lock 文件（声明转换意图）
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n --arg ts "$NOW_ISO" --arg feat_id "$FEAT_ID" --arg target_status "$NEW_STATUS" \
  '{ts: $ts, feat_id: $feat_id, target_status: $target_status}' > "$LOCK_FILE"

# 3. 原子更新 state.json + feature-plan.json
OLD_PHASE=$(jq -r '.phase // "init"' "$STATE_FILE")

# 3a. 更新 state.json
if ! atomic_jq --compact '
  (if $status == "in_progress" then
    .current_feature_id = $fid |
    (if .phase != "feature-loop" then .phase = "feature-loop" else . end)
  elif $status == "done" then
    .current_feature_id = null |
    .completed_features = ((.completed_features // []) | if any(. == $fid) then . else . + [$fid] end)
  elif $status == "done_with_issues" then
    .current_feature_id = null |
    .completed_features = ((.completed_features // []) | if any(. == $fid) then . else . + [$fid] end) |
    .issues_features = ((.issues_features // []) | if any(. == $fid) then . else . + [$fid] end)
  elif ($status == "failed" or $status == "skipped") then
    .current_feature_id = null |
    .skipped_features = ((.skipped_features // []) | if any(. == $fid) then . else . + [$fid] end)
  elif $status == "pending" then
    .current_feature_id = null |
    .completed_features = ((.completed_features // []) | map(select(. != $fid))) |
    .issues_features = ((.issues_features // []) | map(select(. != $fid))) |
    .skipped_features = ((.skipped_features // []) | map(select(. != $fid)))
  else . end) |
  .updated_at = $ts
' "$STATE_FILE" --arg fid "$FEAT_ID" --arg status "$NEW_STATUS" --arg ts "$NOW_ISO"; then
  rm -f "$LOCK_FILE"
  echo "[DAC-STATE-004] ❌ state.json 更新失败" >&2
  exit 1
fi

# 3b. 更新 feature-plan.json（如果存在）
#     协作模式（openspec/changes/{req}/collab.json 存在）下跳过 .status/.current_step/.updated_at
#     的写入：跨人权威落在 status.json（3b.5），feature-plan.json 保持规划时的骨架，
#     避免两人各写 feature-plan.json.status 后 git commit/push 冲突。单人模式行为不变。
_COLLAB_PLAN_JSON="$(get_change_dir "$REQ_NAME")/collab.json"
if [[ -f "$PLAN_JSON" && ! -f "$_COLLAB_PLAN_JSON" ]]; then
  if ! atomic_jq '
    (if type == "array" then . else .features end) as $feats |
    ($feats | map(if .id == $fid then
      .status = $status | .updated_at = $ts |
      (if $step != "" then .current_step = $step else . end) |
      (if $status == "done" then .current_step = null else . end)
    else . end)) as $updated |
    if type == "array" then $updated else .features = $updated end
  ' "$PLAN_JSON" --arg fid "$FEAT_ID" --arg status "$NEW_STATUS" --arg ts "$NOW_ISO" --arg step "$STEP_NAME"; then
    rm -f "$LOCK_FILE"
    echo "[DAC-STATE-004] ❌ feature-plan.json 更新失败" >&2
    exit 1
  fi
fi

# 3b.5. 协作模式：同步 openspec/changes/{req}/features/{id}/status.json
#       协作模式判定仅以 collab.json 存在为准（不看 state.json.collab_mode，reconcile 后可能失同步）
COLLAB_JSON="$(get_change_dir "$REQ_NAME")/collab.json"
if [[ -f "$COLLAB_JSON" ]]; then
  FEAT_DIR_SYNC="$(get_features_dir "$REQ_NAME")/$FEAT_ID"
  mkdir -p "$FEAT_DIR_SYNC"
  STATUS_FILE="$FEAT_DIR_SYNC/status.json"
  GIT_EMAIL=$(git config user.email 2>/dev/null || echo "")
  # 首次写入：seed 一个最小骨架，再 atomic_jq 覆盖字段
  if [[ ! -f "$STATUS_FILE" ]]; then
    echo '{}' > "$STATUS_FILE"
  fi
  if ! atomic_jq '
    .feature_id = $fid |
    .status = $status |
    (if $status == "in_progress" then
       # 未认领过则写；已认领（含恢复：claimed_by == 当前）保持原值
       (if (.claimed_by // "") == "" then
          .claimed_by = $email | .claimed_at = $ts
        else . end) |
       .completed_at = null
     elif $status == "done" or $status == "done_with_issues" then
       .completed_at = $ts
     elif $status == "failed" or $status == "skipped" then
       .completed_at = $ts
     elif $status == "pending" then
       .claimed_by = null | .claimed_at = null | .completed_at = null
     else . end)
  ' "$STATUS_FILE" --arg fid "$FEAT_ID" --arg status "$NEW_STATUS" --arg email "$GIT_EMAIL" --arg ts "$NOW_ISO"; then
    rm -f "$LOCK_FILE"
    echo "[DAC-STATE-004] ❌ status.json 同步失败：$STATUS_FILE" >&2
    exit 1
  fi
fi

# 3c. 检查是否所有功能已完成 → 自动切换 feature-done
if [[ "$NEW_STATUS" == "done" || "$NEW_STATUS" == "done_with_issues" || "$NEW_STATUS" == "failed" || "$NEW_STATUS" == "skipped" ]]; then
  if [[ -f "$PLAN_JSON" ]]; then
    _all_done=$(jq --slurpfile state "$STATE_FILE" '
      (if type == "array" then . else .features end) | [.[].id] as $all |
      if ($all | length) == 0 then false
      else
        ($state[0].completed_features // []) + ($state[0].skipped_features // []) | unique as $done |
        ($all | all(. as $id | $done | any(. == $id)))
      end
    ' "$PLAN_JSON")
    if [[ "$_all_done" == "true" ]]; then
      _cur_phase=$(jq -r '.phase // "init"' "$STATE_FILE")
      _cur_order=$(phase_to_order "$_cur_phase")
      _fd_order=$(phase_to_order "feature-done")
      if [[ $_fd_order -gt $_cur_order ]]; then
        if ! atomic_jq --compact '.phase = "feature-done" | .updated_at = $ts' "$STATE_FILE" --arg ts "$NOW_ISO"; then
          echo "[DAC-STATE-004] ⚠️  自动切换 feature-done 失败，请手动执行 state-update.sh --phase feature-done --force" >&2
        else
          bash "$SCRIPTS_DIR/metrics/cal-req-token-cost.sh" || true
        fi
      fi
    elif [[ -f "$_COLLAB_PLAN_JSON" ]]; then
      # 协作模式且未全量 done：若当前用户 assignee 的 feature 全部 done，触发一次 token 汇总
      # 幂等靠 state.json.collab_token_summary_at 标记，避免每次 done 都重跑
      _my_email=$(git config user.email 2>/dev/null || echo "")
      if [[ -n "$_my_email" ]]; then
        _my_pending=$(jq --slurpfile state "$STATE_FILE" --arg email "$_my_email" '
          (if type == "array" then . else .features end)
          | map(select((.assignee // "") | ascii_downcase == ($email | ascii_downcase)))
          | [.[].id] as $mine |
          if ($mine | length) == 0 then -1
          else
            ($state[0].completed_features // []) + ($state[0].skipped_features // []) | unique as $done |
            ($mine | map(select(. as $id | $done | any(. == $id) | not)) | length)
          end
        ' "$PLAN_JSON")
        _already_fired=$(jq -r '.collab_token_summary_at // ""' "$STATE_FILE")
        if [[ "$_my_pending" == "0" && -z "$_already_fired" ]]; then
          bash "$SCRIPTS_DIR/metrics/cal-req-token-cost.sh" || true
          atomic_jq --compact '.collab_token_summary_at = $ts' "$STATE_FILE" --arg ts "$NOW_ISO" || true
          echo "ℹ️  协作模式：你的 assignee feature 已全部完成，触发本人份额 token 汇总（不改全局 phase）" >&2
        fi
      fi
    fi
  fi
fi

# 3d. 检测 phase 变化，补调 trace 记录
NEW_PHASE=$(jq -r '.phase // "init"' "$STATE_FILE")
if [[ "$NEW_PHASE" != "$OLD_PHASE" ]]; then
  for _i in 1 2 3; do bash "$SCRIPTS_DIR/metrics/record-trace.sh" --phase "$NEW_PHASE" && break || sleep 0.2; done || true
fi

# 4. 删除 lock 文件（转换完成）
rm -f "$LOCK_FILE"

# feature 终态只走 record-trace（A），不再向 /events 补报终态（与 A 重复，看板也不读）

# ── 采集:追加 feature 状态到流程追踪文件;容错不阻断主流程 ──
for _i in 1 2 3; do bash "$SCRIPTS_DIR/metrics/record-trace.sh" --feature "$FEAT_ID" "$NEW_STATUS" && break || sleep 0.2; done || true

# feature 完成后再结算一次自动生成行（与 L2 通过时的结算取 max，把 CR 修补算进去）
if [[ "$NEW_STATUS" == "done" || "$NEW_STATUS" == "done_with_issues" ]]; then
  bash "$SCRIPTS_DIR/metrics/settle-codegen-lines.sh" "$FEAT_ID" || true
fi

# 5. 附带审计日志（可选，减少一次独立调用）
# AUDIT_MSG 格式: "EVENT_TYPE" 或 "EVENT_TYPE detail_text"
if [[ -n "$AUDIT_MSG" ]]; then
  _audit_event="${AUDIT_MSG%% *}"
  _audit_detail="${AUDIT_MSG#"$_audit_event"}"
  _audit_detail="${_audit_detail# }"
  bash "$SCRIPTS_DIR/audit-log.sh" "$FEAT_ID" "$_audit_event" "$_audit_detail"
fi

echo "✅ 状态已更新：$FEAT_ID → $NEW_STATUS"
