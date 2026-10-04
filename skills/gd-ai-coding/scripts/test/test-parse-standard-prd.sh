#!/usr/bin/env bash
# test-parse-standard-prd.sh — 标准 PRD 抽列 + ingest fallback
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PARSE_PY="$REPO_ROOT/scripts/prd/parse-standard-prd.py"
INGEST="$REPO_ROOT/scripts/prd/ingest-prd.sh"
FIXTURE="$REPO_ROOT/openspec/changes/standard-prd-parse-adapt/source-prd.md"

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

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$TEST_DIR"

echo "Test 1: fixture 抽出"
python3 "$PARSE_PY" \
  --input "$FIXTURE" \
  --out "$TEST_DIR/prd-extract.json" \
  --summary "$TEST_DIR/summary.md"
assert_file_exists "extract json" "$TEST_DIR/prd-extract.json"
assert_file_exists "summary md" "$TEST_DIR/summary.md"

FEAT_N=$(jq '.stats.feature_count' "$TEST_DIR/prd-extract.json")
ROW_N=$(jq '.stats.merged_from_rows' "$TEST_DIR/prd-extract.json")
assert_eq "合成后 5 个功能点" "5" "$FEAT_N"
assert_eq "原始 6 行需求" "6" "$ROW_N"

NAMES=$(jq -r '[.features[].name] | join(",")' "$TEST_DIR/prd-extract.json")
assert_eq "功能点顺序与合并" "接单按钮,端内弹窗,接单设置页,外卖接单偏好细节设置页,接单页引导" "$NAMES"

SEG=$(jq '.features[] | select(.name=="接单设置页") | .detail_segments | length' "$TEST_DIR/prd-extract.json")
assert_eq "同名两行详情分段保留" "2" "$SEG"

UI_N=$(jq '[.features[] | select(.name=="接单设置页") | .ui_links[]] | length' "$TEST_DIR/prd-extract.json")
assert_eq "同名 UI 链合并去重" "2" "$UI_N"

VALID=$(jq '[.features[].ui_links[] | select(.valid==true)] | length' "$TEST_DIR/prd-extract.json")
assert_eq "带 layer_id 的链均为有效" "5" "$VALID"

LABELS=$(jq -r '.features[] | select(.name=="外卖接单偏好细节设置页") | .ui_links | map(.label) | join(",")' "$TEST_DIR/prd-extract.json")
assert_eq "UI 链前短标签" "日间,夜间" "$LABELS"

NO_DEV_POPUP=$(jq -r '.features[] | select(.name=="端内弹窗") | .no_dev' "$TEST_DIR/prd-extract.json")
assert_eq "详情含无开发 → no_dev" "true" "$NO_DEV_POPUP"

NO_DEV_BTN=$(jq -r '.features[] | select(.name=="接单按钮") | .no_dev' "$TEST_DIR/prd-extract.json")
assert_eq "仅复用不是无开发" "false" "$NO_DEV_BTN"

NO_DEV_N=$(jq '.stats.no_dev_count' "$TEST_DIR/prd-extract.json")
assert_eq "无开发计数" "1" "$NO_DEV_N"

API_EMPTY=$(jq -r '.features[] | select(.name=="接单按钮") | .api_name' "$TEST_DIR/prd-extract.json")
assert_eq "空 API 列保持空" "" "$API_EMPTY"

UNMATCH=$(jq -r '.trackings_unmatched[0].event_id' "$TEST_DIR/prd-extract.json")
assert_eq "埋点页面名对不上则未挂上" "ibt_gd_sidebar_tripguide_ck" "$UNMATCH"

ATTACHED=$(jq '[.features[].trackings[]] | length' "$TEST_DIR/prd-extract.json")
assert_eq "没有错误挂上的埋点" "0" "$ATTACHED"

DDP=$(jq -r '.ddp_ids | join(",")' "$TEST_DIR/prd-extract.json")
assert_eq "产品文档抽出需求 ID" "T-IBT-647635,R-IBG-737078" "$DDP"

SCOPE_BR=$(jq -r '.scope[] | select(.dimension=="国家/区域") | .value_text' "$TEST_DIR/prd-extract.json")
assert_eq "范围国家/区域原文" "BR" "$SCOPE_BR"

DARK=$(jq -r '.scope[] | select(.dimension=="暗黑模式") | .value | tostring' "$TEST_DIR/prd-extract.json")
assert_eq "暗黑是否归一" "true" "$DARK"

LANG=$(jq -r '.scope[] | select(.dimension=="语言") | .value_text' "$TEST_DIR/prd-extract.json")
assert_eq "空语言合法" "" "$LANG"

IMG=$(jq -r '.features[] | select(.name=="接单按钮") | .online_images[0].path // empty' "$TEST_DIR/prd-extract.json")
if [[ -n "$IMG" && -f "$IMG" ]]; then
  echo "  ✓ 相对路径图能落到本地文件"
  PASS=$((PASS + 1))
else
  echo "  ✗ 相对路径图能落到本地文件 (path=$IMG)"
  FAIL=$((FAIL + 1))
fi

echo "Test 2: 列名带说明括号仍认出标准表"
cat > "$TEST_DIR/annotated.md" <<'EOF'
# 需求文档梳理

## 三、司机端需求列表

| 功能/页面名 | 线上图 | 需求图 | UI 链接 「Mastergo中具体模块的Layer容器链接」 | 需求详情 「和端相关的 不是全复制产品文档」 | API 接口名 | API 字段 |
| --- | --- | --- | --- | --- | --- | --- |
| 测试页 <br> | 无 <br> | 无 <br> |  <br> | 端上改文案 <br> |  <br> |  <br> |
EOF
python3 "$PARSE_PY" \
  --input "$TEST_DIR/annotated.md" \
  --out "$TEST_DIR/annotated.json" \
  --summary "$TEST_DIR/annotated-summary.md"
assert_file_exists "带说明表头写出 extract" "$TEST_DIR/annotated.json"
ANN_NAME=$(jq -r '.features[0].name' "$TEST_DIR/annotated.json")
assert_eq "带说明表头抽出功能名" "测试页" "$ANN_NAME"
ANN_DETAIL=$(jq -r '.features[0].detail_segments[0].detail_text' "$TEST_DIR/annotated.json")
assert_eq "带说明表头抽出需求详情" "端上改文案" "$ANN_DETAIL"

echo "Test 2b: 标准名后面粘了别的字，不当标准列"
cat > "$TEST_DIR/glued.md" <<'EOF'
# 一篇表

| 功能/页面名 | 线上图 | 需求图 | UI 链接 | 需求详情补充 | API 接口名 | API 字段 |
| --- | --- | --- | --- | --- | --- | --- |
| 测试页 | 无 | 无 |  | 端上改文案 |  |  |
EOF
set +e
python3 "$PARSE_PY" --input "$TEST_DIR/glued.md" --out "$TEST_DIR/glued.json"
GLUED_RC=$?
set -e
assert_eq "粘连列名 exit 2" "2" "$GLUED_RC"

echo "Test 3: 非标准列名 exit 2"
cat > "$TEST_DIR/legacy.md" <<'EOF'
# 一篇散文 PRD

## 司机端需求

这里没有标准表，只是说明要改司机端首页文案。
EOF
set +e
python3 "$PARSE_PY" --input "$TEST_DIR/legacy.md" --out "$TEST_DIR/no.json"
RC=$?
set -e
assert_eq "非标准文档 exit 2" "2" "$RC"

echo "Test 4: ingest --input 标准路径"
bash "$INGEST" \
  --input "$FIXTURE" \
  --output "$TEST_DIR/ingest-out.md" \
  --raw "$TEST_DIR/ingest-raw.md" \
  --extract "$TEST_DIR/ingest-extract.json" > "$TEST_DIR/ingest-stdout.txt"
MODE=$(tr -d '[:space:]' < "$TEST_DIR/dac-prd-mode")
assert_eq "ingest 写出 dac-prd-mode=standard" "standard" "$MODE"
assert_file_exists "ingest extract" "$TEST_DIR/ingest-extract.json"
grep -q 'DAC_PRD_MODE=standard' "$TEST_DIR/ingest-stdout.txt"
assert_eq "stdout 含 DAC_PRD_MODE=standard" "0" "$?"

echo "Test 5: ingest --input fallback pre-trim"
bash "$INGEST" \
  --input "$TEST_DIR/legacy.md" \
  --output "$TEST_DIR/legacy-out.md" \
  --raw "$TEST_DIR/legacy-raw.md" \
  --extract "$TEST_DIR/legacy-extract.json" \
  --keywords "司机端" > "$TEST_DIR/legacy-stdout.txt"
MODE2=$(tr -d '[:space:]' < "$TEST_DIR/dac-prd-mode")
assert_eq "ingest fallback dac-prd-mode=legacy" "legacy" "$MODE2"
assert_file_exists "fallback 写出 trimmed" "$TEST_DIR/legacy-out.md"
if [[ -f "$TEST_DIR/legacy-extract.json" ]]; then
  echo "  ✗ fallback 不应留下 extract json"
  FAIL=$((FAIL + 1))
else
  echo "  ✓ fallback 不留半份 extract"
  PASS=$((PASS + 1))
fi

echo "Test 6: sync-skipped-from-plan 只写 skipped_features、不改 phase"
mkdir -p .dac openspec/changes/sync-req
cat > .dac/state.json <<'EOF'
{"phase":"feature-planned","req_name":"sync-req","skipped_features":[],"completed_features":[]}
EOF
cat > openspec/changes/sync-req/feature-plan.json <<'EOF'
{
  "schema_version": 1,
  "features": [
    {
      "id": "popup-reuse",
      "name": "弹窗复用",
      "description": "无开发",
      "type": "page",
      "status": "skipped",
      "dependencies": [],
      "related_requirements": ["§3.1"],
      "proposal_scope": {"new_files": [], "modified_files": [], "proposal_section": "## 1"}
    },
    {
      "id": "settings-page",
      "name": "设置页",
      "description": "有开发",
      "type": "page",
      "status": "pending",
      "dependencies": [],
      "related_requirements": ["§3.2"],
      "proposal_scope": {"new_files": ["lib/a.dart"], "modified_files": [], "proposal_section": "## 2"}
    }
  ]
}
EOF
bash "$REPO_ROOT/scripts/feature/sync-skipped-from-plan.sh" >/dev/null
SKIPPED_IDS=$(jq -r '.skipped_features | join(",")' .dac/state.json)
PHASE=$(jq -r '.phase' .dac/state.json)
assert_eq "skipped id 写入 state" "popup-reuse" "$SKIPPED_IDS"
assert_eq "同步 skipped 不抢跑 feature-done" "feature-planned" "$PHASE"

echo "Test 7: pre-trim --skip-trim 不裁表"
SKIP_OUT="$TEST_DIR/skip-trim.md"
bash "$REPO_ROOT/scripts/prd/pre-trim.sh" \
  --input "$FIXTURE" \
  --output "$SKIP_OUT" \
  --skip-trim >/dev/null
SRC_LINES=$(wc -l < "$FIXTURE" | tr -d ' ')
OUT_LINES=$(wc -l < "$SKIP_OUT" | tr -d ' ')
assert_eq "skip-trim 行数与原文一致" "$SRC_LINES" "$OUT_LINES"
if grep -q '功能/页面名' "$SKIP_OUT"; then
  echo "  ✓ skip-trim 保留需求列表表头"
  PASS=$((PASS + 1))
else
  echo "  ✗ skip-trim 保留需求列表表头"
  FAIL=$((FAIL + 1))
fi

RECORD_PRD="$REPO_ROOT/scripts/prd/record-prd-source.sh"
FAKE_STD="https://cooper.didichuxing.com/knowledge/1111111111111/2222222222222"
FAKE_OTHER="https://cooper.didichuxing.com/knowledge/1111111111111/3333333333333"

echo "Test 8: --url 未确认标准 PRD 则挡住（有 state）"
set +e
bash "$INGEST" \
  --url "$FAKE_STD" \
  --output "$TEST_DIR/blocked-out.md" \
  --raw "$TEST_DIR/blocked-raw.md" >"$TEST_DIR/blocked-stdout.txt" 2>"$TEST_DIR/blocked-stderr.txt"
BLOCK_RC=$?
set -e
assert_eq "有 state 无 prd_source 时 ingest --url exit 1" "1" "$BLOCK_RC"
if grep -q 'DAC-SPEC-005' "$TEST_DIR/blocked-stderr.txt"; then
  echo "  ✓ 报 DAC-SPEC-005"
  PASS=$((PASS + 1))
else
  echo "  ✗ 报 DAC-SPEC-005"
  echo "    stderr: $(cat "$TEST_DIR/blocked-stderr.txt")"
  FAIL=$((FAIL + 1))
fi

echo "Test 8b: --kind none 仍 --url 则挡住"
bash "$RECORD_PRD" --kind none >/dev/null
set +e
bash "$INGEST" \
  --url "$FAKE_STD" \
  --output "$TEST_DIR/none-out.md" \
  --raw "$TEST_DIR/none-raw.md" >"$TEST_DIR/none-stdout.txt" 2>"$TEST_DIR/none-stderr.txt"
NONE_RC=$?
set -e
assert_eq "kind=none 时 ingest --url exit 1" "1" "$NONE_RC"
if grep -q 'DAC-SPEC-006' "$TEST_DIR/none-stderr.txt"; then
  echo "  ✓ 报 DAC-SPEC-006"
  PASS=$((PASS + 1))
else
  echo "  ✗ 报 DAC-SPEC-006"
  echo "    stderr: $(cat "$TEST_DIR/none-stderr.txt")"
  FAIL=$((FAIL + 1))
fi

echo "Test 8c: --url 与已确认链接不一致则挡住"
bash "$RECORD_PRD" --kind standard --url "$FAKE_STD" >/dev/null
set +e
bash "$INGEST" \
  --url "$FAKE_OTHER" \
  --output "$TEST_DIR/mismatch-out.md" \
  --raw "$TEST_DIR/mismatch-raw.md" >"$TEST_DIR/mismatch-stdout.txt" 2>"$TEST_DIR/mismatch-stderr.txt"
MIS_RC=$?
set -e
assert_eq "url 不一致时 ingest --url exit 1" "1" "$MIS_RC"
if grep -q 'DAC-SPEC-008' "$TEST_DIR/mismatch-stderr.txt"; then
  echo "  ✓ 报 DAC-SPEC-008"
  PASS=$((PASS + 1))
else
  echo "  ✗ 报 DAC-SPEC-008"
  echo "    stderr: $(cat "$TEST_DIR/mismatch-stderr.txt")"
  FAIL=$((FAIL + 1))
fi

echo "Test 8d: 无 state 且无 --source 的 --url 也挡住"
NOSTATE="$TEST_DIR/nostate"
mkdir -p "$NOSTATE"
set +e
(
  cd "$NOSTATE"
  bash "$INGEST" \
    --url "$FAKE_STD" \
    --output "$NOSTATE/o.md" \
    --raw "$NOSTATE/r.md"
) >"$NOSTATE/stdout.txt" 2>"$NOSTATE/stderr.txt"
NS_RC=$?
set -e
assert_eq "无 state 无 --source 时 ingest --url exit 1" "1" "$NS_RC"
if grep -q 'DAC-SPEC-005' "$NOSTATE/stderr.txt"; then
  echo "  ✓ 无 state 也报 DAC-SPEC-005"
  PASS=$((PASS + 1))
else
  echo "  ✗ 无 state 也报 DAC-SPEC-005"
  echo "    stderr: $(cat "$NOSTATE/stderr.txt")"
  FAIL=$((FAIL + 1))
fi

echo "Test 8e: --input 不受 prd_source 门禁"
bash "$INGEST" \
  --input "$FIXTURE" \
  --output "$TEST_DIR/after-gate.md" \
  --raw "$TEST_DIR/after-gate-raw.md" \
  --extract "$TEST_DIR/after-gate-extract.json" >/dev/null
assert_file_exists "确认来源后 --input 仍可抽出" "$TEST_DIR/after-gate-extract.json"

echo "Test 8f: record 拒绝非 knowledge 链接"
set +e
bash "$RECORD_PRD" --kind standard --url "https://ddp.intra.xiaojukeji.com/issue/story/T-IBT-1" >/dev/null 2>"$TEST_DIR/ddp-url-stderr.txt"
DDP_RC=$?
set -e
assert_eq "DDP 链接不能当标准 PRD 记下" "1" "$DDP_RC"
if grep -q 'DAC-SPEC-007' "$TEST_DIR/ddp-url-stderr.txt"; then
  echo "  ✓ 报 DAC-SPEC-007"
  PASS=$((PASS + 1))
else
  echo "  ✗ 报 DAC-SPEC-007"
  echo "    stderr: $(cat "$TEST_DIR/ddp-url-stderr.txt")"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "通过 $PASS  失败 $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
