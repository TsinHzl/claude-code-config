#!/usr/bin/env bash
# run-codex-role.sh — 以独立 Codex exec 会话运行已通过门禁的 DAC 角色。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../runtime.sh"
if ! dac_resolve_runtime; then
  printf 'BLOCKED: 无法解析 Codex 运行时\n' >&2
  exit 1
fi

ROLE=""
WORKSPACE=""
PROMPT_FILE=""
OUTPUT_FILE=""
ALLOWED_PATHS_FILE=""
ALLOWED_PATHS_SNAPSHOT=""
REAL_SNAPSHOT_INITIAL=""
REAL_SNAPSHOT_READY=""
STAGING_ROOT=""
STAGING_WORKSPACE=""
STAGING_SNAPSHOT_BEFORE=""
STAGING_SNAPSHOT_AFTER=""
STAGING_SNAPSHOT_READY=""
CHANGE_MANIFEST=""
READ_ONLY_OUTPUT=""

cleanup() {
  [[ -z "$ALLOWED_PATHS_SNAPSHOT" ]] || rm -f "$ALLOWED_PATHS_SNAPSHOT"
  [[ -z "$REAL_SNAPSHOT_INITIAL" ]] || rm -f "$REAL_SNAPSHOT_INITIAL"
  [[ -z "$REAL_SNAPSHOT_READY" ]] || rm -f "$REAL_SNAPSHOT_READY"
  [[ -z "$STAGING_SNAPSHOT_BEFORE" ]] || rm -f "$STAGING_SNAPSHOT_BEFORE"
  [[ -z "$STAGING_SNAPSHOT_AFTER" ]] || rm -f "$STAGING_SNAPSHOT_AFTER"
  [[ -z "$STAGING_SNAPSHOT_READY" ]] || rm -f "$STAGING_SNAPSHOT_READY"
  [[ -z "$CHANGE_MANIFEST" ]] || rm -f "$CHANGE_MANIFEST"
  [[ -z "$READ_ONLY_OUTPUT" ]] || rm -f "$READ_ONLY_OUTPUT"
  [[ -z "$STAGING_ROOT" ]] || rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT INT TERM HUP

usage() {
  cat >&2 <<'EOF'
用法：run-codex-role.sh --role <role> --cwd <workspace> --prompt-file <file> --output-file <file> [--allowed-paths-file <file>]
EOF
}

blocked() {
  printf 'BLOCKED: %s\n' "$1" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="${2:-}"; shift 2 ;;
    --cwd) WORKSPACE="${2:-}"; shift 2 ;;
    --prompt-file) PROMPT_FILE="${2:-}"; shift 2 ;;
    --output-file) OUTPUT_FILE="${2:-}"; shift 2 ;;
    --allowed-paths-file) ALLOWED_PATHS_FILE="${2:-}"; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done

[[ -n "$ROLE" && -n "$WORKSPACE" && -n "$PROMPT_FILE" && -n "$OUTPUT_FILE" ]] || { usage; exit 2; }
bash "$SCRIPT_DIR/codex-agent-gate.sh" "$ROLE"

[[ -d "$WORKSPACE" && ! -L "$WORKSPACE" ]] || blocked "workspace 无效：$WORKSPACE"
WORKSPACE="$(cd "$WORKSPACE" && pwd -P)"

capture_workspace_identity() {
  local identity
  identity="$(python3 - "$WORKSPACE" <<'PY'
import os
import stat
import sys

root = sys.argv[1]
if not hasattr(os, 'O_DIRECTORY') or not hasattr(os, 'O_NOFOLLOW'):
    raise RuntimeError('当前平台不支持安全打开 workspace 根目录所需标志')
fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try:
    info = os.fstat(fd)
    if not stat.S_ISDIR(info.st_mode):
        raise RuntimeError('workspace 根目录不是目录')
    print(f'{info.st_dev} {info.st_ino}')
finally:
    os.close(fd)
PY
)" || blocked '无法捕获 workspace 根目录身份'
  read -r WORKSPACE_DEVICE WORKSPACE_INODE <<< "$identity"
  [[ "$WORKSPACE_DEVICE" =~ ^[0-9]+$ && "$WORKSPACE_INODE" =~ ^[0-9]+$ ]] || blocked 'workspace 根目录身份无效'
}

capture_workspace_identity

resolve_workspace_file() {
  local candidate="$1" label="$2" require_existing="$3" parent resolved
  [[ "$candidate" == /* ]] || blocked "$label 必须使用绝对路径：$candidate"
  if [[ "$require_existing" == true ]]; then
    [[ -f "$candidate" && ! -L "$candidate" ]] || blocked "$label 无效：$candidate"
  elif [[ -L "$candidate" ]]; then
    blocked "$label 不得为符号链接：$candidate"
  fi
  parent="$(dirname "$candidate")"
  [[ -d "$parent" && ! -L "$parent" ]] || blocked "$label 父目录无效：$parent"
  resolved="$(cd "$parent" && pwd -P)/$(basename "$candidate")"
  [[ "$resolved" == "$WORKSPACE/"* ]] || blocked "$label 必须位于 workspace 内：$candidate"
  printf '%s\n' "$resolved"
}

validate_output_path() {
  local relative="${OUTPUT_FILE#$WORKSPACE/}"
  case "$relative" in
    .git|.git/*|.dac/tmp/codex-role-merge.lock|.dac/tmp/codex-role-merge.txn.json|.dac/tmp/codex-role-merge-backups|.dac/tmp/codex-role-merge-backups/*)
      blocked "output 文件不得位于受保护路径：$OUTPUT_FILE"
      ;;
  esac
}

PROMPT_FILE="$(resolve_workspace_file "$PROMPT_FILE" 'prompt 文件' true)"
OUTPUT_FILE="$(resolve_workspace_file "$OUTPUT_FILE" 'output 文件' false)"
validate_output_path
if [[ -n "$ALLOWED_PATHS_FILE" ]]; then
  ALLOWED_PATHS_FILE="$(resolve_workspace_file "$ALLOWED_PATHS_FILE" 'allowlist 文件' true)"
  ALLOWED_PATHS_SNAPSHOT=$(mktemp "${TMPDIR:-/tmp}/dac-codex-allowlist.XXXXXX") || blocked '无法创建 allowlist 冻结副本'
  cp "$ALLOWED_PATHS_FILE" "$ALLOWED_PATHS_SNAPSHOT" || blocked '无法冻结 allowlist'
fi
ROLE_FILE="$DAC_SKILL_HOME/codex-agents/$ROLE/SKILL.md"

is_allowed_path() {
  local path="$1" allowed
  while IFS= read -r allowed || [[ -n "$allowed" ]]; do
    [[ -n "$allowed" && "$allowed" != /* && "$allowed" != *'..'* && "$allowed" != .git && "$allowed" != .git/* ]] || continue
    [[ "$allowed" == *'/**' ]] && [[ "$path" == "${allowed%/**}/"* ]] && return 0
    [[ "$path" == "$allowed" ]] && return 0
  done < "$ALLOWED_PATHS_SNAPSHOT"
  return 1
}

write_snapshot() {
  local root="$1" expected_device="${2:-}" expected_inode="${3:-}"
  python3 - "$root" "$expected_device" "$expected_inode" <<'PY'
import hashlib
import json
import os
import stat
import sys
import time

root, expected_device, expected_inode = sys.argv[1:]
if not all(hasattr(os, flag) for flag in ('O_DIRECTORY', 'O_NOFOLLOW', 'O_NONBLOCK')):
    raise RuntimeError('当前平台不支持安全打开 workspace 根目录所需标志')
DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
FILE_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
entries = {}


def fail(path, reason):
    raise RuntimeError(f'{reason}: {path}')


def same_entry(expected, actual):
    return (
        expected.st_dev == actual.st_dev
        and expected.st_ino == actual.st_ino
        and expected.st_mode == actual.st_mode
        and expected.st_nlink == actual.st_nlink
    )


def record_file(directory_fd, name, relative, metadata):
    if metadata.st_nlink != 1:
        fail(relative, '检测到普通文件硬链接')
    if os.environ.get('DAC_CODEX_TEST_SNAPSHOT_FILE_PATH') == relative:
        ready_path = os.environ.get('DAC_CODEX_TEST_SNAPSHOT_FILE_READY_FILE')
        release_path = os.environ.get('DAC_CODEX_TEST_SNAPSHOT_FILE_RELEASE_FILE')
        if not ready_path or not release_path:
            raise RuntimeError('快照文件检查点缺少 sentinel 路径')
        with open(ready_path, 'w', encoding='utf-8') as ready:
            ready.flush()
            os.fsync(ready.fileno())
        while not os.path.exists(release_path):
            time.sleep(0.01)
    descriptor = os.open(name, FILE_FLAGS, dir_fd=directory_fd)
    try:
        opened = os.fstat(descriptor)
        if not stat.S_ISREG(opened.st_mode) or not same_entry(metadata, opened):
            fail(relative, '打开后文件身份、类型或链接数异常')
        digest = hashlib.sha256()
        with os.fdopen(os.dup(descriptor), 'rb') as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b''):
                digest.update(chunk)
        entries[relative] = ['file', stat.S_IMODE(opened.st_mode), digest.hexdigest()]
    finally:
        os.close(descriptor)


def walk(directory_fd, prefix):
    for name in sorted(os.listdir(directory_fd)):
        if not prefix and name == '.git':
            continue
        relative = f'{prefix}/{name}' if prefix else name
        metadata = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        if stat.S_ISDIR(metadata.st_mode):
            child = os.open(name, DIRECTORY_FLAGS, dir_fd=directory_fd)
            try:
                opened = os.fstat(child)
                if not stat.S_ISDIR(opened.st_mode) or not same_entry(metadata, opened):
                    fail(relative, '打开后目录身份或类型异常')
                entries[relative] = ['directory', stat.S_IMODE(opened.st_mode)]
                walk(child, relative)
            finally:
                os.close(child)
        elif stat.S_ISREG(metadata.st_mode):
            record_file(directory_fd, name, relative, metadata)
        elif stat.S_ISLNK(metadata.st_mode):
            fail(relative, '检测到符号链接')
        else:
            fail(relative, '检测到特殊文件')

root_fd = os.open(root, DIRECTORY_FLAGS)
try:
    root_info = os.fstat(root_fd)
    if not stat.S_ISDIR(root_info.st_mode):
        fail('.', 'workspace 根目录不是目录')
    if expected_device and expected_inode and (root_info.st_dev, root_info.st_ino) != (int(expected_device), int(expected_inode)):
        fail('.', 'workspace 根目录在快照前发生替换')
    entries['.'] = ['directory', stat.S_IMODE(root_info.st_mode)]
    walk(root_fd, '')
finally:
    os.close(root_fd)
print(json.dumps(entries, sort_keys=True, separators=(',', ':')))
PY
}

clone_workspace() {
  python3 - "$WORKSPACE" "$STAGING_WORKSPACE" "$WORKSPACE_DEVICE" "$WORKSPACE_INODE" <<'PY'
import os
import stat
import sys

source_root, destination_root, expected_device, expected_inode = sys.argv[1:]
source_root = os.path.abspath(source_root)
destination_root = os.path.abspath(destination_root)
if not all(hasattr(os, flag) for flag in ('O_DIRECTORY', 'O_NOFOLLOW', 'O_NONBLOCK')):
    raise RuntimeError('当前平台不支持安全克隆 workspace 所需标志')
DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
FILE_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK

def copy_file(source_directory, destination_directory, name, expected_metadata):
    source_descriptor = os.open(name, FILE_FLAGS, dir_fd=source_directory)
    try:
        metadata = os.fstat(source_descriptor)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_nlink != 1
            or (metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_nlink)
            != (expected_metadata.st_dev, expected_metadata.st_ino, expected_metadata.st_mode, expected_metadata.st_nlink)
        ):
            raise RuntimeError(f'复制期间源文件身份、类型或链接数异常: {name}')
        destination_descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, stat.S_IMODE(metadata.st_mode), dir_fd=destination_directory)
        try:
            while True:
                chunk = os.read(source_descriptor, 1024 * 1024)
                if not chunk:
                    break
                view = memoryview(chunk)
                while view:
                    written = os.write(destination_descriptor, view)
                    view = view[written:]
            os.fsync(destination_descriptor)
        finally:
            os.close(destination_descriptor)
    finally:
        os.close(source_descriptor)

def copy_directory(source_directory, destination_directory):
    for name in sorted(os.listdir(source_directory)):
        metadata = os.stat(name, dir_fd=source_directory, follow_symlinks=False)
        if stat.S_ISDIR(metadata.st_mode):
            source_child = os.open(name, DIRECTORY_FLAGS, dir_fd=source_directory)
            try:
                os.mkdir(name, stat.S_IMODE(metadata.st_mode), dir_fd=destination_directory)
                destination_child = os.open(name, DIRECTORY_FLAGS, dir_fd=destination_directory)
                try:
                    copy_directory(source_child, destination_child)
                finally:
                    os.close(destination_child)
            finally:
                os.close(source_child)
        elif stat.S_ISREG(metadata.st_mode):
            if metadata.st_nlink != 1:
                raise RuntimeError(f'不安全源硬链接: {name}')
            copy_file(source_directory, destination_directory, name, metadata)
        else:
            raise RuntimeError(f'不安全源条目: {name}')

source_descriptor = os.open(source_root, DIRECTORY_FLAGS)
try:
    source_metadata = os.fstat(source_descriptor)
    if (
        not stat.S_ISDIR(source_metadata.st_mode)
        or (source_metadata.st_dev, source_metadata.st_ino) != (int(expected_device), int(expected_inode))
    ):
        raise RuntimeError(f'workspace 根目录在 staging 克隆前发生替换: {source_root}')
    os.mkdir(destination_root, stat.S_IMODE(source_metadata.st_mode))
    destination_descriptor = os.open(destination_root, DIRECTORY_FLAGS)
    try:
        copy_directory(source_descriptor, destination_descriptor)
    finally:
        os.close(destination_descriptor)
finally:
    os.close(source_descriptor)
PY
}

snapshot_matches() {
  cmp -s "$1" "$2"
}

relative_workspace_path() {
  local absolute="$1"
  [[ "$absolute" == "$WORKSPACE/"* ]] || blocked "内部路径不在 workspace 内：$absolute"
  printf '%s\n' "${absolute#$WORKSPACE/}"
}

validate_staging_output() {
  local output_relative
  output_relative="$(relative_workspace_path "$OUTPUT_FILE")"
  if ! python3 - "$STAGING_SNAPSHOT_BEFORE" "$STAGING_SNAPSHOT_AFTER" "$output_relative" <<'PY'
import json
import sys

before_path, after_path, output_path = sys.argv[1:]
with open(before_path, encoding='utf-8') as source:
    before = json.load(source)
with open(after_path, encoding='utf-8') as source:
    after = json.load(source)

old, new = before.get(output_path), after.get(output_path)
if new is None or new[0] != 'file':
    raise RuntimeError(f'staging output 未生成普通文件：{output_path}')
if old == new:
    raise RuntimeError(f'staging output 未相对执行前快照变化：{output_path}')
PY
  then
    blocked 'staging output 不符合执行协议'
  fi
}

build_and_validate_manifest() {
  CHANGE_MANIFEST=$(mktemp "${TMPDIR:-/tmp}/dac-codex-manifest.XXXXXX") || blocked '无法创建 staging 差异清单'
  local prompt_relative allowlist_relative output_relative
  prompt_relative="$(relative_workspace_path "$PROMPT_FILE")"
  output_relative="$(relative_workspace_path "$OUTPUT_FILE")"
  allowlist_relative="$(relative_workspace_path "$ALLOWED_PATHS_FILE")"
  if ! python3 - "$STAGING_SNAPSHOT_BEFORE" "$STAGING_SNAPSHOT_AFTER" "$ALLOWED_PATHS_SNAPSHOT" "$prompt_relative" "$allowlist_relative" "$output_relative" > "$CHANGE_MANIFEST" <<'PY'
import json
import sys

before_path, after_path, allowlist_path, prompt_path, allowlist_workspace_path, output_path = sys.argv[1:]
with open(before_path, encoding='utf-8') as source:
    before = json.load(source)
with open(after_path, encoding='utf-8') as source:
    after = json.load(source)
with open(allowlist_path, encoding='utf-8') as source:
    allowed_paths = [line.rstrip('\n') for line in source]

def allowed(path):
    for allowed_path in allowed_paths:
        if not allowed_path or allowed_path.startswith('/') or '..' in allowed_path:
            continue
        if allowed_path == '.git' or allowed_path.startswith('.git/'):
            continue
        if allowed_path.endswith('/**'):
            directory = allowed_path[:-3]
            if path.startswith(directory + '/'):
                return True
        if path == allowed_path:
            return True
    return False

changes = []
for path in sorted(set(before) | set(after)):
    if path == '.git' or path.startswith('.git/'):
        continue
    old, new = before.get(path), after.get(path)
    if old != new:
        changes.append({'path': path, 'old': old, 'new': new})
file_changes = [item for item in changes if (item['old'] or ['missing'])[0] != 'directory' and (item['new'] or ['missing'])[0] != 'directory']
for item in changes:
    path, old, new = item['path'], item['old'], item['new']
    old_kind = (old or ['missing'])[0]
    new_kind = (new or ['missing'])[0]
    if path == '.' or path == '.dac/tmp/codex-role-merge.lock' or path == '.dac/tmp/codex-role-merge.txn.json' or path.startswith('.dac/tmp/codex-role-merge-backups/'):
        raise RuntimeError(f'staging 修改了受保护的合并控制路径：{path}')
    if path in (prompt_path, allowlist_workspace_path):
        raise RuntimeError(f'staging 中 prompt 或 allowlist 被篡改：{path}')
    if old_kind == 'directory' or new_kind == 'directory':
        if old_kind == 'missing' and new_kind == 'directory' and any(
            change['path'].startswith(path + '/')
            and change['old'] is None
            and change['new'] is not None
            and change['new'][0] == 'file'
            for change in file_changes
        ):
            continue
        raise RuntimeError(f'staging 包含显式目录新增、删除或 mode 变更：{path}')
    if old_kind not in ('file', 'missing') or new_kind not in ('file', 'missing'):
        raise RuntimeError(f'staging 包含非普通文件变更：{path}')
    if not allowed(path):
        raise RuntimeError(f'写入范围外文件：{path}')
if not allowed(output_path):
    raise RuntimeError(f'output 文件不在允许写入范围：{output_path}')
output_change = next((item for item in changes if item['path'] == output_path), None)
if output_change is None or output_change['new'] is None or output_change['new'][0] != 'file':
    raise RuntimeError(f'output 未以普通文件变更写入：{output_path}')
for item in changes:
    if (item['old'] or ['missing'])[0] == 'directory' or (item['new'] or ['missing'])[0] == 'directory':
        continue
    print(json.dumps(item, separators=(',', ':')))
PY
  then
    blocked 'staging 差异不符合冻结的 allowlist'
  fi
}

run_codex() {
  local cwd="$1" sandbox="$2" prompt="$3" output="$4"
  python3 - \
    codex exec \
    --sandbox "$sandbox" \
    -C "$cwd" \
    --output-last-message "$output" \
    "阅读并遵循 $ROLE_FILE 的角色约束。只执行 $prompt 中的任务。若证据不足、范围越界或无法独立完成，输出 BLOCKED，不得由当前会话替代该角色。" <<'PY'
import os
import signal
import subprocess
import sys

process = subprocess.Popen(sys.argv[1:], start_new_session=True)
exit_code = process.wait()
try:
    os.killpg(process.pid, signal.SIGTERM)
except ProcessLookupError:
    pass
sys.exit(exit_code)
PY
}

read_only_transfer_checkpoint() {
  if [[ "${DAC_CODEX_TEST_READ_ONLY_TRANSFER_PATH:-}" != "$OUTPUT_RELATIVE" ]]; then
    return 0
  fi
  local ready_path="${DAC_CODEX_TEST_READ_ONLY_TRANSFER_READY_FILE:-}"
  local release_path="${DAC_CODEX_TEST_READ_ONLY_TRANSFER_RELEASE_FILE:-}"
  [[ -n "$ready_path" && -n "$release_path" ]] || blocked '只读 output 转移检查点缺少 sentinel 路径'
  : > "$ready_path"
  while [[ ! -e "$release_path" ]]; do
    sleep 0.01
  done
  return 0
}

transfer_read_only_output() {
  local source="$1" output_relative="$2"
  if ! python3 - "$source" "$output_relative" "$WORKSPACE" "$WORKSPACE_DEVICE" "$WORKSPACE_INODE" <<'PY'
import hashlib
import os
import secrets
import stat
import sys

source_path, output_relative, workspace_path, expected_device, expected_inode = sys.argv[1:]
if not all(hasattr(os, flag) for flag in ('O_DIRECTORY', 'O_NOFOLLOW', 'O_NONBLOCK')):
    raise RuntimeError('当前平台不支持安全打开 workspace 或 output 所需标志，拒绝转移')
if not output_relative or any(part in ('', '.', '..') for part in output_relative.split('/')):
    raise RuntimeError('output 相对路径无效')
FILE_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW

def open_output_parent(root_fd, relative):
    parts = relative.split('/')
    current = os.dup(root_fd)
    try:
        for part in parts[:-1]:
            child = os.open(part, DIRECTORY_FLAGS, dir_fd=current)
            os.close(current)
            current = child
        return current, parts[-1]
    except BaseException:
        os.close(current)
        raise

root_fd = os.open(workspace_path, DIRECTORY_FLAGS)
source_fd = os.open(source_path, FILE_FLAGS)
parent_fd = None
temporary = None
try:
    root_info = os.fstat(root_fd)
    if (
        not stat.S_ISDIR(root_info.st_mode)
        or (root_info.st_dev, root_info.st_ino) != (int(expected_device), int(expected_inode))
    ):
        raise RuntimeError('workspace 根目录在只读 output 转移前发生替换')
    source_info = os.fstat(source_fd)
    if not stat.S_ISREG(source_info.st_mode) or source_info.st_nlink != 1:
        raise RuntimeError('只读角色临时 output 不是普通单链接文件')

    parent_fd, output_name = open_output_parent(root_fd, output_relative)
    if not stat.S_ISDIR(os.fstat(parent_fd).st_mode):
        raise RuntimeError('output 父目录无效')
    try:
        existing = os.lstat(output_name, dir_fd=parent_fd)
    except FileNotFoundError:
        expected_target = None
    else:
        if not stat.S_ISREG(existing.st_mode) or existing.st_nlink != 1:
            raise RuntimeError('output 目标不是普通单链接文件')
        expected_target = (existing.st_dev, existing.st_ino)

    temporary = f'.dac-codex-read-only-{secrets.token_hex(16)}'
    destination_fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, stat.S_IMODE(source_info.st_mode), dir_fd=parent_fd)
    source_digest = hashlib.sha256()
    try:
        while True:
            chunk = os.read(source_fd, 1024 * 1024)
            if not chunk:
                break
            source_digest.update(chunk)
            view = memoryview(chunk)
            while view:
                written = os.write(destination_fd, view)
                if written <= 0:
                    raise RuntimeError('只读角色 output 写入失败')
                view = view[written:]
        os.fsync(destination_fd)
        temporary_info = os.fstat(destination_fd)
        if not stat.S_ISREG(temporary_info.st_mode) or temporary_info.st_nlink != 1:
            raise RuntimeError('内部临时 output 不是普通单链接文件')
    finally:
        os.close(destination_fd)

    source_after = os.fstat(source_fd)
    if (source_after.st_dev, source_after.st_ino, source_after.st_nlink) != (source_info.st_dev, source_info.st_ino, 1):
        raise RuntimeError('只读角色临时 output 在转移期间发生变化')
    os.lseek(source_fd, 0, os.SEEK_SET)
    verified_digest = hashlib.sha256()
    while True:
        chunk = os.read(source_fd, 1024 * 1024)
        if not chunk:
            break
        verified_digest.update(chunk)
    if verified_digest.digest() != source_digest.digest():
        raise RuntimeError('只读角色临时 output 内容在转移期间发生变化')
    try:
        current = os.lstat(output_name, dir_fd=parent_fd)
    except FileNotFoundError:
        current_target = None
    else:
        if not stat.S_ISREG(current.st_mode) or current.st_nlink != 1:
            raise RuntimeError('output 目标在转移前变为不安全文件')
        current_target = (current.st_dev, current.st_ino)
    if current_target != expected_target:
        raise RuntimeError('output 目标在转移期间发生变化')
    temporary_fd = os.open(temporary, FILE_FLAGS, dir_fd=parent_fd)
    try:
        current_temporary = os.fstat(temporary_fd)
        if (
            not stat.S_ISREG(current_temporary.st_mode)
            or current_temporary.st_nlink != 1
            or (current_temporary.st_dev, current_temporary.st_ino) != (temporary_info.st_dev, temporary_info.st_ino)
        ):
            raise RuntimeError('内部临时 output 在替换前发生变化')
        temporary_digest = hashlib.sha256()
        while True:
            chunk = os.read(temporary_fd, 1024 * 1024)
            if not chunk:
                break
            temporary_digest.update(chunk)
        if temporary_digest.digest() != source_digest.digest():
            raise RuntimeError('内部临时 output 内容校验失败')
    finally:
        os.close(temporary_fd)
    os.replace(temporary, output_name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
    os.fsync(parent_fd)
    temporary = None
finally:
    if temporary is not None and parent_fd is not None:
        try:
            os.unlink(temporary, dir_fd=parent_fd)
        except FileNotFoundError:
            pass
    if parent_fd is not None:
        os.close(parent_fd)
    os.close(source_fd)
    os.close(root_fd)
PY
  then
    blocked '只读角色 output 不符合安全转移协议'
  fi
}

controlled_merge() {
  local mode="${1:-merge}"
  python3 - "$WORKSPACE" "$STAGING_WORKSPACE" "$REAL_SNAPSHOT_READY" "$CHANGE_MANIFEST" "$mode" "$WORKSPACE_DEVICE" "$WORKSPACE_INODE" <<'PY'
import fcntl
import hashlib
import json
import os
import secrets
import stat
import sys
import time

real_root, staging_root, baseline_path, manifest_path, mode, expected_device, expected_inode = sys.argv[1:]
real_root = os.path.abspath(real_root)
CONTROL_DIR = '.dac/tmp'
LOCK_NAME = 'codex-role-merge.lock'
JOURNAL_NAME = 'codex-role-merge.txn.json'
BACKUP_ROOT = 'codex-role-merge-backups'
if not all(hasattr(os, flag) for flag in ('O_DIRECTORY', 'O_NOFOLLOW', 'O_NONBLOCK')):
    raise RuntimeError('当前平台不支持安全受控合并所需标志')
DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
FILE_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK

def fsync_dir(fd): os.fsync(fd)
def valid_relative(path): return bool(path) and all(part and part not in ('.', '..') for part in path.split('/'))
def protected(path): return path == f'{CONTROL_DIR}/{LOCK_NAME}' or path == f'{CONTROL_DIR}/{JOURNAL_NAME}' or path.startswith(f'{CONTROL_DIR}/{BACKUP_ROOT}/')

def open_root(path, expected=None):
    fd = os.open(path, DIRECTORY_FLAGS)
    try:
        info = os.fstat(fd)
        if not stat.S_ISDIR(info.st_mode): raise RuntimeError(f'非安全 workspace 根目录: {path}')
        if expected is not None and (info.st_dev, info.st_ino) != expected:
            raise RuntimeError(f'workspace 根目录在受控合并前发生替换: {path}')
        return fd
    except BaseException:
        os.close(fd); raise

def open_dir_path(root_fd, relative, create=False):
    if relative and not valid_relative(relative): raise RuntimeError(f'非法目录路径: {relative!r}')
    current = os.dup(root_fd)
    try:
        for part in ([] if not relative else relative.split('/')):
            try: child = os.open(part, DIRECTORY_FLAGS, dir_fd=current)
            except FileNotFoundError:
                if not create: raise
                os.mkdir(part, 0o700, dir_fd=current); fsync_dir(current)
                child = os.open(part, DIRECTORY_FLAGS, dir_fd=current)
            os.close(current); current = child
        return current
    except BaseException:
        os.close(current); raise

def open_parent(root_fd, relative, create=False):
    if not valid_relative(relative): raise RuntimeError(f'非法相对路径: {relative!r}')
    parts = relative.split('/')
    return open_dir_path(root_fd, '/'.join(parts[:-1]), create), parts[-1]

def metadata_from_fd(fd, relative):
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1: raise RuntimeError(f'非安全普通文件: {relative}')
    digest = hashlib.sha256()
    position = os.lseek(fd, 0, os.SEEK_CUR)
    os.lseek(fd, 0, os.SEEK_SET)
    try:
        with os.fdopen(os.dup(fd), 'rb') as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b''): digest.update(chunk)
    finally:
        os.lseek(fd, position, os.SEEK_SET)
    return ['file', stat.S_IMODE(info.st_mode), digest.hexdigest()]

def checked_file(parent_fd, name, expected, relative):
    fd = os.open(name, FILE_FLAGS, dir_fd=parent_fd)
    try:
        actual = metadata_from_fd(fd, relative)
        if expected is not None and actual != expected: raise RuntimeError(f'文件内容在校验后发生变化: {relative}')
        os.lseek(fd, 0, os.SEEK_SET)
        return fd
    except BaseException:
        os.close(fd); raise

def current_metadata(root_fd, relative):
    parent, name = open_parent(root_fd, relative, False)
    try:
        try: entry = os.lstat(name, dir_fd=parent)
        except FileNotFoundError: return None
        if not stat.S_ISREG(entry.st_mode) or entry.st_nlink != 1: raise RuntimeError(f'恢复目标不是安全普通文件: {relative}')
        fd = checked_file(parent, name, None, relative)
        try: return metadata_from_fd(fd, relative)
        finally: os.close(fd)
    finally: os.close(parent)

def assert_missing(parent_fd, name, relative):
    try: entry = os.lstat(name, dir_fd=parent_fd)
    except FileNotFoundError: return
    if stat.S_ISLNK(entry.st_mode) or not stat.S_ISREG(entry.st_mode) or entry.st_nlink != 1: raise RuntimeError(f'目标路径不安全: {relative}')
    raise RuntimeError(f'目标文件意外存在: {relative}')

def copy_file(source_root_fd, target_root_fd, relative, expected_source, expected_target, create_parent=False):
    source_parent, source_name = open_parent(source_root_fd, relative, False)
    target_parent = source_fd = None; temporary = None
    try:
        source_fd = checked_file(source_parent, source_name, expected_source, relative)
        target_parent, target_name = open_parent(target_root_fd, relative, create_parent)
        if expected_target is None: assert_missing(target_parent, target_name, relative)
        else:
            target_fd = checked_file(target_parent, target_name, expected_target, relative); os.close(target_fd)
        temporary = f'.dac-codex-{secrets.token_hex(16)}'
        output_fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, expected_source[1], dir_fd=target_parent)
        digest = hashlib.sha256()
        with os.fdopen(output_fd, 'wb') as output, os.fdopen(os.dup(source_fd), 'rb') as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b''):
                digest.update(chunk); output.write(chunk)
            output.flush(); os.fsync(output.fileno())
        if metadata_from_fd(source_fd, relative) != expected_source or digest.hexdigest() != expected_source[2]: raise RuntimeError(f'复制期间源文件发生变化: {relative}')
        if expected_target is None: assert_missing(target_parent, target_name, relative)
        else:
            target_fd = checked_file(target_parent, target_name, expected_target, relative); os.close(target_fd)
        os.replace(temporary, target_name, src_dir_fd=target_parent, dst_dir_fd=target_parent); fsync_dir(target_parent); temporary = None
    finally:
        if temporary is not None and target_parent is not None:
            try: os.unlink(temporary, dir_fd=target_parent)
            except FileNotFoundError: pass
        if source_fd is not None: os.close(source_fd)
        if target_parent is not None: os.close(target_parent)
        os.close(source_parent)

def delete_file(root_fd, relative, expected):
    parent, name = open_parent(root_fd, relative, False)
    try:
        fd = checked_file(parent, name, expected, relative); os.close(fd)
        os.unlink(name, dir_fd=parent); fsync_dir(parent)
    finally: os.close(parent)

def copy_backup(real_fd, backup_fd, relative, expected):
    parent, name = open_parent(real_fd, relative, False)
    backup_parent = source_fd = None
    try:
        source_fd = checked_file(parent, name, expected, relative)
        backup_parent, backup_name = open_parent(backup_fd, relative, True)
        output_fd = os.open(backup_name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, expected[1], dir_fd=backup_parent)
        with os.fdopen(output_fd, 'wb') as output, os.fdopen(os.dup(source_fd), 'rb') as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b''): output.write(chunk)
            output.flush(); os.fsync(output.fileno())
        if metadata_from_fd(source_fd, relative) != expected: raise RuntimeError(f'备份期间真实文件发生变化: {relative}')
        verify = checked_file(backup_parent, backup_name, expected, relative); os.close(verify); fsync_dir(backup_parent)
    finally:
        if source_fd is not None: os.close(source_fd)
        if backup_parent is not None: os.close(backup_parent)
        os.close(parent)

def snapshot(root_fd):
    entries = {'.': ['directory', stat.S_IMODE(os.fstat(root_fd).st_mode)]}
    def walk(directory_fd, prefix):
        for name in sorted(os.listdir(directory_fd)):
            if not prefix and name == '.git':
                continue
            relative = f'{prefix}/{name}' if prefix else name
            info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            if stat.S_ISDIR(info.st_mode):
                entries[relative] = ['directory', stat.S_IMODE(info.st_mode)]
                child = os.open(name, DIRECTORY_FLAGS, dir_fd=directory_fd)
                try: walk(child, relative)
                finally: os.close(child)
            elif stat.S_ISREG(info.st_mode):
                if info.st_nlink != 1: raise RuntimeError(f'快照检测到硬链接: {relative}')
                fd = checked_file(directory_fd, name, None, relative)
                try: entries[relative] = metadata_from_fd(fd, relative)
                finally: os.close(fd)
            else: raise RuntimeError(f'快照检测到不安全条目: {relative}')
    walk(root_fd, '')
    return entries

def load_journal(tmp_fd):
    try: fd = os.open(JOURNAL_NAME, FILE_FLAGS, dir_fd=tmp_fd)
    except FileNotFoundError: return None
    try:
        journal_info = os.fstat(fd)
        if not stat.S_ISREG(journal_info.st_mode) or journal_info.st_nlink != 1:
            raise RuntimeError('事务日志不是安全普通单链接文件')
        size = journal_info.st_size
        if size > 16 * 1024 * 1024: raise RuntimeError('事务日志过大')
        journal = json.loads(os.read(fd, size + 1).decode('utf-8'))
    finally: os.close(fd)
    if journal.get('version') != 1 or journal.get('state') != 'active' or not isinstance(journal.get('entries'), list): raise RuntimeError('事务日志格式无效，拒绝覆盖 workspace')
    transaction = journal.get('transaction')
    if not isinstance(transaction, str) or not transaction or any(char not in '0123456789abcdef' for char in transaction): raise RuntimeError('事务日志 transaction 无效')
    for entry in journal['entries']:
        if set(entry) != {'path', 'old', 'new', 'backup', 'status'} or not valid_relative(entry['path']) or protected(entry['path']): raise RuntimeError('事务日志条目无效')
        if entry['status'] not in ('prepared', 'committed'): raise RuntimeError('事务日志状态无效')
        if entry['old'] is None and entry['backup'] is not None: raise RuntimeError('新增文件不应包含备份')
        if entry['old'] is not None and entry['backup'] != entry['path']: raise RuntimeError('事务备份路径无效')
    return journal

def write_journal(tmp_fd, journal):
    temporary = f'.codex-role-merge-{secrets.token_hex(16)}'
    payload = json.dumps(journal, sort_keys=True, separators=(',', ':')).encode('utf-8')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=tmp_fd)
    try:
        pending = memoryview(payload)
        while pending:
            written = os.write(fd, pending)
            if written <= 0: raise RuntimeError('事务日志写入失败')
            pending = pending[written:]
        os.fsync(fd)
    finally: os.close(fd)
    os.replace(temporary, JOURNAL_NAME, src_dir_fd=tmp_fd, dst_dir_fd=tmp_fd); fsync_dir(tmp_fd)

def remove_journal(tmp_fd):
    try: os.unlink(JOURNAL_NAME, dir_fd=tmp_fd)
    except FileNotFoundError: return
    fsync_dir(tmp_fd)

def remove_backup_tree(parent_fd, name, relative):
    entry = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    if not stat.S_ISDIR(entry.st_mode): raise RuntimeError(f'事务备份包含非目录根: {relative}')
    directory_fd = os.open(name, DIRECTORY_FLAGS, dir_fd=parent_fd)
    try:
        for child in sorted(os.listdir(directory_fd)):
            child_relative = f'{relative}/{child}'
            child_entry = os.stat(child, dir_fd=directory_fd, follow_symlinks=False)
            if stat.S_ISDIR(child_entry.st_mode):
                remove_backup_tree(directory_fd, child, child_relative)
            elif stat.S_ISREG(child_entry.st_mode) and child_entry.st_nlink == 1:
                os.unlink(child, dir_fd=directory_fd); fsync_dir(directory_fd)
            else:
                raise RuntimeError(f'事务备份包含不安全条目: {child_relative}')
    finally:
        os.close(directory_fd)
    os.rmdir(name, dir_fd=parent_fd); fsync_dir(parent_fd)

def remove_transaction_backup(real_fd, transaction):
    backup_root_fd = None
    try:
        backup_root_fd = open_dir_path(real_fd, f'{CONTROL_DIR}/{BACKUP_ROOT}', False)
    except FileNotFoundError:
        return
    try:
        try:
            entry = os.stat(transaction, dir_fd=backup_root_fd, follow_symlinks=False)
        except FileNotFoundError:
            return
        if not stat.S_ISDIR(entry.st_mode): raise RuntimeError(f'事务备份根不安全: {transaction}')
        remove_backup_tree(backup_root_fd, transaction, transaction)
    finally:
        os.close(backup_root_fd)

def cleanup_orphan_backups(real_fd, tmp_fd):
    if load_journal(tmp_fd) is not None:
        return
    backup_root_fd = None
    try:
        backup_root_fd = open_dir_path(real_fd, f'{CONTROL_DIR}/{BACKUP_ROOT}', False)
    except FileNotFoundError:
        return
    try:
        for transaction in sorted(os.listdir(backup_root_fd)):
            if not transaction or any(character not in '0123456789abcdef' for character in transaction):
                raise RuntimeError(f'孤儿事务备份目录名无效: {transaction}')
            remove_backup_tree(backup_root_fd, transaction, transaction)
    finally:
        os.close(backup_root_fd)

def restore_pending(real_fd, tmp_fd):
    journal = load_journal(tmp_fd)
    if journal is None: return
    transaction = journal['transaction']
    backup_fd = open_dir_path(real_fd, f'{CONTROL_DIR}/{BACKUP_ROOT}/{transaction}', False)
    try:
        for entry in reversed(journal['entries']):
            path, old, new = entry['path'], entry['old'], entry['new']
            current = current_metadata(real_fd, path)
            if old is None:
                if current is None: continue
                if current != new: raise RuntimeError(f'恢复拒绝覆盖未记录变化: {path}')
                delete_file(real_fd, path, new); continue
            if current_metadata(backup_fd, entry['backup']) != old: raise RuntimeError(f'恢复备份损坏: {path}')
            if current == old: continue
            if current == new:
                copy_file(backup_fd, real_fd, path, old, new); continue
            if current is None and new is None:
                parent, name = open_parent(real_fd, path, True)
                try: assert_missing(parent, name, path)
                finally: os.close(parent)
                copy_file(backup_fd, real_fd, path, old, None, True); continue
            raise RuntimeError(f'恢复拒绝覆盖未记录变化: {path}')
    finally:
        os.close(backup_fd)
    remove_journal(tmp_fd)
    remove_transaction_backup(real_fd, transaction)

def checkpoint(path, status):
    environment_key = 'DAC_CODEX_TEST_MERGE_PREPARED_PATH' if status == 'prepared' else 'DAC_CODEX_TEST_MERGE_AFTER_PATH'
    if os.environ.get(environment_key) == path:
        ready_path, release_path = os.environ.get('DAC_CODEX_TEST_MERGE_READY_FILE'), os.environ.get('DAC_CODEX_TEST_MERGE_RELEASE_FILE')
        if not ready_path or not release_path: raise RuntimeError('测试合并检查点缺少 sentinel 路径')
        process_path = os.environ.get('DAC_CODEX_TEST_MERGE_PROCESS_PID_FILE')
        if process_path:
            with open(process_path, 'w', encoding='utf-8') as process_file:
                process_file.write(str(os.getpid()))
                process_file.flush()
                os.fsync(process_file.fileno())
        with open(ready_path, 'w', encoding='utf-8') as ready: ready.flush(); os.fsync(ready.fileno())
        while not os.path.exists(release_path): time.sleep(0.01)

real_fd = open_root(real_root, (int(expected_device), int(expected_inode)))
try:
    tmp_fd = open_dir_path(real_fd, CONTROL_DIR, True)
    try:
        lock_fd = os.open(LOCK_NAME, os.O_RDWR | os.O_CREAT | getattr(os, 'O_NOFOLLOW', 0), 0o600, dir_fd=tmp_fd)
        try:
            lock_info = os.fstat(lock_fd)
            if not stat.S_ISREG(lock_info.st_mode) or lock_info.st_nlink != 1: raise RuntimeError('事务锁文件不安全')
            try: fcntl.flock(real_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error: raise RuntimeError('已有 Codex writer 正在执行受控合并') from error
            try: fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error: raise RuntimeError('已有 Codex writer 正在执行受控合并') from error
            lock_entry = os.lstat(LOCK_NAME, dir_fd=tmp_fd)
            if (lock_entry.st_dev, lock_entry.st_ino) != (lock_info.st_dev, lock_info.st_ino) or not stat.S_ISREG(lock_entry.st_mode) or lock_entry.st_nlink != 1:
                raise RuntimeError('事务锁文件在加锁期间发生替换')
            restore_pending(real_fd, tmp_fd)
            cleanup_orphan_backups(real_fd, tmp_fd)
            if mode == 'recover': sys.exit(0)
            if mode != 'merge': raise RuntimeError(f'未知受控合并模式: {mode}')
            with open(baseline_path, encoding='utf-8') as source: baseline = json.load(source)
            real_before = snapshot(real_fd)
            if real_before != baseline: raise RuntimeError('取得合并锁后真实 workspace 发生变化')
            changes = [json.loads(line) for line in open(manifest_path, encoding='utf-8')]
            if not changes: raise RuntimeError('受控合并清单为空')
            for item in changes:
                path, old, new = item['path'], item['old'], item['new']
                if protected(path) or path == '.' or (old and old[0] == 'directory') or (new and new[0] == 'directory'): raise RuntimeError(f'受控合并清单包含受保护路径或目录: {path}')
                if real_before.get(path) != old or (old is None and path in real_before): raise RuntimeError(f'真实 workspace 在合并前发生变化: {path}')
            transaction = secrets.token_hex(16)
            backup_fd = open_dir_path(real_fd, f'{CONTROL_DIR}/{BACKUP_ROOT}/{transaction}', True)
            journal = {'version': 1, 'state': 'active', 'transaction': transaction, 'entries': []}
            try:
                staging_fd = open_root(staging_root)
                try:
                    for item in changes:
                        path, old, new = item['path'], item['old'], item['new']
                        if old is not None: copy_backup(real_fd, backup_fd, path, old)
                        entry = {'path': path, 'old': old, 'new': new, 'backup': path if old is not None else None, 'status': 'prepared'}
                        journal['entries'].append(entry); write_journal(tmp_fd, journal); checkpoint(path, 'prepared')
                        if new is None: delete_file(real_fd, path, old)
                        else: copy_file(staging_fd, real_fd, path, new, old, old is None)
                        entry['status'] = 'committed'; write_journal(tmp_fd, journal); checkpoint(path, 'committed')
                    final_snapshot = snapshot(real_fd)
                    changed_targets = {item['path']: item['new'] for item in changes}
                    implicit_directories = set()
                    for path, expected in changed_targets.items():
                        if expected is None:
                            continue
                        parent = path.rpartition('/')[0]
                        while parent and parent not in real_before:
                            implicit_directories.add(parent)
                            parent = parent.rpartition('/')[0]
                    for path in sorted(set(real_before) | set(final_snapshot)):
                        if protected(path) or path == f'{CONTROL_DIR}/{BACKUP_ROOT}':
                            continue
                        if path in changed_targets:
                            expected = changed_targets[path]
                        elif path in implicit_directories:
                            expected = ['directory', final_snapshot[path][1]] if path in final_snapshot and final_snapshot[path][0] == 'directory' else None
                        else:
                            expected = real_before.get(path)
                        if final_snapshot.get(path) != expected:
                            raise RuntimeError(f'受控合并最终快照校验失败: {path}')
                    remove_journal(tmp_fd)
                except BaseException as merge_error:
                    try:
                        restore_pending(real_fd, tmp_fd)
                    except BaseException as rollback_error:
                        raise RuntimeError(f'受控合并失败且回滚未完成: {rollback_error}') from merge_error
                    raise
                finally: os.close(staging_fd)
            finally: os.close(backup_fd)
            remove_transaction_backup(real_fd, transaction)
        finally: os.close(lock_fd)
    finally: os.close(tmp_fd)
finally: os.close(real_fd)
PY
}

writer_initial_snapshot_checkpoint() {
  case "$ROLE" in
    code-generator|test-case-generator) ;;
    *) return 0 ;;
  esac
  local ready_path="${DAC_CODEX_TEST_WRITER_INITIAL_SNAPSHOT_READY_FILE:-}"
  local release_path="${DAC_CODEX_TEST_WRITER_INITIAL_SNAPSHOT_RELEASE_FILE:-}"
  [[ -z "$ready_path" && -z "$release_path" ]] && return 0
  [[ -n "$ready_path" && -n "$release_path" ]] || blocked 'writer 初始快照检查点缺少 sentinel 路径'
  : > "$ready_path"
  while [[ ! -e "$release_path" ]]; do
    sleep 0.01
  done
}

# Every role receives a whole-workspace preflight; read-only roles retain the
# real workspace, while writer roles are additionally isolated below.
writer_initial_snapshot_checkpoint
if ! write_snapshot "$WORKSPACE" "$WORKSPACE_DEVICE" "$WORKSPACE_INODE" >/dev/null; then
  blocked 'workspace 包含符号链接、普通文件硬链接或特殊文件'
fi

case "$ROLE" in
  code-generator|test-case-generator)
    [[ -n "$ALLOWED_PATHS_FILE" ]] || blocked "$ROLE 必须提供 --allowed-paths-file"
    controlled_merge recover || blocked '检测到未完成事务但恢复失败，拒绝继续 writer 合并'
    REAL_SNAPSHOT_INITIAL=$(mktemp "${TMPDIR:-/tmp}/dac-codex-real-initial.XXXXXX") || blocked '无法创建真实 workspace 快照'
    REAL_SNAPSHOT_READY=$(mktemp "${TMPDIR:-/tmp}/dac-codex-real-ready.XXXXXX") || blocked '无法创建真实 workspace 快照'
    STAGING_SNAPSHOT_BEFORE=$(mktemp "${TMPDIR:-/tmp}/dac-codex-staging-before.XXXXXX") || blocked '无法创建 staging 快照'
    STAGING_SNAPSHOT_AFTER=$(mktemp "${TMPDIR:-/tmp}/dac-codex-staging-after.XXXXXX") || blocked '无法创建 staging 快照'
    STAGING_SNAPSHOT_READY=$(mktemp "${TMPDIR:-/tmp}/dac-codex-staging-ready.XXXXXX") || blocked '无法创建 staging 快照'
    write_snapshot "$WORKSPACE" "$WORKSPACE_DEVICE" "$WORKSPACE_INODE" > "$REAL_SNAPSHOT_INITIAL" || blocked '无法创建真实 workspace 初始快照'
    STAGING_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dac-codex-staging.XXXXXX") || blocked '无法创建随机 staging workspace'
    chmod 700 "$STAGING_ROOT"
    STAGING_WORKSPACE="$STAGING_ROOT/workspace"
    clone_workspace || blocked '无法创建 staging workspace 克隆'
    write_snapshot "$WORKSPACE" "$WORKSPACE_DEVICE" "$WORKSPACE_INODE" > "$REAL_SNAPSHOT_READY" || blocked '无法创建真实 workspace 复制后快照'
    snapshot_matches "$REAL_SNAPSHOT_INITIAL" "$REAL_SNAPSHOT_READY" || blocked '复制 staging 期间真实 workspace 发生变化'
    write_snapshot "$STAGING_WORKSPACE" > "$STAGING_SNAPSHOT_BEFORE" || blocked 'staging 包含符号链接、普通文件硬链接或特殊文件'
    snapshot_matches "$REAL_SNAPSHOT_INITIAL" "$STAGING_SNAPSHOT_BEFORE" || blocked '复制 staging 期间真实 workspace 内容发生变化'
    PROMPT_RELATIVE="$(relative_workspace_path "$PROMPT_FILE")"
    OUTPUT_RELATIVE="$(relative_workspace_path "$OUTPUT_FILE")"
    ALLOWLIST_RELATIVE="$(relative_workspace_path "$ALLOWED_PATHS_FILE")"
    STAGING_PROMPT_FILE="$STAGING_WORKSPACE/$PROMPT_RELATIVE"
    STAGING_OUTPUT_FILE="$STAGING_WORKSPACE/$OUTPUT_RELATIVE"
    STAGING_ALLOWLIST_FILE="$STAGING_WORKSPACE/$ALLOWLIST_RELATIVE"
    [[ -f "$STAGING_PROMPT_FILE" && -f "$STAGING_ALLOWLIST_FILE" ]] || blocked 'staging 未包含 prompt 或 allowlist'
    CODEX_EXIT=0
    run_codex "$STAGING_WORKSPACE" workspace-write "$STAGING_PROMPT_FILE" "$STAGING_OUTPUT_FILE" || CODEX_EXIT=$?
    [[ "$CODEX_EXIT" -eq 0 ]] || exit "$CODEX_EXIT"
    write_snapshot "$STAGING_WORKSPACE" > "$STAGING_SNAPSHOT_AFTER" || blocked 'Codex 在 staging 创建了链接、硬链接或特殊文件'
    validate_staging_output
    build_and_validate_manifest
    write_snapshot "$STAGING_WORKSPACE" > "$STAGING_SNAPSHOT_READY" || blocked '无法创建 staging 合并前快照'
    snapshot_matches "$STAGING_SNAPSHOT_AFTER" "$STAGING_SNAPSHOT_READY" || blocked 'staging 在校验后发生变化'
    controlled_merge merge || blocked '受控合并失败，真实 workspace 未完成合并'
    ;;
  *)
    # Read-only roles run in the real workspace only after the full-tree
    # preflight above. Their user-facing output is transferred only after
    # validating an externally created temporary file and the target path.
    READ_ONLY_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/dac-codex-read-only-output.XXXXXX") || blocked '无法创建只读角色临时 output'
    OUTPUT_RELATIVE="$(relative_workspace_path "$OUTPUT_FILE")"
    CODEX_EXIT=0
    run_codex "$WORKSPACE" read-only "$PROMPT_FILE" "$READ_ONLY_OUTPUT" || CODEX_EXIT=$?
    [[ "$CODEX_EXIT" -eq 0 ]] || exit "$CODEX_EXIT"
    read_only_transfer_checkpoint
    transfer_read_only_output "$READ_ONLY_OUTPUT" "$OUTPUT_RELATIVE"
    ;;
esac
