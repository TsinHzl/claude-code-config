#!/usr/bin/env bash
# dependency-check.sh
# 检测 feature-plan.json 中功能依赖图的循环依赖（DFS 三色标记法）
# 同时验证所有依赖目标 ID 存在
# 由 feature-plan 步骤 5 保存前调用

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
import json, sys

plan_json = sys.argv[1]

with open(plan_json) as f:
    data = json.load(f)
features = data.get('features', data) if isinstance(data, dict) else data

ids = {f['id'] for f in features}
graph = {}
for f in features:
    graph[f['id']] = f.get('dependencies', [])

# 验证所有依赖目标存在
for feat_id, deps in graph.items():
    for dep in deps:
        if dep not in ids:
            print(f'[DAC-DEP-002] ❌ 功能 {feat_id} 依赖不存在的 ID：{dep}')
            sys.exit(1)

# DFS 三色标记检测环
WHITE, GRAY, BLACK = 0, 1, 2
color = {fid: WHITE for fid in ids}
path = []

def dfs(node):
    color[node] = GRAY
    path.append(node)
    for neighbor in graph.get(node, []):
        if color[neighbor] == GRAY:
            cycle_start = path.index(neighbor)
            cycle = path[cycle_start:] + [neighbor]
            print(f'[DAC-DEP-001] ❌ 循环依赖：{" → ".join(cycle)}')
            sys.exit(1)
        elif color[neighbor] == WHITE:
            dfs(neighbor)
    path.pop()
    color[node] = BLACK

for fid in sorted(ids):
    if color[fid] == WHITE:
        dfs(fid)

# 输出拓扑排序结果（执行顺序）
topo_order = []
visited = set()

def topo_dfs(node):
    if node in visited:
        return
    visited.add(node)
    for dep in graph.get(node, []):
        topo_dfs(dep)
    topo_order.append(node)

for fid in sorted(ids):
    topo_dfs(fid)

print(f'OK:{len(ids)}:{",".join(topo_order)}')
PYEOF
) || {
  echo "$RESULT"
  exit 1
}

if echo "$RESULT" | grep -q "^OK:"; then
  FEAT_COUNT=$(echo "$RESULT" | cut -d: -f2)
  TOPO_ORDER=$(echo "$RESULT" | cut -d: -f3)
  echo "✅ 依赖图校验通过（${FEAT_COUNT} 个功能，无循环依赖）"
  echo "   执行顺序：$(echo "$TOPO_ORDER" | tr ',' ' → ')"
else
  echo "$RESULT"
  exit 1
fi
