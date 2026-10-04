#!/usr/bin/env bash
# write-single-feature-plan.sh — skip_feature_plan 时仍保留 OpenSpec proposal，
# 只跳过「拆成多个 feature」。从已生成的 proposal.md 写成单 feature plan。
#
# 前置：opsx:propose 已写出 openspec/changes/{req}/proposal.md（本脚本不替代 propose）。
# 用法：在目标 Flutter 仓库根目录执行
#   bash ~/.claude/skills/gd-ai-coding/scripts/feature/write-single-feature-plan.sh
#
# 若 feature-plan.json 已有多于 1 个 feature，不覆盖。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../paths.sh"

STATE_FILE=".dac/state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "[write-single-feature-plan] ❌ .dac/state.json 不存在" >&2
  exit 1
fi

REQ_NAME=$(jq -r '.req_name // empty' "$STATE_FILE")
if [[ -z "$REQ_NAME" ]]; then
  echo "[write-single-feature-plan] ❌ state.json 中 req_name 为空" >&2
  exit 1
fi

CHANGE_DIR="$(get_change_dir "$REQ_NAME")"
PROPOSAL="$CHANGE_DIR/proposal.md"
PLAN_JSON="$CHANGE_DIR/feature-plan.json"
SPEC_FILE="$(get_prd_dir "$REQ_NAME")/prd-spec.md"
PLATFORM=$(jq -r '.available_platforms | keys[0] // "flutter"' "$STATE_FILE" 2>/dev/null || echo "flutter")

if [[ ! -s "$PROPOSAL" ]]; then
  echo "[write-single-feature-plan] ❌ 缺少 $PROPOSAL — skip_feature_plan 只跳过拆分，必须先执行 opsx:propose" >&2
  exit 1
fi

mkdir -p "$CHANGE_DIR"

python3 - "$PROPOSAL" "$PLAN_JSON" "$SPEC_FILE" "$REQ_NAME" "$PLATFORM" <<'PY'
import json, os, re, sys
from pathlib import Path

proposal_path, plan_path, spec_path, req_name, platform = sys.argv[1:6]
plan = Path(plan_path)
if plan.exists() and plan.stat().st_size > 0:
    try:
        data = json.loads(plan.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        data = None
    if data is not None:
        feats = data.get("features", data) if isinstance(data, dict) else data
        if isinstance(feats, list) and len(feats) > 1:
            print(f"[write-single-feature-plan] ⏭ 已有 {len(feats)} 个 feature，不覆盖 {plan_path}")
            sys.exit(0)

text = Path(proposal_path).read_text(encoding="utf-8")

# Backtick file paths (OpenSpec "What Changes" 常见写法)
ext = r"dart|kt|java|swift|vue|ts|tsx|js|json|xml|gradle|plist|m|h|mm"
pat = re.compile(r"`([A-Za-z0-9_./\-]+?\.(?:" + ext + r"))`")
seen = []
for m in pat.finditer(text):
    p = m.group(1).lstrip("./")
    if p not in seen:
        seen.append(p)

new_files, modified_files = [], []
for p in seen:
    if os.path.exists(p):
        modified_files.append(p)
    else:
        new_files.append(p)

section = ""
for m in re.finditer(r"^##\s+(.+)$", text, re.MULTILINE):
    title = m.group(1).strip()
    if re.match(r"(?i)why|what changes|impact|risk|rollback", title):
        continue
    section = "## " + title
    break

related = []
spec = Path(spec_path)
if spec.is_file():
    spec_text = spec.read_text(encoding="utf-8")
    for m in re.finditer(r"^#{2,4}\s*(§?3\.\d+)\s*(.*)$", spec_text, re.MULTILINE):
        ref = m.group(1)
        if not ref.startswith("§"):
            ref = "§" + ref
        title = m.group(2).strip()
        related.append(f"{ref} {title}".strip() if title else ref)
if not related:
    related = ["§3.1"]

blob = " ".join(seen).lower()
if any(k in blob for k in ("page", "view", "screen", "widget")):
    feat_type = "page"
elif any(k in blob for k in ("repository", "service", "usecase", "api")):
    feat_type = "service"
else:
    feat_type = "page"

# 首个非空非标题行作 description
desc = req_name
for line in text.splitlines():
    s = line.strip()
    if not s or s.startswith("#") or s.startswith(">"):
        continue
    desc = s[:100]
    break

feature = {
    "id": "feat-01",
    "name": req_name,
    "description": desc,
    "type": feat_type,
    "platform": platform,
    "dependencies": [],
    "related_requirements": related,
    "design_nodes": [],
    "proposal_scope": {
        "new_files": new_files,
        "modified_files": modified_files,
        "proposal_section": section,
    },
    "status": "pending",
    "current_step": None,
    "error_log": [],
    "started_at": None,
    "updated_at": None,
}

plan.write_text(json.dumps([feature], ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(
    f"[write-single-feature-plan] ✓ {plan_path} "
    f"(new={len(new_files)} modified={len(modified_files)} related={len(related)})"
)
PY

# skip_feature_plan 跳过 LLM 拆分，也就跳过了 index.json 的 design_backfill。
# 单 feature 覆盖整次需求：把尚未关联的设计稿挂到该 feature，否则 copy-design-assets
# 会 exit 2（用户明明在 1.1 给过 MasterGo 链接）。
INDEX="$CHANGE_DIR/ui/index.json"
if [[ -f "$INDEX" ]]; then
  PLAN_LEN=$(jq 'if type == "array" then length else (.features | length) end' "$PLAN_JSON")
  if [[ "$PLAN_LEN" == "1" ]]; then
    FEAT_ID=$(jq -r 'if type == "array" then .[0].id else .features[0].id end' "$PLAN_JSON")
    TMP=$(mktemp)
    jq --arg fid "$FEAT_ID" \
      'map(if ((.features // []) | length) == 0 then .features = [$fid] | .mapping = "auto" else . end)' \
      "$INDEX" > "$TMP" && mv "$TMP" "$INDEX"
    echo "[write-single-feature-plan] ✓ 回填 $INDEX features=[$FEAT_ID]"
  fi
fi
