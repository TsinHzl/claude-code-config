import { TRACE_PHASE_ORDER, chapterDurations } from './phase'
import { DUR_CHART_IDLE_MS } from './durChart'
import { isCanonicalDriverVersion, shortVersionLabel, compareVersionDesc } from './version'
import { getDdpToTrace } from './enrich'
import { avgRounds, avgAttempts } from './qualityStats'

export const CHAPTER_SERIES = [
  { key: 'prd', label: 'PRD处理', color: 'var(--chart-req)' },
  { key: 'spec', label: '方案生成', color: 'var(--chart-mem)' },
  { key: 'plan', label: '功能规划', color: '#F59E0B' },
  { key: 'dev', label: '功能开发', color: 'var(--brand-strong)' },
]
export const GROUP_SERIES = [
  ...CHAPTER_SERIES,
  { key: 'total', label: '总耗时', color: '#64748B' },
]

export const VIEW_MODES = [
  { id: 'combo', label: '柱+折线（单章节）', sub: '左轴=耗时 · 右轴=dac 行数 · 一次一个章节',
    tip: '选一个章节画柱，紫色虚线是该需求 dac 行数（规模）。未完成不画柱。超过 2 天的柱仍从底画到顶，颜色变淡表示搁置，不拉高纵轴。' },
  { id: 'req', label: '需求视图（分组柱）', sub: '横轴=需求 · 一组细柱 · 当前版本',
    tip: '每个需求一组细柱，对比四阶段和总耗时。纵轴主体按不到 24 小时的值来画，短柱会相对高一些；满 24 小时的柱仍从 0 画到顶，落在最上面加宽的「≥24h」那一档。空心短柱=该阶段被跳过，没柱=还没完成。' },
  { id: 'rel', label: '阶段关系', sub: '横轴=阶段 · 平均耗时 vs 轮次 · 当前版本',
    tip: '当前版本四个阶段的平均耗时（左轴）和平均轮次（右轴）。两条线同一阶段一起高，才说明耗时长和返工多有关。满 24 小时的耗时不进平均。开发轮次用代码检查均次。' },
  { id: 'funnel', label: '阶段漏斗', sub: '当前版本 · 到达 vs 完成',
    tip: '只统计当前版本的 DAC 工作流。浅色条=到达过这一阶段的需求数，深色条=走完这一阶段。中位耗时只计不到 24 小时的完成样本。用来看人卡在哪一格。' },
  { id: 'pass', label: '一次通过', sub: '当前版本 · 1 / 2 / ≥3 轮占比',
    tip: '只统计当前版本。左边「N 个需求」是这一门纳入统计的需求个数，不是轮次数。绿=一次通过（1 轮），橙=2 轮，红=≥3 轮。没上报事件的用户门按一次通过计。代码检查 / CR 只计做过该检查的需求，所以个数可能更少。' },
  { id: 'trend', label: '版本趋势', sub: '各正式版本中位耗时',
    tip: '横轴是 Global司机端正式版本。折线是该版本 DAC 各阶段中位耗时（不到 2 天的样本）。橙色虚线=当前版本。坐标轴下的数字是该版本有耗时数据的 DAC 需求数，很少时不要当成趋势。' },
]

export function lastTraceTs(phases) {
  const ts = {}
  for (const p of Array.isArray(phases) ? phases : []) {
    if (p && p.phase && p.ts != null && TRACE_PHASE_ORDER[p.phase] != null) ts[p.phase] = p.ts
  }
  return ts
}

export function isDacTrace(req) {
  return (req?.phases || []).some((p) => p && TRACE_PHASE_ORDER[p.phase] != null)
}

export function uniqueDacTraces(requirementsIndex) {
  const seen = new Set()
  const out = []
  for (const r of requirementsIndex || []) {
    if (!r?.req_name || seen.has(r.req_name) || !isDacTrace(r)) continue
    seen.add(r.req_name)
    out.push(r)
  }
  return out
}

export function median(arr) {
  const s = (arr || []).filter((v) => v != null && Number.isFinite(v)).slice().sort((a, b) => a - b)
  if (!s.length) return null
  const m = Math.floor(s.length / 2)
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2
}

export function mean(arr) {
  const s = (arr || []).filter((v) => v != null && Number.isFinite(v))
  if (!s.length) return null
  return s.reduce((a, b) => a + b, 0) / s.length
}

export function fmtShortDur(ms) {
  if (!(ms > 0)) return '—'
  const h = ms / 3_600_000
  if (h < 1) return `${Math.round(ms / 60_000)}m`
  if (h < 48) return `${Math.round(h * 10) / 10}h`
  return `${Math.round((h / 24) * 10) / 10}天`
}

function qualityOf(stats, name) {
  if (!Array.isArray(stats) || !name) return null
  const k = String(name).toLowerCase()
  return stats.find((r) => String(r?.req_name || '').toLowerCase() === k) || null
}

function qualityOfAny(stats, names) {
  for (const n of names || []) {
    const hit = qualityOf(stats, n)
    if (hit) return hit
  }
  return null
}

function roundsVal(row, key) {
  if (!row) return null
  const v = row[key]
  if (typeof v !== 'number' || v <= 0) return 1
  return v
}

function attemptVal(row, timesKey, totalKey) {
  if (!row) return null
  const tot = row[totalKey] || 0
  if (!tot) return null
  return (row[timesKey] || 0) / tot
}

function skipChapters(tr) {
  const set = new Set()
  for (const s of tr?.skipped_stages || []) {
    if (s === 'prd_parse') set.add('prd')
    if (s === 'feature_plan') {
      set.add('spec')
      set.add('plan')
    }
  }
  return set
}

export function buildReqChartRows(group, requirementsIndex, bindings) {
  const byName = new Map((requirementsIndex || []).map((r) => [r.req_name, r]))
  const map = getDdpToTrace(bindings)
  const rows = []
  const traceNames = []
  const seen = new Set()
  for (const { r } of group?.items || []) {
    if (!r || seen.has(r.req_name)) continue
    let traces = []
    if ((r.workflow_session_ids || []).length > 0) traces = [r]
    else if (r.ddp) traces = (map[r.req_name] || []).map((n) => byName.get(n)).filter(Boolean)
    if (!traces.length) continue
    seen.add(r.req_name)
    const row = { name: r.ddp?.title || r.req_name, dac: 0, skip: new Set() }
    CHAPTER_SERIES.forEach((s) => { row[s.key] = 0 })
    traces.forEach((tr) => {
      const d = chapterDurations(tr.phases)
      row.dac += tr.lines_added || 0
      CHAPTER_SERIES.forEach((s) => { row[s.key] = Math.max(row[s.key], d[s.key] || 0) })
      skipChapters(tr).forEach((k) => row.skip.add(k))
      if (tr.req_name) traceNames.push(tr.req_name)
    })
    row.total = (row.prd || 0) + (row.spec || 0) + (row.plan || 0) + (row.dev || 0)
    rows.push(row)
  }
  return { rows, traceNames: [...new Set(traceNames)] }
}

export function buildStageRelation(chartRows, qualityStats, reqNames, idleMs = DUR_CHART_IDLE_MS) {
  const avgDur = (key) => mean((chartRows || []).map((r) => r[key]).filter((v) => v > 0 && v < idleMs))
  return [
    { key: 'prd', label: 'PRD处理', dur: avgDur('prd'), rnd: avgRounds(qualityStats, reqNames, 'clarify_rounds') },
    { key: 'spec', label: '方案生成', dur: avgDur('spec'), rnd: avgRounds(qualityStats, reqNames, 'proposal_rounds') },
    { key: 'plan', label: '功能规划', dur: avgDur('plan'), rnd: avgRounds(qualityStats, reqNames, 'feature_plan_rounds') },
    { key: 'dev', label: '功能开发', dur: avgDur('dev'), rnd: avgAttempts(qualityStats, reqNames, 'codegen_check_times', 'codegen_feats_total') },
  ]
}

export function buildFunnel(traces, idleMs = DUR_CHART_IDLE_MS) {
  const list = traces || []
  const steps = [
    { key: 'enter', label: '进入工作流', reach: (ts) => Object.keys(ts).length > 0, done: (ts) => Object.keys(ts).length > 0, chapter: null },
    { key: 'prd', label: 'PRD处理', reach: (ts) => 'prd-parsing' in ts, done: (ts) => 'prd-clarified' in ts, chapter: 'prd' },
    { key: 'spec', label: '方案生成', reach: (ts) => 'prd-specing' in ts, done: (ts) => 'proposal-approved' in ts, chapter: 'spec' },
    { key: 'plan', label: '功能规划', reach: (ts) => 'feature-planned' in ts, done: (ts) => 'feature-planned' in ts, chapter: 'plan' },
    { key: 'feat', label: '功能完成', reach: (ts) => 'feature-planned' in ts || 'feature-loop' in ts, done: (ts) => 'feature-done' in ts, chapter: null },
    { key: 'done', label: '归档', reach: (ts) => 'feature-done' in ts, done: (ts) => 'done' in ts, chapter: 'dev' },
  ]
  return {
    total: list.length,
    steps: steps.map((s) => {
      let reach = 0
      let done = 0
      const durs = []
      for (const tr of list) {
        const ts = lastTraceTs(tr.phases)
        const ch = chapterDurations(tr.phases)
        if (s.reach(ts)) reach++
        if (s.done(ts)) done++
        if (s.chapter && ch[s.chapter] > 0 && ch[s.chapter] < idleMs) durs.push(ch[s.chapter])
      }
      return { key: s.key, label: s.label, reach, done, med: median(durs) }
    }),
  }
}

function metricMean(list, pick) {
  const vals = list.map(pick).filter((v) => v != null && Number.isFinite(v))
  return { n: vals.length, v: mean(vals) }
}

function metricMedian(list, pick) {
  const vals = list.map(pick).filter((v) => v != null && Number.isFinite(v))
  return { n: vals.length, v: median(vals) }
}

/** 代理：有功能规划、无方案通过 ≈ 跳过方案门。 */
export function buildSkipContrast(traces, qualityStats, idleMs = DUR_CHART_IDLE_MS) {
  const skip = []
  const thru = []
  for (const tr of traces || []) {
    const ts = lastTraceTs(tr.phases)
    if (!('feature-planned' in ts)) continue
    const row = { ch: chapterDurations(tr.phases), q: qualityOf(qualityStats, tr.req_name) }
    if ('proposal-approved' in ts) thru.push(row)
    else skip.push(row)
  }
  const devPick = (r) => {
    const v = r.ch.dev
    return v > 0 && v < idleMs ? v : null
  }
  return {
    skipN: skip.length,
    thruN: thru.length,
    metrics: [
      {
        key: 'cg', label: '代码检查均次', kind: 'n',
        skip: metricMean(skip, (r) => attemptVal(r.q, 'codegen_check_times', 'codegen_feats_total')),
        thru: metricMean(thru, (r) => attemptVal(r.q, 'codegen_check_times', 'codegen_feats_total')),
      },
      {
        key: 'cr', label: 'CR 均次', kind: 'n',
        skip: metricMean(skip, (r) => attemptVal(r.q, 'cr_check_times', 'cr_feats_total')),
        thru: metricMean(thru, (r) => attemptVal(r.q, 'cr_check_times', 'cr_feats_total')),
      },
      {
        key: 'dev', label: '开发中位耗时', kind: 'dur',
        skip: metricMedian(skip, devPick),
        thru: metricMedian(thru, devPick),
      },
    ],
  }
}

function bucketRounds(v) {
  if (v == null) return null
  if (v <= 1) return 0
  if (v < 3) return 1
  return 2
}

export function buildPassTable(qualityStats, traces, idleMs = DUR_CHART_IDLE_MS, aliasMap = {}) {
  const rows = qualityStats || []
  const chaptersByName = new Map()
  for (const tr of traces || []) {
    if (tr?.req_name) chaptersByName.set(String(tr.req_name).toLowerCase(), chapterDurations(tr.phases))
  }
  const units = (traces || []).length
    ? traces.map((tr) => {
        const aliases = [tr.req_name, aliasMap?.[tr.req_name]].filter(Boolean)
        return {
          name: tr.req_name,
          ch: chapterDurations(tr.phases),
          q: qualityOfAny(rows, aliases),
        }
      })
    : rows.map((r) => ({
        name: r.req_name,
        ch: chaptersByName.get(String(r.req_name || '').toLowerCase()) || {},
        q: r,
      }))
  function gate(label, pick, chapterKey) {
    const vals = []
    const durs = []
    for (const u of units) {
      const v = pick(u.q)
      if (v == null) continue
      vals.push(v)
      const d = chapterKey ? u.ch?.[chapterKey] : 0
      if (d > 0 && d < idleMs) durs.push(d)
    }
    const b = [0, 0, 0]
    vals.forEach((v) => { b[bucketRounds(v)] += 1 })
    return { label, n: vals.length, b, med: median(durs) }
  }
  return [
    gate('PRD澄清', (r) => roundsVal(r, 'clarify_rounds') ?? 1, 'prd'),
    gate('方案', (r) => roundsVal(r, 'proposal_rounds') ?? 1, 'spec'),
    gate('功能规划', (r) => roundsVal(r, 'feature_plan_rounds') ?? 1, 'plan'),
    gate('代码检查', (r) => attemptVal(r, 'codegen_check_times', 'codegen_feats_total'), 'dev'),
    gate('CR', (r) => attemptVal(r, 'cr_check_times', 'cr_feats_total'), null),
  ]
}

export function versionOfTrace(trace, bindings, byName) {
  const ddp = trace?.ddp
  if (ddp?.release_version_name) return { name: ddp.release_version_name, time: ddp.release_version_time || '' }
  const ddpName = bindings?.[trace?.req_name]
  const host = ddpName ? byName.get(ddpName) : null
  const d = host?.ddp
  if (d?.release_version_name) return { name: d.release_version_name, time: d.release_version_time || '' }
  return { name: '', time: '' }
}

export function buildVersionTrend(traces, bindings, requirementsIndex, currentVersionName, idleMs = DUR_CHART_IDLE_MS) {
  const byName = new Map((requirementsIndex || []).map((r) => [r.req_name, r]))
  const groups = new Map()
  for (const tr of traces || []) {
    const { name, time } = versionOfTrace(tr, bindings, byName)
    if (!isCanonicalDriverVersion(name)) continue
    if (!groups.has(name)) groups.set(name, { name, time, traces: [] })
    const g = groups.get(name)
    g.traces.push(tr)
    if (time) g.time = time
  }
  return [...groups.values()]
    .sort((a, b) => -compareVersionDesc(a.name, b.name))
    .map((g) => {
      const row = {
        w: shortVersionLabel(g.name),
        name: g.name,
        n: g.traces.length,
        cur: g.name === currentVersionName,
        prd: null,
        spec: null,
        plan: null,
        dev: null,
      }
      for (const key of ['prd', 'spec', 'plan', 'dev']) {
        const durs = g.traces
          .map((tr) => chapterDurations(tr.phases)[key])
          .filter((v) => v > 0 && v < idleMs)
        row[key] = median(durs)
      }
      return row
    })
}
