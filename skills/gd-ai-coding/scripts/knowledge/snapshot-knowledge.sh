#!/usr/bin/env bash
# snapshot-knowledge.sh — Lock knowledge files at loop start for cache prefix stability.
#
# 每个 feature 的 CR 环节会通过 extract-constraints.sh 向 constraints.md 追加新发现的问题。
# 如果 codegen prompt 直接读原始文件，每个 feature 执行后文件内容都会变化 → prompt 前缀变了
# → API cache 失效 → 每次都要重新计算完整 prompt。
#
# 用 snapshot 锁定内容后，N 个 feature 的 codegen prompt 前缀完全一致（knowledge 部分不变），
# 只有 code-scope / design 等尾部内容不同，cache 命中率从 0% 提升到接近 100%（前缀缓存 TTL 5 分钟内）。
#
# Trade-off：后续 feature 的 codegen 不会看到前面 feature CR 新发现的 constraints。
# 但这些 constraints 已经体现在已生成的代码中（作为 pattern），影响可控。
#
# Usage: snapshot-knowledge.sh [--clean]
#   (no args)  Create snapshots from current knowledge files
#   --clean    Remove snapshot files (call at loop end)
set -euo pipefail

KNOWLEDGE_DIR=".dac/knowledge"

if [[ "${1:-}" == "--clean" ]]; then
  rm -f "$KNOWLEDGE_DIR/constraints.snapshot.md"
  rm -f "$KNOWLEDGE_DIR/error-patterns.snapshot.md"
  rm -f "$KNOWLEDGE_DIR/dep-catalog.md"
  echo "✓ Knowledge snapshots cleaned"
  exit 0
fi

if [[ ! -d "$KNOWLEDGE_DIR" ]]; then
  echo "WARN: $KNOWLEDGE_DIR not found, skipping snapshot" >&2
  exit 0
fi

if [[ -f "$KNOWLEDGE_DIR/constraints.md" ]]; then
  cp "$KNOWLEDGE_DIR/constraints.md" "$KNOWLEDGE_DIR/constraints.snapshot.md"
fi

# 协作模式：合并 openspec 副本（来自对方 CR 的约束）到 snapshot；按 "## [DATE] feat_id"
# 章节去重，仅追加本地缺失的章节。前提是本机存在 .dac/state.json 且对应 openspec/changes/{req}/
# 目录有 collab.json 与 knowledge/constraints.md 副本。
_state_file=".dac/state.json"
if [[ -f "$_state_file" ]]; then
  _req_name=$(jq -r '.req_name // empty' "$_state_file" 2>/dev/null || echo "")
  if [[ -n "$_req_name" ]]; then
    _collab_json="openspec/changes/$_req_name/collab.json"
    _openspec_constraints="openspec/changes/$_req_name/knowledge/constraints.md"
    _snapshot="$KNOWLEDGE_DIR/constraints.snapshot.md"
    if [[ -f "$_collab_json" && -f "$_openspec_constraints" ]]; then
      # 确保 snapshot 存在（空 constraints 时也建立）
      [[ -f "$_snapshot" ]] || : > "$_snapshot"
      _merged=$(python3 - "$_openspec_constraints" "$_snapshot" <<'PYEOF'
import re, sys
with open(sys.argv[1], encoding='utf-8') as f: src = f.read()
with open(sys.argv[2], encoding='utf-8') as f: dst = f.read()
# 章节以 "## [YYYY-MM-DD] feat_id" 起始
_pat = re.compile(r'^## \[\d{4}-\d{2}-\d{2}\] ', re.M)
existing_headers = set()
for m in _pat.finditer(dst):
    header_line = dst[m.start():dst.find('\n', m.start()) if dst.find('\n', m.start()) != -1 else len(dst)]
    existing_headers.add(header_line.strip())
# 切分 src 章节
segments = []
positions = [m.start() for m in _pat.finditer(src)] + [len(src)]
for i in range(len(positions) - 1):
    seg = src[positions[i]:positions[i+1]]
    header = seg.splitlines()[0].strip() if seg else ""
    if header and header not in existing_headers:
        segments.append(seg)
appended = 0
if segments:
    with open(sys.argv[2], 'a', encoding='utf-8') as f:
        if dst and not dst.endswith('\n'):
            f.write('\n')
        for seg in segments:
            f.write(seg)
            if not seg.endswith('\n'):
                f.write('\n')
        appended = len(segments)
print(appended)
PYEOF
)
      if [[ "${_merged:-0}" -gt 0 ]]; then
        echo "✓ 合并 openspec constraints 副本：$_merged 个新章节 → snapshot"
      fi
    fi
  fi
fi

if [[ -f "$KNOWLEDGE_DIR/error-patterns.md" ]]; then
  cp "$KNOWLEDGE_DIR/error-patterns.md" "$KNOWLEDGE_DIR/error-patterns.snapshot.md"
fi

# Generate component dependency catalog (graphify-based, with grep fallback)
bash "$(dirname "$0")/gen-dep-catalog.sh" 2>/dev/null || true

echo "✓ Knowledge snapshots created"
