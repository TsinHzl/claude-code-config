#!/usr/bin/env bash
# test-skill-runtime-paths.sh — Skill 编排文档不得依赖 Claude-only 安装根
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
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

TARGETS=(
  SKILL.md
  references
  prompts
  templates
  skills
)

printf '═══ test-skill-runtime-paths.sh ═══\n\n'

markdown_files=$(cd "$ROOT_DIR" && find "${TARGETS[@]}" -type f -name '*.md')
legacy_paths=$(cd "$ROOT_DIR" && grep -En '(~|\$\{?HOME\}?)/\.claude' $markdown_files || true)
assert_eq '编排 Markdown 不含 Claude-only 安装根' '' "$legacy_paths"

runtime_paths=$(cd "$ROOT_DIR" && grep -En '\$\{?DAC_SKILL_HOME\}?' $markdown_files || true)
assert_eq '编排 Markdown 使用运行时 Skill 根' true "$( [[ -n "$runtime_paths" ]] && printf true || printf false )"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
