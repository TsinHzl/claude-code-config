#!/usr/bin/env bash
# test-merge-codegen-buckets.sh — 看板合并 TRACE /summary 时灌入 codegen/chat 行桶
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER="$SCRIPT_DIR/../metrics/dashboard-server.py"

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

echo "═══ test-merge-codegen-buckets.sh ═══"
echo ""

OUT=$(DASHBOARD_SERVER="$SERVER" python3 - <<'PY'
import importlib.util, os, json
spec = importlib.util.spec_from_file_location('dashboard_server', os.environ['DASHBOARD_SERVER'])
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)

person_map = {
    'alice': {
        'committer': 'alice@example.com',
        'requirements': [{'req_name': 'r1', 'lines_added': 1, 'last_commit_ts': 0, 'ddp': {'id': 'r1'}}],
    },
}
reqs_index = [{'req_name': 'r1', 'lines_added': 1, 'last_commit_ts': 0, 'ddp': {'id': 'r1'}}]
trace_list = [{
    'committer': 'alice@example.com',
    'committer_name': 'Alice',
    'requirements': [{
        'req_name': 'r1',
        'lines_added': 100,
        'lines_deleted': 2,
        'commit_count': 3,
        'codegen_lines_added': 40,
        'chat_lines_added': 60,
        'workflow_session_ids': ['s1'],
        'last_commit_ts': 1,
    }, {
        'req_name': 'orphan',
        'lines_added': 10,
        'codegen_lines_added': 7,
        'chat_lines_added': 3,
        'workflow_session_ids': ['s2'],
        'last_commit_ts': 2,
    }],
}]
server._merge_trace_data(person_map, reqs_index, trace_list)
matched = next(r for r in reqs_index if r['req_name'] == 'r1')
orphan = next(r for r in reqs_index if r['req_name'] == 'orphan')
print(json.dumps({
    'matched_codegen': matched.get('codegen_lines_added'),
    'matched_chat': matched.get('chat_lines_added'),
    'matched_lines': matched.get('lines_added'),
    'orphan_codegen': orphan.get('codegen_lines_added'),
    'person_codegen': person_map['alice']['requirements'][0].get('codegen_lines_added'),
}))
PY
)

assert_eq "匹配 DDP 需求灌入 codegen=40" "40" "$(printf '%s' "$OUT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["matched_codegen"])')"
assert_eq "匹配 DDP 需求灌入 chat=60" "60" "$(printf '%s' "$OUT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["matched_chat"])')"
assert_eq "人员列表同步 codegen=40" "40" "$(printf '%s' "$OUT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["person_codegen"])')"
assert_eq "trace-only orphan 带 codegen=7" "7" "$(printf '%s' "$OUT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["orphan_codegen"])')"

echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
