#!/usr/bin/env bash
# test-copy-design-assets.sh — skip_feature_plan 未回填 features[] 时的兜底
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

cd "$TEST_DIR"
mkdir -p .dac openspec/changes/test-req/ui/001 openspec/changes/test-req/features

cat > .dac/state.json <<'EOF'
{"phase":"feature-planned","req_name":"test-req"}
EOF

cat > openspec/changes/test-req/feature-plan.json <<'EOF'
[
  {
    "id": "feat-01",
    "name": "Login",
    "description": "login",
    "type": "page",
    "dependencies": [],
    "related_requirements": [],
    "proposal_scope": {"new_files": [], "modified_files": [], "proposal_section": ""},
    "status": "pending"
  }
]
EOF

cat > openspec/changes/test-req/ui/index.json <<'EOF'
[
  {
    "id": "ds_001",
    "features": [],
    "node_name": "Login",
    "dir": "001",
    "status": "ok",
    "mapping": "pending"
  }
]
EOF

echo '{"nodes":[{"id":1}]}' > openspec/changes/test-req/ui/001/ui_dsl.json
echo "tree" > openspec/changes/test-req/ui/001/ui_tree.txt

echo "Test 1: empty features[] + single feat-01 copies assets"
bash "$SCRIPTS_DIR/feature/copy-design-assets.sh" feat-01
assert_eq "copied ui_dsl.json" "true" "$( [[ -f openspec/changes/test-req/features/feat-01/ui_dsl.json ]] && echo true || echo false )"
LINKED=$(jq -r '.[0].features[0]' openspec/changes/test-req/ui/index.json)
assert_eq "persisted features backfill" "feat-01" "$LINKED"

echo "Test 2: no match when plan has multiple features"
cat > openspec/changes/test-req/feature-plan.json <<'EOF'
[
  {"id":"feat-01","name":"A","description":"a","type":"page","dependencies":[],"related_requirements":[],"proposal_scope":{"new_files":[],"modified_files":[],"proposal_section":""},"status":"pending"},
  {"id":"feat-02","name":"B","description":"b","type":"page","dependencies":[],"related_requirements":[],"proposal_scope":{"new_files":[],"modified_files":[],"proposal_section":""},"status":"pending"}
]
EOF
cat > openspec/changes/test-req/ui/index.json <<'EOF'
[{"id":"ds_001","features":[],"node_name":"Login","dir":"001","status":"ok","mapping":"pending"}]
EOF
rm -rf openspec/changes/test-req/features/feat-01
set +e
bash "$SCRIPTS_DIR/feature/copy-design-assets.sh" feat-01
RC=$?
set -e
assert_eq "exit 2 when multi-feature and unlinked" "2" "$RC"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
