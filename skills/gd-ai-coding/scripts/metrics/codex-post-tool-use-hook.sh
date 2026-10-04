#!/usr/bin/env bash
# codex-post-tool-use-hook.sh — 消费 Codex apply_patch Pre 快照并记录精确实时增量
# 任意不可信输入、快照竞争或统计异常均 fail-open，不阻断 Codex 工具调用。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../runtime.sh" 2>/dev/null || exit 0
dac_resolve_runtime 2>/dev/null || exit 0
[[ "$DAC_RUNTIME" == codex ]] || exit 0
source "$SCRIPT_DIR/../lib.sh" 2>/dev/null || exit 0
source "$SCRIPT_DIR/report-trace-backend.sh" 2>/dev/null || exit 0
source "$SCRIPT_DIR/codex-hook-lib.sh" 2>/dev/null || exit 0
source "$SCRIPT_DIR/codex-realtime-trace-core.sh" 2>/dev/null || exit 0

INPUT=$(cat) || exit 0
_dac_codex_parse_event "$INPUT" PostToolUse 2>/dev/null || exit 0
RESULT=$(dac_codex_consume_post_snapshot "$INPUT" 2>/dev/null) || exit 0
IFS=$'\t' read -r ADDED FILES_JSON <<< "$RESULT"
[[ "$ADDED" =~ ^[0-9]+$ && -n "$FILES_JSON" ]] || exit 0
REPO_ROOT=$(git -C "$DAC_CODEX_CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
REPO_ROOT=$(cd "$REPO_ROOT" 2>/dev/null && pwd -P) || exit 0
dac_record_codex_realtime_trace "$REPO_ROOT" "$DAC_CODEX_EVENT_ID" "$ADDED" "$FILES_JSON" >/dev/null 2>&1 || true
exit 0
