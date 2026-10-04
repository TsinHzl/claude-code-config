#!/usr/bin/env bash
# test-gen-index.sh — 过滤后 DSL 无顶层 name 时从 nodes[0] / ui_tree 取节点名
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GEN="$REPO_ROOT/scripts/mastergo/gen-index.sh"

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

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$TEST_DIR"

mkdir -p ui/001 ui/002 ui/003

echo '{"nodes":[{"type":"FRAME","name":"总开关关闭","children":[]}]}' > ui/001/ui_dsl.json
echo '└── [FRAME] 总开关关闭 (750×1624 @0,0)' > ui/001/ui_tree.txt
echo 'https://mastergo.com/file/1?layer_id=1:1' > ui/001/.source_link

echo '{"name":"","nodes":[{"name":""}]}' > ui/002/ui_dsl.json
echo '└── [FRAME] 偏好设置页 (750×1624 @0,0) [fill:#FFFFFF]' > ui/002/ui_tree.txt
echo 'https://mastergo.com/file/1?layer_id=1:2' > ui/002/.source_link

echo '{"nodeName":"挽留弹窗"}' > ui/003/ui_dsl.json

bash "$GEN" --ui-dir "$TEST_DIR/ui"

assert_eq "nodes[0].name" "总开关关闭" "$(jq -r '.[] | select(.id=="ds_001") | .node_name' ui/index.json)"
assert_eq "ui_tree 第一行" "偏好设置页" "$(jq -r '.[] | select(.id=="ds_002") | .node_name' ui/index.json)"
assert_eq "顶层 nodeName" "挽留弹窗" "$(jq -r '.[] | select(.id=="ds_003") | .node_name' ui/index.json)"
assert_eq "status ok" "ok" "$(jq -r '.[] | select(.id=="ds_001") | .status' ui/index.json)"

echo ""
echo "结果: $PASS 通过, $FAIL 失败"
[ "$FAIL" -eq 0 ]
