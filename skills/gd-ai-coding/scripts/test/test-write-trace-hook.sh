#!/usr/bin/env bash
# test-write-trace-hook.sh — Unit tests for write-trace-hook.sh 的双管道并行架构
#
# 覆盖 add-personal-trace-pipeline 的核心架构断言（对应 tasks.md 任务 5 验证①②）：
#   ① 未认领 .dac 数据源的目录：个人总量管道无条件执行，需求维度管道（含自愈/回填）不触发
#   ② 已认领 .dac 数据源的目录：两条管道各自独立执行，需求维度侧数值与改动前完全一致（回归）
# 任务 5 验证③（改动前后耗时对比 <50ms）为机器相关的性能基准，需人工用
# `time bash write-trace-hook.sh < fixture.json` 各跑 20 次对比中位数，不纳入本自动化测试。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/.."
HOOK="$SCRIPTS_DIR/metrics/write-trace-hook.sh"
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
    echo "  ✗ $desc (not found in file: '$needle'; actual: $(cat "$filepath" 2>/dev/null || echo '<missing>'))"
    FAIL=$((FAIL + 1))
  fi
}

assert_absent() {
  local desc="$1" path="$2"
  if [[ ! -e "$path" ]]; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc (unexpectedly exists: $path)"
    FAIL=$((FAIL + 1))
  fi
}

# 后台 curl 调用是 disown 的，等待其落盘（最多 3s）后再断言
wait_for_file() {
  local path="$1" waited=0
  while [[ ! -s "$path" ]] && [[ $waited -lt 30 ]]; do
    sleep 0.1
    waited=$((waited + 1))
  done
}

# ── Setup: fake HOME with backend-config.json（个人总量状态目录落在此 HOME 下）───

export HOME="$TEST_DIR/home"
export DAC_RUNTIME=claude
export DAC_SKILL_HOME="$HOME/.claude/skills/gd-ai-coding"
export DAC_STATE_HOME="$DAC_SKILL_HOME/state"
export DAC_CONFIG_HOME="$HOME/.claude/skills/dashboard"
mkdir -p "$DAC_CONFIG_HOME" "$DAC_SKILL_HOME"
cat > "$DAC_CONFIG_HOME/backend-config.json" <<'EOF'
{"base_url": "http://fake-backend.test", "token": "fake-token"}
EOF

# ── Setup: fake curl，按 URL 分流写入不同文件 ────────────────────────────────

CURL_BIN_DIR="$TEST_DIR/bin-curl"
mkdir -p "$CURL_BIN_DIR"
PERSONAL_BODY_FILE="$TEST_DIR/personal-body.json"
PERSONAL_URL_FILE="$TEST_DIR/personal-url.txt"
REPORT_BODY_FILE="$TEST_DIR/report-body.json"
cat > "$CURL_BIN_DIR/curl" <<EOF
#!/bin/sh
url=""
body=""
prev=""
for arg in "\$@"; do
  case "\$arg" in http*) url="\$arg" ;; esac
  if [ "\$prev" = "-d" ]; then body="\$arg"; fi
  prev="\$arg"
done
case "\$url" in
  *personal-report*) printf '%s' "\$body" > "$PERSONAL_BODY_FILE"; printf '%s' "\$url" > "$PERSONAL_URL_FILE" ;;
  *api/v1/trace/report) printf '%s' "\$body" > "$REPORT_BODY_FILE" ;;
esac
exit 0
EOF
chmod +x "$CURL_BIN_DIR/curl"
export PATH="$CURL_BIN_DIR:$PATH"

write_event_json() {
  local content="$1"
  jq -cn --arg c "$content" '{tool_name:"Write", tool_input:{file_path:"demo.dart", content:$c}}'
}

echo "═══ test-write-trace-hook.sh ═══"
echo ""

# ── Test 0: 未显式 DAC_* 变量时，从 Claude-only 安装目录自动解析运行时 ─────────

echo "Test 0: Claude-only 安装目录自动解析运行时"
REPO_AUTO="$TEST_DIR/repo-auto-runtime"
mkdir -p "$REPO_AUTO"
(
  cd "$REPO_AUTO" || exit 1
  git init -q
  git config user.email "tester@example.com"
  git config user.name "Tester"
  git remote add origin git@example.com:group/project-auto.git
  rm -f "$PERSONAL_BODY_FILE" "$PERSONAL_URL_FILE"
  write_event_json "auto" | env -u DAC_RUNTIME -u DAC_SKILL_HOME -u DAC_STATE_HOME -u DAC_CONFIG_HOME bash "$HOOK" >/dev/null 2>&1
)
wait_for_file "$PERSONAL_BODY_FILE"
assert_contains "自动解析 Claude 配置目录后可上报" "personal-report" "$PERSONAL_URL_FILE"
assert_eq "自动解析 Claude 状态目录" "1" "$(jq -r '.total' "$HOME/.claude/skills/gd-ai-coding/state/personal-trace/tester_example.com__group_project-auto.json" 2>/dev/null)"

# ── Test 1: 未认领 .dac 数据源的目录 → 个人总量无条件执行，需求维度不触发 ────

echo "Test 1: 未认领 .dac 数据源的目录（无 state.json/req-bind）"
REPO_A="$TEST_DIR/repo-a"
mkdir -p "$REPO_A"
(
  cd "$REPO_A" || exit 1
  git init -q
  git config user.email "tester@example.com"
  git config user.name "Tester"
  git remote add origin git@example.com:group/project-a.git
  rm -f "$PERSONAL_BODY_FILE" "$PERSONAL_URL_FILE" "$REPORT_BODY_FILE"
  write_event_json "l1
l2
l3
l4
l5" | bash "$HOOK" >/dev/null 2>&1
)
wait_for_file "$PERSONAL_BODY_FILE"
assert_absent "未创建 .dac 目录" "$REPO_A/.dac"
assert_contains "个人总量上报命中 personal-report 端点" "personal-report" "$PERSONAL_URL_FILE"
assert_contains "个人总量 body 携带 committer" '"committer":"tester@example.com"' "$PERSONAL_BODY_FILE"
assert_contains "个人总量 body 携带 repo_path" '"repo_path":"group/project-a"' "$PERSONAL_BODY_FILE"
assert_contains "个人总量 body 首次记录 5 行" '"write_lines_added":5' "$PERSONAL_BODY_FILE"
assert_contains "未走流程桶计入 unused_workflow_lines=5" '"unused_workflow_lines":5' "$PERSONAL_BODY_FILE"
assert_absent "需求维度 /report 未被调用" "$REPORT_BODY_FILE"

# ── Test 2: 已认领 .dac/state.json → 两条管道并行，需求维度数值符合累加预期（回归）──

echo ""
echo "Test 2: 已认领 .dac/state.json 的目录 → 两条管道独立并行"
REPO_B="$TEST_DIR/repo-b"
mkdir -p "$REPO_B/.dac"
(
  cd "$REPO_B" || exit 1
  git init -q
  git config user.email "tester@example.com"
  git config user.name "Tester"
  git remote add origin git@example.com:group/project-b.git
  printf '%s' '{"req_name":"my-req","owner_committer":"tester@example.com"}' > .dac/state.json

  rm -f "$PERSONAL_BODY_FILE" "$REPORT_BODY_FILE"
  write_event_json "a
b
c" | bash "$HOOK" >/dev/null 2>&1
)
wait_for_file "$REPORT_BODY_FILE"
wait_for_file "$PERSONAL_BODY_FILE"
TRACE_FILE="$REPO_B/.dac/trace/my-req.json"
assert_eq "需求维度 trace 文件 write_lines_added=3" "3" "$(jq -r '.write_lines_added' "$TRACE_FILE" 2>/dev/null)"
assert_eq "需求维度 trace 文件 write_events 长度=1" "1" "$(jq -r '.write_events | length' "$TRACE_FILE" 2>/dev/null)"
assert_contains "需求维度 /report body 携带 repo_path" '"repo_path":"group/project-b"' "$REPORT_BODY_FILE"
assert_contains "个人总量 body 携带 repo-b 的 repo_path" '"repo_path":"group/project-b"' "$PERSONAL_BODY_FILE"
assert_contains "个人总量首次记录 3 行（与需求维度独立计数一致）" '"write_lines_added":3' "$PERSONAL_BODY_FILE"
assert_contains "已认领目录 unused_workflow_lines=0" '"unused_workflow_lines":0' "$PERSONAL_BODY_FILE"

# 第二次编辑：同一文件 demo.dart 内容由 3 行(a/b/c)缩为 2 行(d/e)。需求维度按 _added 原样
# 累加（3+2=5，行为不变）；个人总量管道对 Write 采用高水位线去重（write-dedup-reset），
# 本次内容行数(2)未超过本文件本周期内已记录的高水位线(3)，增量记 0，总量维持 3（回归：
# 验证「同文件重复 Write」不会被朴素累加放大成 5，这正是本次修复要解决的虚高问题）。
(
  cd "$REPO_B" || exit 1
  rm -f "$PERSONAL_BODY_FILE" "$REPORT_BODY_FILE"
  write_event_json "d
e" | bash "$HOOK" >/dev/null 2>&1
)
wait_for_file "$REPORT_BODY_FILE"
wait_for_file "$PERSONAL_BODY_FILE"
assert_eq "需求维度 trace 文件累加为 5(3+2)" "5" "$(jq -r '.write_lines_added' "$TRACE_FILE" 2>/dev/null)"
assert_eq "需求维度 trace 文件 write_events 长度=2" "2" "$(jq -r '.write_events | length' "$TRACE_FILE" 2>/dev/null)"
assert_contains "个人总量高水位线去重：同文件内容缩小不计增量(维持 3)" '"write_lines_added":3' "$PERSONAL_BODY_FILE"

# 第三次编辑：同一文件内容增长到 6 行，超过高水位线(3)，只把超出部分(3)计入增量，
# 验证"同一文件被反复 Write 全量计入"的虚高 bug 不会重现（旧逻辑会得到 3+2+6=11）
(
  cd "$REPO_B" || exit 1
  rm -f "$PERSONAL_BODY_FILE" "$REPORT_BODY_FILE"
  write_event_json "d
e
f
g
h
i" | bash "$HOOK" >/dev/null 2>&1
)
wait_for_file "$REPORT_BODY_FILE"
wait_for_file "$PERSONAL_BODY_FILE"
assert_contains "个人总量高水位线去重：超出部分(6-3=3)计入，总量 3+3=6（非旧逻辑的 11）" '"write_lines_added":6' "$PERSONAL_BODY_FILE"

# ── Test 3: git 身份未配置 → 两条管道均跳过，不产生任何文件/网络请求 ──────────

echo ""
echo "Test 3: git 身份未配置（user.email 为空）→ 两条管道均跳过"
REPO_C="$TEST_DIR/repo-c"
mkdir -p "$REPO_C"
(
  cd "$REPO_C" || exit 1
  git init -q
  rm -f "$PERSONAL_BODY_FILE" "$REPORT_BODY_FILE"
  write_event_json "x" | bash "$HOOK" >/dev/null 2>&1
)
sleep 0.3
assert_absent "未创建 .dac 目录" "$REPO_C/.dac"
assert_absent "未产生个人总量上报" "$PERSONAL_BODY_FILE"
assert_absent "未产生需求维度上报" "$REPORT_BODY_FILE"

# ── Test 4: 编辑非代码文件（.md）→ 两条管道均不计入（需求维度亦按白名单过滤）──────
# 行数统计口径收窄为「仅代码文件」后，需求维度管道在创建 trace 文件前就按 dac_is_code_file
# 早退：既不累加 write_lines_added、不追加 write_events、不上报 /report，也不创建 trace 文件。

echo ""
echo "Test 4: 编辑非代码文件(.md) → 需求维度与个人总量两条管道均不计入"
REPO_D="$TEST_DIR/repo-d"
mkdir -p "$REPO_D/.dac"
(
  cd "$REPO_D" || exit 1
  git init -q
  git config user.email "tester@example.com"
  git config user.name "Tester"
  git remote add origin git@example.com:group/project-d.git
  printf '%s' '{"req_name":"my-req","owner_committer":"tester@example.com"}' > .dac/state.json

  rm -f "$PERSONAL_BODY_FILE" "$REPORT_BODY_FILE"
  jq -cn --arg c "x
y
z" '{tool_name:"Write", tool_input:{file_path:"README.md", content:$c}}' | bash "$HOOK" >/dev/null 2>&1
)
sleep 0.3
assert_absent "需求维度未对非代码文件创建 trace 文件（不累加、不记事件）" "$REPO_D/.dac/trace"
assert_absent "需求维度 /report 未对非代码文件上报" "$REPORT_BODY_FILE"
assert_absent "个人总量未对非代码文件产生上报" "$PERSONAL_BODY_FILE"

# ── Test 4b: 已认领目录编辑代码文件（.dart）→ 需求维度正常累加（对比 Test 4 的过滤边界）──

echo ""
echo "Test 4b: 编辑代码文件(.dart) → 需求维度正常累加、正常上报"
REPO_F="$TEST_DIR/repo-f"
mkdir -p "$REPO_F/.dac"
(
  cd "$REPO_F" || exit 1
  git init -q
  git config user.email "tester@example.com"
  git config user.name "Tester"
  git remote add origin git@example.com:group/project-f.git
  printf '%s' '{"req_name":"my-req","owner_committer":"tester@example.com"}' > .dac/state.json

  rm -f "$PERSONAL_BODY_FILE" "$REPORT_BODY_FILE"
  jq -cn --arg c "a
b
c
d" '{tool_name:"Write", tool_input:{file_path:"lib/foo.dart", content:$c}}' | bash "$HOOK" >/dev/null 2>&1
)
wait_for_file "$REPORT_BODY_FILE"
TRACE_FILE_F="$REPO_F/.dac/trace/my-req.json"
assert_eq "需求维度 trace 文件对代码文件累加=4" "4" "$(jq -r '.write_lines_added' "$TRACE_FILE_F" 2>/dev/null)"
assert_eq "需求维度 write_events 记录代码文件编辑=1" "1" "$(jq -r '.write_events | length' "$TRACE_FILE_F" 2>/dev/null)"

# ── Test 5: 未认领目录 + 编辑非代码文件 → 两条管道均不触发个人总量上报 ────────
# 补充 MEDIUM 覆盖缺口：验证过滤条件与 .dac 是否认领无关（同一表达式，非仅在
# 已认领分支生效），防止未来重构误将过滤条件收窄到某一分支

echo ""
echo "Test 5: 未认领目录 + 编辑非代码文件(.md) → 个人总量管道不触发"
REPO_E="$TEST_DIR/repo-e"
mkdir -p "$REPO_E"
(
  cd "$REPO_E" || exit 1
  git init -q
  git config user.email "tester@example.com"
  git config user.name "Tester"
  git remote add origin git@example.com:group/project-e.git
  rm -f "$PERSONAL_BODY_FILE" "$REPORT_BODY_FILE"
  jq -cn --arg c "x
y" '{tool_name:"Write", tool_input:{file_path:"README.md", content:$c}}' | bash "$HOOK" >/dev/null 2>&1
)
sleep 0.3
assert_absent "未创建 .dac 目录" "$REPO_E/.dac"
assert_absent "个人总量未对未认领目录的非代码文件产生上报" "$PERSONAL_BODY_FILE"
assert_absent "需求维度 /report 未被调用" "$REPORT_BODY_FILE"

# ── Test 6: 自愈重装纳入 INCLUDE_MARKER — 缺新口径 marker 的存量 hook 应被升级 ──
# 回归 CR 发现：旧自愈判定只查 RESET+OWNER 两 marker，已自愈过（含此二者）但缺
# code-include-whitelist 的存量仓库不会重装 → 永久停留旧口径。构造这样的伪 hook，
# 断言编辑代码文件后触发后台自愈，重装出的新 hook 含 INCLUDE_MARKER。
echo ""
echo "Test 6: 自愈重装纳入 code-include-whitelist — 缺新口径 marker 的旧 hook 被升级"
# 自愈通过 DAC_SKILL_HOME 定位 setup-hook-wrapper.sh，需就位 wrapper + lib.sh
FAKE_SKILL_SCRIPTS="$DAC_SKILL_HOME/scripts"
mkdir -p "$FAKE_SKILL_SCRIPTS/metrics"
cp "$SCRIPTS_DIR/lib.sh" "$FAKE_SKILL_SCRIPTS/lib.sh"
cp "$SCRIPTS_DIR/metrics/setup-hook-wrapper.sh" "$FAKE_SKILL_SCRIPTS/metrics/setup-hook-wrapper.sh"
REPO_G="$TEST_DIR/repo-selfheal"
mkdir -p "$REPO_G/.dac"
(
  cd "$REPO_G" || exit 1
  git init -q
  git config user.email "tester@example.com"
  git config user.name "Tester"
  git remote add origin git@example.com:group/project-g.git
  printf '%s' '{"req_name":"heal-req","owner_committer":"tester@example.com"}' > .dac/state.json
  _gd=$(git rev-parse --git-dir)
  mkdir -p "$_gd/dac-hooks"
  # 伪旧 hook：含 RESET+OWNER 两 marker，故意缺 code-include-whitelist
  cat > "$_gd/dac-hooks/post-commit" <<'OLDHOOK'
#!/bin/sh
# DAC: write trace to git notes
# 提交后清零本地实时写入行数
# DAC: skip-foreign-owner
exit 0
OLDHOOK
  chmod +x "$_gd/dac-hooks/post-commit"
  git config core.hooksPath "$_gd/dac-hooks"
  write_event_json "code
line
two" | bash "$HOOK" >/dev/null 2>&1
)
# 自愈是后台 disown 重装，等待新 marker 落盘（最多 3s）
_healed_hook="$REPO_G/$(git -C "$REPO_G" rev-parse --git-dir)/dac-hooks/post-commit"
[[ "$_healed_hook" == /* ]] || _healed_hook="$REPO_G/.git/dac-hooks/post-commit"
_waited=0
while ! grep -q "DAC: code-include-whitelist" "$_healed_hook" 2>/dev/null && [[ $_waited -lt 30 ]]; do
  sleep 0.1; _waited=$((_waited + 1))
done
assert_contains "自愈重装后 hook 含 code-include-whitelist marker" "DAC: code-include-whitelist" "$_healed_hook"
assert_contains "自愈重装保留 RESET marker" "提交后清零本地实时写入行数" "$_healed_hook"
assert_contains "自愈重装保留 owner 归属闸门 marker" "DAC: skip-foreign-owner" "$_healed_hook"
assert_contains "自愈重装后 hook 含 personal-reconcile marker" "DAC: personal-reconcile" "$_healed_hook"
assert_contains "自愈重装后 hook 含 write-dedup-reset marker" "DAC: write-dedup-reset" "$_healed_hook"
assert_contains "自愈重装后 hook 含 unused-workflow-lines marker" "DAC: unused-workflow-lines" "$_healed_hook"

# ── Test 7: post-commit 个人总量校正 — 污染的实时估算被清零、committed_total 累加精确 diff ──
# 回归本次修复：个人总量管道实时估算(Write 按整份文件全行计)只加不减，提交后从不回落，导致
# vibe coding 行数虚高；新增 post-commit 校正段用本次 commit 的精确 numstat 累加 committed_total、
# 清零实时估算 total、上报 committed_total。构造被污染的 total=9999 状态文件 + 真实提交 5 行 .dart，
# 断言 total 清零、committed_total=5、上报值回落到精确 5（而非污染的 9999）。
echo ""
echo "Test 7: post-commit 个人总量校正 — 污染的 total 被清零、committed_total 累加精确 diff"
# 补齐校正段依赖：report-trace-backend.sh（Test 6 已备 lib.sh + setup-hook-wrapper.sh）
cp "$SCRIPTS_DIR/metrics/report-trace-backend.sh" "$FAKE_SKILL_SCRIPTS/metrics/report-trace-backend.sh"
_pr_state_dir="$DAC_STATE_HOME/personal-trace"
mkdir -p "$_pr_state_dir"
# 安全键：committer(tester@example.com) + repo_path(group/project-h)，非法字符替换为 _
_pr_state_file="$_pr_state_dir/tester_example.com__group_project-h.json"
echo '{"committed_total":0,"total":9999,"count":3,"unused_total":7}' > "$_pr_state_file"
REPO_H="$TEST_DIR/repo-personal-reconcile"
mkdir -p "$REPO_H"
(
  cd "$REPO_H" || exit 1
  git init -q
  git config user.email "tester@example.com"
  git config user.name "Tester"
  git remote add origin git@example.com:group/project-h.git
  # 安装 hook（setup-hook-wrapper 展开 numstat pathspec、写入 personal-reconcile 段并设 core.hooksPath）
  bash "$FAKE_SKILL_SCRIPTS/metrics/setup-hook-wrapper.sh" >/dev/null 2>&1
  rm -f "$PERSONAL_BODY_FILE"
  # 真实提交 5 行 .dart（触发 post-commit 精确 numstat 校正；无 .dac 故走无条件个人管道）
  printf 'a\nb\nc\nd\ne\n' > foo.dart
  git add foo.dart
  git commit -q -m "add foo.dart" >/dev/null 2>&1
)
wait_for_file "$PERSONAL_BODY_FILE"
assert_eq "个人总量污染的实时估算 total 被清零" "0" "$(jq -r '.total' "$_pr_state_file" 2>/dev/null)"
assert_eq "个人总量 committed_total 累加为精确 diff 5" "5" "$(jq -r '.committed_total' "$_pr_state_file" 2>/dev/null)"
assert_eq "提交校正不清零 unused_total" "7" "$(jq -r '.unused_total' "$_pr_state_file" 2>/dev/null)"
assert_contains "个人总量上报回落到精确值 5（而非污染的 9999）" '"write_lines_added":5' "$PERSONAL_BODY_FILE"
assert_contains "提交校正仍上报 unused_workflow_lines" '"unused_workflow_lines":7' "$PERSONAL_BODY_FILE"

# ── Test 8: 提交后清零 total 使历史遗留虚高值自愈（锁定 clean-zero 语义）──────────
# 主 bug 场景固化：个人总量管道曾把 Write 全文估算只加不减累积成虚高 total（如 11313）。
# 采用「提交后清零」而非「扣减」，确保历史遗留虚高值下次提交即回落——构造已污染的 total=10
# （模拟历史累积）+ 真实提交 4 行 .dart，断言 total 清零为 0（而非扣减到 6）、committed_total=4。
# 权衡（known limitation）：多文件只提交其一时，其余未提交文件估算被一并清零→暂时低估，由后续
# 编辑重新累积自我修正；相较「历史虚高永不自愈」，清零对主 bug 更优（见 setup-hook-wrapper 注释）。
echo ""
echo "Test 8: 提交后清零 total → 历史遗留虚高值下次提交即自愈（total→0）"
_pr_state_file_i="$_pr_state_dir/tester_example.com__group_project-i.json"
echo '{"committed_total":0,"total":10,"count":2}' > "$_pr_state_file_i"
REPO_I="$TEST_DIR/repo-partial-commit"
mkdir -p "$REPO_I"
(
  cd "$REPO_I" || exit 1
  git init -q
  git config user.email "tester@example.com"
  git config user.name "Tester"
  git remote add origin git@example.com:group/project-i.git
  bash "$FAKE_SKILL_SCRIPTS/metrics/setup-hook-wrapper.sh" >/dev/null 2>&1
  printf 'a\nb\nc\nd\n' > only-committed.dart
  git add only-committed.dart
  git commit -q -m "commit clears inflated estimate" >/dev/null 2>&1
)
assert_eq "个人总量历史遗留虚高 total 被清零为 0（而非扣减）" "0" "$(jq -r '.total' "$_pr_state_file_i" 2>/dev/null)"
assert_eq "个人总量 committed_total 累加本次精确 diff 4" "4" "$(jq -r '.committed_total' "$_pr_state_file_i" 2>/dev/null)"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
