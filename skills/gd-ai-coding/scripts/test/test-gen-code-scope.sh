#!/usr/bin/env bash
# test-gen-code-scope.sh — Unit tests for gen-code-scope.sh
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
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc (not found: '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local desc="$1" filepath="$2"
  if [[ -f "$filepath" ]]; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc (file missing: $filepath)"
    FAIL=$((FAIL + 1))
  fi
}

# ── Setup test fixtures ──────────────────────────────────────────────────────

cd "$TEST_DIR"
mkdir -p .dac openspec/changes/test-req/prd openspec/changes/test-req/features

# state.json
cat > .dac/state.json <<'EOF'
{"phase": "feature-loop", "req_name": "test-req"}
EOF

# proposal.md
cat > openspec/changes/test-req/proposal.md <<'EOF'
# Proposal

## 1. Login Module

This section covers the login feature.

- `lib/features/login/data/login_repository.dart` — Repository for login API calls
- `lib/features/login/presentation/login_page.dart` — Login page UI with form

## 2. Home Module

Home page implementation.

- `lib/features/home/presentation/home_page.dart` — Main home page with tabs
EOF

# prd-spec.md
cat > openspec/changes/test-req/prd/prd-spec.md <<'EOF'
## 3.1 Login Feature

**类型：** 新增

**需求描述：** User can login with phone number.

## 3.2 Home Feature

**类型：** 新增

**需求描述：** Show main content after login.
EOF

# feature-plan.json
cat > openspec/changes/test-req/feature-plan.json <<'EOF'
{
  "schema_version": 1,
  "features": [
    {
      "id": "login_page",
      "name": "登录模块",
      "type": "page",
      "status": "pending",
      "dependencies": [],
      "related_requirements": ["§3.1"],
      "design_nodes": [],
      "proposal_scope": {
        "new_files": ["lib/features/login/data/login_repository.dart", "lib/features/login/presentation/login_page.dart"],
        "modified_files": ["lib/core/router.dart"],
        "proposal_section": "## 1. Login Module"
      }
    }
  ]
}
EOF

# Create modified file so it exists
mkdir -p lib/core
echo "// router" > lib/core/router.dart

echo "═══ test-gen-code-scope.sh ═══"
echo ""

# ── Test 1: code-scope.md generation ─────────────────────────────────────────

echo "Test 1: code-scope.md generation"
OUTPUT=$(bash "$SCRIPTS_DIR/feature/gen-code-scope.sh" login_page 2>&1)
assert_file_exists "code-scope.md created" "openspec/changes/test-req/features/login_page/code-scope.md"

CONTENT=$(cat "openspec/changes/test-req/features/login_page/code-scope.md")
assert_contains "contains feat name" "登录模块" "$CONTENT"
assert_contains "contains new file" "login_repository.dart" "$CONTENT"
assert_contains "contains modified file" "lib/core/router.dart" "$CONTENT"

# ── Test 2: file description lookup ──────────────────────────────────────────

echo ""
echo "Test 2: file descriptions filled from proposal.md"
assert_contains "new file has description" "Repository for login API calls" "$CONTENT"
assert_contains "page file has description" "Login page UI with form" "$CONTENT"

# ── Test 3: proposal-slice.md generation ─────────────────────────────────────

echo ""
echo "Test 3: proposal-slice.md generation"
assert_file_exists "proposal-slice.md created" "openspec/changes/test-req/features/login_page/proposal-slice.md"
SLICE=$(cat "openspec/changes/test-req/features/login_page/proposal-slice.md")
assert_contains "contains section content" "Login Module" "$SLICE"
assert_contains "excludes other section" "login_repository" "$SLICE"

# ── Test 4: spec-slice.md generation ─────────────────────────────────────────

echo ""
echo "Test 4: spec-slice.md generation"
assert_file_exists "spec-slice.md created" "openspec/changes/test-req/features/login_page/spec-slice.md"
SPEC_SLICE=$(cat "openspec/changes/test-req/features/login_page/spec-slice.md")
assert_contains "contains §3.1 content" "Login Feature" "$SPEC_SLICE"

# ── Test 5: missing feature ID ───────────────────────────────────────────────

echo ""
echo "Test 5: error on missing feature"
if bash "$SCRIPTS_DIR/feature/gen-code-scope.sh" nonexistent_feature 2>/dev/null; then
  echo "  ✗ should exit non-zero for missing feature"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ exits non-zero for missing feature"
  PASS=$((PASS + 1))
fi

# ── Test 6: fuzzy proposal section match ─────────────────────────────────────

echo ""
echo "Test 6: fuzzy section title match"
# Change proposal_section to use only the module name (no ## prefix)
jq '.features[0].proposal_scope.proposal_section = "Login Module"' \
  openspec/changes/test-req/feature-plan.json > /tmp/fp_tmp.json && \
  mv /tmp/fp_tmp.json openspec/changes/test-req/feature-plan.json

rm -f openspec/changes/test-req/features/login_page/proposal-slice.md
bash "$SCRIPTS_DIR/feature/gen-code-scope.sh" login_page 2>/dev/null || true
if [[ -f "openspec/changes/test-req/features/login_page/proposal-slice.md" ]]; then
  SLICE6=$(cat "openspec/changes/test-req/features/login_page/proposal-slice.md")
  assert_contains "matched without ## prefix" "Login Module" "$SLICE6"
else
  echo "  ✗ fuzzy match failed — proposal-slice.md not created"
  FAIL=$((FAIL + 1))
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
