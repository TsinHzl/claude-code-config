#!/usr/bin/env bash
# gen-changelog.sh — 基于增量 git 历史，调用 claude -p 自动生成一条「更新日志」条目。
# 由 start.sh 后台触发，失败/无新增改动时静默退出，不影响主流程。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib.sh"

DIST_FILE="$SCRIPT_DIR/dashboard-app/dist/release-notes.json"
PUBLIC_FILE="$SCRIPT_DIR/dashboard-app/public/release-notes.json"
LOCK_DIR="/tmp/dac-gen-changelog.lock"
MAX_LOG_CHARS=15000
LOG_PREFIX="[gen-changelog]"

# ── 并发保护：锁已存在说明已有实例在跑，直接放弃退出（不排队）──────────
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "$LOG_PREFIX 已有实例在运行，本次放弃" >&2
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

# ── 水位线读取：优先 dist/，回退 public/ ─────────────────────────────
# 只取第一条 date 的前 10 位（YYYY-MM-DD）：历史遗留条目存在 "2026-08-05 ~ 08-06"
# 区间格式，但迁移后 baseline 与后续生成的新条目均为单日期格式并写在索引 0，
# 区间格式条目会被推到 index 1 之后、永远不会被当作水位线读取，故此处的正则
# 提取仅作防御性兜底，不代表脚本支持解析区间格式作为水位线。
water_file=""
if [[ -f "$DIST_FILE" ]]; then
  water_file="$DIST_FILE"
elif [[ -f "$PUBLIC_FILE" ]]; then
  water_file="$PUBLIC_FILE"
fi

watermark_date=""
if [[ -n "$water_file" ]]; then
  watermark_date=$(jq -r '.[0].date // empty' "$water_file" 2>/dev/null | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
fi
if [[ -z "$watermark_date" ]]; then
  # 兜底场景（非常规路径）：release-notes.json 缺失，用仓库最早一次 commit 日期兜底
  watermark_date=$(git -C "$REPO_ROOT" log --reverse --pretty=format:'%ad' --date=short | head -1)
fi

echo "$LOG_PREFIX 水位线日期: $watermark_date"

# ── git log 增量拉取：不含水位线当天（该日已处理，见 design.md 决策1）───
commit_list=$(git -C "$REPO_ROOT" log --since="${watermark_date} 23:59:59" --pretty=format:'%h|%ad|%s' --date=short)
if [[ -z "$commit_list" ]]; then
  echo "$LOG_PREFIX 无新增 commit，退出"
  exit 0
fi

stat_text=$(git -C "$REPO_ROOT" log --since="${watermark_date} 23:59:59" --stat --pretty=format:'commit %h|%ad|%s' --date=short)
log_text="$commit_list

---

$stat_text"

# 按字符数（非字节数）截断，避免从多字节 UTF-8 字符中间切断
log_tmp="$(mktemp)"
printf '%s' "$log_text" > "$log_tmp"
log_text=$(python3 -c "
import sys
text = open(sys.argv[1], encoding='utf-8').read()
limit = int(sys.argv[2])
if len(text) > limit:
    text = '[注意：以上内容已从尾部截断，仅包含水位线之后最近的部分改动]\n' + text[-limit:]
sys.stdout.write(text)
" "$log_tmp" "$MAX_LOG_CHARS")
rm -f "$log_tmp"

# ── 拼接 prompt 并调用 claude -p ──────────────────────────────────────
PROMPT="你是本仓库的更新日志生成助手。以下是仓库自 ${watermark_date} 之后的 git commit 历史（commit 摘要 + 文件改动统计）：

${log_text}

请只挑选用户可感知的重大功能改动（新功能、重要修复、架构调整），过滤掉格式化/typo/测试补充/文档微调等琢磨性 commit。
输出严格 JSON 对象，格式为：{\"date\": \"YYYY-MM-DD\", \"groups\": [{\"title\": \"分组标题\", \"items\": [\"改动描述1\", \"改动描述2\"]}]}
date 字段取今天的日期。只输出这一个 JSON 对象，不要输出任何解释性文字或 markdown 围栏。"

set +e
ai_output=$(claude -p "$PROMPT" 2>/tmp/dac-changelog-gen-claude.log)
claude_exit=$?
set -e

if [[ $claude_exit -ne 0 ]]; then
  echo "$LOG_PREFIX claude -p 调用失败（exit ${claude_exit}），跳过本次生成" >&2
  exit 1
fi

# ── AI 输出解析：复用 refresh-ddp.sh 的 extract_json_array 扫描模式，
#    改为扫描 '{' 定位对象，并校验 date/groups 字段存在 ─────────────
ai_raw_tmp="$(mktemp)"
ai_json_tmp="$(mktemp)"
printf '%s' "$ai_output" > "$ai_raw_tmp"

if ! python3 - "$ai_raw_tmp" "$ai_json_tmp" <<'PYEOF'
import sys, json
raw = open(sys.argv[1], encoding='utf-8').read()
obj = None
search_from = 0
while True:
    idx = raw.find('{', search_from)
    if idx == -1:
        print("[ERROR] no valid {date, groups} JSON object found in claude output", file=sys.stderr)
        sys.exit(1)
    try:
        candidate, _ = json.JSONDecoder().raw_decode(raw, idx)
        if isinstance(candidate, dict) and 'date' in candidate and 'groups' in candidate:
            obj = candidate
            break
    except json.JSONDecodeError:
        pass
    search_from = idx + 1
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    json.dump(obj, f, ensure_ascii=False)
PYEOF
then
  echo "$LOG_PREFIX AI 输出无法解析为合法 {date, groups} JSON，跳过本次生成" >&2
  rm -f "$ai_raw_tmp" "$ai_json_tmp"
  exit 1
fi
rm -f "$ai_raw_tmp"

new_date=$(jq -r '.date' "$ai_json_tmp")

# ── 空条目拦截：AI 判定「本次无用户可感知改动」时会返回 groups: [] 或 items 全空，
#    若继续写入会在看板留下一条「0 个模块 · 0 项变更」的占位条目。放在合并/前插
#    之前，同时覆盖「新日期前插」与「同日期合并 groups」两条路径。
if [[ "$(jq '[.groups[]?.items[]?] | length' "$ai_json_tmp")" -eq 0 ]]; then
  echo "$LOG_PREFIX AI 未产出任何变更条目（groups/items 为空），跳过写入"
  rm -f "$ai_json_tmp"
  exit 0
fi

# ── 合并/插入逻辑：新日期与现有第一条相同则合并 groups，否则整条前插 ──
for target in "$DIST_FILE" "$PUBLIC_FILE"; do
  [[ -f "$target" ]] || echo '[]' > "$target"
  existing_date=$(jq -r '.[0].date // empty' "$target")
  if [[ "$existing_date" == "$new_date" ]]; then
    atomic_jq '.[0].groups += $new[0].groups' "$target" --slurpfile new "$ai_json_tmp"
  else
    atomic_jq '[$new[0]] + .' "$target" --slurpfile new "$ai_json_tmp"
  fi
done

rm -f "$ai_json_tmp"
echo "$LOG_PREFIX 生成完成，新增/合并日期: $new_date"
