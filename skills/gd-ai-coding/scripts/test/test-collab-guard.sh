#!/usr/bin/env bash
# test-collab-guard.sh — Unit tests for scripts/collab/guard.sh
# 场景覆盖：单人短路、放行、STATE-020、STATE-021、恢复放行（claimed_by=self）、DEP-003、PLAN-006
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/.."
GUARD="$SCRIPTS_DIR/collab/guard.sh"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expect="$2" actual="$3"
  if [[ "$expect" == "$actual" ]]; then
    echo "  ✓ $desc (exit=$actual)"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc — expected exit=$expect, got $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_stderr_contains() {
  local desc="$1" needle="$2" file="$3"
  if grep -qF "$needle" "$file" 2>/dev/null; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc — stderr 未包含 '$needle'"
    cat "$file"
    FAIL=$((FAIL + 1))
  fi
}

# 通用 fixture 布置：req_name=t，feat 集合可自定义
setup_repo() {
  local dir="$1"
  mkdir -p "$dir/.dac" "$dir/openspec/changes/t/features"
  cd "$dir"
  git init -q
  git config user.email "alice@didichuxing.com"
  git config user.name "alice"
  echo '{"req_name":"t"}' > .dac/state.json
}

write_plan() {
  # $1 = path, $2 = jq-friendly features
  local dir="$1"; shift
  cat > "$dir/openspec/changes/t/feature-plan.json" <<PLAN
$1
PLAN
}

# ── 场景 1：单人短路（无 collab.json 且 assignee 为空）──
CASE_DIR="$TEST_DIR/case1"
setup_repo "$CASE_DIR"
write_plan "$CASE_DIR" '[{"id":"a","name":"a","description":"d","type":"page","status":"pending","dependencies":[],"related_requirements":[],"proposal_scope":{"new_files":["x.dart"],"modified_files":[],"proposal_section":"s"}}]'
set +e
bash "$GUARD" a 2>/tmp/g.err; rc=$?
set -e
echo "case1 单人短路："
assert_exit "无 collab.json + 无 assignee → exit 0" 0 "$rc"

# ── 场景 2：放行（assignee=self + 依赖 done + 无交叉）──
CASE_DIR="$TEST_DIR/case2"
setup_repo "$CASE_DIR"
echo '{"mode":"multi","initiated_by":"alice@didichuxing.com"}' > openspec/changes/t/collab.json
write_plan "$CASE_DIR" '[
 {"id":"dep","name":"d","description":"d","type":"service","status":"done","dependencies":[],"related_requirements":[],"proposal_scope":{"new_files":["dep.dart"],"modified_files":[],"proposal_section":"s"},"assignee":"alice@didichuxing.com"},
 {"id":"a","name":"a","description":"d","type":"page","status":"pending","dependencies":["dep"],"related_requirements":[],"proposal_scope":{"new_files":["a.dart"],"modified_files":[],"proposal_section":"s"},"assignee":"alice@didichuxing.com"}
]'
mkdir -p openspec/changes/t/features/dep
echo '{"feature_id":"dep","status":"done"}' > openspec/changes/t/features/dep/status.json
set +e
bash "$GUARD" a 2>/tmp/g.err; rc=$?
set -e
echo "case2 完全放行："
assert_exit "assignee=self + deps done + 无交叉 → exit 0" 0 "$rc"

# ── 场景 3：STATE-020（assignee=他人）──
CASE_DIR="$TEST_DIR/case3"
setup_repo "$CASE_DIR"
echo '{"mode":"multi","initiated_by":"bob@didichuxing.com"}' > openspec/changes/t/collab.json
write_plan "$CASE_DIR" '[{"id":"a","name":"a","description":"d","type":"page","status":"pending","dependencies":[],"related_requirements":[],"proposal_scope":{"new_files":["x.dart"],"modified_files":[],"proposal_section":"s"},"assignee":"bob@didichuxing.com"}]'
set +e
bash "$GUARD" a 2>/tmp/g.err; rc=$?
set -e
echo "case3 assignee 不匹配："
assert_exit "assignee=他人 → exit 1" 1 "$rc"
assert_stderr_contains "含 STATE-020 错误码" "[DAC-STATE-020]" /tmp/g.err

# ── 场景 4：STATE-021（他人 in_progress）──
CASE_DIR="$TEST_DIR/case4"
setup_repo "$CASE_DIR"
echo '{"mode":"multi","initiated_by":"alice@didichuxing.com"}' > openspec/changes/t/collab.json
write_plan "$CASE_DIR" '[{"id":"a","name":"a","description":"d","type":"page","status":"pending","dependencies":[],"related_requirements":[],"proposal_scope":{"new_files":["x.dart"],"modified_files":[],"proposal_section":"s"},"assignee":"alice@didichuxing.com"}]'
mkdir -p openspec/changes/t/features/a
echo '{"feature_id":"a","status":"in_progress","claimed_by":"bob@didichuxing.com"}' > openspec/changes/t/features/a/status.json
set +e
bash "$GUARD" a 2>/tmp/g.err; rc=$?
set -e
echo "case4 他人 in_progress："
assert_exit "他人认领 → exit 1" 1 "$rc"
assert_stderr_contains "含 STATE-021 错误码" "[DAC-STATE-021]" /tmp/g.err

# ── 场景 5：恢复放行（claimed_by=self + in_progress）──
CASE_DIR="$TEST_DIR/case5"
setup_repo "$CASE_DIR"
echo '{"mode":"multi","initiated_by":"alice@didichuxing.com"}' > openspec/changes/t/collab.json
write_plan "$CASE_DIR" '[{"id":"a","name":"a","description":"d","type":"page","status":"in_progress","dependencies":[],"related_requirements":[],"proposal_scope":{"new_files":["x.dart"],"modified_files":[],"proposal_section":"s"},"assignee":"alice@didichuxing.com"}]'
mkdir -p openspec/changes/t/features/a
echo '{"feature_id":"a","status":"in_progress","claimed_by":"alice@didichuxing.com"}' > openspec/changes/t/features/a/status.json
set +e
bash "$GUARD" a 2>/tmp/g.err; rc=$?
set -e
echo "case5 自己上次中断恢复："
assert_exit "claimed_by=self → exit 0（恢复放行）" 0 "$rc"

# ── 场景 6：DEP-003（依赖 status.json 缺失或非 done）──
CASE_DIR="$TEST_DIR/case6"
setup_repo "$CASE_DIR"
echo '{"mode":"multi","initiated_by":"alice@didichuxing.com"}' > openspec/changes/t/collab.json
write_plan "$CASE_DIR" '[
 {"id":"dep","name":"d","description":"d","type":"service","status":"pending","dependencies":[],"related_requirements":[],"proposal_scope":{"new_files":["dep.dart"],"modified_files":[],"proposal_section":"s"},"assignee":"bob@didichuxing.com"},
 {"id":"a","name":"a","description":"d","type":"page","status":"pending","dependencies":["dep"],"related_requirements":[],"proposal_scope":{"new_files":["a.dart"],"modified_files":[],"proposal_section":"s"},"assignee":"alice@didichuxing.com"}
]'
set +e
bash "$GUARD" a 2>/tmp/g.err; rc=$?
set -e
echo "case6 依赖 status.json 缺失："
assert_exit "dep 未 done → exit 1" 1 "$rc"
assert_stderr_contains "含 DEP-003 错误码" "[DAC-DEP-003]" /tmp/g.err

# ── 场景 7：PLAN-006（与另一 in_progress 文件交集）──
CASE_DIR="$TEST_DIR/case7"
setup_repo "$CASE_DIR"
echo '{"mode":"multi","initiated_by":"alice@didichuxing.com"}' > openspec/changes/t/collab.json
write_plan "$CASE_DIR" '[
 {"id":"a","name":"a","description":"d","type":"page","status":"pending","dependencies":[],"related_requirements":[],"proposal_scope":{"new_files":[],"modified_files":["shared/router.dart"],"proposal_section":"s"},"assignee":"alice@didichuxing.com"},
 {"id":"b","name":"b","description":"d","type":"page","status":"in_progress","dependencies":[],"related_requirements":[],"proposal_scope":{"new_files":[],"modified_files":["shared/router.dart"],"proposal_section":"s"},"assignee":"alice@didichuxing.com"}
]'
mkdir -p openspec/changes/t/features/b
echo '{"feature_id":"b","status":"in_progress","claimed_by":"alice@didichuxing.com"}' > openspec/changes/t/features/b/status.json
set +e
bash "$GUARD" a 2>/tmp/g.err; rc=$?
set -e
echo "case7 文件交叉："
assert_exit "与 in_progress b 交叉 → exit 1" 1 "$rc"
assert_stderr_contains "含 PLAN-006 错误码" "[DAC-PLAN-006]" /tmp/g.err

# ── 场景 8：单人模式但 feature 有 assignee → 仍走协作逻辑 ──
# （补充覆盖：无 collab.json 但 assignee 非空 → guard 按协作规则校验 assignee）
CASE_DIR="$TEST_DIR/case8"
setup_repo "$CASE_DIR"
# NOT creating collab.json
write_plan "$CASE_DIR" '[{"id":"a","name":"a","description":"d","type":"page","status":"pending","dependencies":[],"related_requirements":[],"proposal_scope":{"new_files":["x.dart"],"modified_files":[],"proposal_section":"s"},"assignee":"bob@didichuxing.com"}]'
set +e
bash "$GUARD" a 2>/tmp/g.err; rc=$?
set -e
echo "case8 有 assignee 但无 collab.json："
# 无 collab.json 但 assignee 是他人 → 走单人分支的规划期锁 → STATE-020
assert_exit "有 assignee=他人 → exit 1" 1 "$rc"

# ── 场景 9：单人模式 assignee=self → 短路（不做 status.json 相关的 rules 3/4/5）──
# 覆盖回归：旧逻辑会走 dep 检查踩 DEP-003，实际应短路 exit 0
CASE_DIR="$TEST_DIR/case9"
setup_repo "$CASE_DIR"
# NOT creating collab.json
write_plan "$CASE_DIR" '[
 {"id":"dep","name":"d","description":"d","type":"service","status":"pending","dependencies":[],"related_requirements":[],"proposal_scope":{"new_files":["dep.dart"],"modified_files":[],"proposal_section":"s"}},
 {"id":"a","name":"a","description":"d","type":"page","status":"pending","dependencies":["dep"],"related_requirements":[],"proposal_scope":{"new_files":["a.dart"],"modified_files":[],"proposal_section":"s"},"assignee":"alice@didichuxing.com"}
]'
# 故意不建 features/dep/status.json：单人模式下 status.json 从未被写入，
# 旧逻辑会误报 DEP-003；新逻辑应直接短路
set +e
bash "$GUARD" a 2>/tmp/g.err; rc=$?
set -e
echo "case9 单人模式 assignee=self："
assert_exit "无 collab.json + assignee=self → exit 0" 0 "$rc"

# ── 场景 10：协作模式报错含对方 email ──
CASE_DIR="$TEST_DIR/case10"
setup_repo "$CASE_DIR"
echo '{"mode":"multi","initiated_by":"alice@didichuxing.com"}' > openspec/changes/t/collab.json
write_plan "$CASE_DIR" '[{"id":"a","name":"a","description":"d","type":"page","status":"pending","dependencies":[],"related_requirements":[],"proposal_scope":{"new_files":["x.dart"],"modified_files":[],"proposal_section":"s"},"assignee":"alice@didichuxing.com"}]'
mkdir -p openspec/changes/t/features/a
echo '{"feature_id":"a","status":"in_progress","claimed_by":"bob@didichuxing.com"}' > openspec/changes/t/features/a/status.json
set +e
bash "$GUARD" a 2>/tmp/g.err; rc=$?
set -e
echo "case10 STATE-021 提示对方 email："
assert_exit "他人 in_progress → exit 1" 1 "$rc"
assert_stderr_contains "STATE-021 提示含 bob 邮箱" "bob@didichuxing.com" /tmp/g.err

echo ""
echo "───────────────────────────────"
echo "Total: $((PASS + FAIL)) | Pass: $PASS | Fail: $FAIL"
[[ $FAIL -eq 0 ]]