#!/usr/bin/env bash
# test-normalize-version-years.sh — Unit tests for transform-ddp.py normalize_version_years()
#
# 覆盖“基于版本号单调性重排 release_version_time 年份”的核心分支：
#   1. 真实司机端序列（7.9.x/7.10.x，跨 2025→2026）— 错误年份被校正为单调正确
#   2. 审查者反例（仅 7.9.90/7.9.94，无近今版本）— 最高版本锚点确保不把已对条目改错
#   3. 闰日 0229 传播到非闰年 — 放弃校正、保留原值（不写出非法日期）
#   4. release_version_time 为空 — 不新增日期（仅重写已有非空年份）
#   5. 非司机端系列（近今、月-日单调）— 不被误改
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRANSFORM="$SCRIPT_DIR/../metrics/transform-ddp.py"

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

# FakeDate 固定 today=2026-07-21，保证测试与真实日期无关（确定性）。
# 结果以 "name|time" 逐行输出。
OUT=$(python3 - "$TRANSFORM" <<'PY'
import sys, datetime, importlib.util
spec = importlib.util.spec_from_file_location("t", sys.argv[1])
t = importlib.util.module_from_spec(spec); spec.loader.exec_module(t)

class FakeDate(datetime.date):
    @classmethod
    def today(cls):
        return cls(2026, 7, 21)
t.date = FakeDate  # normalize_version_years 内的 date.today()/date(y,m,d) 全部走 FakeDate

def ddp(name, time):
    return {"ddp": {"release_version_name": name, "release_version_time": time}}

reqs = [
    # 1) 真实司机端序列（乱序 + 错误年份）
    ddp("Global司机端7.9.26", "2026-05-15"),   # 应校正 2025-05-15
    ddp("Global司机端7.9.78", "2026-11-27"),   # 应校正 2025-11-27
    ddp("Global司机端7.9.90", "2027-01-09"),   # 应校正 2026-01-09（原始 bug 场景）
    ddp("Global司机端7.9.94", "2026-01-22"),   # 已对，保持
    ddp("Global司机端7.9.98", "2026-02-05"),
    ddp("Global司机端7.10.38", "2026-07-16"),
    ddp("Global司机端7.10.50", "2026-08-27"),  # 最高版本=锚点
    # 2) 审查者反例：独立系列，仅两版本且都距今>半年，无近今锚
    ddp("TestB端7.9.90", "2027-01-09"),        # 应校正 2026-01-09
    ddp("TestB端7.9.94", "2026-01-22"),        # 最高版本锚点，nearest→2026，保持
    # 3) 闰日：非锚点条目传播到 2026(非闰年) → 放弃校正保留原值
    ddp("TestC端1.0.2", "2024-02-29"),
    ddp("TestC端1.0.6", "2024-03-14"),
    # 4) 空日期不新增
    ddp("TestD端5.0.0", ""),
    # 5) 非司机端近今系列，保持
    ddp("Global乘客端v7.6.96/99 v6.64.2", "2026-09-10"),
]
t.normalize_version_years([], reqs)
for r in reqs:
    d = r["ddp"]
    print(f'{d["release_version_name"]}|{d["release_version_time"]}')
PY
)

val() { echo "$OUT" | grep "^$1|" | head -1 | cut -d'|' -f2; }

echo "=== 1) 真实司机端序列：错误年份被校正为单调正确 ==="
assert_eq "7.9.26 → 2025-05-15" "2025-05-15" "$(val "Global司机端7.9.26")"
assert_eq "7.9.78 → 2025-11-27" "2025-11-27" "$(val "Global司机端7.9.78")"
assert_eq "7.9.90 → 2026-01-09（修复 2027 bug）" "2026-01-09" "$(val "Global司机端7.9.90")"
assert_eq "7.9.94 → 2026-01-22（保持）" "2026-01-22" "$(val "Global司机端7.9.94")"
assert_eq "7.10.50 → 2026-08-27（锚点）" "2026-08-27" "$(val "Global司机端7.10.50")"

echo "=== 2) 审查者反例：最高版本锚点，两版本都正确（不反向改错高版本） ==="
assert_eq "TestB 7.9.94 → 2026-01-22" "2026-01-22" "$(val "TestB端7.9.94")"
assert_eq "TestB 7.9.90 → 2026-01-09" "2026-01-09" "$(val "TestB端7.9.90")"

echo "=== 3) 闰日 0229 传播到非闰年 → 保留原值，不写非法日期 ==="
assert_eq "TestC 1.0.2 保留 2024-02-29" "2024-02-29" "$(val "TestC端1.0.2")"

echo "=== 4) 空日期不新增 ==="
assert_eq "TestD 5.0.0 保持空" "" "$(val "TestD端5.0.0")"

echo "=== 5) 非司机端近今系列不被误改 ==="
assert_eq "乘客端 → 2026-09-10" "2026-09-10" "$(val "Global乘客端v7.6.96/99 v6.64.2")"

echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
