#!/usr/bin/env bash
# test-branch-req-fallback.sh — 分支名兜底提取 req_name 优先级回归测试
# 覆盖 setup-hook-wrapper.sh 生成的 post-commit hook 与 backfill-commit-stats-from-history.sh
# 两处分支名兜底：优先匹配 T-IBT-[0-9]+，未命中再回退 R-IBG-[0-9]+。不依赖网络。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/.."
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
  local desc="$1" needle="$2" filepath="$3"
  if grep -qF "$needle" "$filepath" 2>/dev/null; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc (not found in file: '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

# fake HOME：避免 setup-hook-wrapper.sh 生成的 hook 内 report-trace-backend.sh 存在于真实
# ~/.claude 下而触发真实上报/网络调用（两处均以 `[ -f "$_report_lib" ]` 判空静默跳过）
export HOME="$TEST_DIR/home"
export DAC_RUNTIME=codex
export DAC_SKILL_HOME="$HOME/.codex/skills/gd-ai-coding"
export DAC_STATE_HOME="$DAC_SKILL_HOME/state"
export DAC_CONFIG_HOME="$HOME/.codex/skills/dashboard"
mkdir -p "$DAC_CONFIG_HOME"

echo "═══ test-branch-req-fallback.sh ═══"

# ── Part 1: setup-hook-wrapper.sh 生成的真实 post-commit hook ─────────────────

setup_hook_repo() {
  local branch="$1" name="$2"
  local repo_dir="$TEST_DIR/repo-$name"
  mkdir -p "$repo_dir"
  (
    cd "$repo_dir"
    git init -q
    git config user.email "tester@example.com"
    git config user.name "Tester"
    bash "$SCRIPTS_DIR/metrics/setup-hook-wrapper.sh"
    git checkout -q -b "$branch"
  ) >/dev/null 2>&1
  echo "$repo_dir"
}

commit_in_repo() {
  local repo_dir="$1"
  (
    cd "$repo_dir"
    echo "x" >> f.txt
    git add f.txt
    git commit -q -m "test commit"
  ) >/dev/null 2>&1
}

get_note() {
  local repo_dir="$1"
  (cd "$repo_dir" && git notes --ref=refs/notes/dac-trace show HEAD 2>/dev/null) || true
}

echo ""
echo "Test 1: post-commit hook 分支名同时含 T-IBT 与 R-IBG → 优先提取 T-IBT"
REPO1=$(setup_hook_repo "feature/T-IBT-111-and-R-IBG-222" "hook-both")
commit_in_repo "$REPO1"
NOTE1_FILE="$TEST_DIR/note1.json"
get_note "$REPO1" > "$NOTE1_FILE"
assert_contains "note 使用 T-IBT-111 而非 R-IBG-222" '"req_name": "T-IBT-111"' "$NOTE1_FILE"

echo ""
echo "Test 2: post-commit hook 分支名仅含 R-IBG → 回退提取 R-IBG"
REPO2=$(setup_hook_repo "feature/R-IBG-333-only" "hook-r-only")
commit_in_repo "$REPO2"
NOTE2_FILE="$TEST_DIR/note2.json"
get_note "$REPO2" > "$NOTE2_FILE"
assert_contains "note 使用 R-IBG-333" '"req_name": "R-IBG-333"' "$NOTE2_FILE"

echo ""
echo "Test 3: post-commit hook 分支名均不含 → 不写 dac-trace note"
REPO3=$(setup_hook_repo "feature/no-id-here" "hook-none")
commit_in_repo "$REPO3"
NOTE3_FILE="$TEST_DIR/note3.json"
get_note "$REPO3" > "$NOTE3_FILE"
assert_eq "无匹配时不写 note" "" "$(cat "$NOTE3_FILE")"

# ── Part 2: backfill-commit-stats-from-history.sh 分支名兜底 ──────────────────

cat > "$DAC_CONFIG_HOME/backend-config.json" <<'EOF'
{"base_url": "http://fake-backend.test", "token": "fake-token"}
EOF

setup_backfill_repo() {
  local branch="$1" name="$2"
  local repo_dir="$TEST_DIR/repo-$name"
  mkdir -p "$repo_dir"
  (
    cd "$repo_dir"
    git init -q
    git config user.email "tester@example.com"
    git config user.name "Tester"
    echo "x" > f.txt
    git add f.txt
    git commit -q -m "init"
    git checkout -q -b "$branch"
  ) >/dev/null 2>&1
  echo "$repo_dir"
}

echo ""
echo "Test 4: backfill 脚本分支名同时含 T-IBT 与 R-IBG → 优先提取 T-IBT"
REPO4=$(setup_backfill_repo "feature/T-IBT-444-and-R-IBG-555" "backfill-both")
BASE_SHA4=$(cd "$REPO4" && git rev-parse HEAD)
OUT4="$TEST_DIR/backfill4.err"
(cd "$REPO4" && bash "$SCRIPTS_DIR/metrics/backfill-commit-stats-from-history.sh" --base "$BASE_SHA4" --dry-run) >/dev/null 2>"$OUT4" || true
assert_contains "backfill req_name 使用 T-IBT-444" "req_name=T-IBT-444" "$OUT4"

echo ""
echo "Test 5: backfill 脚本分支名仅含 R-IBG → 回退提取 R-IBG"
REPO5=$(setup_backfill_repo "feature/R-IBG-666-only" "backfill-r-only")
BASE_SHA5=$(cd "$REPO5" && git rev-parse HEAD)
OUT5="$TEST_DIR/backfill5.err"
(cd "$REPO5" && bash "$SCRIPTS_DIR/metrics/backfill-commit-stats-from-history.sh" --base "$BASE_SHA5" --dry-run) >/dev/null 2>"$OUT5" || true
assert_contains "backfill req_name 使用 R-IBG-666" "req_name=R-IBG-666" "$OUT5"

echo ""
echo "Test 6: backfill 脚本分支名均不含 → 报错退出，不静默"
REPO6=$(setup_backfill_repo "feature/no-id-here" "backfill-none")
BASE_SHA6=$(cd "$REPO6" && git rev-parse HEAD)
OUT6="$TEST_DIR/backfill6.err"
set +e
(cd "$REPO6" && bash "$SCRIPTS_DIR/metrics/backfill-commit-stats-from-history.sh" --base "$BASE_SHA6" --dry-run) >/dev/null 2>"$OUT6"
EXIT6=$?
set -e
assert_eq "无法推导 req_name 时退出码为 1" "1" "$EXIT6"
assert_contains "stderr 提示无法推导 req_name" "无法推导 req_name" "$OUT6"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
