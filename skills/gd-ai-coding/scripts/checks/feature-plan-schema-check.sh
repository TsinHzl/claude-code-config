#!/usr/bin/env bash
# feature-plan-schema-check.sh
# 校验 feature-plan.json 的结构完整性（必填字段、类型枚举、proposal_scope 格式）
# 由 pre-skill-check.sh (feature-loop) 调用

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

if [[ ! -f "$PLAN_JSON" ]]; then
  echo "[DAC-PLAN-003] ❌ feature-plan.json 不存在：$PLAN_JSON"
  exit 1
fi

RESULT=$(python3 - "$PLAN_JSON" <<'PYEOF' 2>&1
import json, sys, re

PLAN_JSON = sys.argv[1]

REQUIRED_FIELDS = {
    'id': str,
    'name': str,
    'description': str,
    'type': str,
    'dependencies': list,
    'related_requirements': list,
    'proposal_scope': dict,
    'status': str,
}
VALID_TYPES = {'page', 'component', 'service', 'refactor'}
VALID_STATUSES = {'pending', 'in_progress', 'done', 'failed', 'skipped'}
SCOPE_REQUIRED = {'new_files': list, 'modified_files': list, 'proposal_section': str}

errors = []

try:
    with open(PLAN_JSON) as f:
        data = json.load(f)
except json.JSONDecodeError as e:
    print(f'JSON 解析失败：{e}')
    sys.exit(1)

# 兼容 v0（纯数组）和 v1（包裹对象 {"schema_version": 1, "features": [...]}）
if isinstance(data, dict):
    features = data.get('features', [])
    schema_ver = data.get('schema_version', 0)
    if not isinstance(features, list):
        print('feature-plan.json .features 字段必须是数组')
        sys.exit(1)
elif isinstance(data, list):
    features = data
else:
    print('feature-plan.json 格式不合法（需为数组或含 features 字段的对象）')
    sys.exit(1)

if len(features) == 0:
    print('feature-plan.json 功能列表为空')
    sys.exit(1)

seen_ids = set()
for i, feat in enumerate(features):
    prefix = f'features[{i}] (id={feat.get("id", "?")})'

    if not isinstance(feat, dict):
        errors.append(f'{prefix}: 不是有效的 JSON 对象')
        continue

    # 检查必填字段
    for field, expected_type in REQUIRED_FIELDS.items():
        if field not in feat:
            errors.append(f'{prefix}: 缺少必填字段 "{field}"')
        elif feat[field] is not None and not isinstance(feat[field], expected_type):
            errors.append(f'{prefix}: "{field}" 类型应为 {expected_type.__name__}，实际为 {type(feat[field]).__name__}')

    # 检查 type 枚举
    feat_type = feat.get('type', '')
    if feat_type and feat_type not in VALID_TYPES:
        errors.append(f'{prefix}: type "{feat_type}" 不合法，有效值：{VALID_TYPES}')

    # 检查 status 枚举
    feat_status = feat.get('status', '')
    if feat_status and feat_status not in VALID_STATUSES:
        errors.append(f'{prefix}: status "{feat_status}" 不合法，有效值：{VALID_STATUSES}')

    # 检查 proposal_scope 子结构
    scope = feat.get('proposal_scope')
    if isinstance(scope, dict):
        for sf, sf_type in SCOPE_REQUIRED.items():
            if sf not in scope:
                errors.append(f'{prefix}: proposal_scope 缺少 "{sf}"')
            elif not isinstance(scope[sf], sf_type):
                errors.append(f'{prefix}: proposal_scope.{sf} 类型应为 {sf_type.__name__}')

    # 检查 ID 格式
    feat_id = feat.get('id', '')
    if feat_id and not re.match(r'^[a-z][a-z0-9]*(-[a-z0-9]+)*$', feat_id):
        errors.append(f'{prefix}: ID "{feat_id}" 格式不合法，应为 kebab-case 且与 specs/ 目录名一致（如 user-auth、order-detail），不支持下划线')

    # 检查 ID 唯一性
    if feat_id in seen_ids:
        errors.append(f'{prefix}: ID "{feat_id}" 重复')
    seen_ids.add(feat_id)

    # 可选 assignee：存在时必须是 string；空串放行（视为缺省，交给 assign.sh 把关 @）
    if 'assignee' in feat and not isinstance(feat['assignee'], str):
        errors.append(f'{prefix}: assignee 类型应为 string，实际为 {type(feat["assignee"]).__name__}')

if errors:
    for e in errors:
        print(f'  - {e}')
    sys.exit(1)
else:
    print(f'OK:{len(features)}')
    sys.exit(0)
PYEOF
) || {
  echo "[DAC-PLAN-003] ❌ feature-plan.json schema 校验失败："
  echo "$RESULT"
  exit 1
}

FEAT_COUNT=$(echo "$RESULT" | grep -oE 'OK:[0-9]+' | cut -d: -f2)
echo "✅ feature-plan.json schema 校验通过（${FEAT_COUNT:-?} 个功能）"
