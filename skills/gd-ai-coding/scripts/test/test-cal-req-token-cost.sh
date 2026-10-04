#!/usr/bin/env bash
# test-cal-req-token-cost.sh — Unit tests for cal-req-token-cost.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CAL_SCRIPT="$SCRIPT_DIR/../metrics/cal-req-token-cost.sh"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" actual="$3"
  if echo "$actual" | grep -qF "$needle"; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc (not found: '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

run_cal() {
  local proj_dir="$1" home_dir="$2"
  (cd "$proj_dir" && HOME="$home_dir" bash "$CAL_SCRIPT" 2>&1)
}

# ── Helpers ──────────────────────────────────────────────────────────────────

make_project() {
  local dir="$1"
  mkdir -p "$dir/.dac"
  cat > "$dir/.dac/state.json" << 'EOF'
{"phase":"feature-done","req_name":"test-req","req_id":"R-IBG-999","created_at":"2026-01-01T00:00:00Z","updated_at":"2026-08-25T00:00:00Z"}
EOF
}

real_path() {
  (cd "$1" && pwd -P)
}

make_jsonl_record() {
  local model="${1:-claude-opus-4-8}" input="${2:-1000}" output="${3:-500}" cache_read="${4:-2000}" cache_creation="${5:-300}" cwd="$6" ts="${7:-2026-06-01T10:00:00.000Z}"
  printf '{"type":"assistant","timestamp":"%s","cwd":"%s","sessionId":"s1","message":{"model":"%s","usage":{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s}}}\n' \
    "$ts" "$cwd" "$model" "$input" "$output" "$cache_read" "$cache_creation"
}

setup_claude_dir() {
  local proj_dir="$1" home_dir="$2"
  local real_proj_dir
  real_proj_dir="$(cd "$proj_dir" && pwd -P)"
  local encoded
  encoded="$(echo "$real_proj_dir" | tr '/' '-')"
  local claude_dir="$home_dir/.claude/projects/$encoded"
  mkdir -p "$claude_dir"
  echo "$claude_dir"
}

# ══════════════════════════════════════════════════════════════════════════════
echo "=== Test 1: 目录缺失 → 跳过提示 + 无 token_summary ==="

PROJ1="$TEST_DIR/proj1"
mkdir -p "$PROJ1/.dac"
cat > "$PROJ1/.dac/state.json" << 'EOF'
{"phase":"feature-done","req_name":"no-logs","created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}
EOF

HOME1="$TEST_DIR/home1"
mkdir -p "$HOME1"
OUTPUT=$(run_cal "$PROJ1" "$HOME1")
EXIT_CODE=$?
assert_eq "exit code 0" "0" "$EXIT_CODE"
assert_contains "prints skip message" "无 Claude Code 本地日志" "$OUTPUT"
TS=$(jq -r '.token_summary // "NONE"' "$PROJ1/.dac/state.json")
assert_eq "no token_summary written" "NONE" "$TS"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Test 2: 命中记录=0 → 写 token_summary totals 全 0 ==="

PROJ2="$TEST_DIR/proj2"
make_project "$PROJ2"
HOME2="$TEST_DIR/home2"
CLAUDE_DIR2=$(setup_claude_dir "$PROJ2" "$HOME2")
make_jsonl_record "claude-opus-4-8" 100 50 200 30 "/some/other/path" > "$CLAUDE_DIR2/session1.jsonl"

OUTPUT=$(run_cal "$PROJ2" "$HOME2")
assert_contains "prints no-records message" "无 assistant usage 记录" "$OUTPUT"
MATCHED=$(jq -r '.token_summary.records_matched // "NONE"' "$PROJ2/.dac/state.json")
assert_eq "records_matched = 0" "0" "$MATCHED"
INPUT_VAL=$(jq -r '.token_summary.input // "NONE"' "$PROJ2/.dac/state.json")
assert_eq "input = 0" "0" "$INPUT_VAL"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Test 3: 单会话单 model → 数字正确 + by_model 键数=1 ==="

PROJ3="$TEST_DIR/proj3"
make_project "$PROJ3"
PROJ3_REAL=$(real_path "$PROJ3")
HOME3="$TEST_DIR/home3"
CLAUDE_DIR3=$(setup_claude_dir "$PROJ3" "$HOME3")
make_jsonl_record "claude-sonnet-4-6" 5000 2000 10000 1000 "$PROJ3_REAL" "2026-06-15T12:00:00.000Z" > "$CLAUDE_DIR3/session1.jsonl"

OUTPUT=$(run_cal "$PROJ3" "$HOME3")
assert_contains "prints input" "5,000" "$OUTPUT"
assert_contains "prints output" "2,000" "$OUTPUT"
assert_contains "prints cache_read" "10,000" "$OUTPUT"
assert_contains "prints cache_creation" "1,000" "$OUTPUT"
BY_MODEL_KEYS=$(jq -r '.token_summary.by_model | keys | length' "$PROJ3/.dac/state.json")
assert_eq "by_model has 1 key" "1" "$BY_MODEL_KEYS"
MODEL_INPUT=$(jq -r '.token_summary.by_model["claude-sonnet-4-6"].input' "$PROJ3/.dac/state.json")
assert_eq "model input = 5000" "5000" "$MODEL_INPUT"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Test 4: 多会话多 model → 数字正确 ==="

PROJ4="$TEST_DIR/proj4"
make_project "$PROJ4"
PROJ4_REAL=$(real_path "$PROJ4")
HOME4="$TEST_DIR/home4"
CLAUDE_DIR4=$(setup_claude_dir "$PROJ4" "$HOME4")
{
  make_jsonl_record "claude-opus-4-8" 1000 500 2000 300 "$PROJ4_REAL" "2026-03-01T10:00:00.000Z"
  make_jsonl_record "claude-sonnet-4-6" 3000 1500 6000 900 "$PROJ4_REAL" "2026-04-01T10:00:00.000Z"
} > "$CLAUDE_DIR4/session1.jsonl"
make_jsonl_record "claude-haiku-4-5" 200 100 400 60 "$PROJ4_REAL" "2026-05-01T10:00:00.000Z" > "$CLAUDE_DIR4/session2.jsonl"

OUTPUT=$(run_cal "$PROJ4" "$HOME4")
TOTAL_INPUT=$(jq -r '.token_summary.input' "$PROJ4/.dac/state.json")
assert_eq "total input = 4200" "4200" "$TOTAL_INPUT"
TOTAL_OUTPUT=$(jq -r '.token_summary.output' "$PROJ4/.dac/state.json")
assert_eq "total output = 2100" "2100" "$TOTAL_OUTPUT"
BY_MODEL_KEYS=$(jq -r '.token_summary.by_model | keys | length' "$PROJ4/.dac/state.json")
assert_eq "by_model has 3 keys" "3" "$BY_MODEL_KEYS"
SESSIONS=$(jq -r '.token_summary.sessions_scanned' "$PROJ4/.dac/state.json")
assert_eq "sessions_scanned = 2" "2" "$SESSIONS"
MATCHED=$(jq -r '.token_summary.records_matched' "$PROJ4/.dac/state.json")
assert_eq "records_matched = 3" "3" "$MATCHED"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Test 5: 覆盖写入 → 第二次更新 ==="

make_jsonl_record "claude-opus-4-8" 500 250 1000 150 "$PROJ4_REAL" "2026-07-01T10:00:00.000Z" >> "$CLAUDE_DIR4/session2.jsonl"

OUTPUT=$(run_cal "$PROJ4" "$HOME4")
NEW_MATCHED=$(jq -r '.token_summary.records_matched' "$PROJ4/.dac/state.json")
assert_eq "records_matched increased to 4" "4" "$NEW_MATCHED"
NEW_INPUT=$(jq -r '.token_summary.input' "$PROJ4/.dac/state.json")
assert_eq "total input = 4700" "4700" "$NEW_INPUT"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "─────────────────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
echo "All tests passed ✓"