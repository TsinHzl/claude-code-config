#!/usr/bin/env bash
# ==============================================================================
# test-notify-dc.sh - notify-dc.py & cron-notify-dc.sh 回归测试
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
METRICS_DIR="$SCRIPT_DIR/../metrics"
NOTIFY_SCRIPT="$METRICS_DIR/notify-dc.py"
CRON_SCRIPT="$METRICS_DIR/cron-notify-dc.sh"

TEST_DIR=$(mktemp -d)
PASS=0
FAIL=0

MOCK_PORT=$(python3 -c '
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
')

cleanup() {
  if [[ -n "${MOCK_PID:-}" ]]; then
    kill "$MOCK_PID" 2>/dev/null || true
    wait "$MOCK_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT INT TERM

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

assert_contains() {
  local desc="$1" needle="$2" text="$3"
  if echo "$text" | grep -qF "$needle"; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc (not found: '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

# 准备测试数据与配置
MOCK_DATA="$TEST_DIR/data.json"
MOCK_REMARKS="$TEST_DIR/remarks.json"
MOCK_CACHE="$TEST_DIR/cache.json"
MOCK_CONFIG="$TEST_DIR/config.json"
MOCK_LOG="$TEST_DIR/mock-server.log"
UNREACHABLE_DASHBOARD="http://127.0.0.1:1"

cat << 'EOF' > "$MOCK_DATA"
{
  "requirements_index": [
    {
      "req_name": "REQ-DEV-UNREMARKED",
      "lines_added": 0,
      "commit_count": 0,
      "workflow_session_ids": [],
      "committers": ["zhangsan@didiglobal.com"],
      "rd_list": ["zhangsan@didiglobal.com", "unassigned@didiglobal.com"],
      "ddp": {
        "id": "1001",
        "title": "司机端待开发需求A",
        "state": "developing",
        "release_version_name": "Global司机端8.0.0",
        "release_version_time": "2099-12-31"
      }
    },
    {
      "req_name": "REQ-DEV-AI-ACTIVE",
      "lines_added": 120,
      "commit_count": 3,
      "workflow_session_ids": ["session-1"],
      "committers": ["lisi@didiglobal.com"],
      "rd_list": ["lisi@didiglobal.com"],
      "ddp": {
        "id": "1002",
        "title": "司机端已用AI需求B",
        "state": "开发中",
        "release_version_name": "Global司机端8.0.0",
        "release_version_time": "2099-12-31"
      }
    },
    {
      "req_name": "REQ-DEV-REMARKED",
      "lines_added": 0,
      "commit_count": 0,
      "workflow_session_ids": [],
      "committers": ["wangwu@didiglobal.com"],
      "rd_list": ["wangwu@didiglobal.com"],
      "ddp": {
        "id": "1003",
        "title": "司机端已填备注需求C",
        "state": "developing",
        "release_version_name": "Global司机端8.0.0",
        "release_version_time": "2099-12-31"
      }
    },
    {
      "req_name": "REQ-DEV-TECH",
      "lines_added": 0,
      "commit_count": 0,
      "workflow_session_ids": [],
      "committers": ["sunqi@didiglobal.com"],
      "rd_list": ["sunqi@didiglobal.com"],
      "is_technical": true,
      "ddp": {
        "id": "1005",
        "title": "司机端技术需求E",
        "state": "developing",
        "release_version_name": "Global司机端8.0.0",
        "release_version_time": "2099-12-31"
      }
    },
    {
      "req_name": "REQ-RELEASED",
      "lines_added": 0,
      "commit_count": 0,
      "workflow_session_ids": [],
      "committers": ["zhaoliu@didiglobal.com"],
      "rd_list": ["zhaoliu@didiglobal.com"],
      "ddp": {
        "id": "1004",
        "title": "司机端已上线需求D",
        "state": "released",
        "release_version_name": "Global司机端8.0.0",
        "release_version_time": "2099-12-31"
      }
    }
  ]
}
EOF

cat << 'EOF' > "$MOCK_REMARKS"
{
  "REQ-DEV-REMARKED": {
    "reason_tag": "非业务代码",
    "note": "仅改配置",
    "author": "wangwu"
  }
}
EOF

cat << EOF > "$MOCK_CONFIG"
{
  "webhook_url": "http://127.0.0.1:${MOCK_PORT}/dc/send",
  "send_mode": "webhook",
  "notify_nodes": ["developing", "开发中"],
  "dashboard_url": "http://127.0.0.1:47890",
  "cooldown_hours": 72
}
EOF

echo "Case 0: Codex 配置根默认路径"
DEFAULTS=$(DAC_CONFIG_HOME="$TEST_DIR/codex-dashboard" python3 - "$NOTIFY_SCRIPT" <<'PYEOF'
import importlib.util
import sys
spec = importlib.util.spec_from_file_location("notify_dc", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(mod.DEFAULT_CONFIG_PATH)
print(mod.DEFAULT_CACHE_PATH)
print(mod.DEFAULT_REMARKS_PATH)
PYEOF
)
assert_contains "默认配置使用 DAC_CONFIG_HOME" "$TEST_DIR/codex-dashboard/dc-config.json" "$DEFAULTS"
assert_contains "默认缓存使用 DAC_CONFIG_HOME" "$TEST_DIR/codex-dashboard/dc-notified-cache.json" "$DEFAULTS"
assert_contains "默认备注使用 DAC_CONFIG_HOME" "$TEST_DIR/codex-dashboard/remarks.json" "$DEFAULTS"

echo "Case 1: dry-run 模式测试"
OUTPUT=$(python3 "$NOTIFY_SCRIPT" \
  --config "$MOCK_CONFIG" \
  --data-file "$MOCK_DATA" \
  --remarks-file "$MOCK_REMARKS" \
  --cache-file "$MOCK_CACHE" \
  --dashboard-url "$UNREACHABLE_DASHBOARD" \
  --version-name "Global司机端8.0.0" \
  --dry-run 2>&1)

assert_contains "dry-run 群发 @ zhangsan" "将在群内发送提醒并 @ zhangsan" "$OUTPUT"
assert_contains "dry-run 消息含 @人语法 (空格分隔)" "@zhangsan " "$OUTPUT"
assert_contains "dry-run 需求标题匹配" "司机端待开发需求A" "$OUTPUT"
assert_contains "已采用 AI 需求跳过" "已采用 AI 需求数 (跳过): 1" "$OUTPUT"
assert_contains "已有备注需求跳过" "已有备注需求数 (跳过): 1" "$OUTPUT"
assert_contains "技术需求跳过 (统计范围外)" "技术需求数 (统计范围外, 跳过): 1" "$OUTPUT"
assert_contains "非开发中节点跳过" "节点匹配需求数: 3" "$OUTPUT"
assert_eq "dry-run 不生成缓存文件" "false" "$([[ -f "$MOCK_CACHE" ]] && echo "true" || echo "false")"

echo "Case 2: 启动 Mock DC Webhook 接收服务并执行正式推送"
python3 -c "
import http.server, json, sys

class MockHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length).decode('utf-8')
        with open('$MOCK_LOG', 'a', encoding='utf-8') as f:
            f.write(json.dumps({'body': json.loads(body)}) + '\n')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{\"code\":0,\"result\":{\"trace_id\":\"mock-trace-123\"}}')
    def log_message(self, format, *args): pass

server = http.server.HTTPServer(('127.0.0.1', $MOCK_PORT), MockHandler)
server.serve_forever()
" >/dev/null 2>&1 &
MOCK_PID=$!
sleep 0.5

OUTPUT=$(python3 "$NOTIFY_SCRIPT" \
  --config "$MOCK_CONFIG" \
  --data-file "$MOCK_DATA" \
  --remarks-file "$MOCK_REMARKS" \
  --cache-file "$MOCK_CACHE" \
  --dashboard-url "$UNREACHABLE_DASHBOARD" \
  --version-name "Global司机端8.0.0" 2>&1)

assert_contains "正式推送成功日志" "已发送群提醒并 @ zhangsan" "$OUTPUT"
assert_contains "记录 DC trace_id" "trace_id=mock-trace-123" "$OUTPUT"
assert_contains "实际通知人次为 1" "实际通知人次: 1" "$OUTPUT"
assert_eq "缓存文件已创建" "true" "$([[ -f "$MOCK_CACHE" ]] && echo "true" || echo "false")"

# 验证 Mock 接收的请求内容
MOCK_RECORD=$(cat "$MOCK_LOG" 2>/dev/null || true)
assert_eq "Mock 收到 1 条聚合消息" "1" "$(grep -cF '"body"' "$MOCK_LOG" 2>/dev/null || echo 0)"
assert_contains "Mock 收到 D-Chat text 字段" '"text"' "$MOCK_RECORD"
assert_contains "Mock 收到 markdown 字段" '"markdown": true' "$MOCK_RECORD"
assert_contains "Mock 收到 @人语法 (空格分隔)" "@zhangsan " "$MOCK_RECORD"
assert_eq "Mock 不含废弃 msg_type 字段" "0" "$(echo "$MOCK_RECORD" | grep -cF 'msg_type' || true)"
assert_eq "Mock 不含废弃 Authorization 头" "0" "$(echo "$MOCK_RECORD" | grep -cF 'Bearer' || true)"
assert_eq "技术需求负责人未被推送" "false" "$(echo "$MOCK_RECORD" | grep -qF 'sunqi' && echo "true" || echo "false")"

echo "Case 3: 防骚扰冷却周期测试"
OUTPUT=$(python3 "$NOTIFY_SCRIPT" \
  --config "$MOCK_CONFIG" \
  --data-file "$MOCK_DATA" \
  --remarks-file "$MOCK_REMARKS" \
  --cache-file "$MOCK_CACHE" \
  --dashboard-url "$UNREACHABLE_DASHBOARD" \
  --version-name "Global司机端8.0.0" 2>&1)

assert_contains "冷却期内跳过 zhangsan" "冷却期内记录 (跳过): 1" "$OUTPUT"
assert_contains "再次执行实际通知人次为 0" "实际通知人次: 0" "$OUTPUT"

echo "Case 4: cron-notify-dc.sh 包装脚本透传测试"
OUTPUT=$(bash "$CRON_SCRIPT" \
  --config "$MOCK_CONFIG" \
  --data-file "$MOCK_DATA" \
  --remarks-file "$MOCK_REMARKS" \
  --cache-file "$MOCK_CACHE" \
  --dashboard-url "$UNREACHABLE_DASHBOARD" \
  --version-name "Global司机端8.0.0" \
  --dry-run 2>&1)

CRON_LOG="${HOME}/Library/Logs/dac-notify-dc.log"
[[ ! -f "$CRON_LOG" ]] && CRON_LOG="/tmp/dac-notify-dc.log"
CRON_LOG_CONTENT=$(cat "$CRON_LOG" 2>/dev/null || true)
assert_contains "包装脚本执行正常" "DAC DC 提醒调度器启动" "$CRON_LOG_CONTENT"

echo "Case 5: DC Webhook 返回 code!=0 失败路径"
FAIL_LOG="$TEST_DIR/fail-server.log"
python3 -c "
import http.server, json

class FailHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        self.rfile.read(length)
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{\"code\":10001,\"errmsg\":\"invalid webhook\"}')
    def log_message(self, format, *args): pass

server = http.server.HTTPServer(('127.0.0.1', 0), FailHandler)
print(server.server_address[1], flush=True)
server.serve_forever()
" > "$FAIL_LOG" 2>&1 &
FAIL_PID=$!
sleep 0.5
FAIL_PORT=$(head -n 1 "$FAIL_LOG")

cat << EOF > "$MOCK_CONFIG"
{
  "webhook_url": "http://127.0.0.1:${FAIL_PORT}/dc/send",
  "send_mode": "webhook",
  "notify_nodes": ["developing", "开发中"],
  "dashboard_url": "http://127.0.0.1:47890",
  "cooldown_hours": 72
}
EOF
NEW_CACHE="$TEST_DIR/cache-case5.json"

OUTPUT=$(python3 "$NOTIFY_SCRIPT" \
  --config "$MOCK_CONFIG" \
  --data-file "$MOCK_DATA" \
  --remarks-file "$MOCK_REMARKS" \
  --cache-file "$NEW_CACHE" \
  --dashboard-url "$UNREACHABLE_DASHBOARD" \
  --version-name "Global司机端8.0.0" 2>&1)

assert_contains "code!=0 时输出错误码" "code=10001" "$OUTPUT"
assert_contains "code!=0 时推送失败日志" "[fail] 群提醒发送失败" "$OUTPUT"
assert_contains "失败路径实际通知人次为 0" "实际通知人次: 0" "$OUTPUT"
assert_eq "失败路径不写冷却缓存" "false" "$([[ -f "$NEW_CACHE" ]] && echo "true" || echo "false")"
kill "$FAIL_PID" 2>/dev/null || true

echo "Case 6: 3000 字符截断保护"
# 直接以内联方式验证 truncate 逻辑（避免 import 副作用）
TRUNC_RESULT=$(python3 - "$METRICS_DIR/notify-dc.py" << 'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("notify_dc", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
long_msg = "x" * 3500
out = mod.truncate_dc_text(long_msg)
print(len(out))
PYEOF
)
assert_eq "超长消息截断至 3000 字符" "3000" "$TRUNC_RESULT"

echo "=========================================="
echo "测试结果: PASS=$PASS, FAIL=$FAIL"
echo "=========================================="
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
