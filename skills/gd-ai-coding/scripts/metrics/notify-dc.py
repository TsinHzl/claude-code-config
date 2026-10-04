#!/usr/bin/env python3
"""
DC Notification Scheduler for DAC (Driver AI Coding Workflow)
Usage:
    python3 notify-dc.py [--config ~/.claude/skills/dashboard/dc-config.json] [--dry-run]
"""
import argparse
import datetime
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional, Set, Tuple

_DASHBOARD_CONFIG_HOME = os.environ.get(
    'DAC_CONFIG_HOME',
    os.path.expanduser('~/.claude/skills/dashboard'),
)
DEFAULT_CONFIG_PATH = os.path.join(_DASHBOARD_CONFIG_HOME, 'dc-config.json')
DEFAULT_CACHE_PATH = os.path.join(_DASHBOARD_CONFIG_HOME, 'dc-notified-cache.json')
DEFAULT_REMARKS_PATH = os.path.join(_DASHBOARD_CONFIG_HOME, 'remarks.json')
DEFAULT_DATA_FILE = '/tmp/dac-metrics-data.json'
DEFAULT_DASHBOARD_URL = 'http://127.0.0.1:47890'
DEFAULT_NOTIFY_NODES = ['developing', '开发中', 'coding', 'in_progress']
DEFAULT_COOLDOWN_HOURS = 72
DC_TEXT_MAX_LEN = 3000  # D-Chat Incoming Webhook text 字段上限
_INVALID_LDAPS = {'unassigned', 'untitled', 'unknown', 'none'}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='DAC 进入开发阶段需求研发人员 DC 提醒推送脚本')
    parser.add_argument('--config', default=DEFAULT_CONFIG_PATH, help='配置文件路径')
    parser.add_argument('--data-file', default=DEFAULT_DATA_FILE, help='度量数据文件路径')
    parser.add_argument('--remarks-file', default=DEFAULT_REMARKS_PATH, help='备注文件路径')
    parser.add_argument('--cache-file', default=DEFAULT_CACHE_PATH, help='发送防骚扰冷却缓存文件路径')
    parser.add_argument('--dashboard-url', default=None, help='看板 URL (默认 http://127.0.0.1:47890)')
    parser.add_argument('--api-url', default=None, help='DC Incoming Webhook URL')
    parser.add_argument('--mode', choices=['webhook'], default=None,
                        help='发送模式: webhook (群机器人，@人替代私聊；private 私信模式已废弃)')
    parser.add_argument('--nodes', default=None, help='逗号分隔的触发节点列表 (如 developing,开发中)')
    parser.add_argument('--cooldown-hours', type=float, default=None, help='防骚扰冷却时间 (小时，默认 72)')
    parser.add_argument('--version-name', default=None, help='指定目标版本名称 (默认自动计算当前司机端版本)')
    parser.add_argument('--dry-run', action='store_true', help='预览模式: 仅打印待推送人员与消息，不发网络请求与写缓存')
    return parser.parse_args()


def load_config(config_path: str) -> Dict[str, Any]:
    cfg: Dict[str, Any] = {}
    if os.path.exists(config_path):
        try:
            with open(config_path, encoding='utf-8') as f:
                cfg = json.load(f)
        except Exception as e:
            print(f'[warn] 读取配置文件 {config_path} 失败: {e}', file=sys.stderr)
    return cfg


def resolve_options(args: argparse.Namespace, cfg: Dict[str, Any]) -> Dict[str, Any]:
    # 兼容旧配置字段 dc_api_url；webhook 凭据优先读新字段 webhook_url
    api_url = args.api_url or os.environ.get('DAC_DC_API_URL') or cfg.get('webhook_url') or cfg.get('dc_api_url', '')
    mode = args.mode or os.environ.get('DAC_DC_SEND_MODE') or cfg.get('send_mode', 'webhook')
    if mode == 'private':
        print('[warn] send_mode=private (私信) 已废弃: Incoming Webhook 仅支持群会话，自动切换为 webhook 群发 + @人', file=sys.stderr)
        mode = 'webhook'
    dashboard_url = (args.dashboard_url or os.environ.get('DAC_DASHBOARD_URL')
                     or cfg.get('dashboard_url') or DEFAULT_DASHBOARD_URL).rstrip('/')

    nodes_env = os.environ.get('DAC_DC_NODES')
    if args.nodes:
        nodes = [n.strip() for n in args.nodes.split(',') if n.strip()]
    elif nodes_env:
        nodes = [n.strip() for n in nodes_env.split(',') if n.strip()]
    elif 'notify_nodes' in cfg and isinstance(cfg['notify_nodes'], list):
        nodes = [str(n).strip() for n in cfg['notify_nodes'] if str(n).strip()]
    else:
        nodes = list(DEFAULT_NOTIFY_NODES)

    cooldown_env = os.environ.get('DAC_DC_COOLDOWN_HOURS')
    if args.cooldown_hours is not None:
        cooldown_hours = args.cooldown_hours
    elif cooldown_env:
        try:
            cooldown_hours = float(cooldown_env)
        except ValueError:
            cooldown_hours = DEFAULT_COOLDOWN_HOURS
    elif 'cooldown_hours' in cfg:
        try:
            cooldown_hours = float(cfg['cooldown_hours'])
        except (ValueError, TypeError):
            cooldown_hours = DEFAULT_COOLDOWN_HOURS
    else:
        cooldown_hours = DEFAULT_COOLDOWN_HOURS

    dry_run = args.dry_run or (os.environ.get('DAC_DC_DRY_RUN', '').lower() in ('1', 'true', 'yes'))

    return {
        'api_url': api_url,
        'mode': mode,
        'dashboard_url': dashboard_url,
        'notify_nodes': [n.lower() for n in nodes],
        'cooldown_hours': cooldown_hours,
        'version_name': args.version_name,
        'dry_run': dry_run,
        'cache_file': args.cache_file,
        'data_file': args.data_file,
        'remarks_file': args.remarks_file,
    }


def fetch_data(data_file: str, dashboard_url: str) -> Optional[Dict[str, Any]]:
    url = f'{dashboard_url}/api/data'
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'dac-notify-dc/1.0'})
        with urllib.request.urlopen(req, timeout=10, context=build_ssl_context()) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            if isinstance(data, dict):
                return data
    except Exception as e:
        print(f'[warn] 请求看板数据接口 {url} 失败: {e}', file=sys.stderr)

    if os.path.exists(data_file):
        try:
            with open(data_file, encoding='utf-8') as f:
                data = json.load(f)
            if isinstance(data, dict) and ('requirements_index' in data or 'committers' in data):
                return data
        except Exception as e:
            print(f'[warn] 读取本地数据文件 {data_file} 失败: {e}', file=sys.stderr)

    return None


def fetch_remarks(remarks_file: str, dashboard_url: str) -> Dict[str, Any]:
    url = f'{dashboard_url}/api/remarks'
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'dac-notify-dc/1.0'})
        with urllib.request.urlopen(req, timeout=5, context=build_ssl_context()) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            if isinstance(data, dict):
                return data
    except Exception:
        pass

    if os.path.exists(remarks_file):
        try:
            with open(remarks_file, encoding='utf-8') as f:
                data = json.load(f)
                if isinstance(data, dict):
                    return data
        except Exception as e:
            print(f'[warn] 读取本地备注文件 {remarks_file} 失败: {e}', file=sys.stderr)

    return {}


def is_canonical_driver_version(name: str) -> bool:
    return bool(re.match(r'^Global司机端\d', name or ''))


def version_num_parts(name: str) -> List[int]:
    m = re.search(r'(\d+(?:\.\d+)*)\s*$', name or '')
    if m:
        return [int(x) for x in m.group(1).split('.')]
    return [0]


def find_target_version(reqs: List[Dict[str, Any]], target_version_name: Optional[str] = None) -> Optional[str]:
    if target_version_name:
        return target_version_name

    today_str = datetime.date.today().strftime('%Y-%m-%d')
    version_time_map: Dict[str, str] = {}
    for r in reqs:
        ddp = r.get('ddp') or {}
        vname = ddp.get('release_version_name') or ''
        vtime = ddp.get('release_version_time') or ddp.get('expected_release') or ''
        if vname and is_canonical_driver_version(vname):
            if vname not in version_time_map or (vtime and vtime > version_time_map[vname]):
                version_time_map[vname] = vtime

    future_or_today = [
        (vname, vtime) for vname, vtime in version_time_map.items()
        if vtime and vtime >= today_str
    ]
    if future_or_today:
        future_or_today.sort(key=lambda x: x[1])
        return future_or_today[0][0]

    all_driver_versions = list(version_time_map.keys())
    if all_driver_versions:
        all_driver_versions.sort(key=lambda x: version_num_parts(x), reverse=True)
        return all_driver_versions[0]

    return None


def is_req_active_with_ai(req: Dict[str, Any]) -> bool:
    sessions = req.get('workflow_session_ids') or []
    if len(sessions) > 0:
        return True
    lines = int(req.get('lines_added') or 0)
    commits = int(req.get('commit_count') or 0)
    if lines > 0 or commits > 0:
        return True
    return False


def is_req_remarked(req_name: str, ddp_id: str, remarks: Dict[str, Any]) -> bool:
    for raw_key in (req_name, ddp_id):
        key = str(raw_key or '').strip()
        if not key:
            continue
        rem = remarks.get(key)
        if isinstance(rem, dict):
            tag = (rem.get('reason_tag') or '').strip()
            note = (rem.get('note') or '').strip()
            if tag or note:
                return True
    return False


def is_state_matching_nodes(req: Dict[str, Any], notify_nodes: List[str]) -> bool:
    ddp = req.get('ddp') or {}
    state = (ddp.get('state') or '').strip().lower()
    phases = req.get('phases') or []
    current_phase = phases[-1].get('phase', '').strip().lower() if phases else ''

    for node in notify_nodes:
        if node in state or state == node or current_phase == node:
            return True
    return False


def extract_rd_list(req: Dict[str, Any]) -> List[str]:
    res: Set[str] = set()
    for raw in (req.get('committers') or []) + (req.get('rd_list') or []):
        if isinstance(raw, str) and raw.strip():
            ldap = raw.split('@')[0].strip().lower()
            if ldap and ldap not in _INVALID_LDAPS:
                res.add(ldap)

    return sorted(list(res))


def load_cache(cache_file: str) -> Dict[str, float]:
    if os.path.exists(cache_file):
        try:
            with open(cache_file, encoding='utf-8') as f:
                data = json.load(f)
                if isinstance(data, dict):
                    records = data.get('records')
                    if isinstance(records, dict):
                        return records
                    return data
        except Exception as e:
            print(f'[warn] 读取缓存文件 {cache_file} 失败: {e}', file=sys.stderr)
    return {}


def save_cache(cache_file: str, cache: Dict[str, float]) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(cache_file)), exist_ok=True)
    tmp_path = f'{cache_file}.tmp'
    try:
        with open(tmp_path, 'w', encoding='utf-8') as f:
            json.dump({'updated_at': int(time.time() * 1000), 'records': cache}, f, ensure_ascii=False, indent=2)
        os.replace(tmp_path, cache_file)
    except Exception as e:
        print(f'[warn] 保存缓存文件 {cache_file} 失败: {e}', file=sys.stderr)


def is_in_cooldown(cache: Dict[str, float], key: str, cooldown_hours: float) -> bool:
    last_ts = cache.get(key)
    if not last_ts:
        return False
    now_ms = time.time() * 1000
    return (now_ms - last_ts) < (cooldown_hours * 3600 * 1000)


def build_message(req_title: str, req_name: str, version_name: str, dashboard_url: str,
                  rds: Optional[List[str]] = None) -> str:
    encoded_req = urllib.parse.quote(req_name)
    url = f'{dashboard_url}/?req={encoded_req}&tab=reqs'
    # D-Chat @人语法: 顶层 text 中 @<username> 即可 at 用户，username 后必须跟空格
    mention_prefix = ''.join(f'@{rd} ' for rd in (rds or []))
    if mention_prefix:
        mention_prefix = f"{mention_prefix}\n"
    return (
        f"{mention_prefix}"
        f"【司机端 AI 工作流提醒】\n"
        f"您好！您参与的需求已进入开发阶段：\n"
        f"📌 需求：{req_title} ({req_name})\n"
        f"🏷️ 版本：{version_name}\n\n"
        f"💡 推荐使用司机端 AI 编码工作流进行 PRD 澄清、代码生成与 CR，提升研发效率。\n"
        f"🔗 看板与未采用原因备注：{url}\n\n"
        f"如因特殊原因暂未采用（如配置改动、非业务代码、遇到工具/环境问题等），欢迎在看板点击「+备注」填写反馈，感谢支持！"
    )


def truncate_dc_text(message: str, max_len: int = DC_TEXT_MAX_LEN) -> str:
    if len(message) <= max_len:
        return message
    print(f'[warn] 消息长度 {len(message)} 超过 D-Chat text 上限 {max_len}，已截断', file=sys.stderr)
    return message[:max_len]


def build_ssl_context() -> ssl.SSLContext:
    """构建 HTTPS 上下文: certifi 优先 (部分机器 Python 无系统 CA 链),
    无 certifi 时用默认上下文 (证书校验失败由调用方错误处理兜底)"""
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        print('[warn] certifi 未安装，使用默认 SSL 上下文'
              ' (缺系统 CA 链的机器可能证书校验失败)', file=sys.stderr)
        return ssl.create_default_context()


def send_dc_notification(api_url: str, message: str) -> bool:
    if not api_url:
        print('[error] 未配置 webhook_url (或旧字段 dc_api_url)，无法发送 DC 消息', file=sys.stderr)
        return False

    # D-Chat Incoming Webhook: URL 自带鉴权，仅需 POST JSON {"text": ...}
    headers = {
        'Content-Type': 'application/json;charset=utf-8',
        'User-Agent': 'dac-notify-dc/1.0'
    }
    payload = {
        'text': truncate_dc_text(message),
        'markdown': True
    }

    body = json.dumps(payload, ensure_ascii=False).encode('utf-8')
    ctx = build_ssl_context()
    req = urllib.request.Request(api_url, data=body, headers=headers, method='POST')

    try:
        try:
            with urllib.request.urlopen(req, timeout=10, context=ctx) as resp:
                raw = resp.read().decode('utf-8', errors='ignore')
        except urllib.error.URLError as e:
            # 系统证书链缺失 (CERTIFICATE_VERIFY_FAILED) 时用 certifi 证书重试一次。
            # 注: HTTPError 是 URLError 子类，会先被此处捕获再经 else 放行到外层
            if isinstance(getattr(e, 'reason', None), ssl.SSLError) and 'CERTIFICATE_VERIFY_FAILED' in str(e.reason):
                print('[warn] 系统证书校验失败，回退 certifi 证书重试', file=sys.stderr)
                with urllib.request.urlopen(req, timeout=10, context=build_ssl_context()) as resp:
                    raw = resp.read().decode('utf-8', errors='ignore')
            else:
                raise
    except urllib.error.HTTPError as e:
        print(f'[error] 发送 DC 消息失败 (HTTP {e.code}): {e.read().decode("utf-8", errors="ignore")}', file=sys.stderr)
        return False
    except Exception as e:
        print(f'[error] 发送 DC 消息异常: {e}', file=sys.stderr)
        return False

    # 响应校验: HTTP 200 且 body code==0 才算发送成功; trace_id 记录用于排查
    try:
        result = json.loads(raw)
    except Exception:
        print(f'[warn] DC 响应非 JSON，按失败处理: {raw[:200]}', file=sys.stderr)
        return False
    if not isinstance(result, dict):
        print(f'[warn] DC 响应为非对象 JSON，按失败处理: {raw[:200]}', file=sys.stderr)
        return False
    code = result.get('code')
    if code != 0:
        print(f'[error] DC Webhook 返回失败: code={code}, errmsg={result.get("errmsg") or result.get("message")}, body={raw[:200]}', file=sys.stderr)
        return False
    trace_id = (result.get('result') or {}).get('trace_id') or ''
    print(f'[info] DC 发送成功, trace_id={trace_id}')
    return True


def run_scheduler() -> int:
    args = parse_args()
    cfg = load_config(args.config)
    opts = resolve_options(args, cfg)

    print(f"=== DAC DC 提醒调度器启动 ===")
    print(f"模式: {'[DRY-RUN 预览]' if opts['dry_run'] else '[正式发送]'}")
    print(f"提醒节点白名单: {', '.join(opts['notify_nodes'])}")
    print(f"防骚扰冷却周期: {opts['cooldown_hours']} 小时")

    data = fetch_data(opts['data_file'], opts['dashboard_url'])
    if not data:
        print(f"[error] 无法获取度量数据源 (本地文件与看板接口均失败)", file=sys.stderr)
        return 1

    reqs = data.get('requirements_index') or []
    remarks = fetch_remarks(opts['remarks_file'], opts['dashboard_url'])
    cache = load_cache(opts['cache_file'])

    target_version = find_target_version(reqs, opts['version_name'])
    if not target_version:
        print(f"[warn] 未找到符合条件的目标版本需求，跳过本次调度")
        return 0

    print(f"目标版本: {target_version}")

    version_reqs = []
    for r in reqs:
        ddp = r.get('ddp') or {}
        vname = ddp.get('release_version_name') or ''
        if vname == target_version or (target_version and target_version in vname):
            version_reqs.append(r)

    print(f"版本内总需求数: {len(version_reqs)}")

    matched_node_count = 0
    active_ai_count = 0
    remarked_count = 0
    cooldown_count = 0
    tech_skipped_count = 0
    notified_count = 0
    cache_dirty = False

    for r in version_reqs:
        req_name = r.get('req_name') or ''
        ddp = r.get('ddp') or {}
        req_title = ddp.get('title') or req_name
        ddp_id = ddp.get('id') or ''

        # 技术需求（is_technical，sponsorId=3）在看板属统计范围外，跳过提醒
        if r.get('is_technical'):
            tech_skipped_count += 1
            continue

        if not is_state_matching_nodes(r, opts['notify_nodes']):
            continue
        matched_node_count += 1

        if is_req_active_with_ai(r):
            active_ai_count += 1
            continue

        if is_req_remarked(req_name, ddp_id, remarks):
            remarked_count += 1
            continue

        rds = extract_rd_list(r)
        if not rds:
            continue

        # 冷却过滤: 先剔除冷却期内人员，剩余人员按需求聚合为一条群消息 @全员
        active_rds = []
        for rd in rds:
            cache_key = f"{target_version}_{req_name}_{rd}"
            if is_in_cooldown(cache, cache_key, opts['cooldown_hours']):
                cooldown_count += 1
                continue
            active_rds.append(rd)

        if not active_rds:
            continue

        msg = build_message(req_title, req_name, target_version, opts['dashboard_url'], rds=active_rds)

        if opts['dry_run']:
            print(f"[DRY-RUN] 将在群内发送提醒并 @ {' '.join(active_rds)} | 需求: {req_title} ({req_name})")
            print(f"--- 消息预览 ---\n{msg}\n----------------")
            notified_count += len(active_rds)
        else:
            ok = send_dc_notification(opts['api_url'], msg)
            if ok:
                print(f"[success] 已发送群提醒并 @ {' '.join(active_rds)} | 需求: {req_title} ({req_name})")
                for rd in active_rds:
                    cache[f"{target_version}_{req_name}_{rd}"] = time.time() * 1000
                cache_dirty = True
                notified_count += len(active_rds)
            else:
                print(f"[fail] 群提醒发送失败 | 需求: {req_title} ({req_name})")

    if cache_dirty and not opts['dry_run']:
        save_cache(opts['cache_file'], cache)

    print(f"\n=== 调度汇总 ===")
    print(f"节点匹配需求数: {matched_node_count}")
    print(f"技术需求数 (统计范围外, 跳过): {tech_skipped_count}")
    print(f"已采用 AI 需求数 (跳过): {active_ai_count}")
    print(f"已有备注需求数 (跳过): {remarked_count}")
    print(f"冷却期内记录 (跳过): {cooldown_count}")
    print(f"实际{'预览' if opts['dry_run'] else '通知'}人次: {notified_count}")

    return 0


if __name__ == '__main__':
    sys.exit(run_scheduler())
