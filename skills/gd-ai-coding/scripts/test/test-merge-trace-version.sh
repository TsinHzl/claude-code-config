#!/usr/bin/env bash
# test-merge-trace-version.sh — Unit tests for transform-ddp.py merge_trace()._stamp_versions
#
# 覆盖 design 决策 4 的 name/time 取值表格（禁止跨源拼接）：
#   1. trace 自带 name 且与 index 相同 → name=trace(==index), time=index
#   2. trace 自带 name 但与 index 不同/index 缺 → name=trace, time=''（不附错日期）
#   3. trace 无 name, index 有 → name=index, time=index
#   4. trace 无 name, index 无 → 不写 ddp（结构不变）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRANSFORM="$SCRIPT_DIR/../metrics/transform-ddp.py"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

PASS=0
FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS + 1))
  else
    echo "  ✗ $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1))
  fi
}

# 用 Python 直接驱动 merge_trace，断言四行取值。结果以 "req_name|name|time|has_ddp" 逐行输出。
OUT=$(python3 - "$TRANSFORM" "$TEST_DIR" <<'PY'
import sys, json, importlib.util
transform_path, test_dir = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("t", transform_path)
t = importlib.util.module_from_spec(spec); spec.loader.exec_module(t)

dashboard = {
  "committers": [{"committer": "u@e.com", "requirements": []}],
  "requirements_index": [
    {"req_name": "653360-feat", "ddp": {"release_version_name": "Global司机端7.10.42", "release_version_time": "2026-07-30"}},
    {"req_name": "R-IBG-700001", "ddp": {"release_version_name": "Global司机端7.11.0", "release_version_time": "2026-08-15"}},
  ],
}
trace = {"u@e.com": [
  {"req_name": "653360-feat",  "release_version_name": "Global司机端7.10.42"},  # 行1
  {"req_name": "700001-old",   "release_version_name": "Global司机端7.9.0"},    # 行2（数字 id 700001 命中 index 7.11.0，异源）
  {"req_name": "R-IBG-700001"},                                                # 行3
  {"req_name": "999999-x"},                                                    # 行4
]}
tf = test_dir + "/trace.json"
with open(tf, "w", encoding="utf-8") as f:
    json.dump(trace, f, ensure_ascii=False)

t.merge_trace(dashboard, tf)
for r in dashboard["committers"][0]["requirements"]:
    ddp = r.get("ddp")
    if ddp is None:
        print(f'{r["req_name"]}||_|no')
    else:
        print(f'{r["req_name"]}|{ddp.get("release_version_name","")}|{ddp.get("release_version_time","")}|yes')
PY
)

echo "=== _stamp_versions 四行取值 ==="
row() { echo "$OUT" | grep "^$1|"; }

assert_eq "行1 同源: name=trace(==index)"     "Global司机端7.10.42" "$(row 653360-feat | cut -d'|' -f2)"
assert_eq "行1 同源: time=index"              "2026-07-30"          "$(row 653360-feat | cut -d'|' -f3)"
assert_eq "行2 异源: name=trace"              "Global司机端7.9.0"   "$(row 700001-old | cut -d'|' -f2)"
assert_eq "行2 异源: time 置空(不拼错日期)"    ""                    "$(row 700001-old | cut -d'|' -f3)"
assert_eq "行3 回填: name=index"              "Global司机端7.11.0"  "$(row R-IBG-700001 | cut -d'|' -f2)"
assert_eq "行3 回填: time=index"              "2026-08-15"          "$(row R-IBG-700001 | cut -d'|' -f3)"
assert_eq "行4 都无: 不写 ddp"                "no"                  "$(row 999999-x | cut -d'|' -f4)"

echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
