#!/usr/bin/env bash
# test-codex-post-tool-use-hook.sh — Codex apply_patch Pre/Post 实时追踪回归
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PRE_HOOK="$ROOT_DIR/scripts/metrics/codex-pre-tool-use-hook.sh"
POST_HOOK="$ROOT_DIR/scripts/metrics/codex-post-tool-use-hook.sh"
WRITE_HOOK="$ROOT_DIR/scripts/metrics/write-trace-hook.sh"
FIXTURE="$SCRIPT_DIR/fixtures/codex-hooks/codex-0.153.4-apply-patch.json"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
PASS=0
FAIL=0

assert_eq() {
  local description="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  ✓ %s\n' "$description"
    PASS=$((PASS + 1))
  else
    printf '  ✗ %s (expected %s, got %s)\n' "$description" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_json() {
  local description="$1" file="$2"
  if jq -e . "$file" >/dev/null 2>&1; then
    printf '  ✓ %s\n' "$description"
    PASS=$((PASS + 1))
  else
    printf '  ✗ %s\n' "$description"
    FAIL=$((FAIL + 1))
  fi
}

new_repo() {
  local name="$1"
  REPO="$TEST_DIR/$name"
  HOME_DIR="$TEST_DIR/$name-home"
  STATE_HOME="$HOME_DIR/.codex/skills/gd-ai-coding/state"
  CONFIG_HOME="$HOME_DIR/.codex/skills/dashboard"
  mkdir -p "$REPO/lib" "$STATE_HOME" "$CONFIG_HOME"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email tester@example.com
  git -C "$REPO" config user.name Tester
  git -C "$REPO" remote add origin git@example.com:group/"$name".git
  printf '{"base_url":"http://127.0.0.1:1","token":"test"}' > "$CONFIG_HOME/backend-config.json"
}

make_event() {
  local tool_use_id="$1" path="$2"
  jq --arg cwd "$REPO" --arg path "$path" --arg id "$tool_use_id" '
    .pre_tool_use
    | .cwd = $cwd
    | .tool_use_id = $id
    | .tool_input.command |= gsub("/tmp/dac-codex-fixture-repo/lib/example.dart"; $path)
  ' "$FIXTURE"
}

make_mixed_event() {
  local tool_use_id="$1" dart_path="$2" markdown_path="$3" event_type="$4" key
  if [[ "$event_type" == PreToolUse ]]; then key=pre_tool_use; else key=post_tool_use; fi
  jq --arg cwd "$REPO" --arg id "$tool_use_id" --arg dart "$dart_path" --arg markdown "$markdown_path" --arg key "$key" '
    .[$key] | .cwd = $cwd | .tool_use_id = $id
    | .tool_input.command = ("*** Begin Patch\n*** Update File: " + $dart + "\n@@\n-old\n+new\n*** Update File: " + $markdown + "\n@@\n-old\n+new\n*** End Patch")
  ' "$FIXTURE"
}

post_event() {
  jq '.post_tool_use' "$FIXTURE" \
    | jq --arg cwd "$REPO" --arg path "$2" --arg id "$1" '
        .cwd = $cwd
        | .tool_use_id = $id
        | .tool_input.command |= gsub("/tmp/dac-codex-fixture-repo/lib/example.dart"; $path)
      '
}

run_pre() {
  HOME="$HOME_DIR" DAC_RUNTIME=codex \
    DAC_SKILL_HOME="$HOME_DIR/.codex/skills/gd-ai-coding" \
    DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" \
    bash "$PRE_HOOK" <<< "$1"
}

run_post() {
  HOME="$HOME_DIR" DAC_RUNTIME=codex \
    DAC_SKILL_HOME="$HOME_DIR/.codex/skills/gd-ai-coding" \
    DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" \
    bash "$POST_HOOK" <<< "$1"
}

run_generic_write_as_codex() {
  (
    cd "$REPO" || exit 1
    HOME="$HOME_DIR" DAC_RUNTIME=codex \
      DAC_SKILL_HOME="$HOME_DIR/.codex/skills/gd-ai-coding" \
      DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" \
      bash "$WRITE_HOOK" <<< "$1"
  )
}

snapshot_dir() {
  local event="$1"
  local session turn tool
  session=$(jq -r '.session_id' <<< "$event")
  turn=$(jq -r '.turn_id' <<< "$event")
  tool=$(jq -r '.tool_use_id' <<< "$event")
  local event_id
  event_id=$(printf '%s\0%s\0%s' "$session" "$turn" "$tool" | shasum -a 256 | awk '{print $1}')
  printf '%s/codex-hook-snapshots/v1/%s' "$STATE_HOME" "$event_id"
}

echo '═══ test-codex-post-tool-use-hook.sh ═══'
printf '\n'

# 单代码文件：Pre 快照 → 实际修改 → Post 精确行差，同时更新两条管道。
new_repo single
printf 'old\n' > "$REPO/lib/example.dart"
git -C "$REPO" add . && git -C "$REPO" commit -qm initial
mkdir -p "$REPO/.dac"
printf '{"req_name":"codex-req","owner_committer":"tester@example.com"}' > "$REPO/.dac/state.json"
EVENT=$(make_event single "$REPO/lib/example.dart")
run_pre "$EVENT"
printf 'one\ntwo\nthree\n' > "$REPO/lib/example.dart"
run_post "$(post_event single "$REPO/lib/example.dart")"
TRACE="$REPO/.dac/trace/codex-req.json"
PERSONAL="$STATE_HOME/personal-trace/tester_example.com__group_single.json"
assert_eq '单文件需求维度精确增加 2 行' '2' "$(jq -r '.write_lines_added' "$TRACE" 2>/dev/null)"
assert_eq '单文件个人维度精确增加 2 行' '2' "$(jq -r '.total' "$PERSONAL" 2>/dev/null)"
assert_eq '单文件只记录一个逻辑事件' '1' "$(jq -r '.write_events | length' "$TRACE" 2>/dev/null)"
assert_eq '单文件个人计数增加一次' '1' "$(jq -r '.count' "$PERSONAL" 2>/dev/null)"

# 同一工作区若错误触发通用 Write Hook，Codex runtime 必须由专用 apply_patch adapter
# 独占记账，不能对同一 +2 变更写入第二次。
GENERIC_EDIT=$(jq -cn --arg path "$REPO/lib/example.dart" \
  '{tool_name:"Edit",tool_input:{file_path:$path,old_string:"old\n",new_string:"one\ntwo\nthree\n"}}')
run_generic_write_as_codex "$GENERIC_EDIT"
assert_eq 'Codex 专用 adapter 与通用 Hook 不重复累计需求行数' '2' "$(jq -r '.write_lines_added' "$TRACE" 2>/dev/null)"
assert_eq 'Codex 专用 adapter 与通用 Hook 不重复累计个人行数' '2' "$(jq -r '.total' "$PERSONAL" 2>/dev/null)"
assert_eq 'Codex 专用 adapter 与通用 Hook 不重复增加个人计数' '1' "$(jq -r '.count' "$PERSONAL" 2>/dev/null)"
assert_eq 'Codex 专用 adapter 与通用 Hook 不重复记录需求事件' '1' "$(jq -r '.write_events | length' "$TRACE" 2>/dev/null)"

# 重复 Post 必须幂等，快照已消费不得重新累计。
run_post "$(post_event single "$REPO/lib/example.dart")"
assert_eq '重复 Post 不重复累计需求行数' '2' "$(jq -r '.write_lines_added' "$TRACE" 2>/dev/null)"
assert_eq '重复 Post 不重复累计个人行数' '2' "$(jq -r '.total' "$PERSONAL" 2>/dev/null)"

# 未认领目录：需求维度不创建 .dac，个人维度仍精确累计。
new_repo unclaimed
printf 'old\n' > "$REPO/lib/example.dart"
git -C "$REPO" add . && git -C "$REPO" commit -qm initial
EVENT=$(make_event unclaimed "$REPO/lib/example.dart")
run_pre "$EVENT"
printf 'one\ntwo\nthree\n' > "$REPO/lib/example.dart"
run_post "$(post_event unclaimed "$REPO/lib/example.dart")"
PERSONAL="$STATE_HOME/personal-trace/tester_example.com__group_unclaimed.json"
assert_eq '未认领目录不创建 .dac' 'false' "$([[ -e "$REPO/.dac" ]] && echo true || echo false)"
assert_eq '未认领目录个人维度仍增加 2 行' '2' "$(jq -r '.total' "$PERSONAL" 2>/dev/null)"
assert_eq '未认领目录累计 unused_total' '2' "$(jq -r '.unused_total' "$PERSONAL" 2>/dev/null)"

# 混合文件：非代码文件只保留在 patch 中，不可让其污染统计。
new_repo mixed
printf 'old\n' > "$REPO/lib/example.dart"
printf 'old\n' > "$REPO/README.md"
git -C "$REPO" add . && git -C "$REPO" commit -qm initial
mkdir -p "$REPO/.dac"
printf '{"req_name":"mixed-req","owner_committer":"tester@example.com"}' > "$REPO/.dac/state.json"
EVENT=$(make_mixed_event mixed "$REPO/lib/example.dart" "$REPO/README.md" PreToolUse)
run_pre "$EVENT"
printf 'one\ntwo\nthree\n' > "$REPO/lib/example.dart"
printf 'one\ntwo\nthree\nfour\n' > "$REPO/README.md"
run_post "$(make_mixed_event mixed "$REPO/lib/example.dart" "$REPO/README.md" PostToolUse)"
TRACE="$REPO/.dac/trace/mixed-req.json"
assert_eq '混合 patch 仅统计代码文件 2 行' '2' "$(jq -r '.write_lines_added' "$TRACE" 2>/dev/null)"

# 缺失快照、过期快照和篡改 schema 都 fail-open 且零增量。
new_repo invalid
printf 'old\n' > "$REPO/lib/example.dart"
git -C "$REPO" add . && git -C "$REPO" commit -qm initial
mkdir -p "$REPO/.dac"
printf '{"req_name":"invalid-req","owner_committer":"tester@example.com"}' > "$REPO/.dac/state.json"
run_post "$(post_event missing "$REPO/lib/example.dart")"
assert_eq '缺失快照不创建 trace' 'false' "$([[ -e "$REPO/.dac/trace" ]] && echo true || echo false)"
EVENT=$(make_event expired "$REPO/lib/example.dart")
run_pre "$EVENT"
SNAPSHOT=$(snapshot_dir "$EVENT")
jq '.created_at = "2000-01-01T00:00:00Z"' "$SNAPSHOT/meta.json" > "$SNAPSHOT/meta.tmp" && mv "$SNAPSHOT/meta.tmp" "$SNAPSHOT/meta.json"
printf 'one\ntwo\nthree\n' > "$REPO/lib/example.dart"
run_post "$(post_event expired "$REPO/lib/example.dart")"
assert_eq '过期快照不创建 trace' 'false' "$([[ -e "$REPO/.dac/trace" ]] && echo true || echo false)"
EVENT=$(make_event corrupt "$REPO/lib/example.dart")
run_pre "$EVENT"
SNAPSHOT=$(snapshot_dir "$EVENT")
jq '.schema = 99' "$SNAPSHOT/meta.json" > "$SNAPSHOT/meta.tmp" && mv "$SNAPSHOT/meta.tmp" "$SNAPSHOT/meta.json"
run_post "$(post_event corrupt "$REPO/lib/example.dart")"
assert_eq '未知快照 schema 不创建 trace' 'false' "$([[ -e "$REPO/.dac/trace" ]] && echo true || echo false)"

# 同一事件并发消费只能写入一次，状态 JSON 始终合法。
new_repo concurrent
printf 'old\n' > "$REPO/lib/example.dart"
git -C "$REPO" add . && git -C "$REPO" commit -qm initial
mkdir -p "$REPO/.dac"
printf '{"req_name":"concurrent-req","owner_committer":"tester@example.com"}' > "$REPO/.dac/state.json"
EVENT=$(make_event concurrent "$REPO/lib/example.dart")
run_pre "$EVENT"
printf 'one\ntwo\nthree\n' > "$REPO/lib/example.dart"
POST=$(post_event concurrent "$REPO/lib/example.dart")
run_post "$POST" &
run_post "$POST" &
wait
TRACE="$REPO/.dac/trace/concurrent-req.json"
PERSONAL="$STATE_HOME/personal-trace/tester_example.com__group_concurrent.json"
assert_eq '并发 Post 仅累计一次需求行数' '2' "$(jq -r '.write_lines_added' "$TRACE" 2>/dev/null)"
assert_eq '并发 Post 仅累计一次个人行数' '2' "$(jq -r '.total' "$PERSONAL" 2>/dev/null)"
assert_json '并发后需求 trace 保持合法 JSON' "$TRACE"
assert_json '并发后个人状态保持合法 JSON' "$PERSONAL"

# 已消费事件的完整 Pre→Post 重放必须被 tombstone 拒绝。
new_repo replay
printf 'old\n' > "$REPO/lib/example.dart"
git -C "$REPO" add . && git -C "$REPO" commit -qm initial
EVENT=$(make_event replay "$REPO/lib/example.dart")
run_pre "$EVENT"
printf 'one\ntwo\nthree\n' > "$REPO/lib/example.dart"
run_post "$(post_event replay "$REPO/lib/example.dart")"
run_pre "$EVENT"
assert_eq '已消费事件重放不重新创建快照' 'false' "$([[ -d "$(snapshot_dir "$EVENT")" ]] && echo true || echo false)"

# 仓库内 trace 符号链接不得导致工作树外文件被改写。
new_repo trace-link
printf 'old\n' > "$REPO/lib/example.dart"
git -C "$REPO" add . && git -C "$REPO" commit -qm initial
mkdir -p "$REPO/.dac" "$TEST_DIR/outside"
printf '{"req_name":"link-req","owner_committer":"tester@example.com"}' > "$REPO/.dac/state.json"
printf '{"sentinel":true}' > "$TEST_DIR/outside/link-req.json"
ln -s "$TEST_DIR/outside" "$REPO/.dac/trace"
EVENT=$(make_event trace-link "$REPO/lib/example.dart")
run_pre "$EVENT"
printf 'one\ntwo\nthree\n' > "$REPO/lib/example.dart"
run_post "$(post_event trace-link "$REPO/lib/example.dart")"
assert_eq 'trace 符号链接外部文件保持不变' '{"sentinel":true}' "$(< "$TEST_DIR/outside/link-req.json")"

# 非 UTC 时区机器上 iso_to_epoch 必须锚定 UTC 解析，TTL 校验不得因本地时区偏移而误判。
# 先固定当前系统 TZ 为非 UTC（export，使 hook 子进程继承），再走完整 Pre→Post 流程。
SAVED_TZ="${TZ:-}"
export TZ="Asia/Shanghai"
LIB_ROOT="$ROOT_DIR/scripts/lib.sh"
new_repo non-utc-tz
printf 'old\n' > "$REPO/lib/example.dart"
git -C "$REPO" add . && git -C "$REPO" commit -qm initial
mkdir -p "$REPO/.dac"
printf '{"req_name":"non-utc-req","owner_committer":"tester@example.com"}' > "$REPO/.dac/state.json"
EXPECTED_EPOCH=$(TZ=UTC bash -c 'source "$1"; iso_to_epoch "2026-01-01T00:00:00Z"' _ "$LIB_ROOT")
ACTUAL_EPOCH=$(bash -c 'source "$1"; iso_to_epoch "2026-01-01T00:00:00Z"' _ "$LIB_ROOT")
assert_eq '非 UTC TZ 下 iso_to_epoch 锚定 UTC 解析' "$EXPECTED_EPOCH" "$ACTUAL_EPOCH"
EVENT=$(make_event non-utc "$REPO/lib/example.dart")
run_pre "$EVENT"
printf 'one\ntwo\nthree\n' > "$REPO/lib/example.dart"
run_post "$(post_event non-utc "$REPO/lib/example.dart")"
TRACE="$REPO/.dac/trace/non-utc-req.json"
assert_eq '非 UTC TZ 下 TTL 校验通过并累计行数' '2' "$(jq -r '.write_lines_added' "$TRACE" 2>/dev/null)"
if [[ -n "$SAVED_TZ" ]]; then export TZ="$SAVED_TZ"; else unset TZ; fi

printf '\n━━━ Results: %s passed, %s failed ━━━\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
