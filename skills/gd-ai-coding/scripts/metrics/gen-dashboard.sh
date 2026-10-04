#!/usr/bin/env bash
# =============================================================================
# gen-dashboard.sh — 将 dac-metrics-data.json 注入 HTML 模板，生成静态看板
# =============================================================================
# 用法：gen-dashboard.sh <data.json> <output.html>
# =============================================================================
set -euo pipefail

DATA_FILE="${1:?用法: gen-dashboard.sh <data.json> <output.html>}"
OUTPUT="${2:?用法: gen-dashboard.sh <data.json> <output.html>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/dashboard-app/dist-single/index.html"

[[ -f "$TEMPLATE" ]]   || { echo "❌ 找不到模板: $TEMPLATE" >&2; exit 1; }
[[ -f "$DATA_FILE" ]]  || { echo "❌ 找不到数据文件: $DATA_FILE" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "❌ 需要 python3" >&2; exit 1; }

python3 - "$TEMPLATE" "$DATA_FILE" "$OUTPUT" << 'PYEOF'
import sys, json, pathlib

tmpl = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
raw  = pathlib.Path(sys.argv[2]).read_text(encoding='utf-8').strip()

# 校验 JSON 合法性，残缺内容会抛异常并被 set -e 捕获
parsed = json.loads(raw)
# 静态导出用于分发，剔除 personal_totals 避免个人 vibe coding 数据随文件外泄
if isinstance(parsed, dict):
    parsed.pop('personal_totals', None)
# 重新序列化以规范化 + 转义 </ 防止 script 标签裂入
safe = (json.dumps(parsed, ensure_ascii=False)
            .replace('</',   '<\\/')
            .replace('<!--', '<\\!--'))

out = tmpl.replace('__DATA_PLACEHOLDER__', safe, 1)
pathlib.Path(sys.argv[3]).write_text(out, encoding='utf-8')
PYEOF

echo "✅ 已生成: $OUTPUT" >&2
