#!/usr/bin/env bash
# test-tech-requirements-show-not-count.sh — Unit tests for 技术类需求（sponsorId=3）展示保留 + 统计排除
#
# 反转自 test-exclude-technical-reqs.sh（数据层排除已撤，产品语义改为「保留展示 + 打标 + 排除统计」），
# 覆盖新语义五条路径（proposal.md「在范围内」逐项验证）：
#   1. is_technical_requirement() 判定保留：dict {value:3} / 裸 int 3 / 缺失 fail-open /
#      非 3 值（1/2/bad）/ T- 回溯 requirement.sponsorId
#   2. transform() 不再丢弃技术需求：技术（dict/裸 int 双形态）与业务需求全部进入
#      requirements_index 与成员副本，技术条目两副本均写 is_technical=true、业务无该键
#   3. 离线 merge_trace 不被技术排除拦截：技术需求绑 dac trace 后正常合并，且 trace 整段覆盖
#      重建的成员副本经 _stamp_versions 按 requirements_index 的 tech_index 回填 is_technical
#   4. 实时 _accumulate_item 双副本打标：技术 item 写入 person_map 成员副本与 requirements_index
#      条目各打一次 is_technical，业务 item 两处均无该键
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
METRICS_DIR="$SCRIPT_DIR/../metrics"
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
# 取单行输出字段：row <key> <field>
row() { echo "$OUT" | grep "^$1|" | head -1 | cut -d'|' -f"$2"; }

# ── Part 1+2: 判定函数保留 + transform() 双副本打标（技术不丢弃）──────────────────
OUT=$(python3 - "$METRICS_DIR/transform-ddp.py" "$TEST_DIR" <<'PY'
import sys, json, importlib.util
transform_path, test_dir = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("t", transform_path)
t = importlib.util.module_from_spec(spec); spec.loader.exec_module(t)

# Part 1: 判定函数（含 T- 回溯 requirement.sponsorId），仅 sponsorId=3 为 True
checks = [
    ("dict-value3",        t.is_technical_requirement({"sponsorId": {"value": 3}}),                    True),
    ("bare-int3",          t.is_technical_requirement({"sponsorId": 3}),                               True),
    ("missing-failopen",   t.is_technical_requirement({}),                                             False),
    ("non3-business1",     t.is_technical_requirement({"sponsorId": {"value": 1}}),                    False),
    ("non3-product2",      t.is_technical_requirement({"sponsorId": 2}),                               False),
    ("badvalue-failopen",  t.is_technical_requirement({"sponsorId": "bad"}),                           False),
    ("T-requirement-回溯",  t.is_technical_requirement({"requirement.sponsorId": {"value": 3}}),        True),
]
for name, actual, expected in checks:
    print(f"{name}|{actual}|{expected}")

# Part 2: transform() 保留技术需求并双副本打标（dict/裸 int 双形态技术 + 业务）
def mk(link, sponsor_id):
    return {"name": {"link": link, "displayContent": "需求" + link[-4:]},
            "state": {"displayContent": "开发中"}, "sponsorId": sponsor_id,
            "rdOwnerList": {"dataList": [{"ldap": "u1", "hrStatus": "A", "name": "用户1"}]},
            "mtime": {"value": "2026-08-01 10:00:00"}}
items = [
    mk("R-IBG-000001", {"value": 3}),
    mk("R-IBG-000002", 3),
    mk("R-IBG-000003", {"value": 1}),
]
d = t.transform(items)
for r in d["requirements_index"]:
    print(f"idx|{r['req_name']}|{'T' if r.get('is_technical') else 'F'}")
for r in d["committers"][0]["requirements"]:
    print(f"mem|{r['req_name']}|{'T' if r.get('is_technical') else 'F'}")
PY
)

echo "=== is_technical_requirement 判定保留 ==="
for c in dict-value3 bare-int3 missing-failopen non3-business1 non3-product2 badvalue-failopen; do
  assert_eq "判定 $c" "$(row "$c" 3)" "$(row "$c" 2)"
done
# 中文 key 无法进入上方空格分隔 for 循环，单独补 shell 断言（Python 侧已输出判定结果）
assert_eq "判定 T-requirement-回溯" "$(row 'T-requirement-回溯' 3)" "$(row 'T-requirement-回溯' 2)"

echo ""
echo "=== transform() 保留技术需求 + 双副本打标 ==="
assert_eq "requirements_index 技术+业务 三条全在" "3" "$(echo "$OUT" | grep -c '^idx|R-IBG-')"
assert_eq "index 技术(dict) is_technical" "T" "$(row 'idx|R-IBG-000001' 3)"
assert_eq "index 技术(裸int) is_technical" "T" "$(row 'idx|R-IBG-000002' 3)"
assert_eq "index 业务 无 is_technical" "F" "$(row 'idx|R-IBG-000003' 3)"
assert_eq "成员副本 技术(dict) is_technical" "T" "$(row 'mem|R-IBG-000001' 3)"
assert_eq "成员副本 技术(裸int) is_technical" "T" "$(row 'mem|R-IBG-000002' 3)"
assert_eq "成员副本 业务 无 is_technical" "F" "$(row 'mem|R-IBG-000003' 3)"

# ── Part 3: 离线 merge_trace 不拦截技术 trace + trace 覆盖后标记保留（_stamp_versions 回填）──
OUT=$(python3 - "$METRICS_DIR/transform-ddp.py" "$TEST_DIR" <<'PY'
import sys, json, importlib.util
transform_path, test_dir = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("t", transform_path)
t = importlib.util.module_from_spec(spec); spec.loader.exec_module(t)

def mk(link, sponsor_id, versioned=True):
    item = {"name": {"link": link, "displayContent": "需求" + link[-4:]},
            "state": {"displayContent": "开发中"}, "sponsorId": sponsor_id,
            "rdOwnerList": {"dataList": [{"ldap": "u1", "hrStatus": "A", "name": "用户1"}]},
            "mtime": {"value": "2026-08-01 10:00:00"}}
    if versioned:
        # dpmVersion 的 dict 分支守卫要求 value 非空才返回 displayContent，故需带 value 键
        item["dpmVersion"] = {"value": ["x"], "displayContent": "Global司机端100"}
    return item
items = [
    mk("R-IBG-400001", {"value": 3}),        # 技术需求（已绑定真实 dac trace，模拟整段覆盖）
    mk("R-IBG-400002", {"value": 1}),        # 业务需求
    mk("R-IBG-400003", {"value": 3}, False), # 无 release_version_name 的技术需求：trace 整段
                                             # 覆盖后同样须按 tech_index 回填标记（tech_index 收集
                                             # 不受 name-gate 约束，M1 回归锚点）
]
dashboard = t.transform(items)
# 技术需求 trace：req_name 与 DDP 同名，带 workflow_session_ids 模拟真实 dac 绑定。merge_trace
# 仅按既有 hidden_r_ids 过滤（不并入技术 id），故技术 trace 必须正常合并、不得被拦截。
trace = {"u1@didiglobal.com": [
    {"req_name": "R-IBG-400001", "workflow_session_ids": ["sess-tech"],
     "phases": [], "features": [], "lines_added": 100},
    {"req_name": "R-IBG-400002", "workflow_session_ids": ["sess-biz"],
     "phases": [], "features": [], "lines_added": 50},
    {"req_name": "R-IBG-400003", "workflow_session_ids": ["sess-tech-noversion"],
     "phases": [], "features": [], "lines_added": 30},
]}
tf = test_dir + "/trace.json"
with open(tf, "w", encoding="utf-8") as f:
    json.dump(trace, f, ensure_ascii=False)
t.merge_trace(dashboard, tf)   # 与 __main__ 一致：不再收集技术 id 并入 hidden_r_ids

for r in dashboard["committers"][0]["requirements"]:
    print(f"mr|{r['req_name']}|{'T' if r.get('is_technical') else 'F'}")
PY
)
echo ""
echo "=== 离线 merge_trace 不拦截 + 标记保留 ==="
assert_eq "技术 trace 正常合并（未被排除拦截）" "R-IBG-400001" "$(row 'mr|R-IBG-400001' 2)"
assert_eq "业务 trace 正常合并" "R-IBG-400002" "$(row 'mr|R-IBG-400002' 2)"
assert_eq "trace 覆盖后成员副本 is_technical 回填" "T" "$(row 'mr|R-IBG-400001' 3)"
assert_eq "无版本名技术需求 trace 覆盖后标记仍回填（M1）" "T" "$(row 'mr|R-IBG-400003' 3)"
assert_eq "业务 trace 覆盖后无 is_technical" "F" "$(row 'mr|R-IBG-400002' 3)"

# ── Part 4: 实时 _accumulate_item 双副本打标 ─────────────────────────────────────
OUT=$(python3 - "$METRICS_DIR/dashboard-server.py" "$METRICS_DIR/transform-ddp.py" "$TEST_DIR" <<'PY'
import sys, importlib.util
server_path, transform_path, test_dir = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location("t", transform_path)
t = importlib.util.module_from_spec(spec); spec.loader.exec_module(t)
spec2 = importlib.util.spec_from_file_location("srv", server_path)
srv = importlib.util.module_from_spec(spec2); spec2.loader.exec_module(srv)

person_map = {"u1": {"committer": "u1@didiglobal.com", "committer_name": "用户1",
                     "dept": "", "requirements": []}}
reqs_index = []
seen_reqs = set()

def mk(link, sponsor_id):
    return {"name": {"link": link, "displayContent": "需求" + link[-4:]},
            "state": {"displayContent": "开发中"}, "sponsorId": sponsor_id,
            "rdOwnerList": {"dataList": [{"ldap": "u1", "hrStatus": "A", "name": "用户1"}]},
            "mtime": {"value": "2026-08-01 10:00:00"}}

# 技术 item：req_base 写 is_technical 后 deepcopy 进成员副本；index_entry 另打一次
srv._accumulate_item(mk("R-IBG-500001", {"value": 3}), ["u1"], person_map, reqs_index,
                     t, seen_reqs, {"u1"}, req_participants={})
# 业务 item：两处均不携带该键
srv._accumulate_item(mk("R-IBG-500002", {"value": 1}), ["u1"], person_map, reqs_index,
                     t, seen_reqs, {"u1"}, req_participants={})

for r in person_map["u1"]["requirements"]:
    print(f"pt|{r['req_name']}|{'T' if r.get('is_technical') else 'F'}")
for r in reqs_index:
    print(f"ix|{r['req_name']}|{'T' if r.get('is_technical') else 'F'}")
PY
)
echo ""
echo "=== 实时 _accumulate_item 双副本打标 ==="
assert_eq "成员副本 技术 is_technical" "T" "$(row 'pt|R-IBG-500001' 3)"
assert_eq "index 技术 is_technical" "T" "$(row 'ix|R-IBG-500001' 3)"
assert_eq "成员副本 业务 无 is_technical" "F" "$(row 'pt|R-IBG-500002' 3)"
assert_eq "index 业务 无 is_technical" "F" "$(row 'ix|R-IBG-500002' 3)"

# ── Part 5: 实时 _merge_trace_data orphan 注入打标 ───────────────────────────────
OUT=$(python3 - "$METRICS_DIR/dashboard-server.py" "$METRICS_DIR/transform-ddp.py" "$TEST_DIR" <<'PY'
import sys, importlib.util
server_path, transform_path, test_dir = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location("t", transform_path)
t = importlib.util.module_from_spec(spec); spec.loader.exec_module(t)
spec2 = importlib.util.spec_from_file_location("srv", server_path)
srv = importlib.util.module_from_spec(spec2); spec2.loader.exec_module(srv)

# requirements_index 预置一条技术 DDP 条目（index 有 is_technical）。成员 u1 未参与该 DDP（非
# rdOwner → 成员副本无同名 req），但有一笔 dac trace 已绑定到该技术需求（bindings 把 trace 名
# "local-orphan" 指向 R-IBG-600001）。该 trace 在成员副本无同名匹配 → 走 orphan 注入分支；注入的
# new_req 须经绑定目标命中 index 技术条目打 is_technical，否则技术需求经 orphan 注入绕过统计排除。
person_map = {"u1": {"committer": "u1@didiglobal.com", "committer_name": "用户1",
                     "dept": "", "requirements": []}}
reqs_index = [
    {"req_name": "R-IBG-600001", "is_technical": True, "workflow_session_ids": [],
     "phases": [], "features": [], "last_commit_ts": 0,
     "ddp": {"title": "技术需求600001"}},
]
trace = [{"committer": "u1@didiglobal.com", "committer_name": "用户1", "requirements": [
    {"req_name": "local-orphan", "workflow_session_ids": ["sess-orphan"],
     "phases": [], "features": [], "lines_added": 80, "last_commit_ts": 200},
]}]
srv._merge_trace_data(person_map, reqs_index, trace, frozenset(), t,
                      bindings={"local-orphan": "R-IBG-600001"})
for r in person_map["u1"]["requirements"]:
    print(f"or|{r['req_name']}|{'T' if r.get('is_technical') else 'F'}")
for r in reqs_index:
    print(f"ix2|{r['req_name']}|{'T' if r.get('is_technical') else 'F'}")
PY
)
echo ""
echo "=== 实时 orphan 注入技术打标 ==="
assert_eq "orphan 注入 new_req 打 is_technical" "T" "$(row 'or|local-orphan' 3)"
assert_eq "orphan 注入同步 append 进 index 且带标记" "T" "$(row 'ix2|local-orphan' 3)"

# ── Part 5b: local 模式（_do_stream_local）orphan 技术打标回归锚点 ─────────────────
# local 模式无 DDP MCP：reqs_index 来自后端快照（技术 DDP 已带 is_technical），trace 名为
# dac-bind 后缀 R-IBG-<num>-<local>（bindings 为空 → 绑定目标降级为自身），只能经
# tm.extract_ddp_id 提取数字 id 命中 tech_ids 打标。修复前 _do_stream_local 不传 tm/bindings
# （tech_ids 为空、绑定映射缺失）→ 该路径漏标；修复后传 tm+bindings → 命中打标。
OUT=$(python3 - "$METRICS_DIR/dashboard-server.py" "$METRICS_DIR/transform-ddp.py" "$TEST_DIR" <<'PY'
import sys, importlib.util
server_path, transform_path, test_dir = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location("t", transform_path)
t = importlib.util.module_from_spec(spec); spec.loader.exec_module(t)
spec2 = importlib.util.spec_from_file_location("srv", server_path)
srv = importlib.util.module_from_spec(spec2); spec2.loader.exec_module(srv)

# local 快照：index 预置技术 DDP（is_technical 已存在于快照条目）
reqs_index = [
    {"req_name": "R-IBG-600002", "is_technical": True, "workflow_session_ids": [],
     "phases": [], "features": [], "last_commit_ts": 0,
     "ddp": {"title": "技术需求600002"}},
]
# dac-bind 后缀 trace 名：字面不等于 index 技术 req_name，只能经 tm.extract_ddp_id 命中
trace = [{"committer": "u3@didiglobal.com", "committer_name": "用户3", "requirements": [
    {"req_name": "R-IBG-600002-local", "workflow_session_ids": ["sess-loc"],
     "phases": [], "features": [], "lines_added": 70, "last_commit_ts": 400},
]}]

# 修复后：local 传 tm + bindings（bindings 空 dict → 绑定目标降级为自身）
pm = {"u3": {"committer": "u3@didiglobal.com", "committer_name": "用户3", "dept": "", "requirements": []}}
srv._merge_trace_data(pm, reqs_index, trace, frozenset(), t, {})
r = pm["u3"]["requirements"][0]
print(f"lo|{r['req_name']}|{'T' if r.get('is_technical') else 'F'}")

# 修复前等价：不传 tm/bindings → tech_ids 为空、绑定映射缺失 → 数字 id 路径不命中
pm2 = {"u3": {"committer": "u3@didiglobal.com", "committer_name": "用户3", "dept": "", "requirements": []}}
reqs_index2 = [dict(reqs_index[0])]
srv._merge_trace_data(pm2, reqs_index2, trace, frozenset(), None, None)
r2 = pm2["u3"]["requirements"][0]
print(f"lo-nb|{r2['req_name']}|{'T' if r2.get('is_technical') else 'F'}")
PY
)
echo ""
echo "=== local 模式（_do_stream_local）orphan 技术打标 ==="
assert_eq "修复后：local 传 tm 时 dac-bind 后缀技术 trace 打 is_technical" "T" "$(row 'lo|R-IBG-600002-local' 3)"
assert_eq "修复前等价：不传 tm 时该路径漏标（回归锚点）" "F" "$(row 'lo-nb|R-IBG-600002-local' 3)"

echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
