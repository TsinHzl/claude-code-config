#!/usr/bin/env bash
# test-codex-agent-gate.sh — Codex 角色门禁与 staging 执行回归。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$ROOT_DIR/scripts/agents/codex-agent-gate.sh"
RUNNER="$ROOT_DIR/scripts/agents/run-codex-role.sh"
TEST_DIR=$(mktemp -d)
WORKSPACE_ROOT_BACKUP=""
restore_workspace_root() {
  local workspace="${WORKSPACE:-}"
  [[ -n "$WORKSPACE_ROOT_BACKUP" ]] || return
  [[ -n "$workspace" && ( -e "$workspace" || -L "$workspace" ) ]] && rm -rf "$workspace"
  [[ -d "$WORKSPACE_ROOT_BACKUP" ]] && mv "$WORKSPACE_ROOT_BACKUP" "$workspace"
  WORKSPACE_ROOT_BACKUP=""
}
trap 'restore_workspace_root; rm -rf "$TEST_DIR"' EXIT
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

HOME_DIR="$TEST_DIR/home"
SKILL_HOME="$HOME_DIR/.codex/skills/gd-ai-coding"
STATE_HOME="$SKILL_HOME/state"
CONFIG_HOME="$HOME_DIR/.codex/skills/dashboard"
FAKE_BIN="$TEST_DIR/bin"
mkdir -p "$SKILL_HOME" "$STATE_HOME" "$CONFIG_HOME" "$FAKE_BIN"
cp -R "$ROOT_DIR/codex-agents" "$SKILL_HOME/codex-agents"
cat > "$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  features)
    printf 'multi_agent stable true\n'
    ;;
  login)
    printf 'Logged in using test fixture\n'
    ;;
  exec)
    shift
    SANDBOX=""
    SKIP_GIT_REPO_CHECK=false
    CODEX_CWD=""
    OUTPUT=""
    PROMPT=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --sandbox)
          SANDBOX="$2"
          shift 2
          ;;
        --skip-git-repo-check)
          SKIP_GIT_REPO_CHECK=true
          shift
          ;;
        -C)
          CODEX_CWD="$2"
          shift 2
          ;;
        --output-last-message)
          OUTPUT="$2"
          shift 2
          ;;
        -*)
          shift
          ;;
        *)
          PROMPT="$1"
          shift
          ;;
      esac
    done
    [[ -n "$CODEX_CWD" && -n "$OUTPUT" ]] || exit 9
    [[ -z "${FAKE_SANDBOX_RECORD:-}" ]] || printf '%s\n' "$SANDBOX" > "$FAKE_SANDBOX_RECORD"
    [[ -z "${FAKE_SKIP_GIT_REPO_CHECK_RECORD:-}" ]] || printf '%s\n' "$SKIP_GIT_REPO_CHECK" > "$FAKE_SKIP_GIT_REPO_CHECK_RECORD"
    if [[ "$SANDBOX" == read-only \
      && "$(basename "$CODEX_CWD")" == dac-codex-auth-probe.* \
      && "$OUTPUT" == "$CODEX_CWD/output.txt" \
      && "$PROMPT" == '仅返回 DAC_AUTH_PROBE_OK。' ]]; then
      mkdir -p "$(dirname "$OUTPUT")"
      printf 'DAC_AUTH_PROBE_OK\n' > "$OUTPUT"
      exit 0
    fi
    [[ -z "${FAKE_CWD_RECORD:-}" ]] || printf '%s\n' "$CODEX_CWD" > "$FAKE_CWD_RECORD"
    [[ -z "${FAKE_REQUIRE_GIT_METADATA:-}" || -f "$CODEX_CWD/.git/config" ]] || exit 10
    path_in_cwd() {
      local path="$1"
      [[ "$path" == /* ]] && printf '%s\n' "$path" || printf '%s/%s\n' "$CODEX_CWD" "$path"
    }
    mkdir -p "$(dirname "$OUTPUT")"
    if [[ -z "${FAKE_SKIP_OUTPUT:-}" ]]; then
      printf '%s\n' "${FAKE_OUTPUT_CONTENT:-verdict: clean}" > "$OUTPUT"
    fi
    [[ -z "${FAKE_DELETE_OUTPUT:-}" ]] || rm -f "$OUTPUT"
    if [[ -n "${FAKE_WRITE_PATH:-}" ]]; then
      target="$(path_in_cwd "$FAKE_WRITE_PATH")"
      mkdir -p "$(dirname "$target")"
      printf '%s\n' "${FAKE_WRITE_CONTENT:-generated}" > "$target"
    fi
    if [[ -n "${FAKE_GIT_WRITE_PATH:-}" ]]; then
      target="$(path_in_cwd "$FAKE_GIT_WRITE_PATH")"
      mkdir -p "$(dirname "$target")"
      printf '%s\n' "${FAKE_GIT_WRITE_CONTENT:-git metadata}" > "$target"
    fi
    if [[ -n "${FAKE_MODIFY_PATH:-}" ]]; then
      target="$(path_in_cwd "$FAKE_MODIFY_PATH")"
      printf '%s\n' "${FAKE_MODIFY_CONTENT:-modified}" > "$target"
    fi
    if [[ -n "${FAKE_SECOND_MODIFY_PATH:-}" ]]; then
      target="$(path_in_cwd "$FAKE_SECOND_MODIFY_PATH")"
      printf '%s\n' "${FAKE_SECOND_MODIFY_CONTENT:-modified second}" > "$target"
    fi
    if [[ -n "${FAKE_SYMLINK_PATH:-}" ]]; then
      target="$(path_in_cwd "$FAKE_SYMLINK_PATH")"
      mkdir -p "$(dirname "$target")"
      ln -s "${FAKE_SYMLINK_TARGET:-/tmp/target}" "$target"
    fi
    if [[ -n "${FAKE_FIFO_PATH:-}" ]]; then
      mkfifo "$(path_in_cwd "$FAKE_FIFO_PATH")"
    fi
    if [[ -n "${FAKE_HARDLINK_SOURCE:-}" ]]; then
      source="$(path_in_cwd "$FAKE_HARDLINK_SOURCE")"
      destination="$(path_in_cwd "$FAKE_HARDLINK_DEST")"
      rm -f "$destination"
      ln "$source" "$destination"
    fi
    [[ -z "${FAKE_MKDIR_PATH:-}" ]] || mkdir -p "$(path_in_cwd "$FAKE_MKDIR_PATH")"
    [[ -z "${FAKE_DELETE_PATH:-}" ]] || rm -f "$(path_in_cwd "$FAKE_DELETE_PATH")"
    [[ -z "${FAKE_RMDIR_PATH:-}" ]] || rmdir "$(path_in_cwd "$FAKE_RMDIR_PATH")"
    if [[ -n "${FAKE_CHMOD_PATH:-}" ]]; then
      chmod "${FAKE_CHMOD_MODE:-700}" "$(path_in_cwd "$FAKE_CHMOD_PATH")"
    fi
    if [[ -n "${FAKE_READY_FILE:-}" ]]; then
      : > "$FAKE_READY_FILE"
      while [[ ! -e "${FAKE_RELEASE_FILE:?FAKE_RELEASE_FILE is required with FAKE_READY_FILE}" ]]; do :; done
    fi
    if [[ -n "${FAKE_BACKGROUND_WRITE_PATH:-}" ]]; then
      target="$(path_in_cwd "$FAKE_BACKGROUND_WRITE_PATH")"
      setsid sh -c 'sleep "$1"; mkdir -p "$(dirname "$2")"; printf background\\n > "$2"' sh "${FAKE_BACKGROUND_DELAY:-1}" "$target" </dev/null >/dev/null 2>&1 &
    fi
    [[ -z "${FAKE_SLEEP_SECONDS:-}" ]] || sleep "$FAKE_SLEEP_SECONDS"
    ;;
  *)
    printf 'unexpected codex arguments: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$FAKE_BIN/codex"

run_gate() {
  HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" DAC_RUNTIME=codex DAC_SKILL_HOME="$SKILL_HOME" DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" bash "$GATE" "$1" 2>&1
}

readonly -a GATE_ROLES=(
  requirement-gap-checker
  code-generator
  test-case-generator
  test-case-verifier
  code-reviewer
)

role_default_prompt() {
  case "$1" in
    requirement-gap-checker)
      printf '%s' 'Use $dac-requirement-gap-checker to independently check requirement coverage and return only evidence-backed findings.'
      ;;
    code-generator)
      printf '%s' 'Use $dac-code-generator to implement only the supplied scope and report verification evidence.'
      ;;
    test-case-generator)
      printf '%s' 'Use $dac-test-case-generator to create tests and scenarios from the supplied requirement slice.'
      ;;
    test-case-verifier)
      printf '%s' 'Use $dac-test-case-verifier to independently verify supplied UI scenarios against code.'
      ;;
    code-reviewer)
      printf '%s' 'Use $dac-code-reviewer to independently review the supplied change and return evidence-backed findings.'
      ;;
    *)
      return 1
      ;;
  esac
}

set_role_manifest_prompt() {
  local role="$1" prompt="$2"
  local manifest="$SKILL_HOME/codex-agents/$role/agents/openai.yaml"
  cp "$ROOT_DIR/codex-agents/$role/agents/openai.yaml" "$manifest"
  python3 - "$manifest" "$prompt" <<'PY'
import re
import sys

path, prompt = sys.argv[1:]
pattern = re.compile(r'^  default_prompt: "(?:[^"\\]|\\.)*"$', re.MULTILINE)
with open(path, encoding='utf-8') as source:
    content = source.read()
if len(pattern.findall(content)) != 1:
    raise SystemExit('缺少唯一 default_prompt')
with open(path, 'w', encoding='utf-8') as destination:
    destination.write(pattern.sub(f'  default_prompt: "{prompt}"', content))
PY
}

run_role() {
  HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" DAC_RUNTIME=codex DAC_SKILL_HOME="$SKILL_HOME" DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" bash "$RUNNER" "$@" 2>&1
}

wait_for_sentinel() {
  python3 - "$1" <<'PY'
import os
import sys
import time

path = sys.argv[1]
deadline = time.monotonic() + 10
while not os.path.exists(path):
    if time.monotonic() >= deadline:
        raise SystemExit(f'等待 sentinel 超时：{path}')
    time.sleep(0.01)
PY
}

wait_for_process_exit() {
  python3 - "$1" <<'PY'
import os
import signal
import sys
import time

pid = int(sys.argv[1])
deadline = time.monotonic() + 5
while True:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        raise SystemExit(0)
    if time.monotonic() >= deadline:
        os.kill(pid, signal.SIGTERM)
        raise SystemExit(124)
    time.sleep(0.01)
PY
}

has_transaction_backups() {
  local backup_root="$WORKSPACE/.dac/tmp/codex-role-merge-backups"
  [[ -d "$backup_root" ]] && find "$backup_root" -mindepth 1 -maxdepth 1 -type d -print -quit | grep -q .
}

printf 'Codex role gate\n'
SANDBOX_RECORD="$TEST_DIR/auth-probe-sandbox.txt"
SKIP_GIT_REPO_CHECK_RECORD="$TEST_DIR/auth-probe-skip-git-repo-check.txt"
GATE_WRITE_PATH="$TEST_DIR/auth-probe-write.txt"
OUTPUT=$(FAKE_SANDBOX_RECORD="$SANDBOX_RECORD" FAKE_SKIP_GIT_REPO_CHECK_RECORD="$SKIP_GIT_REPO_CHECK_RECORD" FAKE_WRITE_PATH="$GATE_WRITE_PATH" run_gate requirement-gap-checker)
assert_eq '需求核验角色通过完整门禁' 0 "$?"
assert_eq '通过结果包含角色名' true "$(grep -q 'PASS: role=requirement-gap-checker' <<< "$OUTPUT" && printf true || printf false)"
assert_eq '认证探针使用 read-only sandbox' read-only "$(cat "$SANDBOX_RECORD")"
assert_eq '认证探针跳过 Git 仓库检查' true "$(cat "$SKIP_GIT_REPO_CHECK_RECORD")"
assert_eq '认证探针在业务副作用前退出' false "$(test -e "$GATE_WRITE_PATH" && printf true || printf false)"

DIRECT_PROBE_DIR="$TEST_DIR/dac-codex-auth-probe.direct"
DIRECT_PROBE_OUTPUT="$DIRECT_PROBE_DIR/output.txt"
DIRECT_WRITE_PATH="$TEST_DIR/direct-workspace-write.txt"
mkdir -p "$DIRECT_PROBE_DIR"
OUTPUT=$(FAKE_WRITE_PATH="$DIRECT_WRITE_PATH" "$FAKE_BIN/codex" exec --sandbox workspace-write -C "$DIRECT_PROBE_DIR" --output-last-message "$DIRECT_PROBE_OUTPUT" '仅返回 DAC_AUTH_PROBE_OK。' 2>&1)
assert_eq 'workspace-write 不会命中认证探针' 0 "$?"
assert_eq 'workspace-write 探针三元组不返回认证结果' false "$(grep -qx 'DAC_AUTH_PROBE_OK' "$DIRECT_PROBE_OUTPUT" && printf true || printf false)"
assert_eq 'workspace-write 执行业务写入副作用' true "$(test -f "$DIRECT_WRITE_PATH" && printf true || printf false)"

for role in "${GATE_ROLES[@]}"; do
  OUTPUT=$(run_gate "$role")
  assert_eq "$role 通过完整门禁" 0 "$?"
  assert_eq "$role 通过结果包含角色名" true "$(grep -q "PASS: role=$role" <<< "$OUTPUT" && printf true || printf false)"
done

for role in "${GATE_ROLES[@]}"; do
  set_role_manifest_prompt "$role" "$(role_default_prompt "$role") Appended."
  OUTPUT=$(run_gate "$role")
  assert_eq "$role 的附加 default_prompt 被拒绝" 1 "$?"
  assert_eq "$role 的附加 default_prompt 返回 role_manifest_mismatch" true "$(grep -q 'reason=role_manifest_mismatch' <<< "$OUTPUT" && printf true || printf false)"
  set_role_manifest_prompt "$role" "$(role_default_prompt "$role")"
done

for role in "${GATE_ROLES[@]}"; do
  default_prompt="$(role_default_prompt "$role")"
  secondary_role_variable='$dac-code-reviewer'
  if [[ "$role" == code-reviewer ]]; then
    secondary_role_variable='$dac-code-generator'
  fi

  set_role_manifest_prompt "$role" "$default_prompt $secondary_role_variable"
  OUTPUT=$(run_gate "$role")
  assert_eq "$role 的第二合法角色变量篡改被拒绝" 1 "$?"
  assert_eq "$role 的第二合法角色变量篡改返回 role_manifest_mismatch" true "$(grep -q 'reason=role_manifest_mismatch' <<< "$OUTPUT" && printf true || printf false)"

  set_role_manifest_prompt "$role" "$default_prompt \$UNTRUSTED"
  OUTPUT=$(run_gate "$role")
  assert_eq "$role 的外部变量篡改被拒绝" 1 "$?"
  assert_eq "$role 的外部变量篡改返回 role_manifest_mismatch" true "$(grep -q 'reason=role_manifest_mismatch' <<< "$OUTPUT" && printf true || printf false)"
  set_role_manifest_prompt "$role" "$default_prompt"
done

OUTPUT=$(run_gate unknown-role)
assert_eq '未知角色被拒绝' 2 "$?"
assert_eq '未知角色显示用法' true "$(grep -q '可用角色' <<< "$OUTPUT" && printf true || printf false)"

WORKSPACE="$TEST_DIR/workspace"
mkdir -p "$WORKSPACE/.dac/tmp" "$WORKSPACE/.git" "$WORKSPACE/lib"
printf '[core]\n\trepositoryformatversion = 0\n' > "$WORKSPACE/.git/config"
printf '任务输入\n' > "$WORKSPACE/.dac/tmp/prompt.txt"
printf 'lib/**\n.dac/tmp/**\n' > "$WORKSPACE/.dac/tmp/allowlist.txt"
printf 'real output before\n' > "$WORKSPACE/.dac/tmp/output.txt"
PROMPT="$WORKSPACE/.dac/tmp/prompt.txt"
ALLOWLIST="$WORKSPACE/.dac/tmp/allowlist.txt"
OUTPUT_FILE="$WORKSPACE/.dac/tmp/output.txt"

CWD_RECORD="$TEST_DIR/codex-cwd.txt"
RUNNER_SKIP_GIT_REPO_CHECK_RECORD="$TEST_DIR/role-runner-skip-git-repo-check.txt"
WRITER_ROOT_SWAP_READY="$TEST_DIR/writer-root-swap-ready"
WRITER_ROOT_SWAP_RELEASE="$TEST_DIR/writer-root-swap-release"
WRITER_ROOT_SWAP_RUNNER_OUTPUT="$TEST_DIR/writer-root-swap-runner-output.txt"
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" DAC_RUNTIME=codex DAC_SKILL_HOME="$SKILL_HOME" DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" DAC_CODEX_TEST_WRITER_INITIAL_SNAPSHOT_READY_FILE="$WRITER_ROOT_SWAP_READY" DAC_CODEX_TEST_WRITER_INITIAL_SNAPSHOT_RELEASE_FILE="$WRITER_ROOT_SWAP_RELEASE" FAKE_WRITE_PATH='lib/writer-root-swap.dart' FAKE_OUTPUT_CONTENT='must not merge after writer root swap' bash "$RUNNER" --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST" >"$WRITER_ROOT_SWAP_RUNNER_OUTPUT" 2>&1 &
WRITER_ROOT_SWAP_PID=$!
wait_for_sentinel "$WRITER_ROOT_SWAP_READY"
WORKSPACE_ROOT_BACKUP="$TEST_DIR/workspace-before-writer-root-swap"
mv "$WORKSPACE" "$WORKSPACE_ROOT_BACKUP"
mkdir "$WORKSPACE"
: > "$WRITER_ROOT_SWAP_RELEASE"
wait "$WRITER_ROOT_SWAP_PID" || WRITER_ROOT_SWAP_STATUS=$?
WRITER_ROOT_SWAP_STATUS=${WRITER_ROOT_SWAP_STATUS:-0}
assert_eq 'writer 初始快照在 workspace 根目录替换后 fail-closed' 1 "$WRITER_ROOT_SWAP_STATUS"
assert_eq 'writer 根目录替换后不合并到替换目录' false "$(test -e "$WORKSPACE/lib/writer-root-swap.dart" && printf true || printf false)"
assert_eq 'writer 根目录替换后不合并到原 workspace 树' false "$(test -e "$WORKSPACE_ROOT_BACKUP/lib/writer-root-swap.dart" && printf true || printf false)"
restore_workspace_root

OUTPUT=$(FAKE_CWD_RECORD="$CWD_RECORD" FAKE_SKIP_GIT_REPO_CHECK_RECORD="$RUNNER_SKIP_GIT_REPO_CHECK_RECORD" FAKE_REQUIRE_GIT_METADATA=1 FAKE_WRITE_PATH='lib/allowed.dart' FAKE_GIT_WRITE_PATH='.git/ai/logs/session.json' run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq 'staging 保留 Git 元数据且 .git 写入不阻断 allowlist 写入' 0 "$?"
assert_eq 'staging 合法普通文件受控合并' true "$(grep -qx generated "$WORKSPACE/lib/allowed.dart" && printf true || printf false)"
assert_eq 'staging .git 元数据不合并到真实 workspace' false "$(test -e "$WORKSPACE/.git/ai/logs/session.json" && printf true || printf false)"
assert_eq 'Codex -C 使用随机 staging 而非真实 workspace' true "$(test "$(cat "$CWD_RECORD")" != "$WORKSPACE" && [[ "$(cat "$CWD_RECORD")" == */workspace ]] && printf true || printf false)"
assert_eq '角色执行不传入 Git 仓库检查跳过参数' false "$(cat "$RUNNER_SKIP_GIT_REPO_CHECK_RECORD")"
assert_eq 'staging output 经受控转移到真实 output' true "$(grep -qx 'verdict: clean' "$OUTPUT_FILE" && printf true || printf false)"
OUTPUT=$(FAKE_OUTPUT_CONTENT='nested output' FAKE_WRITE_PATH='lib/implicit-parent/nested.dart' run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq 'dir/** 允许隐式父目录下的普通文件' 0 "$?"
assert_eq '隐式父目录不作为 manifest 操作合并' true "$(grep -qx generated "$WORKSPACE/lib/implicit-parent/nested.dart" && printf true || printf false)"
assert_eq '成功提交后删除事务日志' false "$(test -e "$WORKSPACE/.dac/tmp/codex-role-merge.txn.json" && printf true || printf false)"
assert_eq '成功提交后清理事务备份' false "$(has_transaction_backups && printf true || printf false)"

OUTPUT_BEFORE=$(cat "$OUTPUT_FILE")
OUTPUT=$(FAKE_SKIP_OUTPUT=1 FAKE_WRITE_PATH='lib/output-unchanged.dart' run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq '未变化的 staging output fail-closed' 1 "$?"
assert_eq '未变化 output 不合并其他文件' false "$(test -e "$WORKSPACE/lib/output-unchanged.dart" && printf true || printf false)"
assert_eq '未变化 output 保留真实内容' "$OUTPUT_BEFORE" "$(cat "$OUTPUT_FILE")"
OUTPUT=$(FAKE_SKIP_OUTPUT=1 FAKE_DELETE_OUTPUT=1 run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq '删除 staging output fail-closed' 1 "$?"
assert_eq '删除 staging output 保留真实内容' "$OUTPUT_BEFORE" "$(cat "$OUTPUT_FILE")"

OUTPUT=$(FAKE_OUTPUT_CONTENT='directory output' FAKE_MKDIR_PATH='lib/explicit-directory' run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq '显式新增目录 fail-closed' 1 "$?"
assert_eq '显式新增目录不合并' false "$(test -e "$WORKSPACE/lib/explicit-directory" && printf true || printf false)"
OUTPUT=$(FAKE_OUTPUT_CONTENT='directory mode output' FAKE_CHMOD_PATH='lib' run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq '目录 mode 变更 fail-closed' 1 "$?"
mkdir -p "$WORKSPACE/lib/removed-directory"
printf 'remove me\n' > "$WORKSPACE/lib/removed-directory/file.dart"
OUTPUT=$(FAKE_OUTPUT_CONTENT='directory removal output' FAKE_DELETE_PATH='lib/removed-directory/file.dart' FAKE_RMDIR_PATH='lib/removed-directory' run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq '显式删除目录 fail-closed' 1 "$?"
assert_eq '显式删除目录不合并' true "$(test -f "$WORKSPACE/lib/removed-directory/file.dart" && printf true || printf false)"

printf 'lib/allowed.dart\n.dac/tmp/**\n' > "$ALLOWLIST"
rm -f "$WORKSPACE/lib/outside.dart"
OUTPUT=$(FAKE_WRITE_PATH='lib/outside.dart' run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq 'staging 越界写入 fail-closed' 1 "$?"
assert_eq 'staging 越界写入不合并到真实 workspace' false "$(test -e "$WORKSPACE/lib/outside.dart" && printf true || printf false)"

rm -f "$WORKSPACE/lib/allowed.dart outside.dart"
OUTPUT=$(FAKE_WRITE_PATH='lib/allowed.dart outside.dart' run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq '含空格路径不能截断绕过 allowlist' 1 "$?"
assert_eq '含空格越界文件不合并' false "$(test -e "$WORKSPACE/lib/allowed.dart outside.dart" && printf true || printf false)"
printf 'generated\n' > "$WORKSPACE/lib/allowed.dart"

printf 'lib/**\n.dac/tmp/**\n' > "$ALLOWLIST"
OUTPUT=$(FAKE_MODIFY_PATH='.dac/tmp/allowlist.txt' FAKE_MODIFY_CONTENT='lib/**' FAKE_WRITE_PATH='lib/relaxed.dart' run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq 'staging allowlist 篡改 fail-closed' 1 "$?"
assert_eq '真实 allowlist 未被 staging 篡改' true "$(grep -Fqx 'lib/**' "$ALLOWLIST" && grep -Fqx '.dac/tmp/**' "$ALLOWLIST" && printf true || printf false)"
assert_eq '篡改 allowlist 后写入不合并' false "$(test -e "$WORKSPACE/lib/relaxed.dart" && printf true || printf false)"

printf '任务输入\n' > "$PROMPT"
OUTPUT=$(FAKE_MODIFY_PATH='.dac/tmp/prompt.txt' FAKE_MODIFY_CONTENT='tampered prompt' run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq 'staging prompt 篡改 fail-closed' 1 "$?"
assert_eq '真实 prompt 未被 staging 篡改' true "$(grep -qx '任务输入' "$PROMPT" && printf true || printf false)"

OUTPUT=$(FAKE_SYMLINK_PATH='lib/escape' run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq 'staging 符号链接 fail-closed' 1 "$?"
assert_eq 'staging 符号链接不污染真实 workspace' false "$(test -e "$WORKSPACE/lib/escape" && printf true || printf false)"

OUTPUT=$(FAKE_FIFO_PATH='lib/unsafe.fifo' run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq 'staging 特殊文件 fail-closed' 1 "$?"
assert_eq 'staging 特殊文件不污染真实 workspace' false "$(test -e "$WORKSPACE/lib/unsafe.fifo" && printf true || printf false)"

OUTPUT_BEFORE=$(cat "$OUTPUT_FILE")
OUTPUT=$(FAKE_HARDLINK_SOURCE='lib/allowed.dart' FAKE_HARDLINK_DEST='.dac/tmp/output.txt' run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq 'staging 硬链接 output fail-closed' 1 "$?"
assert_eq 'staging 硬链接 output 不转移到真实 workspace' "$OUTPUT_BEFORE" "$(cat "$OUTPUT_FILE")"

rm -f "$WORKSPACE/lib/background.dart"
OUTPUT=$(FAKE_OUTPUT_CONTENT='background verdict' FAKE_BACKGROUND_WRITE_PATH='lib/background.dart' FAKE_BACKGROUND_DELAY=1 run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq 'setsid 延迟写入的主调用通过' 0 "$?"
sleep 2
assert_eq 'setsid 延迟写入不污染真实 workspace' false "$(test -e "$WORKSPACE/lib/background.dart" && printf true || printf false)"

printf 'first original\n' > "$WORKSPACE/lib/first.dart"
printf 'second original\n' > "$WORKSPACE/lib/second.dart"
ROLLBACK_READY="$TEST_DIR/rollback-ready"
ROLLBACK_RELEASE="$TEST_DIR/rollback-release"
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" DAC_RUNTIME=codex DAC_SKILL_HOME="$SKILL_HOME" DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" DAC_CODEX_TEST_MERGE_AFTER_PATH='lib/first.dart' DAC_CODEX_TEST_MERGE_READY_FILE="$ROLLBACK_READY" DAC_CODEX_TEST_MERGE_RELEASE_FILE="$ROLLBACK_RELEASE" FAKE_MODIFY_PATH='lib/first.dart' FAKE_MODIFY_CONTENT='first staged' FAKE_SECOND_MODIFY_PATH='lib/second.dart' FAKE_SECOND_MODIFY_CONTENT='second staged' FAKE_OUTPUT_CONTENT='rollback verdict' bash "$RUNNER" --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST" >/dev/null 2>&1 &
ROLLBACK_PID=$!
wait_for_sentinel "$ROLLBACK_READY"
assert_eq '事务失败前第一个文件已完成合并' true "$(grep -qx 'first staged' "$WORKSPACE/lib/first.dart" && printf true || printf false)"
printf 'second changed concurrently\n' > "$WORKSPACE/lib/second.dart"
: > "$ROLLBACK_RELEASE"
wait "$ROLLBACK_PID" || ROLLBACK_STATUS=$?
ROLLBACK_STATUS=${ROLLBACK_STATUS:-0}
assert_eq '第二个文件预期变化校验失败' 1 "$ROLLBACK_STATUS"
assert_eq '事务失败后第一个文件回滚' true "$(grep -qx 'first original' "$WORKSPACE/lib/first.dart" && printf true || printf false)"
assert_eq '事务不覆盖未成功合并的并发文件' true "$(grep -qx 'second changed concurrently' "$WORKSPACE/lib/second.dart" && printf true || printf false)"

printf 'crash first original\n' > "$WORKSPACE/lib/crash-first.dart"
printf 'crash second original\n' > "$WORKSPACE/lib/crash-second.dart"
CRASH_READY="$TEST_DIR/crash-ready"
CRASH_MERGE_PID_FILE="$TEST_DIR/crash-merge.pid"
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" DAC_RUNTIME=codex DAC_SKILL_HOME="$SKILL_HOME" DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" DAC_CODEX_TEST_MERGE_AFTER_PATH='lib/crash-first.dart' DAC_CODEX_TEST_MERGE_READY_FILE="$CRASH_READY" DAC_CODEX_TEST_MERGE_RELEASE_FILE="$TEST_DIR/crash-release" DAC_CODEX_TEST_MERGE_PROCESS_PID_FILE="$CRASH_MERGE_PID_FILE" FAKE_MODIFY_PATH='lib/crash-first.dart' FAKE_MODIFY_CONTENT='crash first staged' FAKE_SECOND_MODIFY_PATH='lib/crash-second.dart' FAKE_SECOND_MODIFY_CONTENT='crash second staged' FAKE_OUTPUT_CONTENT='crash verdict' bash "$RUNNER" --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST" >/dev/null 2>&1 &
CRASH_PID=$!
wait_for_sentinel "$CRASH_READY"
kill -KILL "$(< "$CRASH_MERGE_PID_FILE")"
wait "$CRASH_PID" || CRASH_STATUS=$?
CRASH_STATUS=${CRASH_STATUS:-0}
assert_eq '第一个目标提交后合并子进程被 SIGKILL 中断' 1 "$CRASH_STATUS"
assert_eq '子进程中断后第一个目标仍处于已提交状态' true "$(grep -qx 'crash first staged' "$WORKSPACE/lib/crash-first.dart" && printf true || printf false)"
assert_eq '子进程中断后后续目标未落地' true "$(grep -qx 'crash second original' "$WORKSPACE/lib/crash-second.dart" && printf true || printf false)"
assert_eq '子进程中断后遗留持久事务日志' true "$(test -f "$WORKSPACE/.dac/tmp/codex-role-merge.txn.json" && printf true || printf false)"
OUTPUT=$(FAKE_SKIP_OUTPUT=1 run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq '下次 writer 调用在 staging 前恢复未完成事务' 1 "$?"
assert_eq '未完成事务恢复第一个原文件' true "$(grep -qx 'crash first original' "$WORKSPACE/lib/crash-first.dart" && printf true || printf false)"
assert_eq '未完成事务恢复不落地后续文件' true "$(grep -qx 'crash second original' "$WORKSPACE/lib/crash-second.dart" && printf true || printf false)"
assert_eq '恢复成功后删除事务日志' false "$(test -e "$WORKSPACE/.dac/tmp/codex-role-merge.txn.json" && printf true || printf false)"
assert_eq '修改崩溃恢复后清理事务备份' false "$(has_transaction_backups && printf true || printf false)"

printf 'added original sentinel\n' > "$WORKSPACE/lib/crash-added-sentinel.dart"
ADDED_READY="$TEST_DIR/added-ready"
ADDED_MERGE_PID_FILE="$TEST_DIR/added-merge.pid"
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" DAC_RUNTIME=codex DAC_SKILL_HOME="$SKILL_HOME" DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" DAC_CODEX_TEST_MERGE_AFTER_PATH='lib/crash-added.dart' DAC_CODEX_TEST_MERGE_READY_FILE="$ADDED_READY" DAC_CODEX_TEST_MERGE_RELEASE_FILE="$TEST_DIR/added-release" DAC_CODEX_TEST_MERGE_PROCESS_PID_FILE="$ADDED_MERGE_PID_FILE" FAKE_WRITE_PATH='lib/crash-added.dart' FAKE_WRITE_CONTENT='added staged' FAKE_OUTPUT_CONTENT='added verdict' bash "$RUNNER" --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST" >/dev/null 2>&1 &
ADDED_PID=$!
wait_for_sentinel "$ADDED_READY"
kill -KILL "$(< "$ADDED_MERGE_PID_FILE")"
wait "$ADDED_PID" || ADDED_STATUS=$?
ADDED_STATUS=${ADDED_STATUS:-0}
assert_eq '新增文件提交后合并子进程被 SIGKILL 中断' 1 "$ADDED_STATUS"
assert_eq '新增文件崩溃后仍处于已提交状态' true "$(grep -qx 'added staged' "$WORKSPACE/lib/crash-added.dart" && printf true || printf false)"
OUTPUT=$(FAKE_SKIP_OUTPUT=1 run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq '下次 writer 调用恢复新增文件事务' 1 "$?"
assert_eq '新增文件崩溃恢复后删除已提交文件' false "$(test -e "$WORKSPACE/lib/crash-added.dart" && printf true || printf false)"
assert_eq '新增文件崩溃恢复后清理事务备份' false "$(has_transaction_backups && printf true || printf false)"

printf 'deleted original\n' > "$WORKSPACE/lib/crash-deleted.dart"
DELETED_READY="$TEST_DIR/deleted-ready"
DELETED_MERGE_PID_FILE="$TEST_DIR/deleted-merge.pid"
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" DAC_RUNTIME=codex DAC_SKILL_HOME="$SKILL_HOME" DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" DAC_CODEX_TEST_MERGE_AFTER_PATH='lib/crash-deleted.dart' DAC_CODEX_TEST_MERGE_READY_FILE="$DELETED_READY" DAC_CODEX_TEST_MERGE_RELEASE_FILE="$TEST_DIR/deleted-release" DAC_CODEX_TEST_MERGE_PROCESS_PID_FILE="$DELETED_MERGE_PID_FILE" FAKE_DELETE_PATH='lib/crash-deleted.dart' FAKE_OUTPUT_CONTENT='deleted verdict' bash "$RUNNER" --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST" >/dev/null 2>&1 &
DELETED_PID=$!
wait_for_sentinel "$DELETED_READY"
kill -KILL "$(< "$DELETED_MERGE_PID_FILE")"
wait "$DELETED_PID" || DELETED_STATUS=$?
DELETED_STATUS=${DELETED_STATUS:-0}
assert_eq '删除文件提交后合并子进程被 SIGKILL 中断' 1 "$DELETED_STATUS"
assert_eq '删除文件崩溃后仍处于已提交状态' false "$(test -e "$WORKSPACE/lib/crash-deleted.dart" && printf true || printf false)"
OUTPUT=$(FAKE_SKIP_OUTPUT=1 run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq '下次 writer 调用恢复删除文件事务' 1 "$?"
assert_eq '删除文件崩溃恢复后还原原文件' true "$(grep -qx 'deleted original' "$WORKSPACE/lib/crash-deleted.dart" && printf true || printf false)"
assert_eq '删除文件崩溃恢复后清理事务备份' false "$(has_transaction_backups && printf true || printf false)"

printf 'prepared original\n' > "$WORKSPACE/lib/crash-prepared.dart"
PREPARED_READY="$TEST_DIR/prepared-ready"
PREPARED_MERGE_PID_FILE="$TEST_DIR/prepared-merge.pid"
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" DAC_RUNTIME=codex DAC_SKILL_HOME="$SKILL_HOME" DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" DAC_CODEX_TEST_MERGE_PREPARED_PATH='lib/crash-prepared.dart' DAC_CODEX_TEST_MERGE_READY_FILE="$PREPARED_READY" DAC_CODEX_TEST_MERGE_RELEASE_FILE="$TEST_DIR/prepared-release" DAC_CODEX_TEST_MERGE_PROCESS_PID_FILE="$PREPARED_MERGE_PID_FILE" FAKE_MODIFY_PATH='lib/crash-prepared.dart' FAKE_MODIFY_CONTENT='prepared staged' FAKE_OUTPUT_CONTENT='prepared verdict' bash "$RUNNER" --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST" >/dev/null 2>&1 &
PREPARED_PID=$!
wait_for_sentinel "$PREPARED_READY"
kill -KILL "$(< "$PREPARED_MERGE_PID_FILE")"
wait "$PREPARED_PID" || PREPARED_STATUS=$?
PREPARED_STATUS=${PREPARED_STATUS:-0}
assert_eq 'prepared 状态合并子进程被 SIGKILL 中断' 1 "$PREPARED_STATUS"
assert_eq 'prepared 崩溃前目标仍保持原内容' true "$(grep -qx 'prepared original' "$WORKSPACE/lib/crash-prepared.dart" && printf true || printf false)"
OUTPUT=$(FAKE_SKIP_OUTPUT=1 run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq '下次 writer 调用清理 prepared 事务' 1 "$?"
assert_eq 'prepared 崩溃恢复后保留原内容' true "$(grep -qx 'prepared original' "$WORKSPACE/lib/crash-prepared.dart" && printf true || printf false)"
assert_eq 'prepared 崩溃恢复后清理事务备份' false "$(has_transaction_backups && printf true || printf false)"

ORPHAN_BACKUP="$WORKSPACE/.dac/tmp/codex-role-merge-backups/deadbeef"
mkdir -p "$ORPHAN_BACKUP"
printf 'orphan backup\n' > "$ORPHAN_BACKUP/file.dart"
OUTPUT=$(FAKE_SKIP_OUTPUT=1 run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq '无日志孤儿备份清理后调用仍在 staging 校验处失败' 1 "$?"
assert_eq '受合并锁保护清理无日志孤儿备份' false "$(test -e "$ORPHAN_BACKUP" && printf true || printf false)"

UNSAFE_ORPHAN_BACKUP="$WORKSPACE/.dac/tmp/codex-role-merge-backups/cafebabe"
printf 'unsafe orphan backup\n' > "$UNSAFE_ORPHAN_BACKUP"
OUTPUT=$(FAKE_SKIP_OUTPUT=1 run_role --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST")
assert_eq '非目录孤儿备份 fail-closed' 1 "$?"
assert_eq '非目录孤儿备份不被删除' true "$(test -f "$UNSAFE_ORPHAN_BACKUP" && printf true || printf false)"
rm -f "$UNSAFE_ORPHAN_BACKUP"

printf 'lock first original\n' > "$WORKSPACE/lib/lock-first.dart"
printf 'lock second original\n' > "$WORKSPACE/lib/lock-second.dart"
LOCK_READY="$TEST_DIR/lock-ready"
LOCK_RELEASE="$TEST_DIR/lock-release"
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" DAC_RUNTIME=codex DAC_SKILL_HOME="$SKILL_HOME" DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" DAC_CODEX_TEST_MERGE_AFTER_PATH='lib/lock-first.dart' DAC_CODEX_TEST_MERGE_READY_FILE="$LOCK_READY" DAC_CODEX_TEST_MERGE_RELEASE_FILE="$LOCK_RELEASE" FAKE_MODIFY_PATH='lib/lock-first.dart' FAKE_MODIFY_CONTENT='lock first staged' FAKE_SECOND_MODIFY_PATH='lib/lock-second.dart' FAKE_SECOND_MODIFY_CONTENT='lock second staged' FAKE_OUTPUT_CONTENT='lock verdict' bash "$RUNNER" --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST" >/dev/null 2>&1 &
LOCK_PID=$!
wait_for_sentinel "$LOCK_READY"
assert_eq '锁检查点出现时首个 writer 仍存活' true "$(kill -0 "$LOCK_PID" 2>/dev/null && printf true || printf false)"
LOCK_CONTENDER_OUTPUT="$TEST_DIR/lock-contender-output.txt"
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" DAC_RUNTIME=codex DAC_SKILL_HOME="$SKILL_HOME" DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" FAKE_WRITE_PATH='lib/lock-rejected.dart' FAKE_OUTPUT_CONTENT='second lock verdict' bash "$RUNNER" --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST" >"$LOCK_CONTENDER_OUTPUT" 2>&1 &
LOCK_CONTENDER_PID=$!
wait_for_process_exit "$LOCK_CONTENDER_PID" || LOCK_CONTENDER_WATCHDOG=$?
wait "$LOCK_CONTENDER_PID" || LOCK_CONTENDER_STATUS=$?
LOCK_CONTENDER_STATUS=${LOCK_CONTENDER_STATUS:-0}
LOCK_CONTENDER_WATCHDOG=${LOCK_CONTENDER_WATCHDOG:-0}
assert_eq '锁竞争调用未阻塞超时' 0 "$LOCK_CONTENDER_WATCHDOG"
assert_eq '锁持有期间第二个 writer 非阻塞拒绝' 1 "$LOCK_CONTENDER_STATUS"
assert_eq '锁竞争拒绝来自受控合并锁' true "$(grep -Fq '已有 Codex writer 正在执行受控合并' "$LOCK_CONTENDER_OUTPUT" && printf true || printf false)"
assert_eq '锁持有期间第二个 writer 不进入合并' false "$(test -e "$WORKSPACE/lib/lock-rejected.dart" && printf true || printf false)"
: > "$LOCK_RELEASE"
wait "$LOCK_PID" || LOCK_STATUS=$?
LOCK_STATUS=${LOCK_STATUS:-0}
assert_eq '持锁 writer 释放后完成自身事务' 0 "$LOCK_STATUS"

SNAPSHOT_FIFO_PATH='lib/snapshot-open-race.dart'
SNAPSHOT_FIFO_READY="$TEST_DIR/snapshot-fifo-ready"
SNAPSHOT_FIFO_RELEASE="$TEST_DIR/snapshot-fifo-release"
SNAPSHOT_FIFO_RUNNER_OUTPUT="$TEST_DIR/snapshot-fifo-runner-output.txt"
printf 'snapshot target before replacement\n' > "$WORKSPACE/$SNAPSHOT_FIFO_PATH"
printf 'output before snapshot FIFO replacement\n' > "$OUTPUT_FILE"
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" DAC_RUNTIME=codex DAC_SKILL_HOME="$SKILL_HOME" DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" DAC_CODEX_TEST_SNAPSHOT_FILE_PATH="$SNAPSHOT_FIFO_PATH" DAC_CODEX_TEST_SNAPSHOT_FILE_READY_FILE="$SNAPSHOT_FIFO_READY" DAC_CODEX_TEST_SNAPSHOT_FILE_RELEASE_FILE="$SNAPSHOT_FIFO_RELEASE" FAKE_OUTPUT_CONTENT='must not transfer after snapshot FIFO replacement' bash "$RUNNER" --role code-reviewer --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" >"$SNAPSHOT_FIFO_RUNNER_OUTPUT" 2>&1 &
SNAPSHOT_FIFO_PID=$!
wait_for_sentinel "$SNAPSHOT_FIFO_READY"
rm -f "$WORKSPACE/$SNAPSHOT_FIFO_PATH"
mkfifo "$WORKSPACE/$SNAPSHOT_FIFO_PATH"
: > "$SNAPSHOT_FIFO_RELEASE"
wait_for_process_exit "$SNAPSHOT_FIFO_PID" || SNAPSHOT_FIFO_WATCHDOG=$?
wait "$SNAPSHOT_FIFO_PID" || SNAPSHOT_FIFO_STATUS=$?
SNAPSHOT_FIFO_WATCHDOG=${SNAPSHOT_FIFO_WATCHDOG:-0}
SNAPSHOT_FIFO_STATUS=${SNAPSHOT_FIFO_STATUS:-0}
assert_eq '快照文件 stat 与 open 间替换 FIFO 不会挂起' 0 "$SNAPSHOT_FIFO_WATCHDOG"
assert_eq '快照文件替换 FIFO 后 fail-closed' 1 "$SNAPSHOT_FIFO_STATUS"
assert_eq '快照文件替换 FIFO 后不转移输出' true "$(grep -qx 'output before snapshot FIFO replacement' "$OUTPUT_FILE" && printf true || printf false)"
rm -f "$WORKSPACE/$SNAPSHOT_FIFO_PATH"

READ_ONLY_OUTPUT="$WORKSPACE/.dac/tmp/code-review-output.txt"
printf 'read-only output before\n' > "$READ_ONLY_OUTPUT"
OUTPUT=$(FAKE_OUTPUT_CONTENT='read-only transferred' run_role --role code-reviewer --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$READ_ONLY_OUTPUT")
assert_eq '只读角色通过外部临时 output 原子转移' 0 "$?"
assert_eq '只读角色 output 转移后内容正确' true "$(grep -qx 'read-only transferred' "$READ_ONLY_OUTPUT" && printf true || printf false)"

ROOT_SWAP_READY="$TEST_DIR/read-only-root-swap-ready"
ROOT_SWAP_RELEASE="$TEST_DIR/read-only-root-swap-release"
ROOT_SWAP_EXTERNAL="$TEST_DIR/read-only-root-swap-external"
ROOT_SWAP_EXTERNAL_OUTPUT="$ROOT_SWAP_EXTERNAL/.dac/tmp/code-review-output.txt"
ROOT_SWAP_RUNNER_OUTPUT="$TEST_DIR/read-only-root-swap-runner-output.txt"
mkdir -p "$(dirname "$ROOT_SWAP_EXTERNAL_OUTPUT")"
printf 'external output before root swap\n' > "$ROOT_SWAP_EXTERNAL_OUTPUT"
printf 'workspace output before root swap\n' > "$READ_ONLY_OUTPUT"
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" DAC_RUNTIME=codex DAC_SKILL_HOME="$SKILL_HOME" DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" DAC_CODEX_TEST_READ_ONLY_TRANSFER_PATH='.dac/tmp/code-review-output.txt' DAC_CODEX_TEST_READ_ONLY_TRANSFER_READY_FILE="$ROOT_SWAP_READY" DAC_CODEX_TEST_READ_ONLY_TRANSFER_RELEASE_FILE="$ROOT_SWAP_RELEASE" FAKE_OUTPUT_CONTENT='must not transfer after root swap' bash "$RUNNER" --role code-reviewer --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$READ_ONLY_OUTPUT" >"$ROOT_SWAP_RUNNER_OUTPUT" 2>&1 &
ROOT_SWAP_PID=$!
wait_for_sentinel "$ROOT_SWAP_READY"
WORKSPACE_ROOT_BACKUP="$TEST_DIR/workspace-before-read-only-root-swap"
mv "$WORKSPACE" "$WORKSPACE_ROOT_BACKUP"
ln -s "$ROOT_SWAP_EXTERNAL" "$WORKSPACE"
: > "$ROOT_SWAP_RELEASE"
wait "$ROOT_SWAP_PID" || ROOT_SWAP_STATUS=$?
ROOT_SWAP_STATUS=${ROOT_SWAP_STATUS:-0}
restore_workspace_root
assert_eq '只读 transfer 在 workspace 根目录替换后 fail-closed' 1 "$ROOT_SWAP_STATUS"
assert_eq '只读 transfer 根目录替换后不写外部目标' true "$(grep -qx 'external output before root swap' "$ROOT_SWAP_EXTERNAL_OUTPUT" && printf true || printf false)"
assert_eq '只读 transfer 根目录替换后保留原 workspace output' true "$(grep -qx 'workspace output before root swap' "$READ_ONLY_OUTPUT" && printf true || printf false)"

rm -f "$WORKSPACE/lib/concurrent.dart" "$WORKSPACE/concurrent-change.txt"
CONCURRENT_READY="$TEST_DIR/concurrent-ready"
CONCURRENT_RELEASE="$TEST_DIR/concurrent-release"
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" DAC_RUNTIME=codex DAC_SKILL_HOME="$SKILL_HOME" DAC_STATE_HOME="$STATE_HOME" DAC_CONFIG_HOME="$CONFIG_HOME" FAKE_WRITE_PATH='lib/concurrent.dart' FAKE_OUTPUT_CONTENT='concurrent verdict' FAKE_READY_FILE="$CONCURRENT_READY" FAKE_RELEASE_FILE="$CONCURRENT_RELEASE" bash "$RUNNER" --role code-generator --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE" --allowed-paths-file "$ALLOWLIST" >/dev/null 2>&1 &
RUNNER_PID=$!
wait_for_sentinel "$CONCURRENT_READY"
printf 'concurrent real change\n' > "$WORKSPACE/concurrent-change.txt"
: > "$CONCURRENT_RELEASE"
wait "$RUNNER_PID" || RUNNER_STATUS=$?
RUNNER_STATUS=${RUNNER_STATUS:-0}
assert_eq '合并前真实 workspace 并发变更被拒绝' 1 "$RUNNER_STATUS"
assert_eq '并发时 staging 写入不合并' false "$(test -e "$WORKSPACE/lib/concurrent.dart" && printf true || printf false)"
assert_eq '并发真实变更被保留' true "$(grep -qx 'concurrent real change' "$WORKSPACE/concurrent-change.txt" && printf true || printf false)"
rm -f "$WORKSPACE/concurrent-change.txt"

EXTERNAL_OUTPUT="$TEST_DIR/external-output.txt"
printf 'external output before\n' > "$EXTERNAL_OUTPUT"
rm -f "$OUTPUT_FILE"
ln "$EXTERNAL_OUTPUT" "$OUTPUT_FILE"
OUTPUT=$(run_role --role code-reviewer --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$OUTPUT_FILE")
assert_eq '只读角色硬链接 output fail-closed' 1 "$?"
assert_eq '只读角色硬链接 output 不被覆盖' true "$(grep -qx 'external output before' "$EXTERNAL_OUTPUT" && printf true || printf false)"
rm -f "$OUTPUT_FILE"
printf 'output restored\n' > "$OUTPUT_FILE"

GIT_OUTPUT="$WORKSPACE/.git/ai/logs/session.json"
mkdir -p "$(dirname "$GIT_OUTPUT")"
printf 'git output before\n' > "$GIT_OUTPUT"
OUTPUT=$(run_role --role code-reviewer --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$GIT_OUTPUT")
assert_eq '只读角色拒绝 .git 输出路径' 1 "$?"
assert_eq '.git 输出路径原文件不被覆盖' true "$(grep -qx 'git output before' "$GIT_OUTPUT" && printf true || printf false)"

TRANSACTION_OUTPUT="$WORKSPACE/.dac/tmp/codex-role-merge.txn.json"
printf 'transaction output before\n' > "$TRANSACTION_OUTPUT"
OUTPUT=$(run_role --role code-reviewer --cwd "$WORKSPACE" --prompt-file "$PROMPT" --output-file "$TRANSACTION_OUTPUT")
assert_eq '只读角色拒绝事务输出路径' 1 "$?"
assert_eq '事务输出路径原文件不被覆盖' true "$(grep -qx 'transaction output before' "$TRANSACTION_OUTPUT" && printf true || printf false)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
