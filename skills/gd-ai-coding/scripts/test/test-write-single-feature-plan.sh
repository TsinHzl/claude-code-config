#!/usr/bin/env bash
# test-write-single-feature-plan.sh — unit tests for write-single-feature-plan.sh
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

cd "$TEST_DIR"
mkdir -p .dac openspec/changes/test-req/prd

cat > .dac/state.json <<'EOF'
{"phase":"prd-speced","req_name":"test-req","available_platforms":{"flutter":{}}}
EOF

cat > openspec/changes/test-req/proposal.md <<'EOF'
# Proposal

## 1. Login Module

This section covers the login feature.

- `lib/features/login/data/login_repository.dart` — Repository for login API calls
- `lib/features/login/presentation/login_page.dart` — Login page UI with form
EOF

cat > openspec/changes/test-req/prd/prd-spec.md <<'EOF'
### 3.1 Login Feature

**类型：** 新增
EOF

echo "Test 1: missing proposal.md fails"
rm -f openspec/changes/test-req/proposal.md
if bash "$SCRIPTS_DIR/feature/write-single-feature-plan.sh" >/tmp/wsp.out 2>/tmp/wsp.err; then
  echo "  ✗ should exit 1 without proposal.md"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ exits non-zero without proposal.md"
  PASS=$((PASS + 1))
fi

cat > openspec/changes/test-req/proposal.md <<'EOF'
# Proposal

## 1. Login Module

This section covers the login feature.

- `lib/features/login/data/login_repository.dart` — Repository for login API calls
- `lib/features/login/presentation/login_page.dart` — Login page UI with form
EOF

echo "Test 2: writes schema-valid single feature from proposal"
bash "$SCRIPTS_DIR/feature/write-single-feature-plan.sh"
assert_file_exists "feature-plan.json created" "openspec/changes/test-req/feature-plan.json"

ID=$(jq -r '.[0].id' openspec/changes/test-req/feature-plan.json)
assert_eq "id is feat-01" "feat-01" "$ID"

NEW_COUNT=$(jq -r '.[0].proposal_scope.new_files | length' openspec/changes/test-req/feature-plan.json)
assert_eq "two new files from backticks" "2" "$NEW_COUNT"

REL=$(jq -r '.[0].related_requirements[0]' openspec/changes/test-req/feature-plan.json)
assert_eq "related_requirements from spec" "§3.1 Login Feature" "$REL"

SEC=$(jq -r '.[0].proposal_scope.proposal_section' openspec/changes/test-req/feature-plan.json)
assert_eq "proposal_section from first ##" "## 1. Login Module" "$SEC"

echo "Test 3: backfills ui/index.json features onto feat-01"
mkdir -p openspec/changes/test-req/ui/001
cat > openspec/changes/test-req/ui/index.json <<'EOF'
[
  {
    "id": "ds_001",
    "source_link": "https://mastergo.com/file/1",
    "sections": [],
    "features": [],
    "node_name": "Login",
    "dir": "001",
    "status": "ok",
    "mapping": "pending"
  }
]
EOF
rm -f openspec/changes/test-req/feature-plan.json
bash "$SCRIPTS_DIR/feature/write-single-feature-plan.sh"
LINKED=$(jq -r '.[0].features[0]' openspec/changes/test-req/ui/index.json)
assert_eq "index.json features backfilled" "feat-01" "$LINKED"
MAP=$(jq -r '.[0].mapping' openspec/changes/test-req/ui/index.json)
assert_eq "mapping set to auto" "auto" "$MAP"

echo "Test 4: does not overwrite multi-feature plan"
cat > openspec/changes/test-req/feature-plan.json <<'EOF'
[
  {"id":"a","name":"A","description":"a","type":"page","dependencies":[],"related_requirements":["§3.1"],"proposal_scope":{"new_files":[],"modified_files":[],"proposal_section":""},"status":"pending"},
  {"id":"b","name":"B","description":"b","type":"page","dependencies":[],"related_requirements":["§3.1"],"proposal_scope":{"new_files":[],"modified_files":[],"proposal_section":""},"status":"pending"}
]
EOF
bash "$SCRIPTS_DIR/feature/write-single-feature-plan.sh" >/tmp/wsp2.out
COUNT=$(jq 'length' openspec/changes/test-req/feature-plan.json)
assert_eq "kept 2 features" "2" "$COUNT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
