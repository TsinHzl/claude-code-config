#!/usr/bin/env python3
"""
Transform raw DDP API objectList items into dashboard JSON format.
Usage: python3 transform-ddp.py <raw-items.json> <output.json>
"""
import json, sys, re, time
from datetime import date, datetime, timezone, timedelta

CST = timezone(timedelta(hours=8))  # DDP mtime 字段为北京时间，非 UTC

DDP_PHASES = [
    "waiting-tech",  # 待技术准入
    "tech-review",   # 技术准入
    "scheduled",     # 已排期
    "developing",    # 开发中
    "submitted",     # 已提测
    "testing",       # 测试中
    "qa-passed",     # 已准出
    "released",      # 已上线
]
DDP_STATE_TO_PHASE = {
    "待技术准入": "waiting-tech",
    "技术准入":   "tech-review",
    "已排期":     "scheduled",
    "开发中":     "developing",
    "已提测":     "submitted",
    "测试中":     "testing",
    "已准出":     "qa-passed",
    "已上线":     "released",
    # 上线后终态：DDP 状态机在「已上线」之后还会流转 已验收(411) → 小流量(21) → 已完成(22)
    # （getIssueState/getRequirementState 实测）。这三个原先不在表内，make_phases 返回 None、
    # 调用方直接丢弃整条需求，导致已交付完成的需求在看板上彻底消失（单次刷新实测丢 349 条）。
    # 语义上均已发布，统一收敛到最后一个阶段 released。新增 DDP 状态必须同步补进本表。
    "已验收":     "released",
    "小流量":     "released",
    "已完成":     "released",
}

def mtime_to_ts(mtime_str):
    m = re.match(r'(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}):(\d{2}))?', mtime_str or '')
    if m:
        y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
        h, mi, s = int(m.group(4) or 0), int(m.group(5) or 0), int(m.group(6) or 0)
        try:
            return int(datetime(y, mo, d, h, mi, s, tzinfo=CST).timestamp() * 1000)
        except ValueError:
            return 1780000000000
    return 1780000000000

def make_phases(state, mtime_str):
    last = DDP_STATE_TO_PHASE.get(state)
    if last is None:
        print(f"[warn] unknown DDP state: {state!r}, skipping", file=sys.stderr)
        return None
    idx = DDP_PHASES.index(last)
    base_ts = mtime_to_ts(mtime_str)
    step = 3600 * 1000
    return [{"phase": p, "ts": base_ts - (idx - i) * step}
            for i, p in enumerate(DDP_PHASES[:idx + 1])]

def make_features(state, req_link, mtime_str):
    if state in ("已上线", "已准出", "小流量", "已完成", "已验收"):
        st = "done"
    elif state in ("开发中", "已提测", "测试中"):
        st = "in_progress"
    else:
        st = "pending"
    return [{"id": req_link.lower().replace("-", "_"), "status": st,
             "ts": mtime_to_ts(mtime_str)}]

def _select_dpm_display_content(dpm_field):
    """需求（R-）的 dpmVersion 是单个 dict；任务（T-）的 dpmVersion 是 dict 列表
    （一个任务常同时挂多端版本，如乘客端+司机端各一条）。列表时优先选包含"司机端"的
    条目，找不到则取第一条。"""
    if isinstance(dpm_field, dict):
        if not (dpm_field.get('value') or []):
            return ''
        return dpm_field.get('displayContent', '')
    if isinstance(dpm_field, list):
        candidates = [d.get('displayContent', '') for d in dpm_field
                      if isinstance(d, dict) and d.get('displayContent')]
        if not candidates:
            return ''
        for c in candidates:
            if '司机端' in c:
                return c
        return candidates[0]
    return ''

def parse_dpm_version(dpm_field):
    display = _select_dpm_display_content(dpm_field)
    if not display:
        return '', ''
    m = re.match(r'^\[(\d{2})(\d{2})\]\s*(.*)$', display)
    if not m:
        return display, ''
    month, day, name = int(m.group(1)), int(m.group(2)), m.group(3)
    # dpmVersion 只带月-日（[MMDD]），无年份。年份锚定"距今最近的一次"而非任务 mtime：
    # mtime 会因早期规划/后期回改而漂移，使同一版本得到不同年份（如 7.10.42 混出
    # 2025/2026-07-30）。以 today 为锚取最近一次 MM-DD，保证同版本所有任务年份一致，
    # 且近半年内的版本（含当前/即将发布）年份准确。
    today = date.today()
    try:
        candidate = date(today.year, month, day)
    except ValueError:
        # 已知限制：2-29 落在非闰年的 today.year 时直接丢弃日期（返回空），
        # 不回退到邻近闰年——约 4 年一遇的极端个案，不影响常规版本。
        return name, ''
    # 取距今最近的同月-日：偏离超过半年则前后挪一年
    try:
        if (candidate - today).days > 182:
            candidate = candidate.replace(year=today.year - 1)
        elif (today - candidate).days > 182:
            candidate = candidate.replace(year=today.year + 1)
    except ValueError:
        pass  # 闰日边界，保持当年
    return name, candidate.strftime('%Y-%m-%d')


def _version_number_tuple(name):
    """从版本名尾部提取版本号元组 + 系列前缀，如 'Global司机端7.10.42' → ((7,10,42),'Global司机端')。
    同系列（前缀相同）内版本号单调 = 上线时间单调。无尾部版本号则返回 (None, name)。"""
    m = re.search(r'(\d+(?:\.\d+)*)\s*$', name or '')
    if not m:
        return None, name or ''
    return tuple(int(x) for x in m.group(1).split('.')), (name or '')[:m.start()].rstrip()


def normalize_version_years(committers, reqs_index):
    """基于版本号单调性重排 release_version_time 的年份（就地修改所有 ddp）。

    dpmVersion 只带 [MMDD] 无年份，parse_dpm_version 逐条按“距今最近”锚定，对跨越半年以上的
    历史版本会锚错（如司机端 7.9.90 的 0109 被推成 2027-01-09）。此函数在全量数据组装完成后统一
    校正：同系列内版本号单调 = 上线时间单调，以“距今最近的版本”为可靠锚，沿版本号升序双向传播
    年份，MM-DD 回绕处进退一年。仅重写已有非空 release_version_time 的年份，不新增日期、不改月-日。"""
    today = date.today()
    ddps = []
    for c in committers:
        if not isinstance(c, dict):
            continue
        for r in c.get('requirements', []) or []:
            d = r.get('ddp') if isinstance(r, dict) else None
            if isinstance(d, dict):
                ddps.append(d)
    for r in reqs_index or []:
        d = r.get('ddp') if isinstance(r, dict) else None
        if isinstance(d, dict):
            ddps.append(d)

    # 1) 按系列前缀归组：{prefix: {version_tuple: (name, month, day)}}
    series = {}
    for d in ddps:
        name = d.get('release_version_name') or ''
        t = d.get('release_version_time') or ''
        if not name or len(t) < 10:
            continue
        vt, prefix = _version_number_tuple(name)
        if vt is None:
            continue
        try:
            month, day = int(t[5:7]), int(t[8:10])
        except ValueError:
            continue
        series.setdefault(prefix, {})[vt] = (name, month, day)

    def _nearest_year(month, day):
        best_y, best_dist = today.year, None
        for y in (today.year - 1, today.year, today.year + 1):
            try:
                dist = abs((date(y, month, day) - today).days)
            except ValueError:
                continue
            if best_dist is None or dist < best_dist:
                best_dist, best_y = dist, y
        return best_y

    # 2) 逐系列计算校正后的年份：锚点固定取版本号最高者（末位=最新发布，年份最可信；
    #    避免用“距今最近”挑锚——那正是原始 bug 的同套不可靠假设，且当整条系列都远离今天时会锚错）。
    #    沿版本号降序向低版本单向传播：本版 MM-DD 晚于其后继（更高版本）说明落在上一年 → 年份 -1。
    name_time = {}
    for prefix, vmap in series.items():
        entries = sorted(vmap.items())  # 按版本号升序，末位即最高版本
        n = len(entries)
        if n == 0:
            continue
        years = [None] * n
        am, ad = entries[-1][1][1], entries[-1][1][2]
        years[-1] = _nearest_year(am, ad)
        for i in range(n - 2, -1, -1):
            nm, nd = entries[i + 1][1][1], entries[i + 1][1][2]
            cm, cd = entries[i][1][1], entries[i][1][2]
            years[i] = years[i + 1] - (1 if (cm, cd) > (nm, nd) else 0)
        for i, (_vt, (nm2, m, dd)) in enumerate(entries):
            try:
                name_time[nm2] = date(years[i], m, dd).strftime('%Y-%m-%d')
            except ValueError:
                pass  # 闰日 0229 落到非闰年 → 放弃校正保留原值（约 4 年一遇，与 parse_dpm_version 同策略）

    # 3) 就地重写（仅覆盖已有非空日期的年份）
    changed = 0
    for d in ddps:
        nm = d.get('release_version_name') or ''
        if nm in name_time and (d.get('release_version_time') or ''):
            if d['release_version_time'] != name_time[nm]:
                changed += 1
            d['release_version_time'] = name_time[nm]
    if changed:
        print(f"[version-year] 校正 {changed} 处版本上线年份", flush=True)

def get_rdowners(item):
    rd = item.get('rdOwnerList')
    if not isinstance(rd, dict):
        return []
    return [o for o in (rd.get('dataList') or [])
            if isinstance(o, dict) and o.get('hrStatus') == 'A']

def get_pmowner(item):
    # 任务（T- 前缀）没有顶层 pmOwner，PM Owner 挂在其所属需求下的 requirement.pmOwner
    pm = item.get('pmOwner') or item.get('requirement.pmOwner')
    if not isinstance(pm, dict):
        return ''
    dl = pm.get('dataList') or []
    return dl[0].get('name', '') if dl and isinstance(dl[0], dict) else pm.get('displayContent', '')

def get_requirement_link(item):
    """任务（T-）通过 requirementId 回指其父需求（R-）。返回父 R 的 link（如
    `R-IBG-653360`），字段缺失/非 dict/空值一律返回空字符串。"""
    rid = item.get('requirementId')
    if not isinstance(rid, dict):
        return ''
    return rid.get('displayContent', '') or ''


def collect_hidden_r_links(items):
    """收集应被隐藏的父需求 R-link：某个任务 T 通过 requirementId 指向的父 R，只要该父 R 也出现在
    本批 items 中，就隐藏之（纯父子关系，全局隐藏，不看 rdOwner 是否重叠）。返回 R-link 集合。"""
    r_links = set()
    parent_links = set()
    for item in items:
        nf = item.get('name', {})
        link = nf.get('link', '') if isinstance(nf, dict) else ''
        if link.startswith('R-'):
            r_links.add(link)
        elif link.startswith('T-'):
            parent = get_requirement_link(item)
            if parent:
                parent_links.add(parent)
    return parent_links & r_links


def extract_ddp_id(s):
    """从完整 link（`R-IBG-653360` / `R-RLAB-12345`）或 dac-bind 后的 trace req_name
    （`R-IBG-653360-<local>` / 纯数字 `653360-<local>`）中提取前导数字 id（全局唯一，等于需求
    的 name.value）。无匹配返回空字符串。用于以数字 id 为键跨空间前缀/绑定格式比对隐藏集。"""
    m = re.match(r'^(?:[RT]-[A-Z]+-)?(\d+)', s or '')
    return m.group(1) if m else ''


def is_technical_requirement(item):
    """判定 DDP 需求是否为技术类需求（发起方 sponsorId=3：业务1/产品2/技术3/设计6/数据8）。

    MCP searchRequirements 返回的 sponsorId 实证形态为 {"displayContent": "技术"}（仅中文
    标签、无数值 value 键），兼容 {"value": 3} 包裹、裸 int 3 及中文标签三种形态。取值来源：
    顶层字段或 requirement.sponsorId 回溯（照抄 get_pmowner 的 T- 回溯模式）。displayContent
    标签优先（displayContent 与 value 并存时标签更直观且不受枚举漂移影响），无标签再回退数值。
    字段缺失或解析失败返回 False（fail-open：宁漏排不误删，与「任务缺失父子关联字段——安全
    降级」策略一致）。"""
    raw = item.get('sponsorId') or item.get('requirement.sponsorId') or {}
    if isinstance(raw, dict):
        label = (raw.get('displayContent') or '').strip()
        if label:
            return label == '技术'
        value = raw.get('value')
    else:
        value = raw
    try:
        return int(value) == 3
    except (TypeError, ValueError):
        return False


def transform(items):
    person_map = {}
    reqs_index = []

    # R/T 去重：隐藏「已有子任务 T 同时出现在本批数据中」的父需求 R，以 T 为展示主体
    hidden_r_links = collect_hidden_r_links(items)

    for item in items:
        nf = item.get('name', {})
        link  = nf.get('link', '') if isinstance(nf, dict) else ''
        if link in hidden_r_links:
            continue
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

        release_version_name, release_version_time = parse_dpm_version(item.get('dpmVersion', {}))

        pm_name = get_pmowner(item)
        owners  = get_rdowners(item)
        phases  = make_phases(state, mtime)
        if phases is None:
            continue
        features = make_features(state, link, mtime)
        # 技术类需求（sponsorId=3）不再于数据层排除，仅打 is_technical 标记（成员副本与
        # requirements_index 各写一次）。仅命中携带该键；无该键即非技术（判定函数 fail-open）。
        is_tech = is_technical_requirement(item)

        req_obj = {
            "req_name": link,
            "workflow_session_ids": [],
            "phases": phases,
            "features": features,
            "last_note_id": "",
            "last_commit": "",
            "last_commit_ts": phases[-1]['ts'],
            "ddp": {
                "id": link, "title": title, "state": state,
                "expected_release": expected, "direction": direction, "pm_owner": pm_name,
                "release_version_name": release_version_name,
                "release_version_time": release_version_time
            }
        }
        if is_tech:
            req_obj["is_technical"] = True

        for owner in owners:
            ldap = owner.get('ldap', '')
            if ldap not in person_map:
                person_map[ldap] = {
                    "committer": f"{ldap}@didiglobal.com",
                    "committer_name": owner.get('name', ldap),
                    "dept": owner.get('deptName', ''),
                    "requirements": []
                }
            person_map[ldap]['requirements'].append(req_obj)

        if not owners:
            key = '__unassigned__'
            if key not in person_map:
                person_map[key] = {"committer": "unassigned@didiglobal.com",
                                   "committer_name": "未分配", "dept": "", "requirements": []}
            person_map[key]['requirements'].append(req_obj)

        index_entry = {
            "req_name": link,
            "committers": [f"{o.get('ldap','')}@didiglobal.com" for o in owners],
            "phases": phases,
            "features": features,
            "last_commit_ts": phases[-1]['ts'],
            "ddp": req_obj['ddp']
        }
        if is_tech:
            index_entry["is_technical"] = True
        reqs_index.append(index_entry)

    return {
        "generatedAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        "committers": list(person_map.values()),
        "requirements_index": reqs_index
    }

def merge_ai_stats(dashboard, ai_stats_file):
    """Attach ai_stats from git-ai notes onto matching committer objects."""
    with open(ai_stats_file, encoding='utf-8') as f:
        ai_stats = json.load(f)
    matched = 0
    for c in dashboard['committers']:
        email = c.get('committer', '')
        if email in ai_stats:
            c['ai_stats'] = ai_stats[email]
            matched += 1
    print(f"[ai-stats] 匹配 {matched}/{len(dashboard['committers'])} 位成员", flush=True)


def merge_trace(dashboard, trace_file, hidden_r_ids=frozenset()):
    """Replace committer requirements with dac-trace data when available.

    hidden_r_ids: 被隐藏父需求 R 的数字 id 集合。dac-bind 后 trace req_name 形如
    `R-IBG-<num>-<local>` 或纯数字 `<num>-<local>`；命中隐藏集则剔除，避免被隐藏的 R
    经整段覆盖复活（守护 R/T 去重不变量）。"""
    with open(trace_file, encoding='utf-8') as f:
        trace = json.load(f)

    # requirements_index 版本索引：{req_name→(name,time), 数字id→(name,time)}，仅收非空版本名。
    # 用于给 trace 覆盖后的 committer requirements 补 ddp.release_version_name（见 _stamp_versions）。
    rv_index = {}
    # 技术需求索引：{req_name, 数字id} 命中 is_technical=true 的 requirements_index 条目。
    # 技术需求不再于数据层排除，但 trace 覆盖整段重建 committer requirements 时不保留顶层
    # is_technical；此处按 index 回填，避免技术需求绑 trace 后丢失标记（见 _stamp_versions）。
    tech_index = set()
    for ri in dashboard.get('requirements_index', []):
        ddp = ri.get('ddp') or {}
        name = ddp.get('release_version_name') or ''
        rn = ri.get('req_name', '')
        did = extract_ddp_id(rn)
        # 技术需求索引不随 rv_index 一起受 name-gate 约束：技术需求若缺 release_version_name
        # （未排期/未归档进某版本），其 trace 覆盖整段重建成员副本时仍需回填 is_technical，
        # 故 tech_index 收集必须在 continue 之前（tech_index 只回填标记，不参与版本名配对）。
        if ri.get('is_technical'):
            if rn:
                tech_index.add(rn)
            if did:
                tech_index.add(did)
        if not name:
            continue
        time = ddp.get('release_version_time') or ''
        if rn:
            rv_index.setdefault(rn, (name, time))
        if did:
            rv_index.setdefault(did, (name, time))

    def _lookup(req):
        rn = req.get('req_name', '')
        if rn in rv_index:
            return rv_index[rn]
        did = extract_ddp_id(rn)
        return rv_index.get(did) if did else None

    def _stamp_versions(reqs):
        """给 trace 覆盖后的 requirements 写 ddp.release_version_name/time，并回填 is_technical。
        铁律：name 与 time 绝不来自不同解析时刻（见 design 决策 4）——
        trace 自带版本名优先；仅当 requirements_index 当前解析出的版本名与之相同才附 index 的 time，
        否则 time 置空，避免"旧版本名 + 错日期"误导拼接。"""
        for req in reqs:
            if not isinstance(req, dict):
                continue
            # 回填技术标记：trace 整段覆盖丢失的 is_technical 按 requirements_index 补回。
            rn = req.get('req_name', '')
            if not req.get('is_technical'):
                if rn in tech_index:
                    req['is_technical'] = True
                else:
                    did = extract_ddp_id(rn)
                    if did and did in tech_index:
                        req['is_technical'] = True
            trace_name = (req.get('release_version_name')
                          or (req.get('ddp') or {}).get('release_version_name') or '')
            idx = _lookup(req)  # (name, time) or None
            if trace_name:
                if idx and idx[0] == trace_name:
                    name, time = trace_name, idx[1]      # 同源配对安全
                else:
                    name, time = trace_name, ''          # 不跨源拼接日期
            elif idx:
                name, time = idx[0], idx[1]              # 同取 index，配对安全
            else:
                name, time = '', ''
            # name 为空且原本无 ddp 时不改结构；否则规范化写入 ddp 两字段
            if name or req.get('ddp') is not None:
                ddp = req.setdefault('ddp', {})
                ddp['release_version_name'] = name
                ddp['release_version_time'] = time

    merged = 0
    for c in dashboard['committers']:
        email = c.get('committer', '')
        if email in trace:
            reqs = trace[email]
            if hidden_r_ids:
                reqs = [r for r in reqs
                        if extract_ddp_id(r.get('req_name', '')) not in hidden_r_ids]
            _stamp_versions(reqs)
            c['requirements'] = reqs
            merged += 1
    print(f"[trace] 合并 {merged}/{len(dashboard['committers'])} 位成员的 trace 数据", flush=True)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('raw_file')
    parser.add_argument('output_file')
    parser.add_argument('--ai-stats', default=None, dest='ai_stats')
    parser.add_argument('--trace',    default=None)
    args = parser.parse_args()

    with open(args.raw_file, encoding='utf-8') as f:
        items = json.load(f)
    dashboard = transform(items)

    if args.ai_stats:
        merge_ai_stats(dashboard, args.ai_stats)
    if args.trace:
        # 与 transform() 内一致的隐藏集，换算成数字 id 供 trace 过滤（守护去重不变量）。
        # 技术需求不再并入隐藏集：技术需求不再于数据层排除，若其绑了 dac trace 应正常合并展示。
        hidden_r_ids = {extract_ddp_id(l) for l in collect_hidden_r_links(items)} - {''}
        merge_trace(dashboard, args.trace, hidden_r_ids)

    normalize_version_years(dashboard['committers'], dashboard['requirements_index'])

    with open(args.output_file, 'w', encoding='utf-8') as f:
        json.dump(dashboard, f, ensure_ascii=False, indent=2)
    c = len(dashboard['committers'])
    r = len(dashboard['requirements_index'])
    print(f"✅ 转换完成：{c} 位成员，{r} 条需求", flush=True)
