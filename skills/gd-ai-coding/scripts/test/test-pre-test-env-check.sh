#!/usr/bin/env bash
# test-pre-test-env-check.sh — pre-test-env-check.sh 已声明/未声明依赖两种 fixture + 非 flutter 平台跳过
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/.."
CHECK="$SCRIPTS_DIR/checks/pre-test-env-check.sh"
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

cd "$TEST_DIR"

# ── fixture 1：依赖已声明 ──
cat > pubspec.yaml <<'EOF'
name: demo
dev_dependencies:
  flutter_test:
    sdk: flutter
  mocktail: ^1.0.0
EOF

set +e
out=$(bash "$CHECK" feat-a 2>&1)
code=$?
set -e
assert_eq "依赖已声明 exit 0" "0" "$code"
assert_eq "依赖已声明输出通过信息" "true" "$(echo "$out" | grep -q "测试环境检查通过" && echo true || echo false)"

# ── fixture 2：mockito 依赖已声明 ──
cat > pubspec.yaml <<'EOF'
name: demo
dev_dependencies:
  flutter_test:
    sdk: flutter
  mockito: ^5.0.0
EOF

set +e
out=$(bash "$CHECK" feat-a 2>&1)
code=$?
set -e
assert_eq "mockito 依赖已声明 exit 0" "0" "$code"
assert_eq "mockito 依赖已声明输出通过信息" "true" "$(echo "$out" | grep -q "测试环境检查通过" && echo true || echo false)"

# ── fixture 3：依赖未声明 ──
cat > pubspec.yaml <<'EOF'
name: demo
dependencies:
  flutter:
    sdk: flutter
EOF

set +e
out=$(bash "$CHECK" feat-a 2>&1)
code=$?
set -e
assert_eq "依赖未声明 exit 1" "1" "$code"
assert_eq "错误信息包含 DAC-GEN-012" "true" "$(echo "$out" | grep -q "DAC-GEN-012" && echo true || echo false)"
assert_eq "错误信息列出缺失的 flutter_test" "true" "$(echo "$out" | grep -q "flutter_test" && echo true || echo false)"
assert_eq "错误信息列出缺失的 mocktail" "true" "$(echo "$out" | grep -q "mocktail" && echo true || echo false)"

# ── fixture 4：pubspec.yaml 不存在 ──
rm -f pubspec.yaml
set +e
out=$(bash "$CHECK" feat-a 2>&1)
code=$?
set -e
assert_eq "pubspec.yaml 不存在 exit 1" "1" "$code"

# ── fixture 5：非 flutter 平台跳过 ──
set +e
out=$(PLATFORM=vue bash "$CHECK" feat-a 2>&1)
code=$?
set -e
assert_eq "非 flutter 平台 exit 0" "0" "$code"
assert_eq "非 flutter 平台输出跳过信息" "true" "$(echo "$out" | grep -q "跳过" && echo true || echo false)"

echo ""
echo "通过: $PASS / 失败: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
