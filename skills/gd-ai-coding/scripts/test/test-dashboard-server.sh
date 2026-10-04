#!/usr/bin/env bash
# test-dashboard-server.sh — dashboard-server.py 路由回归测试
#
# 覆盖 Vue/Vite 迁移后未预期改变的既有行为：
#   - `/` 静态 serve 返回构建产物（dashboard-app/dist/index.html），Cache-Control 头存在
#   - `/assets/*` 返回构建产物资源，长缓存 Cache-Control 头存在，路径穿越仍被拦截
#   - `/api/config`、`/api/data`、`/api/status` 现有响应格式未被破坏
#   - `/release-notes.json` 文件存在时返回其内容，不存在时返回 200 + `[]`（不是 404）
#
# DATA_FILE(/tmp/dac-metrics-data.json)、PID_FILE(/tmp/dac-dashboard-server.pid) 与
# RELEASE_NOTES_FILE(dashboard-app/dist/release-notes.json) 是 dashboard-server.py 硬编码
# 的共享路径（无环境变量可覆盖）。若本机已有真实 dashboard server 在运行，测试期间会短暂
# 覆盖这三个文件内容，结束时通过 trap 恢复原始内容，不影响真实 server 进程本身的存活
#（该进程不会重新读取这几个文件）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
METRICS_DIR="$SCRIPT_DIR/../metrics"
DASHBOARD_SERVER="$METRICS_DIR/dashboard-server.py"
DIST_DIR="$METRICS_DIR/dashboard-app/dist"
DATA_FILE="/tmp/dac-metrics-data.json"
PID_FILE="/tmp/dac-dashboard-server.pid"
RELEASE_NOTES_FILE="$DIST_DIR/release-notes.json"

TEST_DIR=$(mktemp -d)
TEST_CONFIG_HOME="$TEST_DIR/codex-dashboard"
REMARKS_FILE="$TEST_CONFIG_HOME/remarks.json"
BACKEND_CONFIG_FILE="$TEST_CONFIG_HOME/backend-config.json"
TEST_PORT=$(python3 -c '
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
')

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

assert_contains() {
  local desc="$1" needle="$2" filepath="$3"
  if grep -qF "$needle" "$filepath" 2>/dev/null; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc (not found in file: '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

# ── Setup: 备份共享全局文件，退出时恢复 + 杀掉测试用 server 进程 ──────────────

DATA_FILE_BACKUP="$TEST_DIR/data-file.orig"
PID_FILE_BACKUP="$TEST_DIR/pid-file.orig"
RELEASE_NOTES_BACKUP="$TEST_DIR/release-notes.orig"
REMARKS_BACKUP="$TEST_DIR/remarks.orig"
BACKEND_CONFIG_BACKUP="$TEST_DIR/backend-config.orig"
[[ -f "$DATA_FILE" ]] && cp "$DATA_FILE" "$DATA_FILE_BACKUP"
[[ -f "$PID_FILE" ]] && cp "$PID_FILE" "$PID_FILE_BACKUP"
[[ -f "$RELEASE_NOTES_FILE" ]] && cp "$RELEASE_NOTES_FILE" "$RELEASE_NOTES_BACKUP"
[[ -f "$REMARKS_FILE" ]] && cp "$REMARKS_FILE" "$REMARKS_BACKUP" && rm -f "$REMARKS_FILE"
[[ -f "$BACKEND_CONFIG_FILE" ]] && cp "$BACKEND_CONFIG_FILE" "$BACKEND_CONFIG_BACKUP" && rm -f "$BACKEND_CONFIG_FILE"

# `trap cleanup EXIT` 覆盖正常退出、SIGINT/SIGTERM 等绝大多数退出路径（bash 的 EXIT
# 伪信号会在这些场景下触发）；唯一无法覆盖的是 SIGKILL（Unix 语义上不可被任何进程捕获），
# 若测试脚本本身被 SIGKILL，DATA_FILE/PID_FILE 会保留测试期间的覆写值。这是 bash trap
# 机制的固有边界，不依赖 dashboard-server.py 内部对 KeyboardInterrupt 的处理（后者只影响
# server 进程自身退出时的行为，与本脚本恢复共享文件的逻辑无关）。
SERVER_PID=""
MOCK_BACKEND_PID=""
cleanup() {
  if [[ -n "$MOCK_BACKEND_PID" ]]; then
    kill "$MOCK_BACKEND_PID" 2>/dev/null || true
    wait "$MOCK_BACKEND_PID" 2>/dev/null || true
  fi
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  if [[ -f "$DATA_FILE_BACKUP" ]]; then
    cp "$DATA_FILE_BACKUP" "$DATA_FILE"
  else
    rm -f "$DATA_FILE"
  fi
  if [[ -f "$PID_FILE_BACKUP" ]]; then
    cp "$PID_FILE_BACKUP" "$PID_FILE"
  else
    rm -f "$PID_FILE"
  fi
  if [[ -f "$RELEASE_NOTES_BACKUP" ]]; then
    cp "$RELEASE_NOTES_BACKUP" "$RELEASE_NOTES_FILE"
  else
    rm -f "$RELEASE_NOTES_FILE"
  fi
  if [[ -f "$REMARKS_BACKUP" ]]; then
    cp "$REMARKS_BACKUP" "$REMARKS_FILE"
  else
    rm -f "$REMARKS_FILE"
  fi
  if [[ -f "$BACKEND_CONFIG_BACKUP" ]]; then
    cp "$BACKEND_CONFIG_BACKUP" "$BACKEND_CONFIG_FILE"
  else
    rm -f "$BACKEND_CONFIG_FILE"
  fi
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# ── Setup: 写入测试用 DATA_FILE 固定内容 ──────────────────────────────────────

cat > "$DATA_FILE" <<'EOF'
{"committers": [], "__test_marker__": "dashboard-server-test-fixture"}
EOF

# ── Setup: 启动 server（测试端口，仅回环地址） ────────────────────────────────

DAC_PORT="$TEST_PORT" DAC_HOST=127.0.0.1 DAC_CONFIG_HOME="$TEST_CONFIG_HOME" python3 "$DASHBOARD_SERVER" \
  >"$TEST_DIR/server.out" 2>"$TEST_DIR/server.err" &
SERVER_PID=$!

READY=0
for _ in $(seq 1 50); do
  if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$TEST_PORT/api/status"; then
    READY=1
    break
  fi
  sleep 0.2
done
if [[ "$READY" -ne 1 ]]; then
  echo "server 未在预期时间内就绪，日志如下："
  cat "$TEST_DIR/server.err" || true
  exit 1
fi

BASE_URL="http://127.0.0.1:$TEST_PORT"

echo "═══ test-dashboard-server.sh ═══"
echo ""

# ── Test 1: `/` 返回构建产物 index.html，且带 no-cache 类 Cache-Control ──────

echo "Test 1: GET / 返回 dashboard-app/dist/index.html，Cache-Control 阻止缓存"
STATUS=$(curl -s -D "$TEST_DIR/h1.txt" -o "$TEST_DIR/b1.html" -w '%{http_code}' "$BASE_URL/")
assert_eq "状态码 200" "200" "$STATUS"
assert_contains "响应体来自实际构建产物（含标题标记）" "DAC 司机端工作流数据看板" "$TEST_DIR/b1.html"
assert_contains "Cache-Control 阻止缓存" "Cache-Control: no-cache, no-store, must-revalidate" "$TEST_DIR/h1.txt"

# ── Test 2: `/assets/*` 返回真实构建资源，长缓存 Cache-Control ───────────────

echo ""
echo "Test 2: GET /assets/<真实构建资源> 返回长缓存 Cache-Control"
ASSET_NAME=$(ls "$DIST_DIR/assets" | head -1)
STATUS=$(curl -s -D "$TEST_DIR/h2.txt" -o "$TEST_DIR/b2.bin" -w '%{http_code}' "$BASE_URL/assets/$ASSET_NAME")
assert_eq "状态码 200" "200" "$STATUS"
assert_contains "Cache-Control 长缓存" "Cache-Control: public, max-age=31536000, immutable" "$TEST_DIR/h2.txt"

# ── Test 3: `/assets/` 路径穿越仍被 realpath + commonpath 校验拦截 ───────────

echo ""
echo "Test 3: /assets/ 路径穿越请求被拦截（不返回 assets 目录之外的文件）"
STATUS=$(curl -s --path-as-is -o "$TEST_DIR/b3.bin" -w '%{http_code}' \
  "$BASE_URL/assets/../../../dashboard-server.py")
assert_eq "状态码 404" "404" "$STATUS"

# ── Test 3.1: `/favicon.svg` 与 `/dac-favicon-brand.svg` 静态文件路由及缓存头 ──────────────

echo ""
echo "Test 3.1: GET /favicon.svg 及 /dac-favicon-brand.svg 返回 200 与 1 小时缓存"
STATUS=$(curl -s -D "$TEST_DIR/h3_fav.txt" -o "$TEST_DIR/b3_fav.svg" -w '%{http_code}' "$BASE_URL/favicon.svg")
assert_eq "favicon.svg 状态码 200" "200" "$STATUS"
assert_contains "favicon.svg Content-Type 正确" "Content-Type: image/svg+xml" "$TEST_DIR/h3_fav.txt"
assert_contains "favicon.svg 1 小时缓存" "Cache-Control: public, max-age=3600" "$TEST_DIR/h3_fav.txt"

STATUS=$(curl -s -D "$TEST_DIR/h3_brand.txt" -o "$TEST_DIR/b3_brand.svg" -w '%{http_code}' "$BASE_URL/dac-favicon-brand.svg")
assert_eq "dac-favicon-brand.svg 状态码 200" "200" "$STATUS"
assert_contains "dac-favicon-brand.svg Content-Type 正确" "Content-Type: image/svg+xml" "$TEST_DIR/h3_brand.txt"
assert_contains "dac-favicon-brand.svg 1 小时缓存" "Cache-Control: public, max-age=3600" "$TEST_DIR/h3_brand.txt"

# ── Test 4: `/api/config` 响应格式未被破坏 ───────────────────────────────────

echo ""
echo "Test 4: GET /api/config 返回 vibeVisible 字段"
STATUS=$(curl -s -o "$TEST_DIR/b4.json" -w '%{http_code}' "$BASE_URL/api/config")
assert_eq "状态码 200" "200" "$STATUS"
assert_contains "响应含 vibeVisible: true" '"vibeVisible": true' "$TEST_DIR/b4.json"

# ── Test 5: `/api/data` 原样返回 DATA_FILE 内容 ──────────────────────────────

echo ""
echo "Test 5: GET /api/data 原样返回 DATA_FILE 内容"
STATUS=$(curl -s -o "$TEST_DIR/b5.json" -w '%{http_code}' "$BASE_URL/api/data")
assert_eq "状态码 200" "200" "$STATUS"
assert_contains "返回内容含测试 marker" "dashboard-server-test-fixture" "$TEST_DIR/b5.json"

# ── Test 6: `/api/status` 响应格式未被破坏 ───────────────────────────────────

echo ""
echo "Test 6: GET /api/status 返回 running 字段"
STATUS=$(curl -s -o "$TEST_DIR/b6.json" -w '%{http_code}' "$BASE_URL/api/status")
assert_eq "状态码 200" "200" "$STATUS"
assert_contains "响应含 running 字段" '"running"' "$TEST_DIR/b6.json"

# ── Test 7: `/release-notes.json` 文件存在时返回其内容 ──────────────────────

echo ""
echo "Test 7: GET /release-notes.json 文件存在时返回其内容"
cat > "$RELEASE_NOTES_FILE" <<'EOF'
[{"date":"2026-08-07","groups":[{"title":"测试分组","items":["release-notes-test-fixture"]}]}]
EOF
STATUS=$(curl -s -o "$TEST_DIR/b7.json" -w '%{http_code}' "$BASE_URL/release-notes.json")
assert_eq "状态码 200" "200" "$STATUS"
assert_contains "返回内容含测试 marker" "release-notes-test-fixture" "$TEST_DIR/b7.json"

# ── Test 8: `/release-notes.json` 文件不存在时返回 200 + [] ──────────────────

echo ""
echo "Test 8: GET /release-notes.json 文件不存在时返回 200 + []（不是 404）"
rm -f "$RELEASE_NOTES_FILE"
STATUS=$(curl -s -o "$TEST_DIR/b8.json" -w '%{http_code}' "$BASE_URL/release-notes.json")
assert_eq "状态码 200" "200" "$STATUS"
assert_eq "返回内容为空数组" "[]" "$(cat "$TEST_DIR/b8.json")"

# ── Test 9: `/api/remarks` 文件不存在时返回 {} ──────────────────────────────

echo ""
echo "Test 9: GET /api/remarks 文件不存在时返回 {}"
rm -f "$REMARKS_FILE"
STATUS=$(curl -s -o "$TEST_DIR/b9.json" -w '%{http_code}' "$BASE_URL/api/remarks")
assert_eq "状态码 200" "200" "$STATUS"
assert_eq "返回内容为空对象" "{}" "$(cat "$TEST_DIR/b9.json" | tr -d ' \n')"

# ── Test 10: `POST /api/remarks` 写入备注成功 ────────────────────────────────

echo ""
echo "Test 10: POST /api/remarks 写入需求备注并返回最新数据"
STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
  -d '{"req_name":"T-IBT-TEST","reason_tag":"非业务代码","note":"测试备注说明","author":"张三"}' \
  -o "$TEST_DIR/b10.json" -w '%{http_code}' "$BASE_URL/api/remarks")
assert_eq "状态码 200" "200" "$STATUS"
assert_contains "响应含需求名称" "T-IBT-TEST" "$TEST_DIR/b10.json"
assert_contains "响应含原因标签" "非业务代码" "$TEST_DIR/b10.json"
assert_contains "响应含更新时间戳" "updated_at" "$TEST_DIR/b10.json"

# ── Test 11: `POST /api/remarks` clear=true 清空备注 ─────────────────────────

echo ""
echo "Test 11: POST /api/remarks clear=true 清空需求备注"
STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
  -d '{"req_name":"T-IBT-TEST","clear":true}' \
  -o "$TEST_DIR/b11.json" -w '%{http_code}' "$BASE_URL/api/remarks")
assert_eq "状态码 200" "200" "$STATUS"
assert_eq "已清空备注对象" "{}" "$(cat "$TEST_DIR/b11.json" | tr -d ' \n')"

# ── Test 12: `POST /api/remarks` 缺少 req_name 时返回 400 ────────────────────

echo ""
echo "Test 12: POST /api/remarks 缺失 req_name 返回 400"
STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
  -d '{"note":"无需求名称"}' \
  -o "$TEST_DIR/b12.json" -w '%{http_code}' "$BASE_URL/api/remarks")
assert_eq "状态码 400" "400" "$STATUS"

# ── Test 13: 启动 mock 后端，GET /api/remarks 从远端拉取并刷新本地缓存 ─────────

echo ""
echo "Test 13: 启动 mock 后端，GET /api/remarks 从远端拉取并刷新本地缓存"
MOCK_PORT=$(python3 -c '
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
')
python3 -c "
import http.server, socketserver, json
class MockHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/v1/remarks':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'REQ-MOCK-1': {'reason_tag': '非业务代码', 'note': '远端拉取测试', 'author': '李四', 'updated_at': 1700000000000}}).encode())
    def do_POST(self):
        if self.path == '/api/v1/remarks':
            l = int(self.headers.get('Content-Length', 0))
            b = self.rfile.read(l)
            open('$TEST_DIR/mock_post.json', 'wb').write(b)
            self.send_response(200)
            self.end_headers()
http.server.HTTPServer(('127.0.0.1', $MOCK_PORT), MockHandler).serve_forever()
" >/dev/null 2>&1 &
MOCK_BACKEND_PID=$!
sleep 0.3

mkdir -p "$(dirname "$BACKEND_CONFIG_FILE")"
echo "{\"base_url\":\"http://127.0.0.1:$MOCK_PORT\",\"token\":\"mock-token\"}" > "$BACKEND_CONFIG_FILE"
rm -f "$REMARKS_FILE"

STATUS=$(curl -s -o "$TEST_DIR/b13.json" -w '%{http_code}' "$BASE_URL/api/remarks")
assert_eq "状态码 200" "200" "$STATUS"
assert_contains "响应包含 mock 后端数据" "REQ-MOCK-1" "$TEST_DIR/b13.json"
assert_contains "本地 remarks.json 已自动同步写入" "REQ-MOCK-1" "$REMARKS_FILE"

# ── Test 14: POST /api/remarks 同步推送至 mock 后端 ────────────────────────────

echo ""
echo "Test 14: POST /api/remarks 同步推送至 mock 后端"
STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
  -d '{"req_name":"REQ-MOCK-2","reason_tag":"仅改配置","note":"同步推送测试","author":"王五"}' \
  -o "$TEST_DIR/b14.json" -w '%{http_code}' "$BASE_URL/api/remarks")
assert_eq "状态码 200" "200" "$STATUS"
assert_contains "mock 后端收到推过来的备注" "REQ-MOCK-2" "$TEST_DIR/mock_post.json"

# ── Test 15: mock 后端宕机后，GET/POST 平滑降级本地文件存储 ──────────────────

echo ""
echo "Test 15: mock 后端异常时平滑降级本地读写"
kill "$MOCK_BACKEND_PID" 2>/dev/null || true
wait "$MOCK_BACKEND_PID" 2>/dev/null || true
MOCK_BACKEND_PID=""

STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
  -d '{"req_name":"REQ-LOCAL-ONLY","reason_tag":"排期较紧","note":"降级写入","author":"赵六"}' \
  -o "$TEST_DIR/b15.json" -w '%{http_code}' "$BASE_URL/api/remarks")
assert_eq "后端宕机时 POST 依然成功返回 200" "200" "$STATUS"
assert_contains "本地文件正常保留该备注" "REQ-LOCAL-ONLY" "$REMARKS_FILE"

# ── Test 16: local 快照的 requirements_index 回填到人员需求列表 ───────────────

# _do_stream_local 在集中部署时使用后端快照。快照可能已有完整 requirements_index，
# 但 committers[].requirements 是旧副本；此时必须按 committers/rd_list 重建人员 DDP 列表。
echo ""
echo "Test 16: local 快照索引中的 DDP 需求回填到人员需求列表"
DASHBOARD_SERVER="$DASHBOARD_SERVER" DAC_CONFIG_HOME="$TEST_CONFIG_HOME" python3 - <<'PY' > "$TEST_DIR/b16.json"
import importlib.util
import os

spec = importlib.util.spec_from_file_location('dashboard_server', os.environ['DASHBOARD_SERVER'])
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)

person_map = {
    'harriswu': {
        'committer': 'harriswu@didiglobal.com',
        'requirements': [{'req_name': 'driver-login', 'ddp': None, 'workflow_session_ids': ['session-1']}],
    },
}
req = {
    'req_name': 'T-IBT-TEST-DDP',
    'committers': ['harriswu@didiglobal.com'],
    'rd_list': [],
    'ddp': {'id': 'T-IBT-TEST-DDP'},
}
server._rebuild_person_requirements_from_index(person_map, [req])
print([item['req_name'] for item in person_map['harriswu']['requirements']])
PY
assert_contains "人员列表保留已有 trace 需求" "driver-login" "$TEST_DIR/b16.json"
assert_contains "人员列表补入索引中的 DDP 需求" "T-IBT-TEST-DDP" "$TEST_DIR/b16.json"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
