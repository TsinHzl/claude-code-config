#!/usr/bin/env bash
# feature-harness.sh — Unified harness for feature-loop phases.
# Merges multiple bash calls into 3 phases to reduce main-session output tokens.
# Usage: feature-harness.sh <feat_id> <phase>
#   phase: init | pre-codegen | post-codegen
# Exit codes: 0=success, 1=hard failure (sub-step failed), 2=retry exceeded, 3=auto-fixed
set -euo pipefail

FEAT_ID="${1:?Usage: feature-harness.sh <feat_id> <phase>}"
PHASE="${2:?Usage: feature-harness.sh <feat_id> <phase>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/paths.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/feature/codegen-checkpoint.sh"

CHANGE_DIR="$(get_change_dir)"
FEAT_DIR="$(get_feat_dir "" "$FEAT_ID")"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# ── Phase: init ──────────────────────────────────────────────────────────────
# Combines: mkdir + knowledge/snapshot-knowledge + audit-log START + state-update in_progress
# Also: inject CR rule on first feature (conditional)

phase_init() {
  # 1. Create feature working directory
  mkdir -p "$FEAT_DIR"

  # 2. Lock knowledge file snapshot (idempotent, ensures codegen prompt prefix stability)
  bash "$SCRIPT_DIR/knowledge/snapshot-knowledge.sh"

  # 3. Inject CR trigger rule (idempotent, only if not already present)
  local TEMPLATES_DIR="$PLUGIN_DIR/templates"
  local TARGET_RULE=".claude/rules/dac-cr-trigger.md"
  if [[ -f "$TEMPLATES_DIR/dac-cr-trigger.md" && ! -f "$TARGET_RULE" ]]; then
    mkdir -p ".claude/rules"
    cp "$TEMPLATES_DIR/dac-cr-trigger.md" "$TARGET_RULE"
    echo "✓ Injected CR trigger rule: $TARGET_RULE"
  fi

  # 4. Update feature state + audit log (single invocation)
  bash "$SCRIPT_DIR/state-update.sh" "$FEAT_ID" in_progress --audit "STEP:START feature-loop"

  echo "✓ Phase init complete for $FEAT_ID"
}

# ── Phase: pre-codegen ───────────────────────────────────────────────────────
# Combines: scaffold-feature + pre-skill-check + pre-codegen-check + audit-log
# + .codegen_checkpoint（回滚/结算锚点，已有文件不覆盖）

phase_pre_codegen() {
  # 1. Generate scaffold files (zero LLM tokens) — skip if flow_profile says so
  local skip_scaffold
  skip_scaffold=$(jq -r '.flow_profile.skip_scaffold // false' .dac/state.json 2>/dev/null)
  if [[ "$skip_scaffold" == "true" ]]; then
    echo "⏭ 跳过骨架（flow_profile）"
    for _i in 1 2 3; do bash "$SCRIPT_DIR/metrics/record-trace.sh" --skip-stage scaffold && break || sleep 0.2; done || true
  else
    bash "$SCRIPT_DIR/feature/scaffold-feature.sh" "$FEAT_ID" || {
      local rc=$?
      # exit 2 = no new_files, not fatal — codegen may only modify existing files
      if [[ $rc -eq 2 ]]; then
        echo "INFO: No new files to scaffold (modify-only feature)"
      else
        echo "ERROR: scaffold-feature.sh failed with exit $rc" >&2
        exit 1
      fi
    }
  fi

  # 2. Graphify context (optional, silent skip if no graph.json)
  bash "$SCRIPT_DIR/feature/gen-graphify-context.sh" "$FEAT_ID" || true

  # 3+4. Pre-checks (independent, run in parallel)
  bash "$SCRIPT_DIR/checks/pre-skill-check.sh" codegen "$FEAT_ID" &
  local pid1=$!
  bash "$SCRIPT_DIR/checks/pre-codegen-check.sh" "$FEAT_ID" &
  local pid2=$!

  local fail=0
  wait $pid1 || fail=1
  wait $pid2 || fail=1
  if [[ $fail -ne 0 ]]; then
    echo "ERROR: Pre-codegen checks failed" >&2
    exit 1
  fi

  # 4. Audit log
  bash "$SCRIPT_DIR/audit-log.sh" "$FEAT_ID" "STEP:START" "codegen"

  # 5. codegen 回滚/结算锚点：门禁通过后落盘，不覆盖已有文件（重跑不能漂基准）。
  #    失败不阻断；无此文件时 settle-codegen-lines.sh 会空跑，自动生成行一直是 0。
  write_codegen_checkpoint "$FEAT_DIR" || true

  echo "✓ Phase pre-codegen complete for $FEAT_ID"
}

# ── Phase: post-codegen ──────────────────────────────────────────────────────
# Combines: post-codegen-check + extract-constraints + audit-log DONE
# Passes through exit code from post-codegen-check (0/1/2/3)

phase_post_codegen() {
  local POST_EXIT=0

  # 0. 检查开始：必须先报 started，成功/失败才有分母
  bash "$SCRIPT_DIR/metrics/report-workflow-event.sh" \
    "codegen_check_started" "{\"feat_id\":\"$FEAT_ID\"}" || true

  # 1. Post-codegen check (dart analyze + format + naming)
  bash "$SCRIPT_DIR/checks/post-codegen-check.sh" "$FEAT_ID" --check-retry-count || POST_EXIT=$?

  # 2. Audit log (always, regardless of check result)
  bash "$SCRIPT_DIR/audit-log.sh" "$FEAT_ID" "STEP:DONE" "codegen exit=$POST_EXIT"

  # 3. If check passed (0 or 3), extract constraints for knowledge flywheel
  if [[ $POST_EXIT -eq 0 || $POST_EXIT -eq 3 ]]; then
    bash "$SCRIPT_DIR/knowledge/extract-constraints.sh" "$FEAT_ID" 2>/dev/null || true
  fi

  # 4. 成对上报结果：0=通过，3=自动 format 后通过，1=硬失败，2=超重试
  local event_type=""
  case $POST_EXIT in
    0) event_type="codegen_check_passed" ;;
    3) event_type="codegen_check_auto_fixed" ;;
    1|2) event_type="codegen_check_failed" ;;
  esac
  if [[ -n "$event_type" ]]; then
    bash "$SCRIPT_DIR/metrics/report-workflow-event.sh" \
      "$event_type" "{\"feat_id\":\"$FEAT_ID\",\"exit_code\":$POST_EXIT}" || true
  fi

  # L2 通过才结算自动生成行（失败不结算）。feature done 还会再结算一次取 max（含 CR 修补）
  if [[ $POST_EXIT -eq 0 || $POST_EXIT -eq 3 ]]; then
    bash "$SCRIPT_DIR/metrics/settle-codegen-lines.sh" "$FEAT_ID" || true
  fi

  # Pass through the exit code (0=pass, 1=hard fail, 2=retry exceeded, 3=auto-fixed)
  exit $POST_EXIT
}

# ── Dispatch ─────────────────────────────────────────────────────────────────

case "$PHASE" in
  init)         phase_init ;;
  pre-codegen)  phase_pre_codegen ;;
  post-codegen) phase_post_codegen ;;
  *)
    echo "ERROR: Unknown phase '$PHASE'. Use: init | pre-codegen | post-codegen" >&2
    exit 1
    ;;
esac
