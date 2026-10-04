#!/usr/bin/env python3
"""
DAC Dashboard HTTP Server
Usage: python3 dashboard-server.py [port]
"""
import calendar
import copy
import http.server
import importlib.util
import json
import mimetypes
import os
import shutil
import socketserver
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, timedelta
from typing import Dict, List
from urllib.parse import urlencode, urlparse

PORT = int(os.environ.get('DAC_PORT', 47890))
# 监听地址：默认 0.0.0.0（全网卡），使部署在服务器上时可经外部 IP 访问；
# 本地想收敛到回环可设 DAC_HOST=127.0.0.1
HOST = os.environ.get('DAC_HOST', '0.0.0.0')
# DDP 数据源模式：'mcp'（默认，调 DDP MCP 全量拉取）/ 'local'（不调 DDP MCP，只读后端
# 已存的 DDP 快照 + trace 汇总，用于无法配置 DDP MCP 的服务器）
DDP_SOURCE = os.environ.get('DAC_DDP_SOURCE', 'mcp').strip().lower()
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DIST_DIR = os.path.join(SCRIPT_DIR, 'dashboard-app', 'dist')
DATA_FILE = '/tmp/dac-metrics-data.json'
_DASHBOARD_CONFIG_HOME = os.environ.get(
    'DAC_CONFIG_HOME',
    os.path.expanduser('~/.claude/skills/dashboard'),
)
REMARKS_FILE = os.path.join(_DASHBOARD_CONFIG_HOME, 'remarks.json')
REFRESH_SCRIPT = os.path.join(SCRIPT_DIR, 'refresh-ddp.sh')
PID_FILE = '/tmp/dac-dashboard-server.pid'

_refresh_lock = threading.Lock()
_refresh_state = {'running': False, 'last_updated': None, 'error': None}
_stream_lock = threading.Lock()
_stream_cancel = threading.Event()  # set by new connection to abort the running stream
_remarks_lock = threading.Lock()

# /api/data 下发时实时补拉 personal_totals 的内存缓存。磁盘快照的 personal_totals 只在
# 重量级全量刷新末尾落盘，页面加载若直接下发会让 vibe coding 冻结在上次刷新时刻（实测十几
# 小时）；personal-summary 是轻量 GET，按 TTL 补拉即可。进程重启即失效，无需落盘。
_PERSONAL_FRESH_TTL = 30
_personal_fresh_cache = {'ts': 0.0, 'data': None}
_personal_fresh_lock = threading.Lock()

# DDP config is read dynamically from ~/.claude.json on each call — no hardcoded URL/token
_CLAUDE_JSON = os.path.expanduser('~/.claude.json')

# dac-trace backend config: shared with Shell 脚本 (report-trace-backend.sh) 的同一份文件；
# DAC_TRACE_BACKEND_URL 环境变量可覆盖 base_url，token 始终来自文件
_DAC_TRACE_BACKEND_CONFIG = os.path.join(_DASHBOARD_CONFIG_HOME, 'backend-config.json')

# Driver Mobile Tech team — (ldap, display_name) pairs, used as the single source of truth
_TEAM_MEMBERS = [
    ('zhangyiteng',      '张翼腾'),
    ('lijunde',          '李俊德'),
    ('menglanwu',        '武梦岚'),
    ('eurekalin_i',      '林于翔'),
    ('mengfanrong',      '孟凡荣'),
    ('robinyang',        '杨冰'),
    ('jialiang',         '贾靓'),
    ('edgarwangjun',     '王俊'),
    ('xufangzhen',       '许方镇'),
    ('seanjie',          '介扬'),
    ('harriswu',         '吴洪键'),
    ('luowencheng_i',    '罗文程'),
    ('muchangqing',      '慕常青'),
    ('zhangyixiao',      '张一潇'),
    ('liujianquan',      '刘剑全'),
    ('shankuizhang',     '闪奎章'),
    ('cuishuai',         '崔帅'),
    ('vincechen',        '陈文校'),
    ('wengle',           '翁乐'),
    ('harllanhezhonglin','贺中林'),
    ('tianxiao',         '田啸'),
    ('chenshujun',       '陈书军'),
    ('majianzhe',        '马建哲'),
    ('wangyongqian',     '王永乾'),
    ('ianlu',            '卢建至'),
]
_TEAM_LDAPS = [ldap for ldap, _ in _TEAM_MEMBERS]
_TEAM_LDAP_SET = set(_TEAM_LDAPS)

_EXCLUDED_TEAM_LDAPS = {'shankuizhang'}

# 已知在职但被 DDP getResourceStatistics 部门统计口径遗漏的人（如实习生）。
# 与 _TEAM_MEMBERS（API 整体失败时的全量降级名单）区分：这里只在 API 调用
# 成功后用于补齐口径缺口，人员发生离职/转岗时需及时从此处移除。
_STATISTICS_GAP_MEMBERS = [
    ('eurekalin_i',      '林于翔'),
    ('luowencheng_i',    '罗文程'),
    ('tianxiao',         '田啸'),
    ('xingjingmin',      '邢敬敏'),
    ('chenshujun',       '陈书军'),
    ('majianzhe',        '马建哲'),
    ('wangyongqian',     '王永乾'),
]

# 全量已知人员集合：_TEAM_MEMBERS ∪ _STATISTICS_GAP_MEMBERS。trace 源头守卫
# （_merge_trace_data case B）以它判定「是否团队成员」，避免 DDP API 失败降级
# 到 _TEAM_MEMBERS 时，补丁名单成员的 trace 数据被当成脏数据丢弃。
_KNOWN_TEAM_LDAP_SET = _TEAM_LDAP_SET | {ldap for ldap, _ in _STATISTICS_GAP_MEMBERS}

# 展示层过滤（非团队成员剔除）使用的白名单：全量已知人员集合扣除 _EXCLUDED_TEAM_LDAPS，
# 与 mcp live 流 _fetch_team_members() 的名单口径保持一致（否则 shankuizhang 会在
# 快照/local 路径出现、mcp live 路径不出现，同一人两种口径）。
_DISPLAY_LDAP_SET = _KNOWN_TEAM_LDAP_SET - _EXCLUDED_TEAM_LDAPS

# ldap -> 中文名统一映射：local 模式（_do_stream_local）与后端快照叠加路径均不经过
# _fetch_team_members()，trace 数据里的 committer_name 可能是 git 提交时的英文/拼音名，
# 需要在 _merge_trace_data 里强制覆盖，而不能只靠 mcp 模式的 person_map 兜底。
_TEAM_LDAP_NAME_MAP = dict(_TEAM_MEMBERS)
_TEAM_LDAP_NAME_MAP.update(dict(_STATISTICS_GAP_MEMBERS))

# 需求分发/协调角色：relatedLdapList 会因分发职责挂上大量与其实际开发无关的需求，
# 若不加区分会被人员视图「名下需求数」、committers 兜底、rd_list 参与人三处一并误计。
# 对这两人特殊处理：仅当其确实是该需求 rdOwnerList 中的真实负责人时才计入上述三处；
# 其余人（含正常分发但同时又是 rdOwner 的场景）逻辑不变。
_RESOURCE_ATTRIBUTION_RESTRICTED_LDAPS = {'cuishuai', 'xingjingmin'}

_req_counter = 0
_req_counter_lock = threading.Lock()


def _next_req_id():
    global _req_counter
    with _req_counter_lock:
        _req_counter += 1
        return _req_counter


def _ddp_config():
    """Return (hub_url, token) read from ~/.claude.json mcpServers.ddp."""
    try:
        with open(_CLAUDE_JSON, encoding='utf-8') as f:
            d = json.load(f)
        ddp = d.get('mcpServers', {}).get('ddp', {})
        url = ddp.get('url', '')
        auth = ddp.get('headers', {}).get('Authorization', '')
        token = auth[7:].strip() if auth.lower().startswith('bearer ') else auth.strip()
        return url, token
    except Exception as e:
        print(f'[ddp_config] {type(e).__name__}: {e}', flush=True)
        return '', ''


def _call_ddp(tool_name, arguments, timeout=30):
    """Call DDP via local mcporter hub (HTTP MCP streamable protocol)."""
    hub_url, token = _ddp_config()
    if not hub_url or not token:
        raise RuntimeError('~/.claude.json 中缺少 DDP hub 配置，请确认 mcporter 已为 ddp 服务配置')

    req_id = _next_req_id()
    payload = json.dumps({
        'jsonrpc': '2.0',
        'method': 'tools/call',
        'params': {'name': tool_name, 'arguments': arguments},
        'id': req_id,
    }, ensure_ascii=False).encode('utf-8')

    req = urllib.request.Request(
        hub_url,
        data=payload,
        headers={
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            'Authorization': f'Bearer {token}',
            'mcp-session-id': f'dac-{req_id}',
        },
        method='POST',
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode('utf-8')

    # Hub responds as SSE: "data: {...}\n\n"
    for line in raw.splitlines():
        if line.startswith('data: '):
            try:
                rpc = json.loads(line[6:])
            except json.JSONDecodeError as e:
                raise RuntimeError(f'DDP hub 响应非 JSON: {e}') from e
            result = rpc.get('result', {})
            if result.get('isError'):
                content_text = (result.get('content') or [{}])[0].get('text', '')
                raise RuntimeError(f'DDP 工具调用失败: {content_text[:300]}')
            # content[0].text is a JSON string containing the actual data
            content_text = (result.get('content') or [{}])[0].get('text', '')
            if not content_text:
                raise RuntimeError('DDP hub 返回空 content text')
            try:
                inner = json.loads(content_text)
            except json.JSONDecodeError as e:
                raise RuntimeError(f'DDP 内层 JSON 解析失败: {e}') from e
            if inner.get('code', 0) != 0:
                raise RuntimeError(inner.get('message') or f'DDP code={inner.get("code")}')
            data = inner.get('data')
            if data is None:
                raise RuntimeError(f'DDP 响应缺少 data 字段: {content_text[:200]}')
            return data
    raise RuntimeError(f'DDP hub 无 SSE data 行: {raw[:200]}')


class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # suppress per-request logs

    def do_OPTIONS(self):
        self.send_response(200)
        self._cors()
        self.end_headers()

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ('/', '/index.html'):
            self._html()
        elif path == '/api/data':
            self._file(DATA_FILE)
        elif path == '/api/status':
            self._json(_refresh_state)
        elif path == '/api/bindings':
            bindings = _fetch_bindings_from_backend()
            if bindings is None:
                self.send_error(502, 'dac-trace-service unavailable')
                return
            self._json(bindings)
        elif path == '/api/remarks':
            self._remarks_get()
        elif path == '/api/stream':
            self._sse_stream()
        elif path == '/api/config':
            self._json({'vibeVisible': self._is_vibe_visible()})
        elif path == '/release-notes.json':
            self._release_notes()
        elif path in ('/favicon.svg', '/favicon.ico', '/dac-favicon-brand.svg') or path.startswith('/assets/'):
            self._static_asset(path)
        else:
            self.send_error(404)

    def do_POST(self):
        path = urlparse(self.path).path
        if path == '/api/refresh':
            self._refresh()
        elif path == '/api/bind-req':
            self._bind_req()
        elif path == '/api/delete-trace':
            self._delete_trace()
        elif path == '/api/remarks':
            self._remarks_post()
        else:
            self.send_error(404)

    # ── helpers ────────────────────────────────────────────────

    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')

    def _is_vibe_visible(self):
        """个人 vibe coding 信息在所有 dashboard 页面、所有访问来源均展示，
        不再按请求 Host 头区分本机访问与团队共享访问。"""
        return True

    def _html(self):
        try:
            with open(os.path.join(DIST_DIR, 'index.html'), 'rb') as f:
                body = f.read()
        except FileNotFoundError:
            body = b'<h1>dashboard-app/dist/index.html not found - run npm run build</h1>'
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.send_header('Pragma', 'no-cache')
        self.end_headers()
        self.wfile.write(body)

    def _static_asset(self, path):
        # path 形如 '/assets/index-XXXX.js' 或 '/favicon.svg'；仅允许访问 DIST_DIR 下的文件，
        # 用 realpath 校验杜绝 '..' 路径穿越
        rel = path.lstrip('/')
        full = os.path.realpath(os.path.join(DIST_DIR, rel))
        dist_root = os.path.realpath(DIST_DIR)
        if os.path.commonpath([full, dist_root]) != dist_root or not os.path.isfile(full):
            self.send_error(404)
            return
        with open(full, 'rb') as f:
            body = f.read()
        content_type = mimetypes.guess_type(full)[0] or 'application/octet-stream'
        self.send_response(200)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        if path.startswith('/assets/'):
            self.send_header('Cache-Control', 'public, max-age=31536000, immutable')
        else:
            self.send_header('Cache-Control', 'public, max-age=3600')
        self.end_headers()
        self.wfile.write(body)

    def _file(self, path):
        try:
            with open(path, encoding='utf-8') as f:
                data = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            data = {}
        # 磁盘快照的 personal_totals 可能是上次全量刷新时的历史值，这里实时补拉覆盖，
        # 使任何人打开/刷新页面即看到最新 vibe coding，无需先跑一遍重量级刷新。
        if isinstance(data, dict) and path == DATA_FILE:
            fresh = _personal_totals_fresh()
            if fresh:
                data['personal_totals'] = fresh
            fresh_q = _fetch_events_stats(timeout=3)
            if fresh_q:
                data['quality_stats'] = fresh_q
        # 展示层过滤：磁盘快照可能残留历史非团队成员数据（如测试脏数据），下发前剔除
        if isinstance(data, dict) and path == DATA_FILE and 'committers' in data:
            data = _filter_snapshot_payload(data)
        # 磁盘文件始终保留完整 personal_totals（供本机访问复用），仅按本次请求的 Host 头
        # 判定结果决定是否在响应中剔除该字段，不影响落盘内容本身。
        if isinstance(data, dict) and not self._is_vibe_visible():
            data = {k: v for k, v in data.items() if k != 'personal_totals'}
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _release_notes(self):
        try:
            with open(os.path.join(DIST_DIR, 'release-notes.json'), encoding='utf-8') as f:
                data = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            data = []
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj):
        body = json.dumps(obj, ensure_ascii=False).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _bind_req(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length).decode('utf-8')
        try:
            req_body = json.loads(body)
        except json.JSONDecodeError:
            self.send_error(400, 'invalid json')
            return
        if not isinstance(req_body, dict):
            self.send_error(400, 'invalid json body type')
            return
        trace_req = req_body.get('trace_req', '').strip()
        ddp_req = req_body.get('ddp_req', '').strip()
        unbind = bool(req_body.get('unbind', False))
        if not trace_req:
            self.send_error(400, 'trace_req required')
            return
        if unbind or ddp_req:
            if not _push_binding_to_backend(trace_req, ddp_req, unbind):
                self.send_error(502, 'dac-trace-service unavailable')
                return
        bindings = _fetch_bindings_from_backend()
        if bindings is None:
            self.send_error(502, 'dac-trace-service unavailable')
            return
        self._json({'ok': True, 'bindings': bindings})

    def _delete_trace(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length).decode('utf-8')
        try:
            req_body = json.loads(body)
        except json.JSONDecodeError:
            self.send_error(400, 'invalid json')
            return
        if not isinstance(req_body, dict):
            self.send_error(400, 'invalid json body type')
            return
        committer = (req_body.get('committer') or '').strip()
        req_name = (req_body.get('req_name') or '').strip()
        if not committer or not req_name:
            self.send_error(400, 'committer and req_name required')
            return
        result = _delete_trace_from_backend(committer, req_name)
        if result is None:
            self.send_error(502, 'dac-trace-service unavailable')
            return
        try:
            _quick_resync_after_delete(committer, req_name)
        except Exception as e:
            print(f'[trace-delete] 轻量同步失败（不影响删除结果）: {e}', flush=True)
        self._json({'ok': True, **result})

    def _remarks_get(self):
        backend_remarks = _fetch_remarks_from_backend()
        if backend_remarks is not None:
            # 持锁前先读本地副本，将后端未同步的 excluded_from_stats 字段补充到后端数据中
            try:
                with open(REMARKS_FILE, encoding='utf-8') as f:
                    local_remarks = json.load(f)
            except (FileNotFoundError, json.JSONDecodeError):
                local_remarks = {}
            with _remarks_lock:
                for req_name, local_val in local_remarks.items():
                    if local_val.get('excluded_from_stats'):
                        if req_name in backend_remarks:
                            # 防御性拷贝，避免原地修改后端返回的共享引用
                            backend_remarks[req_name] = {**backend_remarks[req_name], 'excluded_from_stats': True}
                        # 后端不存在该条目时不补充（以后端为主，仅补充字段）
                try:
                    os.makedirs(os.path.dirname(REMARKS_FILE), exist_ok=True)
                    tmp_file = REMARKS_FILE + f'.tmp.{os.getpid()}.{threading.get_ident()}'
                    with open(tmp_file, 'w', encoding='utf-8') as f:
                        json.dump(backend_remarks, f, ensure_ascii=False, indent=2)
                    os.replace(tmp_file, REMARKS_FILE)
                except Exception as e:
                    print(f'[req-remark-pull] 写本地离线副本失败: {e}', flush=True)
            self._json(backend_remarks)
            return

        with _remarks_lock:
            try:
                with open(REMARKS_FILE, encoding='utf-8') as f:
                    data = json.load(f)
            except (FileNotFoundError, json.JSONDecodeError):
                data = {}
        self._json(data)

    def _remarks_post(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length).decode('utf-8')
        try:
            req_body = json.loads(body)
        except json.JSONDecodeError:
            self.send_error(400, 'invalid json')
            return
        if not isinstance(req_body, dict):
            self.send_error(400, 'invalid json body type')
            return
        req_name = (req_body.get('req_name') or '').strip()
        if not req_name:
            self.send_error(400, 'req_name required')
            return

        clear = bool(req_body.get('clear', False))
        reason_tag = str(req_body.get('reason_tag', '')).strip()
        note = str(req_body.get('note', '')).strip()
        author = str(req_body.get('author', '')).strip()
        excluded_from_stats = bool(req_body.get('excluded_from_stats', False))

        _push_remark_to_backend(req_name, reason_tag, note, author, clear, excluded_from_stats)

        with _remarks_lock:
            try:
                with open(REMARKS_FILE, encoding='utf-8') as f:
                    remarks = json.load(f)
            except (FileNotFoundError, json.JSONDecodeError):
                remarks = {}

            if clear:
                remarks.pop(req_name, None)
            else:
                remarks[req_name] = {
                    'reason_tag': reason_tag,
                    'note': note,
                    'author': author,
                    'excluded_from_stats': excluded_from_stats,
                    'updated_at': int(time.time() * 1000)
                }

            os.makedirs(os.path.dirname(REMARKS_FILE), exist_ok=True)
            tmp_file = REMARKS_FILE + f'.tmp.{os.getpid()}.{threading.get_ident()}'
            try:
                with open(tmp_file, 'w', encoding='utf-8') as f:
                    json.dump(remarks, f, ensure_ascii=False, indent=2)
                os.replace(tmp_file, REMARKS_FILE)
            except Exception as e:
                if os.path.exists(tmp_file):
                    try:
                        os.remove(tmp_file)
                    except OSError:
                        pass
                self.send_error(500, f'failed to write remarks: {e}')
                return

        self._json(remarks)

    def _refresh(self):
        if _refresh_state['running']:
            self._json({'status': 'already_running', **_refresh_state})
            return
        threading.Thread(target=_do_refresh, daemon=True).start()
        self._json({'status': 'started'})

    def _sse_stream(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'keep-alive')
        self.send_header('X-Accel-Buffering', 'no')
        self._cors()
        self.end_headers()
        # Signal any running stream to abort, then wait up to 8s for it to release the lock
        _stream_cancel.set()
        if not _stream_lock.acquire(timeout=8):
            try:
                _send_sse(self.wfile, {'type': 'error', 'message': '刷新超时，请重试'})
            except Exception:
                pass
            return
        _stream_cancel.clear()
        try:
            _do_stream_pages(self.wfile, not self._is_vibe_visible())
        except BrokenPipeError:
            pass
        except Exception as e:
            try:
                _send_sse(self.wfile, {'type': 'error', 'message': str(e)})
            except Exception:
                pass
        finally:
            _stream_lock.release()


# ── SSE streaming ──────────────────────────────────────────────

def _send_sse(wfile, data):
    msg = f'data: {json.dumps(data, ensure_ascii=False)}\n\n'
    wfile.write(msg.encode('utf-8'))
    wfile.flush()


def _six_months_ago():
    d = date.today()
    m, y = d.month - 6, d.year
    if m <= 0:
        m += 12
        y -= 1
    try:
        return date(y, m, min(d.day, calendar.monthrange(y, m)[1])).strftime('%Y-%m-%d')
    except Exception:
        return date(y, m, 1).strftime('%Y-%m-%d')


def _extract_array_from_text(text):
    search_from = 0
    while True:
        idx = text.find('[', search_from)
        if idx == -1:
            return None
        try:
            candidate, _ = json.JSONDecoder().raw_decode(text, idx)
            if isinstance(candidate, list):
                return candidate
        except json.JSONDecodeError:
            pass
        search_from = idx + 1


def _dac_trace_backend_config():
    """Return (base_url, token) for dac-trace backend, read from the same
    backend-config.json shared with report-trace-backend.sh.
    DAC_TRACE_BACKEND_URL env var overrides base_url when set."""
    base_url, token = '', ''
    try:
        with open(_DAC_TRACE_BACKEND_CONFIG, encoding='utf-8') as f:
            d = json.load(f)
        base_url = d.get('base_url', '')
        token = d.get('token', '')
    except Exception as e:
        print(f'[dac-trace-backend] {type(e).__name__}: {e}', flush=True)
    base_url = os.environ.get('DAC_TRACE_BACKEND_URL', base_url)
    return base_url, token


def _run_aggregate_trace():
    """GET dac-trace backend's /api/v1/trace/summary.
    Returns list of committer trace objects, or [] on any failure (missing
    config, unreachable backend, 401, timeout, non-list response) — never raises,
    so callers degrade gracefully without impacting the rest of the dashboard."""
    base_url, token = _dac_trace_backend_config()
    if not base_url or not token:
        print('[aggregate-trace] 缺少后端地址或 token，跳过', flush=True)
        return []
    req = urllib.request.Request(
        f'{base_url}/api/v1/trace/summary',
        headers={'Authorization': f'Bearer {token}'}
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        print(f'[aggregate-trace] 后端返回 {e.code}，跳过', flush=True)
        return []
    except Exception as e:
        print(f'[aggregate-trace] 异常: {e}', flush=True)
        return []
    if not isinstance(data, list):
        print(f'[aggregate-trace] 返回值非列表 (type={type(data).__name__})，跳过', flush=True)
        return []
    return data


def _run_aggregate_personal_trace(timeout=10):
    """GET dac-trace backend's /api/v1/trace/personal-summary.
    Returns list of {committer, committer_name, total_lines, repos: [{repo_path,
    write_lines_added}]} dicts covering every repo_path the committer edited.
    失败（缺配置 / 后端不可达 / 401 / 超时 / 返回值非列表）一律返回 None，后端合法无数据
    返回 []：二者必须区分，调用方据此判断「拉取失败该降级」还是「确实没数据、可正常缓存」。
    never raises；只需要「失败即空」语义的调用方写 `_run_aggregate_personal_trace() or []`。"""
    base_url, token = _dac_trace_backend_config()
    if not base_url or not token:
        print('[aggregate-personal-trace] 缺少后端地址或 token，跳过', flush=True)
        return None
    req = urllib.request.Request(
        f'{base_url}/api/v1/trace/personal-summary',
        headers={'Authorization': f'Bearer {token}'}
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        print(f'[aggregate-personal-trace] 后端返回 {e.code}，跳过', flush=True)
        return None
    except Exception as e:
        print(f'[aggregate-personal-trace] 异常: {e}', flush=True)
        return None
    if not isinstance(data, list):
        print(f'[aggregate-personal-trace] 返回值非列表 (type={type(data).__name__})，跳过', flush=True)
        return None
    return data


def _personal_totals_fresh():
    """TTL 内复用的实时个人总量；拉取失败返回 None，调用方降级用磁盘快照（即改动前行为）；
    后端合法返回的空列表同样入缓存（与失败区分），否则 TTL 失效、每次请求都白打一次后端。
    整段持锁做 single-flight：并发请求在 miss 瞬间不会各发一次 3s 请求，后到者复用前者结果。
    首屏路径用 3s 短超时，后端不可达时页面最多多等 3s，不会白屏。"""
    with _personal_fresh_lock:
        if (_personal_fresh_cache['data'] is not None
                and time.monotonic() - _personal_fresh_cache['ts'] < _PERSONAL_FRESH_TTL):
            return _personal_fresh_cache['data']
        data = _run_aggregate_personal_trace(timeout=3)
        if data is None:
            return None
        _personal_fresh_cache['ts'] = time.monotonic()
        _personal_fresh_cache['data'] = data
        return data


def _fetch_events_stats(req_names=None, timeout=10):
    """GET backend /api/v1/trace/events/stats，按需求列表请求（不传=全量）。
    返回 List[{req_name, clarify_rounds, proposal_rounds, feature_plan_rounds,
    codegen_feats_total, codegen_check_times, cr_feats_total, cr_check_times}]。
    失败（缺配置 / 后端不可达 / 401 / 超时 / 非 list）返回 None，与「后端合法无数据返回 []」区分。
    never raises；需要「失败即空」语义的调用方写 `_fetch_events_stats() or []`。"""
    base_url, token = _dac_trace_backend_config()
    if not base_url or not token:
        return None
    qs = ''
    if req_names:
        qs = '?req_list=' + urllib.parse.quote(','.join(req_names))
    req = urllib.request.Request(
        f'{base_url}/api/v1/trace/events/stats{qs}',
        headers={'Authorization': f'Bearer {token}'}
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        print(f'[events-stats] 后端返回 {e.code}，跳过', flush=True)
        return None
    except Exception as e:
        print(f'[events-stats] 异常: {e}', flush=True)
        return None
    if not isinstance(data, list):
        return None
    return data


def _push_binding_to_backend(trace_req, ddp_req, unbind):
    """POST /api/v1/ddp/bindings to sync a single bind/unbind to the backend.
    Synchronous: returns True on success, False on any failure (missing
    config/unreachable/timeout/non-2xx) — callers surface the failure to
    the client rather than caching the change locally."""
    base_url, token = _dac_trace_backend_config()
    if not base_url or not token:
        print('[req-binding-push] 缺少后端地址或 token', flush=True)
        return False
    body = json.dumps(
        {'trace_req': trace_req, 'ddp_req': ddp_req, 'unbind': unbind}, ensure_ascii=False
    ).encode('utf-8')
    req = urllib.request.Request(
        f'{base_url}/api/v1/ddp/bindings',
        data=body,
        headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'},
        method='POST',
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            resp.read()
    except urllib.error.HTTPError as e:
        print(f'[req-binding-push] 后端返回 {e.code}', flush=True)
        return False
    except Exception as e:
        print(f'[req-binding-push] 异常: {e}', flush=True)
        return False
    return True


def _delete_trace_from_backend(committer, req_name):
    """DELETE /api/v1/trace/record?committer=&req_name= to hard-delete a
    committer's requirement records across all repo_path. Returns the backend
    JSON dict (e.g. {'deleted': n}) on success, or None on any failure (missing
    config/unreachable/timeout/non-2xx/non-dict) — caller surfaces failure to
    the client rather than reporting a false success."""
    base_url, token = _dac_trace_backend_config()
    if not base_url or not token:
        print('[trace-delete] 缺少后端地址或 token', flush=True)
        return None
    qs = urlencode({'committer': committer, 'req_name': req_name})
    req = urllib.request.Request(
        f'{base_url}/api/v1/trace/record?{qs}',
        headers={'Authorization': f'Bearer {token}'},
        method='DELETE',
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        print(f'[trace-delete] 后端返回 {e.code}', flush=True)
        return None
    except Exception as e:
        print(f'[trace-delete] 异常: {e}', flush=True)
        return None
    return data if isinstance(data, dict) else None


def _fetch_bindings_from_backend():
    """GET /api/v1/ddp/bindings. Returns the backend's full {trace_req:
    ddp_req} dict, or None on any failure (missing config/unreachable/
    timeout/non-2xx/non-dict response) — never raises."""
    base_url, token = _dac_trace_backend_config()
    if not base_url or not token:
        print('[req-binding-pull] 缺少后端地址或 token，跳过', flush=True)
        return None
    req = urllib.request.Request(
        f'{base_url}/api/v1/ddp/bindings',
        headers={'Authorization': f'Bearer {token}'},
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        print(f'[req-binding-pull] 后端返回 {e.code}，跳过', flush=True)
        return None
    except Exception as e:
        print(f'[req-binding-pull] 异常: {e}', flush=True)
        return None
    return data if isinstance(data, dict) else None


def _fetch_ddp_snapshot_from_backend():
    """GET /api/v1/ddp/snapshot. Returns the backend's cached team-wide DDP
    snapshot dict, or None on any failure (missing config/unreachable/timeout/
    404 no-snapshot-yet/non-2xx/non-dict/missing committers or requirements_index) —
    never raises."""
    base_url, token = _dac_trace_backend_config()
    if not base_url or not token:
        print('[ddp-snapshot-pull] 缺少后端地址或 token，跳过', flush=True)
        return None
    req = urllib.request.Request(
        f'{base_url}/api/v1/ddp/snapshot',
        headers={'Authorization': f'Bearer {token}'},
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        print(f'[ddp-snapshot-pull] 后端返回 {e.code}，跳过', flush=True)
        return None
    except Exception as e:
        print(f'[ddp-snapshot-pull] 异常: {e}', flush=True)
        return None
    if not isinstance(data, dict) or 'committers' not in data or 'requirements_index' not in data:
        print('[ddp-snapshot-pull] 快照格式不合法（缺 committers/requirements_index），跳过', flush=True)
        return None
    return data


def _push_ddp_snapshot_to_backend(snapshot):
    """POST /api/v1/ddp/snapshot to sync the latest full local DDP snapshot to
    the backend. Best-effort: returns True on success, False on any failure
    (missing config/unreachable/timeout/non-2xx) — failures are logged and
    swallowed so this optional sync never impacts the local refresh flow."""
    base_url, token = _dac_trace_backend_config()
    if not base_url or not token:
        print('[ddp-snapshot-push] 缺少后端地址或 token，跳过', flush=True)
        return False
    body = json.dumps(snapshot, ensure_ascii=False).encode('utf-8')
    req = urllib.request.Request(
        f'{base_url}/api/v1/ddp/snapshot',
        data=body,
        headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'},
        method='POST',
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            resp.read()
    except urllib.error.HTTPError as e:
        print(f'[ddp-snapshot-push] 后端返回 {e.code}', flush=True)
        return False
    except Exception as e:
        print(f'[ddp-snapshot-push] 异常: {e}', flush=True)
        return False
    return True


def _fetch_remarks_from_backend():
    """GET /api/v1/remarks. Returns the backend's full {req_name: {reason_tag, note, author, updated_at}}
    dict, or None on any failure (missing config/unreachable/timeout/non-2xx/non-dict response) — never raises."""
    base_url, token = _dac_trace_backend_config()
    if not base_url or not token:
        print('[req-remark-pull] 缺少后端地址或 token，跳过', flush=True)
        return None
    req = urllib.request.Request(
        f'{base_url}/api/v1/remarks',
        headers={'Authorization': f'Bearer {token}'},
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        print(f'[req-remark-pull] 后端返回 {e.code}，跳过', flush=True)
        return None
    except Exception as e:
        print(f'[req-remark-pull] 异常: {e}', flush=True)
        return None
    return data if isinstance(data, dict) else None


def _push_remark_to_backend(req_name, reason_tag, note, author, clear, excluded_from_stats=False):
    """POST /api/v1/remarks to sync a single remark (or clear) to the backend.
    Best-effort: returns True on success, False on any failure (missing config/unreachable/timeout/non-2xx) —
    failures are logged and swallowed so local storage fallback works seamlessly."""
    base_url, token = _dac_trace_backend_config()
    if not base_url or not token:
        print('[req-remark-push] 缺少后端地址或 token，跳过', flush=True)
        return False
    body = json.dumps(
        {
            'req_name': req_name,
            'reason_tag': reason_tag,
            'note': note,
            'author': author,
            'excluded_from_stats': excluded_from_stats,
            'clear': clear,
        },
        ensure_ascii=False,
    ).encode('utf-8')
    req = urllib.request.Request(
        f'{base_url}/api/v1/remarks',
        data=body,
        headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'},
        method='POST',
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            resp.read()
    except urllib.error.HTTPError as e:
        print(f'[req-remark-push] 后端返回 {e.code}', flush=True)
        return False
    except Exception as e:
        print(f'[req-remark-push] 异常: {e}', flush=True)
        return False
    return True


def _sort_by_dac(committers, reqs_index):
    """Sort committers and reqs with dac usage first; within each group keep original order."""
    def c_key(c):
        has_dac = any((r.get('workflow_session_ids') or []) for r in c.get('requirements', []))
        return 0 if has_dac else 1
    sorted_committers = sorted(committers, key=c_key)

    def r_key(r):
        return 0 if (r.get('workflow_session_ids') or []) else 1
    sorted_reqs = sorted(reqs_index, key=r_key)
    return sorted_committers, sorted_reqs


def _copy_codegen_line_buckets(req, tr, *, required=False):
    """把 /summary 的自动生成 / 对话桶灌进看板需求。
    required=True 用于新建 trace-only 条目（字段始终带上，缺省 0）。
    已有 DDP 需求仅在 TRACE 带了该键时覆盖，避免旧快照无字段时被写成 None。"""
    if required or 'codegen_lines_added' in tr:
        req['codegen_lines_added'] = tr.get('codegen_lines_added') or 0
    if required or 'chat_lines_added' in tr:
        req['chat_lines_added'] = tr.get('chat_lines_added') or 0


def _merge_trace_data(person_map, reqs_index, trace_list, hidden_r_ids=frozenset(), tm=None, bindings=None):
    """Enrich person_map and reqs_index with git dac-trace data.

    For matching (committer, req_name) entries, overwrite phases/features/
    workflow_session_ids/last_commit/last_note_id/last_commit_ts/reported_at
    from the trace; the DDP 'ddp' sub-object is preserved.

    hidden_r_ids: 被隐藏父需求 R 的数字 id 集合。orphan 注入分支写回前用 tm.extract_ddp_id 从
    trace req_name（dac-bind 后形如 R-IBG-<num>-<local> 或纯数字 <num>-<local>）提取数字 id，
    命中则跳过，避免被隐藏的 R 经 trace 复活（守护 R/T 去重不变量）。
    tm: 已加载的 transform 模块（由调用方传入复用，避免重复 _load_transform）；仅在
    hidden_r_ids 非空时使用。
    """
    committer_trace = {}   # {email: {req_name: trace_req}}
    all_req_trace = {}     # {req_name: trace_req} — highest last_commit_ts wins

    for entry in trace_list:
        email = entry.get('committer', '')
        reqs = {}
        for r in (entry.get('requirements') or []):
            rn = r.get('req_name')
            # 过滤未绑定需求的兜底记录：write-trace-hook 在无 req_name/bind 时归为 "untitled"，
            # 属噪声，不计入需求维度展示与计数（真实需求恒有具体名或 req_id 派生名）
            if not rn or rn == 'untitled':
                continue
            prev = reqs.get(rn)
            if prev is None or (r.get('last_commit_ts') or 0) >= (prev.get('last_commit_ts') or 0):
                reqs[rn] = r
        if email:
            existing = committer_trace.get(email, {})
            for rn, tr in reqs.items():
                prev = existing.get(rn)
                if prev is None or (tr.get('last_commit_ts') or 0) >= (prev.get('last_commit_ts') or 0):
                    existing[rn] = tr
            committer_trace[email] = existing
        for req_name, tr in reqs.items():
            prev = all_req_trace.get(req_name)
            if prev is None or (tr.get('last_commit_ts') or 0) > (prev.get('last_commit_ts') or 0):
                all_req_trace[req_name] = tr

    for person in person_map.values():
        email = person.get('committer', '')
        trace_reqs = committer_trace.get(email, {})
        for req in person.get('requirements', []):
            tr = trace_reqs.get(req.get('req_name', ''))
            if not tr:
                continue
            if tr.get('phases'):
                req['phases'] = tr['phases']
            if tr.get('features'):
                req['features'] = tr['features']
            req['workflow_session_ids'] = tr.get('workflow_session_ids', [])
            # 标记真实归属人：与 reqs_index 全局条目的 committers（rdOwner 口径）语义不同，
            # 这里是该 trace 实际所属的 committer，供前端 enrichReq 直连分支校验用
            req['committers'] = [email]
            req['last_note_id'] = tr.get('last_note_id', '')
            req['last_commit'] = tr.get('last_commit', '')
            req['last_commit_ts'] = tr.get('last_commit_ts', req['last_commit_ts'])
            req['reported_at'] = tr.get('reported_at')
            # 回填行数/提交数：快照二次叠加时命中该分支，须刷新 +N 行，否则仅时间更新
            # （缺字段回退既有值，禁止硬编码 0 以免误清零）
            req['lines_added']   = tr.get('lines_added',   req.get('lines_added', 0))
            req['lines_deleted'] = tr.get('lines_deleted', req.get('lines_deleted', 0))
            req['commit_count']  = tr.get('commit_count',  req.get('commit_count', 0))
            _copy_codegen_line_buckets(req, tr)
            if 'skipped_stages' in tr:
                req['skipped_stages'] = tr.get('skipped_stages') or []

    for req in reqs_index:
        tr = all_req_trace.get(req.get('req_name', ''))
        if not tr:
            continue
        if tr.get('phases'):
            req['phases'] = tr['phases']
        if tr.get('features'):
            req['features'] = tr['features']
        req['last_commit_ts'] = tr.get('last_commit_ts', req['last_commit_ts'])
        req['reported_at'] = tr.get('reported_at')
        if tr.get('req_id') is not None:
            req['req_id'] = tr['req_id']
        # 回填行数/提交数：快照二次叠加时命中该分支，须刷新 +N 行（缺字段回退既有值）
        req['lines_added']   = tr.get('lines_added',   req.get('lines_added', 0))
        req['lines_deleted'] = tr.get('lines_deleted', req.get('lines_deleted', 0))
        req['commit_count']  = tr.get('commit_count',  req.get('commit_count', 0))
        _copy_codegen_line_buckets(req, tr)
        if 'skipped_stages' in tr:
            req['skipped_stages'] = tr.get('skipped_stages') or []

    # Inject trace reqs that have no DDP req_name match.
    # trace req_name (e.g. "driver-side") never equals a Cooper URL, so the loop
    # above never fires for trace-only data.  Two cases:
    #   A) committer is already in person_map (DDP team member): append unmatched trace reqs
    #   B) committer is not in person_map (outside DDP team): add the person with trace reqs only
    trace_name_map = {e.get('committer', ''): e.get('committer_name', '')
                      for e in trace_list if e.get('committer')}
    # 技术类 index 条目（req_name 全名 + 数字 id）：orphan 注入的 new_req 完全由 trace 构造，
    # 不携带 is_technical。若其绑定目标/自身命中原 DDP 技术需求，须补打标记，否则技术需求绑
    # trace 走 orphan 分支后会绕过统计排除（与 transform._stamp_versions 的回填同源）。
    tech_names = {r.get('req_name', '') for r in reqs_index if r.get('is_technical')}
    tech_ids = set()
    if tm:
        for _rn in tech_names:
            _did = tm.extract_ddp_id(_rn)
            if _did:
                tech_ids.add(_did)
    for email, trace_reqs in committer_trace.items():
        ldap = email.split('@')[0]
        # 该守卫必须置于 hidden_r_ids 过滤之前，避免被排除人员 trace 先经历一轮 hidden 判定再被跳过。
        if ldap in _EXCLUDED_TEAM_LDAPS:
            continue
        # 非团队成员（如历史测试脏数据）从源头拦截：不注入 person_map，也不向 reqs_index 新增 trace-only 条目。
        # 用全量已知人员集合（含 _STATISTICS_GAP_MEMBERS），否则 DDP API 失败降级到 _TEAM_MEMBERS 时
        # 补丁名单成员（如 xingjingmin）的 trace 会被误判丢弃。
        if ldap not in _KNOWN_TEAM_LDAP_SET:
            continue
        if ldap not in person_map:
            person_map[ldap] = {
                'committer': email,
                'committer_name': _TEAM_LDAP_NAME_MAP.get(ldap, trace_name_map.get(email, ldap)),
                'dept': '',
                'requirements': [],
            }
        person = person_map[ldap]
        # 团队名单里的中文名强制覆盖：trace/后端快照可能携带 git 提交时的英文/拼音 committer_name
        if ldap in _TEAM_LDAP_NAME_MAP:
            person['committer_name'] = _TEAM_LDAP_NAME_MAP[ldap]
        # 快照喂入路径下 committer 可能缺 requirements 键，setdefault 保证下方 matched 推导与 append 不 KeyError
        person.setdefault('requirements', [])
        matched = {req.get('req_name', '') for req in person['requirements']}
        for req_name, tr in trace_reqs.items():
            if req_name in matched:
                continue
            # 用绑定目标（而非 trace 名前缀）判断是否命中隐藏 R：已绑定到可见 T 的 trace，其名
            # 前缀可能恰为被隐藏父 R 的数字 id（如 702627-account-health 绑到可见 T-IBT-615723，
            # 其父 R-702627 因子任务在批次内被 R/T 去重隐藏），按前缀过滤会把这条合法 trace 误删。
            # 未绑定 / 绑定到隐藏 R 的 trace 仍按原逻辑过滤（守护 R/T 去重不变量）。
            # 仅过滤「无真实 dac」的噪声 trace：带 workflow_session_ids 的 trace 是真实开发，
            # 即便绑定目标是被 R/T 去重隐藏的父 R，也必须注入为 trace-only orphan 保留该人 dac
            # 归属，否则唯一 dac 绑到隐藏父 R 的成员整条消失（武梦岚 driver-map-entrance→R-IBG-705905）。
            _has_dac = bool(tr.get('workflow_session_ids'))
            _hidden_check = (bindings or {}).get(req_name, req_name)
            if not _has_dac and hidden_r_ids and tm and tm.extract_ddp_id(_hidden_check) in hidden_r_ids:
                continue
            new_req = {
                'req_name': req_name,
                'committers': [email],
                'workflow_session_ids': tr.get('workflow_session_ids', []),
                'phases': tr.get('phases', []),
                'features': tr.get('features', []),
                'last_note_id': tr.get('last_note_id', ''),
                'last_commit': tr.get('last_commit', ''),
                'last_commit_ts': tr.get('last_commit_ts', 0),
                'reported_at': tr.get('reported_at'),
                'commit_count': tr.get('commit_count', 0),
                'lines_added': tr.get('lines_added', 0),
                'lines_deleted': tr.get('lines_deleted', 0),
                'req_id': tr.get('req_id'),
                'skipped_stages': tr.get('skipped_stages') or [],
                'ddp': None,
            }
            # 技术类打标：orphan 仅看 req_name 是否等于某 DDP 技术需求（或经绑定目标指向），
            # 命中则在 append 前补写 is_technical，保证 reqs_index 与成员副本两条一致。
            if (req_name in tech_names or _hidden_check in tech_names
                    or (tm and (tm.extract_ddp_id(req_name) in tech_ids
                                or tm.extract_ddp_id(_hidden_check) in tech_ids))):
                new_req['is_technical'] = True
            _copy_codegen_line_buckets(new_req, tr, required=True)
            person['requirements'].append(new_req)
            reqs_index.append(new_req)


def _is_non_team_trace_req(req: dict) -> bool:
    """判断需求是否为「非团队成员的 trace-only 条目」：无 DDP 归属（ddp 为空）且
    committers 全为 _DISPLAY_LDAP_SET 之外成员。有 DDP 归属的需求一律保留，避免误删真实需求。"""
    if req.get('ddp'):
        return False
    ldaps = {str(e).split('@')[0] for e in (req.get('committers') or [])}
    return bool(ldaps) and ldaps.isdisjoint(_DISPLAY_LDAP_SET)


def _filter_non_team_data(person_map: Dict[str, dict], reqs_index: List[dict]) -> None:
    """展示层过滤：就地剔除非团队成员数据——person_map 删除非成员 key，
    reqs_index 剔除非成员 trace-only 条目（判定见 _is_non_team_trace_req）。
    供 local/mcp 两条数据流在排序、落盘、回推前统一调用。"""
    for ldap in [k for k in person_map if k not in _DISPLAY_LDAP_SET]:
        del person_map[ldap]
    reqs_index[:] = [r for r in reqs_index if not _is_non_team_trace_req(r)]


def _filter_snapshot_payload(payload: dict) -> dict:
    """对快照类 payload（含 committers/requirements_index）做非团队成员过滤。
    返回新 dict 不修改入参——hide_vibe=False 时入参即 backend_snapshot 原对象，
    主线程就地修改会与 _bg_trace 线程并发读产生竞态。"""
    filtered = dict(payload)
    filtered['committers'] = [
        c for c in payload.get('committers') or []
        if isinstance(c, dict) and c.get('committer', '').split('@')[0] in _DISPLAY_LDAP_SET
    ]
    filtered['requirements_index'] = [
        r for r in payload.get('requirements_index') or []
        if not (isinstance(r, dict) and _is_non_team_trace_req(r))
    ]
    return filtered


def _enrich_person_gitai(person_map, stats):
    """Write gitai_accepted_lines and gitai_ai_commits into each person_map entry (0 if no data)."""
    for person in person_map.values():
        email = person.get('committer', '')
        s = stats.get(email, {})
        person['gitai_accepted_lines'] = s.get('accepted_lines', 0)
        person['gitai_ai_commits'] = s.get('ai_commits', 0)


_DRIVER_MOBILE_TECH_DEPT_ID = 103793


def _fetch_team_members():
    """Fetch Driver Mobile Tech members from DDP getResourceStatistics.
    On success, merges in any _STATISTICS_GAP_MEMBERS entries missing from the
    API result (people known to be outside its statistics scope, e.g. interns).
    Falls back entirely to _TEAM_MEMBERS if the API call fails."""
    d = date.today()
    monday = (d - timedelta(days=d.weekday())).strftime('%Y-%m-%d')
    try:
        data = _call_ddp('getResourceStatistics', {
            'weekDate': monday,
            'deptIds': [_DRIVER_MOBILE_TECH_DEPT_ID],
            'type': 'deptSummary',
        }, timeout=15)
        summaries = data.get('deptSummary') or []
        members = []
        for node in summaries:
            for child in (node.get('children') or []):
                if child.get('nodeType') == 2:
                    ldap = child.get('userLdap', '')
                    name = child.get('userName', '')
                    if ldap and ldap not in _EXCLUDED_TEAM_LDAPS:
                        members.append((ldap, name))
        if members:
            seen = {ldap for ldap, _ in members}
            extra = [(ldap, name) for ldap, name in _STATISTICS_GAP_MEMBERS if ldap not in seen]
            return members + extra
    except Exception as e:
        print(f'[fetch_team_members] DDP 失败，使用硬编码列表: {e}', flush=True)
    return _TEAM_MEMBERS


def _load_transform():
    spec = importlib.util.spec_from_file_location(
        "transform_ddp",
        os.path.join(SCRIPT_DIR, "transform-ddp.py")
    )
    tm = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tm)
    return tm


def _get_related_team_ldaps(item):
    """Extract team-member LDAPs from item's relatedLdapList field."""
    rf = item.get('relatedLdapList')
    if not rf:
        return []
    if isinstance(rf, list):
        entries = rf
    elif isinstance(rf, dict):
        value = rf.get('value')
        entries = value if isinstance(value, list) else []
    else:
        return []
    result = []
    for entry in entries:
        if isinstance(entry, dict):
            ldap = entry.get('ldap') or entry.get('value', '')
        else:
            ldap = str(entry)
        if ldap and ldap in _TEAM_LDAP_SET:
            result.append(ldap)
    return result


def _accumulate_item(item, target_ldaps, person_map, reqs_index, tm, seen_reqs, team_ldap_set,
                     hidden_r_links=frozenset(), req_participants=None):
    """Add item to each of target_ldaps' requirements. reqs_index is de-duped by req_name.

    hidden_r_links: 被判定隐藏的父需求 R-link 集合（其子任务 T 已在本批数据中）；命中即跳过，
    以任务 T 为展示主体，避免 R/T 重复展示与重复计数。
    req_participants: {req_link: set(ldap)} 反向聚合映射（见 _do_stream_pages），提供该需求全部
    司机端参与 RD 的 ldap 集合，用于填充 rd_list；缺省 None 时 rd_list 退化为空（standalone/旧路径）。"""
    nf = item.get('name', {})
    link  = nf.get('link', '') if isinstance(nf, dict) else ''
    if not link:
        return
    if link in hidden_r_links:
        return
    title = nf.get('displayContent', '') if isinstance(nf, dict) else ''
    sf = item.get('state', {})
    state = sf.get('displayContent', '待技术准入') if isinstance(sf, dict) else '待技术准入'
    # 任务（T- 前缀）没有顶层 directionId，方向信息挂在其所属需求下的 requirement.directionId
    df = item.get('directionId') or item.get('requirement.directionId') or {}
    direction = df.get('displayContent', '') if isinstance(df, dict) else ''
    ef = item.get('expectReleaseTime', {})
    expected = ef.get('value', '') if isinstance(ef, dict) else ''
    mf = item.get('mtime', {})
    # 任务（T- 前缀）的 mtime 用 displayContent 而非 value 表示，两者都要兼容
    mtime = (mf.get('value') or mf.get('displayContent') or '') if isinstance(mf, dict) else ''
    release_version_name, release_version_time = tm.parse_dpm_version(item.get('dpmVersion', {}))
    pm_name = tm.get_pmowner(item)
    phases  = tm.make_phases(state, mtime)
    if phases is None:
        return
    features = tm.make_features(state, link, mtime)
    ddp_obj = {
        "id": link, "title": title, "state": state,
        "expected_release": expected, "direction": direction, "pm_owner": pm_name,
        "release_version_name": release_version_name,
        "release_version_time": release_version_time
    }
    req_base = {
        "req_name": link,
        "workflow_session_ids": [],
        "phases": phases,
        "features": features,
        "last_note_id": "",
        "last_commit": "",
        "last_commit_ts": phases[-1]['ts'],
        "ddp": ddp_obj,
    }
    # 技术类需求（sponsorId=3）不再于数据层排除，仅打 is_technical 标记：req_base 经
    # deepcopy 写入各成员副本，一处打标即覆盖全部成员副本；reqs_index 条目另打一次。
    # 仅命中携带该键，无该键即非技术（判定函数 fail-open，单一来源复用 tm）。
    is_tech = tm.is_technical_requirement(item)
    if is_tech:
        req_base["is_technical"] = True
    owners = tm.get_rdowners(item)
    owner_ldaps = {o.get('ldap', '') for o in owners}
    # 名下需求归属限制：受限 ldap（需求分发/协调角色，relatedLdapList 命中量与实际开发无关）
    # 仅当其确实是该需求 rdOwnerList 中的真实负责人时才可被计入归属，其余人不受此限制。
    def _attributable(ldap):
        return ldap not in _RESOURCE_ATTRIBUTION_RESTRICTED_LDAPS or ldap in owner_ldaps

    team_owners = [o for o in owners if o.get('ldap', '') in team_ldap_set and o.get('ldap', '') not in _EXCLUDED_TEAM_LDAPS and _attributable(o.get('ldap', ''))]
    fallback_ldaps = [ldap for ldap in target_ldaps if ldap not in _EXCLUDED_TEAM_LDAPS and _attributable(ldap)]
    committers = ([f"{o['ldap']}@didiglobal.com" for o in team_owners]
                  or [f"{ldap}@didiglobal.com" for ldap in fallback_ldaps])
    # rd_list = 需求全部司机端参与 RD（relatedLdapList 反向聚合 ∩ 团队白名单），
    # 独立于 committers（rdOwnerList 口径）
    rd_ldaps = (req_participants or {}).get(link, set())
    rd_list = sorted(f"{ldap}@didiglobal.com" for ldap in rd_ldaps
                     if ldap in team_ldap_set and ldap not in _EXCLUDED_TEAM_LDAPS and _attributable(ldap))
    # committers(归属) + rd_list(参与人) 均为空 → 此需求与团队无真实关联，
    # 阻止 person_map 挂载与 reqs_index 写入，避免幽灵挂载
    if not committers and not rd_list:
        return
    for ldap in target_ldaps:
        if ldap in person_map and _attributable(ldap):
            person_map[ldap]['requirements'].append(copy.deepcopy(req_base))
    if link not in seen_reqs:
        seen_reqs.add(link)
        index_entry = {
            "req_name": link,
            "committers": committers,
            "rd_list": rd_list,
            "phases": phases,
            "features": features,
            "last_commit_ts": phases[-1]['ts'],
            "ddp": ddp_obj,
        }
        if is_tech:
            index_entry["is_technical"] = True
        reqs_index.append(index_entry)


def _strip_stale_trace_overlay(person_map, reqs_index):
    """本地模式合并前的清洗：backend_snapshot 是上一次 mcp 全量刷新回推的缓存快照，其
    requirements_index / 各成员 requirements 里可能叠着那一次合并进去的 trace 派生字段（含纯
    trace 编排条目，ddp 为空）。_merge_trace_data 只做新增/覆盖、从不删除，若不先清洗，已被
    删除/不再活跃的 trace 会因"不在本次新鲜 trace_result 里所以不被触碰"而在快照里原样残留、
    每次刷新都重新展示（对应 bug：删除 trace 后刷新又复现，因为本地模式不会把删除结果回推到
    这份快照，见 _quick_resync_after_delete 注释）。
    ddp 为空的纯 trace 条目直接丢弃；ddp 非空且从未绑定 trace（workflow_session_ids 为空）
    的需求直接保留原值（这些字段是 DDP mtime 兜底值，不是 trace 派生，没有过期残留问题）；
    已绑定 trace 的需求才清零 trace 派生字段，交给下方 _merge_trace_data 用本次新鲜数据重新
    写入。"""
    def _is_ghost_req(req):
        if not req.get('ddp'):
            return False
        c_list = [c for c in (req.get('committers') or []) if c.split('@')[0] not in _EXCLUDED_TEAM_LDAPS]
        r_list = [c for c in (req.get('rd_list') or []) if c.split('@')[0] not in _EXCLUDED_TEAM_LDAPS]
        return not c_list and not r_list and not (req.get('workflow_session_ids') or [])

    def _reset_or_drop(req_list):
        kept = []
        for req in req_list:
            if not req.get('ddp'):
                continue
            if _is_ghost_req(req):
                continue
            if not (req.get('workflow_session_ids') or []):
                # 从未绑定 trace：last_commit_ts 等字段是 DDP mtime 兜底值，非 trace 派生，
                # 不存在过期残留问题，直接保留后端快照原值
                kept.append(req)
                continue
            req['phases'] = []
            req['features'] = []
            req['workflow_session_ids'] = []
            req['lines_added'] = 0
            req['lines_deleted'] = 0
            req['commit_count'] = 0
            req['last_commit'] = ''
            req['last_commit_ts'] = 0
            req['reported_at'] = None
            kept.append(req)
        return kept

    reqs_index[:] = _reset_or_drop(reqs_index)
    for person in person_map.values():
        person['requirements'] = _reset_or_drop(person.get('requirements') or [])


def _rebuild_person_requirements_from_index(person_map, reqs_index):
    """用本地快照的权威需求索引重建每位成员的 DDP 需求列表。

    后端快照中的 committers[].requirements 是历史派生副本，可能未包含普通 DDP 需求；
    requirements_index 的 committers 与 rd_list 才是完整的人员归属口径。"""
    for person in person_map.values():
        person['requirements'] = [
            req for req in person.get('requirements', []) if not req.get('ddp')
        ]

    for req in reqs_index:
        if not req.get('ddp'):
            continue
        emails = set(req.get('committers') or []) | set(req.get('rd_list') or [])
        for email in emails:
            ldap = email.split('@', 1)[0]
            if ldap in _EXCLUDED_TEAM_LDAPS or ldap not in person_map:
                continue
            person_map[ldap]['requirements'].append(copy.deepcopy(req))


def _do_stream_local(wfile):
    """本地模式（DAC_DDP_SOURCE=local）：不调用任何 DDP MCP，只读后端已存的 DDP 快照
    （GET /api/v1/ddp/snapshot）+ dac trace 汇总（GET /api/v1/trace/summary），合并、排序后
    落盘 DATA_FILE 并经 SSE 推送。用于无法配置 DDP MCP 的服务器。

    与 _do_stream_pages（mcp 模式）的区别：无 team-member DDP 全量拉取、
    不回推快照（_push_ddp_snapshot_to_backend）——本机是快照消费方而非生产方，回推会用
    「快照+trace」结果覆盖后端由真实 DDP 生成的权威快照。"""
    _send_sse(wfile, {'type': 'progress', 'message': '本地模式：读取服务端 DDP 快照与 trace 数据...'})
    backend_snapshot = _fetch_ddp_snapshot_from_backend()
    trace_result = _run_aggregate_trace()

    if _stream_cancel.is_set():
        return

    if backend_snapshot:
        # committer 为完整邮箱，.split('@')[0] 取 ldap 作 person_map key（与 mcp 路径一致）
        person_map = {
            c.get('committer', '').split('@')[0]: copy.deepcopy(c)
            for c in backend_snapshot.get('committers', [])
        }
        reqs_index = copy.deepcopy(backend_snapshot.get('requirements_index', []))
        _strip_stale_trace_overlay(person_map, reqs_index)
        _rebuild_person_requirements_from_index(person_map, reqs_index)
    else:
        # 降级：后端无 DDP 快照 → 仅展示 trace 数据（无 DDP 需求维度），不崩溃
        person_map = {}
        reqs_index = []
        _send_sse(wfile, {'type': 'warning',
                          'message': '后端无 DDP 快照，仅展示 git trace 数据（无 DDP 需求维度）'})

    # tm/bindings 复用于 trace 合并与 normalize：本地模式同样需要按 index 技术条目回填 orphan
    # 的 is_technical（dac-bind 后缀 trace 名 R-IBG-<num>-<local> 经 tm.extract_ddp_id 命中
    # tech_ids），否则技术需求在 local 模式经 orphan 注入绕过统计排除（与 mcp 模式口径一致）。
    tm = _load_transform()
    if trace_result:
        # hidden_r_ids 留空：本地模式无 DDP items 计算隐藏父需求集合，故 hidden_r_ids 保持空
        # frozenset() 不触发隐藏 R 过滤；tm/bindings 照常传入供 orphan 技术打标。
        _merge_trace_data(person_map, reqs_index, trace_result, frozenset(),
                          tm, _fetch_bindings_from_backend() or {})
        _send_sse(wfile, {'type': 'progress',
                          'message': f'已合并 {len(trace_result)} 位成员的 git trace 数据'})
    else:
        _send_sse(wfile, {'type': 'warning',
                          'message': 'git trace 不可用（后端无 trace 汇总），仅显示 DDP 快照数据'})

    # 展示层过滤：剔除非团队成员（如历史测试脏数据）后再排序与落盘
    _filter_non_team_data(person_map, reqs_index)

    if not reqs_index:
        _send_sse(wfile, {'type': 'error', 'message': '本地模式无可展示数据（后端快照与 trace 均为空）'})
        return

    tm.normalize_version_years(list(person_map.values()), reqs_index)
    _enrich_person_gitai(person_map, {})
    sorted_committers, sorted_reqs = _sort_by_dac(list(person_map.values()), reqs_index)
    dac_req_count = sum(1 for r in sorted_reqs
                        if (r.get('workflow_session_ids') or []) and not r.get('is_technical'))

    if _stream_cancel.is_set():
        return

    generated_at = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime())
    _quality_stats = _fetch_events_stats() or []
    _send_sse(wfile, {
        'type': 'page',
        'page': 1,
        'count': len(sorted_reqs),
        'dac_req_count': dac_req_count,
        'generatedAt': generated_at,
        'committers': sorted_committers,
        'requirements_index': sorted_reqs,
        'quality_stats': _quality_stats,
    })

    final = {
        'generatedAt': generated_at,
        'committers': sorted_committers,
        'requirements_index': sorted_reqs,
        'dac_req_count': dac_req_count,
        'personal_totals': _run_aggregate_personal_trace() or [],
        'quality_stats': _quality_stats,
    }
    with open(DATA_FILE, 'w', encoding='utf-8') as f:
        json.dump(final, f, ensure_ascii=False, indent=2)

    # 本地模式刻意不调 _push_ddp_snapshot_to_backend（见 docstring）
    _send_sse(wfile, {'type': 'done', 'total': len(sorted_reqs)})


def _quick_resync_after_delete(committer, req_name):
    """删除单条 trace 记录后的轻量同步：直接在已缓存的 DATA_FILE 里定位并处理该
    (committer, req_name) 条目，不重新拉取 DDP、也不经过 _merge_trace_data 的增量合并
    （该函数只做新增/覆盖、从不删除，若照搬全量刷新缓存的快照重新合并，被删除的记录会
    因"已存在则跳过"原样保留，导致删除后 UI 无变化）：
      - 纯 trace 编排条目（未绑定 DDP，req['ddp'] 为空）：直接从列表中移除；
      - 已绑定 DDP 的需求（req['ddp'] 非空）：需求本身保留，清空其 trace 派生字段
        （phases/features/workflow_session_ids/lines_added/lines_deleted/commit_count/
        codegen_lines_added/chat_lines_added/last_commit/last_commit_ts/reported_at），回落为"未使用 dac"状态。
    committer 为完整邮箱（前端上报口径）；person_map 以 ldap（@ 前缀）为 key 匹配。"""
    ldap = (committer or '').split('@')[0]

    def _reset_or_drop(req_list, require_committer_match):
        kept = []
        for req in req_list:
            if req.get('req_name') != req_name:
                kept.append(req)
                continue
            scoped = req.get('committers')
            # scoped 为 None（旧快照缺字段）视为无限制，放行匹配（兼容既有行为）；
            # scoped 为显式空列表（如受限 ldap 分发命中但无真实 rdOwner）视为无人可
            # 归属，不放行匹配，避免绕过校验误清空/误删无关人的 trace 数据。
            if require_committer_match and scoped is not None and (
                    not scoped or (committer not in scoped and ldap not in scoped)):
                kept.append(req)
                continue
            if req.get('ddp'):
                req['phases'] = []
                req['features'] = []
                req['workflow_session_ids'] = []
                req['lines_added'] = 0
                req['lines_deleted'] = 0
                req['commit_count'] = 0
                req['codegen_lines_added'] = 0
                req['chat_lines_added'] = 0
                req['last_commit'] = ''
                req['last_commit_ts'] = 0
                req['reported_at'] = None
                kept.append(req)
            # ddp 为空（纯 trace 编排条目）：不放入 kept，即从列表中移除
        return kept

    try:
        with open(DATA_FILE, encoding='utf-8') as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return
    if not isinstance(data, dict):
        return

    data['requirements_index'] = _reset_or_drop(data.get('requirements_index') or [], True)
    for person in (data.get('committers') or []):
        if person.get('committer', '').split('@')[0] != ldap:
            continue
        person['requirements'] = _reset_or_drop(person.get('requirements') or [], False)

    data['dac_req_count'] = sum(
        1 for r in data['requirements_index']
        if (r.get('workflow_session_ids') or []) and not r.get('is_technical')
    )
    with open(DATA_FILE, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    # 仅 mcp 模式（快照生产者）才回推：本地模式是快照消费方，回推会用自己这份
    # 非权威副本覆盖后端的真实 DDP 快照（同 _do_stream_local 的既有约束）。
    # 不回推会导致下次「刷新数据」时开头基于后端旧快照的过渡事件短暂复活刚删的记录，
    # 直至全量拉取完成后才自我修正。
    if DDP_SOURCE == 'mcp':
        _push_ddp_snapshot_to_backend(data)


def _do_stream_pages(wfile, hide_vibe):
    # 本地模式（服务器无 DDP MCP）：改走只读后端快照 + trace 的本地流程，不拉 DDP。
    # 本地流程不经 SSE 直接下发 personal_totals（只落盘），故不需要 hide_vibe。
    # mcp 模式（默认）以下原有逻辑逐字节不变。
    if DDP_SOURCE == 'local':
        _do_stream_local(wfile)
        return
    six_months_ago = _six_months_ago()
    tm = _load_transform()

    hub_url, _ = _ddp_config()
    if not hub_url:
        _send_sse(wfile, {'type': 'error', 'message': '~/.claude.json 中缺少 DDP hub 配置'})
        return

    backend_snapshot = _fetch_ddp_snapshot_from_backend()
    has_backend_snapshot = bool(backend_snapshot)
    # 工作流质量统计拉一次全程复用：SSE 各消息(backend_snapshot/trace_preview/page)都会被
    # 前端 setData 整体覆盖，漏带 quality_stats 会把 /api/data 首屏拉到的数据冲掉（闪烁归零）。
    # 拉取失败(None)时用上次落盘快照里的旧值兜底，再不行才空数组。
    _quality_stats = _fetch_events_stats()
    if _quality_stats is None:
        _quality_stats = backend_snapshot.get('quality_stats') if isinstance(backend_snapshot, dict) else None
    if _quality_stats is None:
        _quality_stats = []
    if backend_snapshot:
        # backend_snapshot 来自后端存储，可能含 personal_totals（由上一次刷新落盘时带入）；
        # 按本次请求的 hide_vibe 过滤后再展开到 SSE 消息，不影响 backend_snapshot 变量本身。
        _snapshot_payload = ({k: v for k, v in backend_snapshot.items() if k != 'personal_totals'}
                             if hide_vibe else backend_snapshot)
        _snapshot_payload = _filter_snapshot_payload(_snapshot_payload)
        _send_sse(wfile, {'type': 'backend_snapshot', **_snapshot_payload, 'quality_stats': _quality_stats})

    _send_sse(wfile, {'type': 'progress', 'message': '正在获取 Driver Mobile Tech 成员列表...'})
    team_members = _fetch_team_members()
    team_ldap_set = {ldap for ldap, _ in team_members}
    total_members = len(team_members)

    person_map = {
        ldap: {"committer": f"{ldap}@didiglobal.com", "committer_name": name,
               "dept": "Driver Mobile Tech", "requirements": []}
        for ldap, name in team_members
    }

    wfile_lock = threading.Lock()
    member_items = {}       # {ldap: [item, ...]}，线程写入
    items_lock = threading.Lock()
    completed = [0]
    abort_event = threading.Event()
    _sem = threading.Semaphore(4)   # 最多 4 条线程同时持有 DDP 连接

    def _sse(data):
        try:
            with wfile_lock:
                _send_sse(wfile, data)
        except OSError:
            abort_event.set()
            raise

    def _fetch_ddp_paginated(method, ldap, name):
        """按 relatedLdapList 分页拉取 DDP 数据（needs/tasks 共用），超过 6 个月窗口即停止。
        遇到不可恢复错误时置位 abort_event 并返回 None（调用方据此跳过本成员的落盘）。"""
        collected = []
        page_no = 1
        while not abort_event.is_set():
            _retry = 0
            while True:
                try:
                    data = _call_ddp(method, {
                        'pageNo': page_no,
                        'pageSize': 25,
                        'rules': [{'fieldName': 'relatedLdapList', 'ruleType': 'in', 'value': [ldap]}],
                        'extraFields': ['pmOwner', 'rdOwnerList', 'expectReleaseTime', 'dpmVersion', 'requirementId', 'sponsorId', 'requirement.sponsorId'],
                        'orderBy': 'mtime',
                    }, timeout=30)
                    break
                except urllib.error.HTTPError as e:
                    if e.code == 429 and _retry < 3:
                        _retry += 1
                        _wait = 2 ** _retry
                        _sse({'type': 'progress',
                              'message': f'[{name}] 触发限速 (429)，{_wait}s 后重试 ({_retry}/3)...'})
                        time.sleep(_wait)
                        continue
                    _sse({'type': 'error', 'message': f'DDP hub 不可用（{hub_url}）: {e}'})
                    abort_event.set()
                    return None
                except (urllib.error.URLError, OSError) as e:
                    _sse({'type': 'error', 'message': f'DDP hub 不可用（{hub_url}）: {e}'})
                    abort_event.set()
                    return None
                except Exception as e:
                    _sse({'type': 'warning', 'message': f'[{name}] 跳过（DDP 错误）: {e}'})
                    data = None
                    break
            if data is None:
                break

            content_block = data.get('content') or {}
            items = content_block.get('objectList') or []
            if not items:
                break

            oldest = ''
            for item in items:
                mf = item.get('mtime', {})
                # 任务（T- 前缀）的 mtime 用 displayContent 而非 value 表示，两者都要兼容
                mt = (mf.get('value') or mf.get('displayContent') or '') if isinstance(mf, dict) else ''
                if mt[:10] >= six_months_ago:
                    collected.append(item)
                if not oldest or mt < oldest:
                    oldest = mt

            if oldest and oldest[:10] < six_months_ago:
                break
            if len(items) < 25:
                break
            page_no += 1
        return collected

    def fetch_member(ldap, name, idx):
        if abort_event.is_set() or _stream_cancel.is_set():
            return
        _sse({'type': 'progress', 'message': f'[{idx + 1}/{total_members}] 正在获取 {name} 的需求...'})
        with _sem:
            # searchRequirements 只覆盖"需求"（R- 前缀）；DDP 还存在直接挂在项目下、不关联任何
            # 需求的独立"任务"（T- 前缀，searchIssues 覆盖），必须两者都拉取才不会漏掉后者
            requirements = _fetch_ddp_paginated('searchRequirements', ldap, name)
            if requirements is None:
                return
            issues = _fetch_ddp_paginated('searchIssues', ldap, name)
            if issues is None:
                return
            collected = requirements + issues

        with items_lock:
            member_items[ldap] = collected
            completed[0] += 1
            done = completed[0]
        _sse({'type': 'progress',
              'message': f'✅ [{done}/{total_members}] {name} 完成，共 {len(collected)} 条需求'})

    # 与 DDP 并发：提前启动 trace 后台聚合
    _trace_result: list = []

    def _bg_trace():
        result = _run_aggregate_trace()
        _trace_result.extend(result)
        if not result or abort_event.is_set() or _stream_cancel.is_set():
            return
        if not has_backend_snapshot:
            # 无缓存快照：trace_preview 提前展示本机 trace（只有本机 trace，没有 DDP 需求）
            trace_person_map = {}
            trace_reqs_index = []
            _merge_trace_data(trace_person_map, trace_reqs_index, result)
            if trace_reqs_index:
                _preview_event = {
                    'type': 'trace_preview',
                    'generatedAt': time.strftime('%Y-%m-%d %H:%M:%S', time.localtime()),
                    'committers': list(trace_person_map.values()),
                    'requirements_index': trace_reqs_index,
                    'quality_stats': _quality_stats,
                }
                if not hide_vibe:
                    _preview_event['personal_totals'] = _run_aggregate_personal_trace() or []
                _sse(_preview_event)
        else:
            # 有缓存快照：将新鲜 trace 叠加到快照副本上提前推送，使 +N 行/最近AI编辑
            # 秒级浮现，无需等 5–9 分钟 DDP 全量拉取。深拷贝避免污染 backend_snapshot 原对象。
            snap_person_map = {
                c.get('committer', '').split('@')[0]: copy.deepcopy(c)
                for c in backend_snapshot.get('committers', [])
            }
            snap_reqs_index = copy.deepcopy(backend_snapshot.get('requirements_index', []))
            _merge_trace_data(snap_person_map, snap_reqs_index, result)
            _filter_non_team_data(snap_person_map, snap_reqs_index)
            _snapshot_event = {
                'type': 'backend_snapshot',
                'generatedAt': backend_snapshot.get('generatedAt', ''),
                'committers': list(snap_person_map.values()),
                'requirements_index': snap_reqs_index,
                'dac_req_count': backend_snapshot.get('dac_req_count', 0),
                'quality_stats': _quality_stats,
            }
            if not hide_vibe:
                _snapshot_event['personal_totals'] = _run_aggregate_personal_trace() or []
            _sse(_snapshot_event)

    bg_trace = threading.Thread(target=_bg_trace, daemon=True)
    bg_trace.start()

    # 每人一条线程，并发拉取 DDP
    # 经加锁 _sse 推送：_bg_trace 线程（存活至下方 bg_trace.join）也经 _sse 写 wfile，
    # 主线程侧若直接 _send_sse 则与其无互斥，/summary 慢速降级时可能交叉写坏 SSE 帧
    _sse({'type': 'progress',
          'message': f'并发获取 {total_members} 位成员的需求数据...'})
    threads = [
        threading.Thread(target=fetch_member, args=(ldap, name, i), daemon=True)
        for i, (ldap, name) in enumerate(team_members)
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    if abort_event.is_set() or _stream_cancel.is_set():
        return

    # 并发阶段结束后，串行 accumulate 并逐步推送 page 事件
    # R/T 去重：先用全量 items 计算应隐藏的父需求 R-link 集合（其子任务 T 已在本批数据中），
    # 复用 transform-ddp.py 的 collect_hidden_r_links，保证与离线批量路径行为一致
    all_items = [it for its in member_items.values() for it in its]
    hidden_r_links = tm.collect_hidden_r_links(all_items)
    # 反向聚合参与 RD：member_items 的 key（ldap）即通过 relatedLdapList 查询命中该需求的团队成员，
    # 故某需求的全部司机端参与 RD = 所有 member_items 中出现该需求 link 的成员 ldap 并集。
    # 必须在串行 accumulate（按 req_name 去重先建条目）之前基于全量 member_items 建好，
    # 否则同一需求只会记录首个建条目成员，漏掉后续成员。
    req_participants = {}
    for ldap, items in member_items.items():
        for item in items:
            nf = item.get('name', {})
            link = nf.get('link', '') if isinstance(nf, dict) else ''
            if link:
                req_participants.setdefault(link, set()).add(ldap)
    reqs_index = []
    seen_reqs = set()
    for member_idx, (ldap, name) in enumerate(team_members):
        for item in member_items.get(ldap, []):
            _accumulate_item(item, [ldap], person_map, reqs_index, tm, seen_reqs, team_ldap_set,
                             hidden_r_links, req_participants)
        # 经加锁 _sse 推送：与仍可能存活的 _bg_trace 线程共享 wfile_lock，避免交叉写坏 SSE 帧
        _sse({
            'type': 'page',
            'page': member_idx + 1,
            'count': len(person_map[ldap]['requirements']),
            'generatedAt': time.strftime('%Y-%m-%d %H:%M:%S', time.localtime()),
            'committers': list(person_map.values()),
            'requirements_index': reqs_index,
            'quality_stats': _quality_stats,
        })

    if _stream_cancel.is_set():
        return

    # 等后台聚合完成（SSH 超时场景下可能达 300s，TTL 正常时约 10s）
    bg_trace.join(timeout=300)
    if _trace_result:
        # 换算隐藏集为数字 id，过滤 orphan 注入分支，避免被隐藏 R 经 trace 复活
        hidden_r_ids = {tm.extract_ddp_id(l) for l in hidden_r_links} - {''}
        # 传入 bindings：orphan 注入守卫据此用绑定目标判断隐藏 R，避免绑定到可见 T 的 trace
        # （名前缀恰为被隐藏父 R 的 id）被误删（best-effort，后端不可达时降级为空 dict 保持原过滤）
        _bindings = _fetch_bindings_from_backend() or {}
        _merge_trace_data(person_map, reqs_index, _trace_result, hidden_r_ids, tm, _bindings)
        _send_sse(wfile, {'type': 'progress', 'message': f'已合并 {len(_trace_result)} 位成员的 git trace 数据'})
    else:
        _send_sse(wfile, {'type': 'warning', 'message': 'git trace 不可用（非 git 仓库或无 dac-trace notes），仅显示 DDP 数据'})

    # 展示层过滤：剔除非团队成员（如历史测试脏数据）后再排序、落盘与回推
    _filter_non_team_data(person_map, reqs_index)

    dac_req_count = sum(1 for r in reqs_index
                        if (r.get('workflow_session_ids') or []) and not r.get('is_technical'))

    if _stream_cancel.is_set():
        return

    tm.normalize_version_years(list(person_map.values()), reqs_index)
    _enrich_person_gitai(person_map, {})
    sorted_committers, sorted_reqs = _sort_by_dac(list(person_map.values()), reqs_index)

    if not reqs_index:
        _send_sse(wfile, {'type': 'error', 'message': '未获取到任何需求数据'})
        return

    _send_sse(wfile, {
        'type': 'page',
        'page': total_members + 1,
        'count': len(sorted_reqs),
        'dac_req_count': dac_req_count,
        'generatedAt': time.strftime('%Y-%m-%d %H:%M:%S', time.localtime()),
        'committers': sorted_committers,
        'requirements_index': sorted_reqs,
        'quality_stats': _quality_stats,
    })

    final = {
        'generatedAt': time.strftime('%Y-%m-%d %H:%M:%S', time.localtime()),
        'committers': sorted_committers,
        'requirements_index': sorted_reqs,
        'dac_req_count': dac_req_count,
        'personal_totals': _run_aggregate_personal_trace() or [],
        'quality_stats': _fetch_events_stats() or [],
    }
    with open(DATA_FILE, 'w', encoding='utf-8') as f:
        json.dump(final, f, ensure_ascii=False, indent=2)

    _push_ddp_snapshot_to_backend(final)

    _send_sse(wfile, {'type': 'done', 'total': len(sorted_reqs)})


# ── legacy refresh (kept for backward compat) ──────────────────

def _do_refresh():
    with _refresh_lock:
        _refresh_state['running'] = True
        _refresh_state['error'] = None
        try:
            result = subprocess.run(
                ['bash', REFRESH_SCRIPT],
                capture_output=True, text=True, timeout=600
            )
            if result.returncode != 0:
                _refresh_state['error'] = (result.stderr or result.stdout or 'unknown error')[-1200:]
            else:
                _refresh_state['last_updated'] = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime())
        except subprocess.TimeoutExpired:
            _refresh_state['error'] = 'timeout (10 min)'
        except Exception as e:
            _refresh_state['error'] = str(e)
        finally:
            _refresh_state['running'] = False


def _ensure_initial_data():
    if not os.path.exists(DATA_FILE):
        demo = os.path.join(SCRIPT_DIR, 'dashboard-demo.json')
        if os.path.exists(demo):
            shutil.copy(demo, DATA_FILE)


if __name__ == '__main__':
    _ensure_initial_data()
    server = ThreadedHTTPServer((HOST, PORT), Handler)
    with open(PID_FILE, 'w') as f:
        f.write(str(os.getpid()))
    print(f'DAC Dashboard → http://{HOST}:{PORT}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)
