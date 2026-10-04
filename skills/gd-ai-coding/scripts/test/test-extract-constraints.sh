#!/usr/bin/env bash
# test-extract-constraints.sh — Unit tests for extract-constraints.sh
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

assert_not_contains() {
  local desc="$1" needle="$2" filepath="$3"
  if ! grep -qF "$needle" "$filepath" 2>/dev/null; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc (should NOT be found: '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

# ── Setup test fixtures ──────────────────────────────────────────────────────

cd "$TEST_DIR"
mkdir -p .dac/knowledge openspec/changes/test-req/features/login_page

cat > .dac/state.json <<'EOF'
{"phase": "feature-loop", "req_name": "test-req"}
EOF

cat > .dac/knowledge/constraints.md <<'EOF'
# 项目约束积累

> 本文件由 extract-constraints.sh 自动追加。
EOF

echo "═══ test-extract-constraints.sh ═══"
echo ""

# ── Test 1: extract from report with issues ──────────────────────────────────

echo "Test 1: extract constraints from CR report"
cat > openspec/changes/test-req/features/login_page/cr-report.md <<'EOF'
# CR 报告：登录模块

## verdict: with_issues

### 🔴 严重（必须修复）
1. **[功能完整性]** `lib/features/login/login_page.dart:42` 未处理空态
   - 建议修复：增加 EmptyState widget

### 🟡 一般（建议修复）
1. **[数据正确性]** `lib/features/login/data/models/user_model.dart:15` JSON 字段不匹配
   - 建议：添加 @JsonKey 注解

### 🔵 建议（可选）
1. 变量命名可优化
EOF

bash "$SCRIPTS_DIR/knowledge/extract-constraints.sh" login_page

assert_contains "🔴 issue extracted" "功能完整性" ".dac/knowledge/constraints.md"
assert_contains "🟡 issue extracted" "数据正确性" ".dac/knowledge/constraints.md"
assert_not_contains "🔵 not extracted" "变量命名" ".dac/knowledge/constraints.md"
assert_contains "source header" "login_page" ".dac/knowledge/constraints.md"

# ── Test 2: dedup on same day + feat_id ──────────────────────────────────────

echo ""
echo "Test 2: dedup prevents duplicate extraction"
BEFORE=$(wc -l < .dac/knowledge/constraints.md)
OUTPUT=$(bash "$SCRIPTS_DIR/knowledge/extract-constraints.sh" login_page 2>&1)
AFTER=$(wc -l < .dac/knowledge/constraints.md)
assert_eq "no lines added on re-run" "$BEFORE" "$AFTER"

# ── Test 3: clean report produces no extraction ──────────────────────────────

echo ""
echo "Test 3: clean verdict produces no extraction"
mkdir -p openspec/changes/test-req/features/home_page
cat > openspec/changes/test-req/features/home_page/cr-report.md <<'EOF'
# CR 报告：首页模块

## verdict: clean

6 维度检查全部通过，无问题。
EOF

OUTPUT=$(bash "$SCRIPTS_DIR/knowledge/extract-constraints.sh" home_page 2>&1)
assert_not_contains "no home_page header" "home_page" ".dac/knowledge/constraints.md"

# ── Test 4: missing report file ──────────────────────────────────────────────

echo ""
echo "Test 4: error on missing cr-report.md"
if bash "$SCRIPTS_DIR/knowledge/extract-constraints.sh" nonexistent_feature 2>/dev/null; then
  echo "  ✗ should exit non-zero for missing report"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ exits non-zero for missing report"
  PASS=$((PASS + 1))
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
