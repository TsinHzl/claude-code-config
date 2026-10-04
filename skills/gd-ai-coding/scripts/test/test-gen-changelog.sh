#!/usr/bin/env bash
# test-gen-changelog.sh — gen-changelog.sh 行为回归测试
#
# 覆盖：
#   - 无新增 commit 时不调用 AI 且不改动文件
#   - AI 输出夹带解释性文字仍能正确提取 JSON，且新日期条目正确插入到索引 0
#   - AI 返回非法 JSON 时不改动文件且非 0 退出
#   - 同日期条目正确合并 groups
#   - 锁目录已存在时新实例直接退出且不修改任何文件
#   - AI 返回空 groups / items 全空时不写入占位条目（避免看板出现「0 个模块 · 0 项变更」）
#
# gen-changelog.sh 的 DIST_FILE/PUBLIC_FILE（dashboard-app/dist|public/release-notes.json）
# 与 LOCK_DIR（/tmp/dac-gen-changelog.lock）均为硬编码共享路径，无环境变量可覆盖。测试期间
# 会临时覆写这两个 release-notes.json 的内容，结束时通过 trap 恢复原始内容；claude 命令通过
# 在 PATH 中前置一个 mock 可执行文件替身，避免任何真实网络调用。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
METRICS_DIR="$SCRIPT_DIR/../metrics"
GEN_CHANGELOG="$METRICS_DIR/gen-changelog.sh"
DIST_FILE="$METRICS_DIR/dashboard-app/dist/release-notes.json"
PUBLIC_FILE="$METRICS_DIR/dashboard-app/public/release-notes.json"
LOCK_DIR="/tmp/dac-gen-changelog.lock"

TEST_DIR=$(mktemp -d)
MOCK_BIN="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN"
CALLED_MARKER="$TEST_DIR/claude-called"

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

assert_true() {
  local desc="$1" cond="$2"
  if [[ "$cond" == "true" ]]; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc"
    FAIL=$((FAIL + 1))
  fi
}

# ── Setup: mock claude 可执行文件 ────────────────────────────────────────────
# 读取 MOCK_CLAUDE_OUTPUT_FILE 内容输出到 stdout，用 MOCK_CLAUDE_CALLED_FILE 记录
# 是否被调用，退出码取 MOCK_CLAUDE_EXIT（默认 0）。真实 gen-changelog.sh 用字面
# `claude -p "$PROMPT"` 调用，前置本目录到 PATH 即可完全替换，不触发真实网络请求。
cat > "$MOCK_BIN/claude" <<'EOF'
#!/usr/bin/env bash
touch "$MOCK_CLAUDE_CALLED_FILE" 2>/dev/null || true
cat "$MOCK_CLAUDE_OUTPUT_FILE"
exit "${MOCK_CLAUDE_EXIT:-0}"
EOF
chmod +x "$MOCK_BIN/claude"

# ── Setup: 备份真实共享文件，退出时恢复 + 清理残留锁目录 ─────────────────────
DIST_BACKUP="$TEST_DIR/dist.orig"
PUBLIC_BACKUP="$TEST_DIR/public.orig"
[[ -f "$DIST_FILE" ]] && cp "$DIST_FILE" "$DIST_BACKUP"
[[ -f "$PUBLIC_FILE" ]] && cp "$PUBLIC_FILE" "$PUBLIC_BACKUP"

cleanup() {
  if [[ -f "$DIST_BACKUP" ]]; then cp "$DIST_BACKUP" "$DIST_FILE"; fi
  if [[ -f "$PUBLIC_BACKUP" ]]; then cp "$PUBLIC_BACKUP" "$PUBLIC_FILE"; fi
  rmdir "$LOCK_DIR" 2>/dev/null || true
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

if [[ -d "$LOCK_DIR" ]]; then
  echo "⚠️  $LOCK_DIR 已存在（可能是上次测试异常残留），测试前先清理" >&2
  rmdir "$LOCK_DIR" 2>/dev/null || true
fi

seed_baseline() {
  local content="$1"
  printf '%s' "$content" > "$DIST_FILE"
  printf '%s' "$content" > "$PUBLIC_FILE"
}

run_gen_changelog() {
  local output_file="${1:-/dev/null}" mock_exit="${2:-0}"
  rm -f "$CALLED_MARKER"
  set +e
  PATH="$MOCK_BIN:$PATH" \
    MOCK_CLAUDE_OUTPUT_FILE="$output_file" \
    MOCK_CLAUDE_CALLED_FILE="$CALLED_MARKER" \
    MOCK_CLAUDE_EXIT="$mock_exit" \
    bash "$GEN_CHANGELOG" >"$TEST_DIR/run.out" 2>"$TEST_DIR/run.err"
  RUN_EXIT=$?
  set -e
}

echo "═══ test-gen-changelog.sh ═══"
echo ""

# ── Test 1: 无新增 commit 时不调用 AI 且不改动文件 ────────────────────────────
echo "Test 1: 水位线设为未来日期（无新增 commit）→ exit 0，不调用 AI，不改动文件"
BASELINE='[{"date":"2099-01-01","groups":[{"title":"历史分组","items":["历史条目"]}]}]'
seed_baseline "$BASELINE"
run_gen_changelog
assert_eq "exit code 为 0" "0" "$RUN_EXIT"
assert_eq "DIST_FILE 未改动" "$BASELINE" "$(cat "$DIST_FILE")"
assert_eq "PUBLIC_FILE 未改动" "$BASELINE" "$(cat "$PUBLIC_FILE")"
assert_true "claude 未被调用" "$([[ -f "$CALLED_MARKER" ]] && echo false || echo true)"

# ── Test 2: AI 输出夹带解释性文字仍可提取 JSON，新日期插入到索引 0 ───────────
echo ""
echo "Test 2: AI 输出夹带解释性文字 → 正确提取 JSON，新日期条目插入到索引 0"
BASELINE='[{"date":"2020-01-01","groups":[{"title":"旧分组","items":["旧条目"]}]}]'
seed_baseline "$BASELINE"
cat > "$TEST_DIR/ai-wrapped.txt" <<'EOF'
好的，这是我总结的更新日志：

{"date": "2026-08-07", "groups": [{"title": "新分组", "items": ["新条目1"]}]}

希望对你有帮助。
EOF
run_gen_changelog "$TEST_DIR/ai-wrapped.txt"
assert_eq "exit code 为 0" "0" "$RUN_EXIT"
assert_eq "DIST_FILE[0].date 为新日期" "2026-08-07" "$(jq -r '.[0].date' "$DIST_FILE")"
assert_eq "DIST_FILE[1].date 为原日期（被推到索引1）" "2020-01-01" "$(jq -r '.[1].date' "$DIST_FILE")"
assert_eq "PUBLIC_FILE[0].date 为新日期" "2026-08-07" "$(jq -r '.[0].date' "$PUBLIC_FILE")"
assert_eq "claude 被调用" "true" "$([[ -f "$CALLED_MARKER" ]] && echo true || echo false)"

# ── Test 3: AI 返回非法 JSON 时不改动文件且非 0 退出 ─────────────────────────
echo ""
echo "Test 3: AI 返回非法 JSON（不含 date/groups 字段）→ 非 0 退出，不改动文件"
BASELINE='[{"date":"2020-01-01","groups":[{"title":"旧分组","items":["旧条目"]}]}]'
seed_baseline "$BASELINE"
printf '抱歉，我无法完成这个任务。' > "$TEST_DIR/ai-invalid.txt"
run_gen_changelog "$TEST_DIR/ai-invalid.txt"
assert_true "exit code 非 0" "$([[ "$RUN_EXIT" -ne 0 ]] && echo true || echo false)"
assert_eq "DIST_FILE 未改动" "$BASELINE" "$(cat "$DIST_FILE")"
assert_eq "PUBLIC_FILE 未改动" "$BASELINE" "$(cat "$PUBLIC_FILE")"

# ── Test 4: 同日期条目正确合并 groups ────────────────────────────────────────
echo ""
echo "Test 4: AI 返回日期与现有第一条相同 → 合并 groups，而非新插入一条"
BASELINE='[{"date":"2020-01-01","groups":[{"title":"旧分组","items":["旧条目"]}]}]'
seed_baseline "$BASELINE"
cat > "$TEST_DIR/ai-same-date.txt" <<'EOF'
{"date": "2020-01-01", "groups": [{"title": "新分组", "items": ["新条目"]}]}
EOF
run_gen_changelog "$TEST_DIR/ai-same-date.txt"
assert_eq "exit code 为 0" "0" "$RUN_EXIT"
assert_eq "DIST_FILE 仍只有 1 条日期条目" "1" "$(jq 'length' "$DIST_FILE")"
assert_eq "DIST_FILE[0].groups 合并为 2 组" "2" "$(jq '.[0].groups | length' "$DIST_FILE")"
assert_eq "DIST_FILE[0].groups 含旧分组标题" "旧分组" "$(jq -r '.[0].groups[0].title' "$DIST_FILE")"
assert_eq "DIST_FILE[0].groups 含新分组标题" "新分组" "$(jq -r '.[0].groups[1].title' "$DIST_FILE")"

# ── Test 5: 锁目录已存在时新实例直接退出且不修改任何文件 ─────────────────────
echo ""
echo "Test 5: 锁目录已存在（模拟并发） → 新实例直接 exit 0，不调用 AI，不改动文件"
BASELINE='[{"date":"2020-01-01","groups":[{"title":"旧分组","items":["旧条目"]}]}]'
seed_baseline "$BASELINE"
mkdir "$LOCK_DIR"
run_gen_changelog
assert_eq "exit code 为 0" "0" "$RUN_EXIT"
assert_eq "DIST_FILE 未改动" "$BASELINE" "$(cat "$DIST_FILE")"
assert_eq "PUBLIC_FILE 未改动" "$BASELINE" "$(cat "$PUBLIC_FILE")"
assert_true "claude 未被调用" "$([[ -f "$CALLED_MARKER" ]] && echo false || echo true)"
rmdir "$LOCK_DIR" 2>/dev/null || true

# ── Test 6: AI 返回空 groups / items 全空时不写入占位条目 ────────────────────
echo ""
echo "Test 6: AI 返回 groups 为空 → exit 0，不写入占位条目"
BASELINE='[{"date":"2020-01-01","groups":[{"title":"旧分组","items":["旧条目"]}]}]'
seed_baseline "$BASELINE"
printf '{"date": "2026-08-18", "groups": []}' > "$TEST_DIR/ai-empty-groups.txt"
run_gen_changelog "$TEST_DIR/ai-empty-groups.txt"
assert_eq "exit code 为 0" "0" "$RUN_EXIT"
assert_eq "DIST_FILE 未改动" "$BASELINE" "$(cat "$DIST_FILE")"
assert_eq "PUBLIC_FILE 未改动" "$BASELINE" "$(cat "$PUBLIC_FILE")"

echo ""
echo "Test 6b: AI 返回 groups 非空但 items 全空 → exit 0，不写入占位条目"
seed_baseline "$BASELINE"
printf '{"date": "2026-08-18", "groups": [{"title": "空分组", "items": []}]}' > "$TEST_DIR/ai-empty-items.txt"
run_gen_changelog "$TEST_DIR/ai-empty-items.txt"
assert_eq "exit code 为 0" "0" "$RUN_EXIT"
assert_eq "DIST_FILE 未改动" "$BASELINE" "$(cat "$DIST_FILE")"
assert_eq "PUBLIC_FILE 未改动" "$BASELINE" "$(cat "$PUBLIC_FILE")"

echo ""
echo "Test 6c: 同日期且 AI 返回空 groups → 不与现有条目合并（groups 数量不变）"
# 日期沿用 2020-01-01（同 BASELINE），保证水位线足够早、必然有新增 commit 触发 AI 调用；
# 若用「今天」作日期，当天无 commit 时会走「无新增 commit」提前退出，测不到本拦截逻辑
seed_baseline "$BASELINE"
printf '{"date": "2020-01-01", "groups": []}' > "$TEST_DIR/ai-empty-same-date.txt"
run_gen_changelog "$TEST_DIR/ai-empty-same-date.txt"
assert_eq "exit code 为 0" "0" "$RUN_EXIT"
assert_eq "DIST_FILE 未改动" "$BASELINE" "$(cat "$DIST_FILE")"
assert_eq "PUBLIC_FILE 未改动" "$BASELINE" "$(cat "$PUBLIC_FILE")"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
