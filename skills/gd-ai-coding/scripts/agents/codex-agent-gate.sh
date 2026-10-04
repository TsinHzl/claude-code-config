#!/usr/bin/env bash
# codex-agent-gate.sh — 验证 Codex 独立角色执行所需能力，缺失时 fail-closed。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../runtime.sh"
dac_resolve_runtime

ROLE="${1:-}"
readonly -a ROLES=(
  requirement-gap-checker
  code-generator
  test-case-generator
  test-case-verifier
  code-reviewer
)

usage() {
  printf '用法：%s <role>\n' "$(basename "$0")" >&2
  printf '可用角色：%s\n' "${ROLES[*]}" >&2
}

is_supported_role() {
  local candidate="$1" role
  for role in "${ROLES[@]}"; do
    [[ "$candidate" == "$role" ]] && return 0
  done
  return 1
}

blocked() {
  printf 'BLOCKED: role=%s; reason=%s; recovery=%s\n' "$ROLE" "$1" "$2" >&2
  exit 1
}

[[ -n "$ROLE" ]] || { usage; exit 2; }
is_supported_role "$ROLE" || { usage; exit 2; }
[[ "$DAC_RUNTIME" == "codex" ]] || blocked 'runtime_not_codex' '在 Codex 会话中重试，或使用 Claude 的 Agent 编排路径'
command -v codex >/dev/null 2>&1 || blocked 'codex_cli_missing' '安装 Codex CLI 并重新打开 Codex 会话'

FEATURES=$(codex features list 2>&1) || blocked 'feature_check_failed' '确认 Codex CLI 可执行并重新登录'
printf '%s\n' "$FEATURES" | grep -Eq '^multi_agent[[:space:]]+stable[[:space:]]+true([[:space:]]|$)' \
  || blocked 'multi_agent_unavailable' '启用支持 multi_agent 的 Codex 版本后重试'

PROBE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dac-codex-auth-probe.XXXXXX") || blocked 'authentication_probe_unavailable' '确认临时目录可写后重试'
trap 'rm -rf "$PROBE_DIR"' EXIT
PROBE_OUTPUT="$PROBE_DIR/output.txt"
codex exec \
  --sandbox read-only \
  --skip-git-repo-check \
  -C "$PROBE_DIR" \
  --output-last-message "$PROBE_OUTPUT" \
  '仅返回 DAC_AUTH_PROBE_OK。' >/dev/null 2>&1 \
  || blocked 'authentication_probe_failed' '检查 config.toml Provider、认证环境变量和网络连接后重试'
[[ -f "$PROBE_OUTPUT" && ! -L "$PROBE_OUTPUT" ]] \
  || blocked 'authentication_probe_failed' '检查 config.toml Provider、认证环境变量和网络连接后重试'
grep -qx 'DAC_AUTH_PROBE_OK' "$PROBE_OUTPUT" \
  || blocked 'authentication_probe_failed' '检查 config.toml Provider、认证环境变量和网络连接后重试'

ROLE_DIR="$DAC_SKILL_HOME/codex-agents/$ROLE"
SKILL_FILE="$ROLE_DIR/SKILL.md"
MANIFEST_FILE="$ROLE_DIR/agents/openai.yaml"
[[ -f "$SKILL_FILE" && ! -L "$SKILL_FILE" ]] \
  || blocked 'role_definition_missing' "重新安装 gd-ai-coding，确保 $SKILL_FILE 存在"
[[ -f "$MANIFEST_FILE" && ! -L "$MANIFEST_FILE" ]] \
  || blocked 'role_manifest_missing' "重新安装 gd-ai-coding，确保 $MANIFEST_FILE 存在"
EXPECTED_SKILL_NAME="dac-$ROLE"
grep -Fx "name: $EXPECTED_SKILL_NAME" "$SKILL_FILE" >/dev/null \
  || blocked 'role_definition_mismatch' "修复 ${SKILL_FILE}，使其角色标识为 ${EXPECTED_SKILL_NAME}"
python3 - "$MANIFEST_FILE" "$ROLE" <<'PY' \
  || blocked 'role_manifest_mismatch' "修复 ${MANIFEST_FILE}，使 interface.default_prompt 与 ${ROLE} 的预期值完全一致"
import re
import sys

EXPECTED_PROMPTS = {
    'requirement-gap-checker': (
        'Use $dac-requirement-gap-checker to independently check requirement coverage '
        'and return only evidence-backed findings.'
    ),
    'code-generator': (
        'Use $dac-code-generator to implement only the supplied scope and report '
        'verification evidence.'
    ),
    'test-case-generator': (
        'Use $dac-test-case-generator to create tests and scenarios from the supplied '
        'requirement slice.'
    ),
    'test-case-verifier': (
        'Use $dac-test-case-verifier to independently verify supplied UI scenarios '
        'against code.'
    ),
    'code-reviewer': (
        'Use $dac-code-reviewer to independently review the supplied change and return '
        'evidence-backed findings.'
    ),
}
SCALAR = re.compile(r'^  default_prompt: ("(?:[^"\\]|\\.)*")$')
TOP_LEVEL = re.compile(r'^[^ \t].*:$')
DEFAULT_PROMPT_KEY = re.compile(r'^[ \t]*default_prompt:')


def parse_double_quoted_scalar(scalar):
    body = scalar[1:-1]
    escapes = {
        '0': '\0', 'a': '\a', 'b': '\b', 't': '\t', 'n': '\n', 'v': '\v',
        'f': '\f', 'r': '\r', 'e': '\x1b', ' ': ' ', '"': '"', '/': '/', '\\': '\\',
        'N': '', '_': ' ', 'L': ' ', 'P': ' ',
    }
    value = []
    index = 0
    while index < len(body):
        char = body[index]
        if char != '\\':
            value.append(char)
            index += 1
            continue
        index += 1
        if index == len(body):
            raise ValueError('trailing escape')
        escape = body[index]
        if escape in escapes:
            value.append(escapes[escape])
            index += 1
            continue
        widths = {'x': 2, 'u': 4, 'U': 8}
        width = widths.get(escape)
        if width is None:
            raise ValueError('unsupported escape')
        digits = body[index + 1:index + 1 + width]
        if len(digits) != width or not re.fullmatch(r'[0-9A-Fa-f]+', digits):
            raise ValueError('invalid Unicode escape')
        codepoint = int(digits, 16)
        if 0xD800 <= codepoint <= 0xDFFF or codepoint > 0x10FFFF:
            raise ValueError('invalid Unicode code point')
        value.append(chr(codepoint))
        index += width + 1
    return ''.join(value)


manifest, role = sys.argv[1:]
expected = EXPECTED_PROMPTS.get(role)
if expected is None:
    raise SystemExit(1)
section = None
default_prompts = []
implicit_invocation = []
with open(manifest, encoding='utf-8') as source:
    for raw in source:
        line = raw.rstrip('\n')
        if not line or line.lstrip().startswith('#'):
            continue
        if TOP_LEVEL.fullmatch(line):
            section = line[:-1]
            continue
        if DEFAULT_PROMPT_KEY.match(line):
            scalar = SCALAR.fullmatch(line)
            if section != 'interface' or scalar is None:
                raise SystemExit(1)
            try:
                default_prompts.append(parse_double_quoted_scalar(scalar.group(1)))
            except ValueError:
                raise SystemExit(1)
        if section == 'policy' and line == '  allow_implicit_invocation: false':
            implicit_invocation.append(line)
if default_prompts != [expected] or len(implicit_invocation) != 1:
    raise SystemExit(1)
PY

printf 'PASS: role=%s; runtime=codex; authentication=probe_verified; multi_agent=available\n' "$ROLE"
