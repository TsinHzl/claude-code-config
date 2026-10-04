#!/usr/bin/env bash
# coverage-check.sh
# 双向覆盖校验：
# 1. 正向：prd-spec.md 中每个 §3.x 章节是否被至少一个 feature 的 related_requirements 覆盖
# 2. 反向：每个 feature 的 related_requirements 是否非空（可溯源）
# 由 feature-plan 步骤 3.2 调用

set -euo pipefail

STATE_FILE=".dac/state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "[DAC-STATE-003] ❌ .dac/state.json 不存在"
  exit 1
fi

REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE" 2>/dev/null)
if [[ -z "$REQ_NAME" ]]; then
  echo "[DAC-STATE-003] ❌ state.json 中缺少 req_name 字段"
  exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/../paths.sh"
PLAN_JSON="$(get_change_dir "$REQ_NAME")/feature-plan.json"
SPEC_FILE="$(get_prd_dir "$REQ_NAME")/prd-spec.md"

if [[ ! -f "$PLAN_JSON" ]]; then
  echo "[DAC-PLAN-003] ❌ feature-plan.json 不存在：$PLAN_JSON"
  exit 1
fi

if [[ ! -f "$SPEC_FILE" ]]; then
  echo "[DAC-PLAN-001] ❌ prd-spec.md 不存在：$SPEC_FILE"
  exit 1
fi

RESULT=$(python3 - "$SPEC_FILE" "$PLAN_JSON" <<'PYEOF' 2>&1
import json, re, sys

spec_file = sys.argv[1]
plan_json = sys.argv[2]

# 从 prd-spec.md 提取 §3.x 功能章节标题
with open(spec_file, encoding='utf-8') as f:
    spec_content = f.read()

# 匹配 ### 3.1 / ## §3.1 / ### §3.2 等章节头
spec_sections = []
for match in re.finditer(r'^#{2,4}\s*(§?3\.\d+)\s*(.*)$', spec_content, re.MULTILINE):
    ref = match.group(1)
    title = match.group(2).strip()
    if not ref.startswith('§'):
        ref = '§' + ref
    spec_sections.append((ref, title))

spec_refs = {s[0] for s in spec_sections}

if not spec_refs:
    print('WARN:prd-spec.md 中未找到 §3.x 章节，跳过覆盖校验')
    sys.exit(0)

# 加载 features（兼容 v1 包裹对象和 v0 纯数组）
with open(plan_json, encoding='utf-8') as f:
    data = json.load(f)
features = data.get('features', data) if isinstance(data, dict) else data

# 收集所有 related_requirements
feature_refs = set()
orphan_features = []
for feat in features:
    refs = feat.get('related_requirements', [])
    if not refs:
        orphan_features.append(f"{feat['id']} ({feat.get('name', '?')})")
    for r in refs:
        # 标准化引用格式
        m = re.search(r'(§?3\.\d+)', r)
        if m:
            ref = m.group(1)
            if not ref.startswith('§'):
                ref = '§' + ref
            feature_refs.add(ref)

# 正向检查：spec 中未被覆盖的章节
uncovered = spec_refs - feature_refs
# 反向检查：feature 无需求溯源
errors = []
warnings = []

if uncovered:
    errors.append(f'正向 gap：{len(uncovered)} 个需求章节未被任何功能覆盖：')
    for u in sorted(uncovered):
        title = next((s[1] for s in spec_sections if s[0] == u), '')
        errors.append(f'  - {u} {title}')

if orphan_features:
    warnings.append(f'反向 gap：{len(orphan_features)} 个功能无需求溯源（related_requirements 为空）：')
    for o in orphan_features:
        warnings.append(f'  - {o}')

if errors:
    for e in errors:
        print(e)
    if warnings:
        for w in warnings:
            print(w)
    sys.exit(1)
elif warnings:
    for w in warnings:
        print('WARN:' + warnings[0])
        for w in warnings[1:]:
            print(w)
    sys.exit(0)
else:
    print(f'OK:{len(spec_refs)}:{len(features)}')
    sys.exit(0)
PYEOF
) || {
  echo "[DAC-PLAN-005] ❌ 需求覆盖校验失败："
  echo "$RESULT"
  echo ""
  echo "   请补充 feature 的 related_requirements 或新增 feature 覆盖遗漏的需求章节"
  exit 1
}

if echo "$RESULT" | grep -q "^OK:"; then
  SPEC_COUNT=$(echo "$RESULT" | cut -d: -f2)
  FEAT_COUNT=$(echo "$RESULT" | cut -d: -f3)
  echo "✅ 双向覆盖校验通过（需求章节 ${SPEC_COUNT} 项，功能 ${FEAT_COUNT} 个，全部覆盖）"
elif echo "$RESULT" | grep -q "^WARN:"; then
  echo "⚠️  $(echo "$RESULT" | sed 's/^WARN://')"
fi
