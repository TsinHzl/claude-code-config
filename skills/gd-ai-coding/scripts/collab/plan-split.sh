#!/usr/bin/env bash
# plan-split.sh — 只读分析 feature-plan.json 的 DAG 分层、文件交叉与并行建议
# 用法：plan-split.sh
# 输入：从 .dac/state.json 读取 req_name → openspec/changes/{req}/feature-plan.json
# 输出：stdout JSON —— {layers, overlaps, chain_depth, recommendation}
# 错误码：
#   [DAC-PLAN-007] feature-plan.json 不存在
#   [DAC-STATE-003] state.json 或 req_name 缺失

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../paths.sh"

STATE_FILE=".dac/state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "[DAC-STATE-003] ❌ .dac/state.json 不存在" >&2
  exit 1
fi

REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE" 2>/dev/null)
if [[ -z "$REQ_NAME" ]]; then
  echo "[DAC-STATE-003] ❌ state.json 缺少 req_name" >&2
  exit 1
fi

PLAN_JSON="$(get_change_dir "$REQ_NAME")/feature-plan.json"
if [[ ! -f "$PLAN_JSON" ]]; then
  echo "[DAC-PLAN-007] ❌ feature-plan.json 不存在：$PLAN_JSON" >&2
  exit 1
fi

python3 - "$PLAN_JSON" <<'PYEOF'
import json, sys
from collections import defaultdict, deque

with open(sys.argv[1]) as f:
    data = json.load(f)

features = data.get('features', data) if isinstance(data, dict) else data
if not isinstance(features, list) or not features:
    print(json.dumps({"error": "empty features"}))
    sys.exit(1)

by_id = {f['id']: f for f in features}
deps = {f['id']: list(f.get('dependencies', [])) for f in features}

# 拓扑分层（Kahn）：无入度为一层
indeg = {fid: len(deps[fid]) for fid in by_id}
layers = []
remaining = set(by_id.keys())
while remaining:
    layer = sorted([fid for fid in remaining if indeg[fid] == 0])
    if not layer:
        # 有环，剩余节点都放在最后一层（此处不做循环检测，dependency-check.sh 已负责）
        layers.append(sorted(list(remaining)))
        break
    layers.append(layer)
    for fid in layer:
        remaining.discard(fid)
        for other in remaining:
            if fid in deps[other]:
                indeg[other] -= 1

# 文件交叉：对每对 feature 计算 proposal_scope 交集
def scope_files(f):
    s = f.get('proposal_scope') or {}
    return set(s.get('new_files', []) or []) | set(s.get('modified_files', []) or [])

overlaps = []
seen = set()
fids = list(by_id.keys())
for i in range(len(fids)):
    for j in range(i + 1, len(fids)):
        a, b = fids[i], fids[j]
        inter = scope_files(by_id[a]) & scope_files(by_id[b])
        if inter:
            key = (a, b)
            if key in seen:
                continue
            seen.add(key)
            overlaps.append({"features": [a, b], "files": sorted(inter)})

# 最长依赖链深度（DAG 最长路径）
memo = {}
def depth(fid):
    if fid in memo:
        return memo[fid]
    if not deps[fid]:
        memo[fid] = 1
    else:
        memo[fid] = 1 + max(depth(d) for d in deps[fid] if d in by_id) if any(d in by_id for d in deps[fid]) else 1
    return memo[fid]

chain_depth = max((depth(fid) for fid in by_id), default=0)

# 推荐值 —— 阈值一起打进 stdout，skill 展示时可直接引用来源
CHAIN_DEPTH_SERIAL_THRESHOLD = 4       # 链深 ≥ 该值 → 建议串行（拆两人整体更慢）
OVERLAP_RATIO_FIX_THRESHOLD = 0.5      # 涉及交叉的 feature 占比 > 该值 → 建议先改 plan

n_feat = len(features)
overlap_feats = set()
for o in overlaps:
    overlap_feats.update(o['features'])
overlap_ratio = len(overlap_feats) / n_feat if n_feat else 0

if chain_depth >= CHAIN_DEPTH_SERIAL_THRESHOLD:
    recommendation = "serial_only"
    reason = f"chain_depth={chain_depth} ≥ {CHAIN_DEPTH_SERIAL_THRESHOLD}（长依赖链，拆两人整体更慢）"
elif overlap_ratio > OVERLAP_RATIO_FIX_THRESHOLD:
    recommendation = "fix_plan"
    reason = f"overlap_ratio={overlap_ratio:.2f} > {OVERLAP_RATIO_FIX_THRESHOLD}（超半数 feature 存在文件交集，先调整 feature-plan 边界降低耦合）"
else:
    recommendation = "parallel_ok"
    reason = f"chain_depth={chain_depth} < {CHAIN_DEPTH_SERIAL_THRESHOLD} 且 overlap_ratio={overlap_ratio:.2f} ≤ {OVERLAP_RATIO_FIX_THRESHOLD}"

print(json.dumps({
    "layers": layers,
    "overlaps": overlaps,
    "chain_depth": chain_depth,
    "overlap_ratio": round(overlap_ratio, 2),
    "recommendation": recommendation,
    "reason": reason,
    "thresholds": {
        "chain_depth_serial": CHAIN_DEPTH_SERIAL_THRESHOLD,
        "overlap_ratio_fix": OVERLAP_RATIO_FIX_THRESHOLD,
    },
}, ensure_ascii=False, indent=2))
PYEOF