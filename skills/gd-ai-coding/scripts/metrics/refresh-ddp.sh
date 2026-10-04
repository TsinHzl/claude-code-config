#!/usr/bin/env bash
# Fetch fresh DDP data via claude CLI, then transform to dashboard JSON.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAW_FILE="/tmp/ddp-raw-items.json"
DATA_FILE="/tmp/dac-metrics-data.json"
LOG_FILE="/tmp/dac-refresh.log"

# Six-months-ago date for DDP mtime filter
SIX_MONTHS_AGO=$(python3 -c "
from datetime import date
import calendar
d = date.today()
m = d.month - 6; y = d.year
if m <= 0: m += 12; y -= 1
print(date(y, m, min(d.day, calendar.monthrange(y, m)[1])).strftime('%Y-%m-%d'))
")

# Model selection: if DAC_CLAUDE_MODEL is set, pass --model explicitly.
# Otherwise no --model flag is passed, so claude uses whatever is configured locally:
# ANTHROPIC_BASE_URL / ANTHROPIC_API_KEY from env, and the account's default model.
MODEL_ARGS=()
[[ -n "${DAC_CLAUDE_MODEL:-}" ]] && MODEL_ARGS=("--model" "${DAC_CLAUDE_MODEL}")

echo "[$(date '+%H:%M:%S')] 开始获取 DDP 数据（最近半年 >= ${SIX_MONTHS_AGO}）" | tee "$LOG_FILE"
[[ ${#MODEL_ARGS[@]} -gt 0 ]] && echo "[INFO] claude model: ${DAC_CLAUDE_MODEL}" | tee -a "$LOG_FILE"

trap 'rm -f "${RAW_FILE}.tmp"' EXIT

# ── JSON 数组提取函数（heredoc Python）─────────────────────────────────────
extract_json_array() {
    local src="$1" dst="$2" label="$3"
    if ! python3 - "$src" "$dst" 2>> "$LOG_FILE" <<'PYEOF'
import sys, json
raw = open(sys.argv[1], encoding='utf-8').read()
obj = None
search_from = 0
while True:
    idx = raw.find('[', search_from)
    if idx == -1:
        print("[ERROR] no valid JSON array found in claude output", file=sys.stderr)
        sys.exit(1)
    try:
        candidate, _ = json.JSONDecoder().raw_decode(raw, idx)
        if isinstance(candidate, list):
            obj = candidate
            break
    except json.JSONDecodeError:
        pass
    search_from = idx + 1
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    json.dump(obj, f, ensure_ascii=False)
PYEOF
    then
        echo "[ERROR] failed to extract JSON array: ${label}" | tee -a "$LOG_FILE"
        return 1
    fi
}

# ── Step 1: 分页抓取最近半年所有需求 ────────────────────────────────────
# pageSize 上限 25，需循环翻页直到取完。transform 层再按 dept 过滤司机端成员。
echo "[$(date '+%H:%M:%S')] Step 1: 分页查询需求（mtime >= ${SIX_MONTHS_AGO}）..." | tee -a "$LOG_FILE"
set +e
claude ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} -p "
Fetch ALL requirements from the last 6 months by paginating through mcp__ddp__searchRequirements.

Use these FIXED parameters for EVERY call:
- rules: [{\"fieldName\": \"mtime\", \"ruleType\": \"gte\", \"value\": \"${SIX_MONTHS_AGO}\"}]
- extraFields: [\"pmOwner\", \"rdOwnerList\", \"expectReleaseTime\", \"dpmVersion\", \"requirementId\", \"sponsorId\", \"requirement.sponsorId\"]
- pageSize: 25
- orderBy: mtime

Pagination loop (MUST follow exactly):
1. Call with pageNo: 1. Collect all items from data.content.objectList into a running list.
2. If you received exactly 25 items, call again with pageNo: 2 (same other params).
3. Keep incrementing pageNo and collecting items until a page returns fewer than 25 items.
4. Stop when a page returns 0 items OR fewer than 25 items.
5. Do NOT stop early — fetch ALL pages.

After the loop is done, output ONLY the combined JSON array of ALL collected items.
Start with '[', end with ']'. No explanation, no markdown, no surrounding text.
" > "${RAW_FILE}.tmp" 2>> "$LOG_FILE"
CLAUDE_EXIT=$?
set -e

if [[ $CLAUDE_EXIT -ne 0 ]]; then
    echo "[ERROR] searchRequirements exited with code ${CLAUDE_EXIT}" | tee -a "$LOG_FILE"
    exit "$CLAUDE_EXIT"
fi

extract_json_array "${RAW_FILE}.tmp" "$RAW_FILE" "searchRequirements" || exit 1

# ── Step 2: 验证原始数据 ──────────────────────────────────────────────────
python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
if not isinstance(data, list):
    print(f'[ERROR] expected array, got {type(data).__name__}', file=sys.stderr)
    sys.exit(1)
print(f'[OK] {len(data)} items')
" "$RAW_FILE" | tee -a "$LOG_FILE"

echo "[$(date '+%H:%M:%S')] 原始数据有效，开始转换..." | tee -a "$LOG_FILE"

# ── Step 3: git notes（可选）─────────────────────────────────────────────
AI_STATS_FILE="/tmp/dac-git-ai-notes.json"
TRACE_FILE="/tmp/dac-git-trace-notes.json"
rm -f "$AI_STATS_FILE" "$TRACE_FILE"

if [[ -n "${FLUTTER_REPO_URL:-}" ]]; then
    echo "[$(date '+%H:%M:%S')] 获取 git notes (FLUTTER_REPO_URL=${FLUTTER_REPO_URL})" | tee -a "$LOG_FILE"
    bash "$SCRIPT_DIR/fetch-git-notes.sh" 2>&1 | tee -a "$LOG_FILE" || \
        echo "[WARN] git notes 获取失败，跳过 AI 使用量数据" | tee -a "$LOG_FILE"
else
    echo "[INFO] FLUTTER_REPO_URL 未设置，跳过 git notes 步骤" | tee -a "$LOG_FILE"
fi

# ── Step 4: transform ─────────────────────────────────────────────────────
EXTRA_ARGS=""
[[ -f "$AI_STATS_FILE" ]] && EXTRA_ARGS="$EXTRA_ARGS --ai-stats $AI_STATS_FILE"
[[ -f "$TRACE_FILE"    ]] && EXTRA_ARGS="$EXTRA_ARGS --trace $TRACE_FILE"

python3 "$SCRIPT_DIR/transform-ddp.py" "$RAW_FILE" "$DATA_FILE" $EXTRA_ARGS 2>&1 | tee -a "$LOG_FILE"

# ── Step 5: 自动纠正历史 R- 需求级绑定为 T- 任务级（best-effort，失败不影响本脚本退出码）──
echo "[$(date '+%H:%M:%S')] Step 5: 检查 R->T 自动改绑..." | tee -a "$LOG_FILE"
bash "$SCRIPT_DIR/rebind-ddp-r-to-t.sh" 2>&1 | tee -a "$LOG_FILE" || true

echo "[$(date '+%H:%M:%S')] 完成" | tee -a "$LOG_FILE"
