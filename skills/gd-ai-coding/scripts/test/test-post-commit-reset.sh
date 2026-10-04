#!/usr/bin/env bash
# test-post-commit-reset.sh — Unit tests for post-commit hook 提交后清零本地 write_lines_added
#
# 覆盖 CR 指出的关键路径：清零逻辑必须对「完整工作流(state.json)」与「dac-bind 轻量(req-bind)」
# 两条 req 路径都生效。测试直接从 setup-hook-wrapper.sh 提取真实生成的 post-commit hook 文本运行，
# 用 fake HOME + 真实 lib.sh 保证 atomic_jq 真正执行；不配置 backend-config → _report_progress /
# _report_commit_stats 静默降级不触网。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/.."
REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
WRAPPER="$SCRIPTS_DIR/metrics/setup-hook-wrapper.sh"
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

# ── Setup: fake HOME 携带真实 lib.sh + report-trace-backend.sh，无 backend-config ──
export HOME="$TEST_DIR/home"
export DAC_RUNTIME=claude
export DAC_SKILL_HOME="$HOME/.claude/skills/gd-ai-coding"
export DAC_STATE_HOME="$DAC_SKILL_HOME/state"
export DAC_CONFIG_HOME="$HOME/.claude/skills/dashboard"
FAKE_SKILL="$DAC_SKILL_HOME/scripts"
mkdir -p "$FAKE_SKILL/metrics"
cp "$SCRIPTS_DIR/lib.sh" "$FAKE_SKILL/lib.sh"
cp "$SCRIPTS_DIR/metrics/report-trace-backend.sh" "$FAKE_SKILL/metrics/report-trace-backend.sh"

# ── 提取 setup-hook-wrapper.sh 中真实生成的 post-commit hook 文本 ──────────────
GEN_HOOK="$TEST_DIR/post-commit"
awk '/cat > "\$DAC_HOOKS\/post-commit" << '"'"'HOOK'"'"'/{f=1;next} f&&/^HOOK$/{exit} f{print}' "$WRAPPER" > "$GEN_HOOK"
# 复刻 setup-hook-wrapper.sh 的生成期占位符替换，使 GEN_HOOK 与真实安装 hook 完全一致
# （否则 numstat 行残留 @@DAC_NUMSTAT_PATHSPEC@@ 占位符，跑的是假 hook）。
# shellcheck source=/dev/null
source "$SCRIPTS_DIR/lib.sh"
DAC_NUMSTAT_PS="$(dac_numstat_pathspec_quoted)" \
DAC_RUNTIME_SCRIPT="$(printf '%q' "$SCRIPTS_DIR/runtime.sh")" \
  perl -i -pe 's/\@\@DAC_NUMSTAT_PATHSPEC\@\@/$ENV{DAC_NUMSTAT_PS}/g; s/\@\@DAC_RUNTIME_SCRIPT\@\@/$ENV{DAC_RUNTIME_SCRIPT}/g' "$GEN_HOOK"
chmod +x "$GEN_HOOK"

echo "═══ test-post-commit-reset.sh ═══"
echo ""

# 在 fake git repo 中构造一次 commit + 指定 req 身份 + 带 write_lines_added 的 trace 文件，
# 运行提取出的 hook，断言清零结果。$1=场景名 $2=身份构造函数
run_scenario() {
  local desc="$1" req="$2" setup_identity="$3"
  local repo="$TEST_DIR/repo-$4"
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q
    git config user.email "tester@example.com"
    git config user.name "Tester"
    git remote add origin git@example.com:group/project.git 2>/dev/null
    git checkout -q -b feature/test-branch
    # 真实完整工作流的 .dac 一定含 logs/（record-trace/state-update 会写入）；
    # 缺失时完整工作流分支的 `: > "$_errlog"`（POSIX 特殊内建重定向失败）会让 sh 直接退出。
    mkdir -p .dac/trace .dac/logs
    # 身份文件（state.json 或 req-bind）
    eval "$setup_identity"
    # 待清零的真实 trace：write_lines_added=363 + write_events + phases（须保留）
    cat > ".dac/trace/${req}.json" <<EOF
{"req_name":"${req}","write_lines_added":363,"write_events":[{"tool":"Edit","file":"a.dart","ts":1},{"tool":"Write","file":"b.dart","ts":2}],"phases":[{"phase":"init","ts":1}]}
EOF
    echo x > f.txt && git add f.txt && git commit -q -m "seed"
    sh "$GEN_HOOK" >/dev/null 2>&1
  )
  local tf="$repo/.dac/trace/${req}.json"
  assert_eq "${desc}: write_lines_added 归零" "0" "$(jq -r '.write_lines_added' "$tf" 2>/dev/null)"
  assert_eq "${desc}: write_events 保留(2 条)" "2" "$(jq -r '.write_events|length' "$tf" 2>/dev/null)"
  assert_eq "${desc}: phases 保留" "1" "$(jq -r '.phases|length' "$tf" 2>/dev/null)"
}

# owner 归属闸门场景：hook 应因 owner/committer 不匹配而跳过——
# write_lines_added 保持不变(363、未被清零)，且不写 refs/notes/dac-trace（不产生上报）。
# $1=场景名 $2=req $3=身份构造函数(写入非本人 owner 的 state.json 或 req-bind) $4=repo tag
run_skip_scenario() {
  local desc="$1" req="$2" setup_identity="$3"
  local repo="$TEST_DIR/repo-$4"
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q
    git config user.email "tester@example.com"
    git config user.name "Tester"
    git remote add origin git@example.com:group/project.git 2>/dev/null
    git checkout -q -b feature/test-branch
    mkdir -p .dac/trace .dac/logs
    eval "$setup_identity"
    cat > ".dac/trace/${req}.json" <<EOF
{"req_name":"${req}","write_lines_added":363,"write_events":[{"tool":"Edit","file":"a.dart","ts":1}],"phases":[{"phase":"init","ts":1}]}
EOF
    echo x > f.txt && git add f.txt && git commit -q -m "seed"
    sh "$GEN_HOOK" >/dev/null 2>&1
  )
  local tf="$repo/.dac/trace/${req}.json"
  assert_eq "${desc}: write_lines_added 保持不变(未清零)" "363" "$(jq -r '.write_lines_added' "$tf" 2>/dev/null)"
  local note_out
  note_out=$(cd "$repo" && git notes --ref=refs/notes/dac-trace show HEAD 2>/dev/null || echo "__NONE__")
  assert_eq "${desc}: 未写 dac-trace note(不上报)" "__NONE__" "$note_out"
}

echo "Test 1: 完整工作流路径(.dac/state.json)提交后清零 write_lines_added"
run_scenario "完整工作流" "driver-contact-preference" \
  'printf "%s" "{\"req_name\":\"driver-contact-preference\"}" > .dac/state.json' \
  "full"

echo ""
echo "Test 2: dac-bind 轻量路径(.dac/req-bind，无 state.json)提交后同样清零"
run_scenario "bind 轻量" "R-IBG-100" \
  'printf "%s" "{\"req\":\"R-IBG-100\",\"branch\":\"feature/test-branch\"}" > .dac/req-bind' \
  "bind"

echo ""
echo "Test 3: 非本人 owner 的 state.json(别人 .dac/ 随主分支合并进本地) → 跳过，不清零、不上报"
run_skip_scenario "非本人 owner state" "foreign-req" \
  'printf "%s" "{\"req_name\":\"foreign-req\",\"owner_committer\":\"wangjun@example.com\"}" > .dac/state.json' \
  "foreign-state"

echo ""
echo "Test 4: 本人 owner 的 state.json → 正常清零(证明自己的数据照常上报)"
run_scenario "本人 owner state" "own-req" \
  'printf "%s" "{\"req_name\":\"own-req\",\"owner_committer\":\"tester@example.com\"}" > .dac/state.json' \
  "own"

echo ""
echo "Test 5: 非本人 committer 的 req-bind → 跳过，不清零、不上报"
run_skip_scenario "非本人 committer req-bind" "R-IBG-999" \
  'printf "%s" "{\"req\":\"R-IBG-999\",\"branch\":\"feature/test-branch\",\"committer\":\"wangjun@example.com\"}" > .dac/req-bind' \
  "foreign-bind"

# ── Test 6: 混合提交（代码 + 文档 + 生成文件）→ /commit-stats 仅计代码行 ────────
# 验证生成 hook 的 numstat 代码白名单口径端到端生效：foo.dart(3 行代码) 计入，
# README.md(文档)、foo.g.dart(生成文件) 均排除，上报 lines_added=3。
# 此场景需 backend-config + fake curl 捕获 /commit-stats body；置于末尾，
# 前 5 个场景已在无 backend-config 下跑完（静默降级），不受影响。
echo ""
echo "Test 6: 混合提交（代码 + 文档 + 生成文件）→ /commit-stats 仅计代码行"
mkdir -p "$HOME/.claude/skills/dashboard"
cat > "$HOME/.claude/skills/dashboard/backend-config.json" <<'EOF'
{"base_url": "http://fake-backend.test", "token": "fake-token"}
EOF
CS_BODY_FILE="$TEST_DIR/commit-stats-body.json"
CURL_BIN_DIR="$TEST_DIR/bin-curl"
mkdir -p "$CURL_BIN_DIR"
cat > "$CURL_BIN_DIR/curl" <<EOF
#!/bin/sh
url=""; body=""; prev=""
for arg in "\$@"; do
  case "\$arg" in http*) url="\$arg" ;; esac
  [ "\$prev" = "-d" ] && body="\$arg"
  prev="\$arg"
done
case "\$url" in *api/v1/trace/commit-stats) printf '%s' "\$body" > "$CS_BODY_FILE" ;; esac
exit 0
EOF
chmod +x "$CURL_BIN_DIR/curl"
MIX_REPO="$TEST_DIR/repo-mixed"
mkdir -p "$MIX_REPO"
(
  export PATH="$CURL_BIN_DIR:$PATH"
  cd "$MIX_REPO" || exit 1
  git init -q
  git config user.email "tester@example.com"
  git config user.name "Tester"
  git remote add origin git@example.com:group/project-mixed.git 2>/dev/null
  git checkout -q -b feature/test-branch
  mkdir -p .dac/trace .dac/logs lib
  printf '%s' '{"req_name":"mixed-req","owner_committer":"tester@example.com"}' > .dac/state.json
  printf 'a\nb\nc\n' > lib/foo.dart          # 3 行代码 → 计入
  printf '# doc\nmore doc\n' > README.md      # 文档 → 排除
  printf 'g1\ng2\ng3\ng4\ng5\n' > lib/foo.g.dart  # 生成文件 → 排除
  git add -A && git commit -q -m "mixed"
  sh "$GEN_HOOK" >/dev/null 2>&1
)
assert_eq "混合提交 /commit-stats lines_added 仅计代码行(foo.dart=3)" \
  "3" "$(jq -r '.lines_added' "$CS_BODY_FILE" 2>/dev/null)"

# ── Test 7: Codex-only HOME 且未注入 DAC_* 时，真实 post-commit 仍完成全链路 ──
# 真实 Codex Git 子进程未必继承 shell_environment_policy；wrapper 必须从已安装的
# runtime.sh 自行解析客户端路径，不能依赖调用者预先注入 DAC_*。
echo ""
echo "Test 7: Codex-only HOME + 无 DAC_* → note、精确 numstat、上报与重放幂等"
CODEX_HOME="$TEST_DIR/codex-home"
CODEX_SKILL="$CODEX_HOME/.codex/skills/gd-ai-coding"
CODEX_CONFIG="$CODEX_HOME/.codex/skills/dashboard"
mkdir -p "$CODEX_SKILL/scripts/metrics" "$CODEX_CONFIG"
cp "$SCRIPTS_DIR/runtime.sh" "$CODEX_SKILL/scripts/runtime.sh"
cp "$SCRIPTS_DIR/lib.sh" "$CODEX_SKILL/scripts/lib.sh"
cp "$SCRIPTS_DIR/metrics/setup-hook-wrapper.sh" "$CODEX_SKILL/scripts/metrics/setup-hook-wrapper.sh"
cp "$SCRIPTS_DIR/metrics/report-trace-backend.sh" "$CODEX_SKILL/scripts/metrics/report-trace-backend.sh"
printf '%s' '{"base_url":"http://fake-backend.test","token":"fake-token"}' > "$CODEX_CONFIG/backend-config.json"
CODEX_BODY_FILE="$TEST_DIR/codex-commit-stats-body.json"
cat > "$CURL_BIN_DIR/curl" <<EOF
#!/bin/sh
url=""; body=""; prev=""
for arg in "\$@"; do
  case "\$arg" in http*) url="\$arg" ;; esac
  [ "\$prev" = "-d" ] && body="\$arg"
  prev="\$arg"
done
case "\$url" in *api/v1/trace/commit-stats) printf '%s' "\$body" > "$CODEX_BODY_FILE" ;; esac
exit 0
EOF
chmod +x "$CURL_BIN_DIR/curl"
CODEX_REPO="$TEST_DIR/repo-codex-post-commit"
mkdir -p "$CODEX_REPO"
(
  cd "$CODEX_REPO" || exit 1
  git init -q
  git config user.email "tester@example.com"
  git config user.name "Tester"
  git remote add origin git@example.com:group/project-codex.git
  mkdir -p .dac/trace .dac/logs lib
  printf '%s' '{"req_name":"codex-req","owner_committer":"tester@example.com"}' > .dac/state.json
  printf '%s' '{"req_name":"codex-req","write_lines_added":99}' > .dac/trace/codex-req.json
  env -u DAC_RUNTIME -u DAC_SKILL_HOME -u DAC_STATE_HOME -u DAC_CONFIG_HOME \
    HOME="$CODEX_HOME" PATH="$CURL_BIN_DIR:$PATH" \
    bash "$CODEX_SKILL/scripts/metrics/setup-hook-wrapper.sh" >/dev/null 2>&1
  printf 'a\nb\nc\n' > lib/foo.dart
  printf '# doc\n' > README.md
  printf 'generated\n' > lib/foo.g.dart
  git add -A && env -u DAC_RUNTIME -u DAC_SKILL_HOME -u DAC_STATE_HOME -u DAC_CONFIG_HOME \
    HOME="$CODEX_HOME" PATH="$CURL_BIN_DIR:$PATH" git commit -q -m "codex post-commit"
)
CODEX_HEAD=$(git -C "$CODEX_REPO" rev-parse HEAD)
CODEX_NOTE=$(git -C "$CODEX_REPO" notes --ref=refs/notes/dac-trace show HEAD 2>/dev/null || true)
CODEX_PERSONAL="$CODEX_SKILL/state/personal-trace/tester_example.com__group_project-codex.json"
assert_eq "Codex post-commit 写入 DAC note" "codex-req" "$(printf '%s' "$CODEX_NOTE" | jq -r '.req_name // empty' 2>/dev/null)"
assert_eq "Codex /commit-stats 仅上报代码新增 3 行" "3" "$(jq -r '.lines_added // empty' "$CODEX_BODY_FILE" 2>/dev/null)"
assert_eq "Codex /commit-stats 携带当前 HEAD" "$CODEX_HEAD" "$(jq -r '.last_commit // empty' "$CODEX_BODY_FILE" 2>/dev/null)"
assert_eq "Codex 个人 committed_total 精确累加 3 行" "3" "$(jq -r '.committed_total // empty' "$CODEX_PERSONAL" 2>/dev/null)"
assert_eq "Codex 个人实时估算被清零" "0" "$(jq -r '.total // empty' "$CODEX_PERSONAL" 2>/dev/null)"
env -u DAC_RUNTIME -u DAC_SKILL_HOME -u DAC_STATE_HOME -u DAC_CONFIG_HOME \
  HOME="$CODEX_HOME" PATH="$CURL_BIN_DIR:$PATH" \
  "$CODEX_REPO/.git/dac-hooks/post-commit" >/dev/null 2>&1
assert_eq "Codex 重放同一 HEAD 不重复累计" "3" "$(jq -r '.committed_total // empty' "$CODEX_PERSONAL" 2>/dev/null)"

echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
