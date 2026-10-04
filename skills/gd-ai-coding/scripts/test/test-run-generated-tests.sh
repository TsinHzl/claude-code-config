#!/usr/bin/env bash
# test-run-generated-tests.sh — run-generated-tests.sh 通过/失败/无适用文件/缺失清单/非flutter平台 fixture
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/.."
CHECK="$SCRIPTS_DIR/checks/run-generated-tests.sh"
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

REQ="demo-req"
FEAT="feat-a"
FEAT_DIR="openspec/changes/$REQ/features/$FEAT"
mkdir -p "$FEAT_DIR"
mkdir -p .dac
echo '{"req_name":"'"$REQ"'"}' > .dac/state.json

# 伪造 flutter 二进制：按传入文件名判断是否模拟失败
FAKE_BIN_DIR="$TEST_DIR/bin"
mkdir -p "$FAKE_BIN_DIR"
cat > "$FAKE_BIN_DIR/flutter" <<'EOF'
#!/usr/bin/env bash
# 伪造 flutter test：文件名含 "_fail_" 则退出 1，否则退出 0
if [[ "$2" == *"_fail_"* ]]; then
  echo "00:01 +0 -1: some test failed"
  exit 1
fi
echo "00:01 +1: All tests passed!"
exit 0
EOF
chmod +x "$FAKE_BIN_DIR/flutter"
export PATH="$FAKE_BIN_DIR:$PATH"

mkdir -p test/features/order/domain
touch test/features/order/domain/discount_calculator_test.dart

# ── fixture 1：全部通过 ──
cat > "$FEAT_DIR/test-cases.md" <<'EOF'
## 需求点类型判定

| 需求点 | 类型 | 理由 |
|--------|------|------|
| §3.1 订单折扣计算 | 逻辑/数据类 | 可归约为输入输出断言 |

## 生成的逻辑/数据类测试文件

- `test/features/order/domain/discount_calculator_test.dart`（对应 §3.1）

## 生成的 UI/交互类场景清单

（无）
EOF

set +e
out=$(bash "$CHECK" "$FEAT" 2>&1)
code=$?
set -e
assert_eq "全部通过 exit 0" "0" "$code"
assert_eq "全部通过输出通过信息" "true" "$(echo "$out" | grep -q "全部 1 个逻辑/数据类测试文件通过" && echo true || echo false)"

# ── fixture 2：存在失败用例 ──
touch test/features/order/domain/discount_calculator_fail_test.dart
cat > "$FEAT_DIR/test-cases.md" <<'EOF'
## 生成的逻辑/数据类测试文件

- `test/features/order/domain/discount_calculator_test.dart`（对应 §3.1）
- `test/features/order/domain/discount_calculator_fail_test.dart`（对应 §3.2）
EOF

set +e
out=$(bash "$CHECK" "$FEAT" 2>&1)
code=$?
set -e
assert_eq "存在失败用例 exit 1" "1" "$code"
assert_eq "错误信息包含 DAC-GEN-013" "true" "$(echo "$out" | grep -q "DAC-GEN-013" && echo true || echo false)"
assert_eq "错误信息列出失败文件" "true" "$(echo "$out" | grep -q "discount_calculator_fail_test.dart" && echo true || echo false)"

# ── fixture 3：测试文件缺失于磁盘 ──
cat > "$FEAT_DIR/test-cases.md" <<'EOF'
## 生成的逻辑/数据类测试文件

- `test/features/order/domain/not_exist_test.dart`（对应 §3.3）
EOF

set +e
out=$(bash "$CHECK" "$FEAT" 2>&1)
code=$?
set -e
assert_eq "测试文件不存在 exit 1" "1" "$code"
assert_eq "错误信息包含文件不存在说明" "true" "$(echo "$out" | grep -q "文件不存在" && echo true || echo false)"

# ── fixture 4：无适用逻辑/数据类测试文件（清单为空） ──
cat > "$FEAT_DIR/test-cases.md" <<'EOF'
## 生成的逻辑/数据类测试文件

（无，本 feature 全部为 UI/交互类需求点）

## 生成的 UI/交互类场景清单

### 场景：提交按钮过渡动画
EOF

set +e
out=$(bash "$CHECK" "$FEAT" 2>&1)
code=$?
set -e
assert_eq "无适用文件 exit 0" "0" "$code"
assert_eq "无适用文件输出跳过信息" "true" "$(echo "$out" | grep -q "跳过" && echo true || echo false)"

# ── fixture 5：test-cases.md 不存在 ──
rm -f "$FEAT_DIR/test-cases.md"
set +e
out=$(bash "$CHECK" "$FEAT" 2>&1)
code=$?
set -e
assert_eq "test-cases.md 不存在 exit 1" "1" "$code"
assert_eq "错误信息包含 DAC-GEN-013" "true" "$(echo "$out" | grep -q "DAC-GEN-013" && echo true || echo false)"

# ── fixture 6：非 flutter 平台跳过 ──
set +e
out=$(PLATFORM=vue bash "$CHECK" "$FEAT" 2>&1)
code=$?
set -e
assert_eq "非 flutter 平台 exit 0" "0" "$code"
assert_eq "非 flutter 平台输出跳过信息" "true" "$(echo "$out" | grep -q "跳过" && echo true || echo false)"

echo ""
echo "通过: $PASS / 失败: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
