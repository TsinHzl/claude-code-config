#!/usr/bin/env bash
# cal-req-token-cost.sh — 聚合本次需求的 Claude token 消耗并写入 state.json.token_summary
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPTS_DIR/lib.sh"

STATE_FILE=".dac/state.json"

# ─── 前置检查 ───
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE" 2>/dev/null)
CREATED_AT=$(jq -r '.created_at // empty' "$STATE_FILE" 2>/dev/null)
REQ_ID=$(jq -r '.req_id // empty' "$STATE_FILE" 2>/dev/null)

if [[ -z "$REQ_NAME" || -z "$CREATED_AT" ]]; then
  exit 0
fi

# ─── 计算 Claude Code 项目日志目录 ───
export PROJECT_ROOT=$(pwd -P)
ENCODED_CWD="${PROJECT_ROOT//\//-}"
export CLAUDE_PROJECT_DIR="$HOME/.claude/projects/$ENCODED_CWD"
export CREATED_AT

if [[ ! -d "$CLAUDE_PROJECT_DIR" ]]; then
  [[ "${DAC_TOKEN_COST_QUIET:-}" != "1" ]] && echo "[token-summary] 无 Claude Code 本地日志,跳过"
  exit 0
fi

# ─── Python 流式聚合 ───
JSON_OUTPUT=$(python3 << 'PYEOF'
import json, os, sys, glob, time

project_root = os.environ["PROJECT_ROOT"]
claude_dir = os.environ["CLAUDE_PROJECT_DIR"]
created_at = os.environ["CREATED_AT"]

totals = {"input": 0, "output": 0, "cache_read": 0, "cache_creation": 0}
by_model = {}
sessions_scanned = 0
records_matched = 0

jsonl_files = glob.glob(os.path.join(claude_dir, "*.jsonl"))
sessions_scanned = len(jsonl_files)

for fpath in jsonl_files:
    try:
        with open(fpath, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except (json.JSONDecodeError, ValueError):
                    continue

                if entry.get("type") != "assistant":
                    continue

                msg = entry.get("message")
                if not isinstance(msg, dict):
                    continue

                usage = msg.get("usage")
                if not isinstance(usage, dict):
                    continue

                cwd = entry.get("cwd", "")
                try:
                    resolved_cwd = os.path.realpath(cwd) if cwd else ""
                except (OSError, ValueError):
                    resolved_cwd = ""

                if resolved_cwd != project_root:
                    continue

                ts = entry.get("timestamp", "")
                if ts < created_at:
                    continue

                records_matched += 1
                inp = usage.get("input_tokens", 0) or 0
                out = usage.get("output_tokens", 0) or 0
                cr = usage.get("cache_read_input_tokens", 0) or 0
                cc = usage.get("cache_creation_input_tokens", 0) or 0

                totals["input"] += inp
                totals["output"] += out
                totals["cache_read"] += cr
                totals["cache_creation"] += cc

                model = msg.get("model", "unknown")
                if model not in by_model:
                    by_model[model] = {"input": 0, "output": 0, "cache_read": 0, "cache_creation": 0}
                by_model[model]["input"] += inp
                by_model[model]["output"] += out
                by_model[model]["cache_read"] += cr
                by_model[model]["cache_creation"] += cc
    except (IOError, OSError):
        continue

import time
now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
result = {
    "input": totals["input"],
    "output": totals["output"],
    "cache_read": totals["cache_read"],
    "cache_creation": totals["cache_creation"],
    "by_model": by_model,
    "sessions_scanned": sessions_scanned,
    "records_matched": records_matched,
    "updated_at": now_iso
}

print(json.dumps(result, ensure_ascii=False))
PYEOF
)

if [[ -z "$JSON_OUTPUT" ]]; then
  exit 0
fi

RECORDS_MATCHED=$(echo "$JSON_OUTPUT" | jq -r '.records_matched')

# ─── stdout 输出 ───
if [[ "${DAC_TOKEN_COST_QUIET:-}" != "1" ]]; then
  if [[ "$RECORDS_MATCHED" -eq 0 ]]; then
    echo "[token-summary] 本需求区间内无 assistant usage 记录"
  else
    DATE_PART="${CREATED_AT:0:10}"
    INPUT_FMT=$(python3 -c "print(f'{$(echo "$JSON_OUTPUT" | jq -r '.input'):,}')")
    OUTPUT_FMT=$(python3 -c "print(f'{$(echo "$JSON_OUTPUT" | jq -r '.output'):,}')")
    CACHE_READ_FMT=$(python3 -c "print(f'{$(echo "$JSON_OUTPUT" | jq -r '.cache_read'):,}')")
    CACHE_CREATION_FMT=$(python3 -c "print(f'{$(echo "$JSON_OUTPUT" | jq -r '.cache_creation'):,}')")
    echo "需求: ${REQ_NAME}  (自 ${DATE_PART} 起)"
    printf "  %-15s %s\n" "input:" "$INPUT_FMT"
    printf "  %-15s %s\n" "output:" "$OUTPUT_FMT"
    printf "  %-15s %s\n" "cache_read:" "$CACHE_READ_FMT"
    printf "  %-15s %s\n" "cache_creation:" "$CACHE_CREATION_FMT"
  fi
fi

# ─── 写入 state.json.token_summary ───
if [[ "${DAC_TOKEN_COST_NO_WRITE:-}" == "1" ]]; then
  exit 0
fi

atomic_jq --compact '.token_summary = $ts' "$STATE_FILE" --argjson ts "$JSON_OUTPUT"