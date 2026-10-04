export const PHASE_META = [
  { key: 'waiting-tech', label: '待技术准入' },
  { key: 'tech-review', label: '技术准入' },
  { key: 'scheduled', label: '已排期' },
  { key: 'developing', label: '开发中' },
  { key: 'submitted', label: '已提测' },
  { key: 'testing', label: '测试中' },
  { key: 'qa-passed', label: '已准出' },
  { key: 'released', label: '已上线' },
]
export const PHASE_ORDER = Object.fromEntries(PHASE_META.map((p, i) => [p.key, i]))
export const PHASE_LABEL = Object.fromEntries(PHASE_META.map(p => [p.key, p.label]))

export const TRACE_PHASE_META = [
  { key: 'init', label: '初始化' },
  { key: 'prd-parsing', label: '解析PRD' },
  { key: 'prd-parsed', label: 'PRD完成' },
  { key: 'prd-clarified', label: '需求澄清' },
  { key: 'prd-specing', label: '生成规格' },
  { key: 'prd-speced', label: '规格完成' },
  { key: 'proposal-approved', label: '方案通过' },
  { key: 'feature-planned', label: '功能规划' },
  { key: 'feature-done', label: '功能完成' },
  { key: 'done', label: '已完成' },
]
/** 含 feature-loop（卡片不单独占格，但算耗时/当前阶段时要认）。 */
export const TRACE_PHASE_ORDER = {
  init: 0,
  'prd-parsing': 1,
  'prd-parsed': 2,
  'prd-clarified': 3,
  'prd-specing': 4,
  'prd-speced': 5,
  'proposal-approved': 6,
  'feature-planned': 7,
  'feature-loop': 8,
  'feature-done': 9,
  done: 10,
}
export const TRACE_PHASE_LABEL = Object.fromEntries(TRACE_PHASE_META.map(p => [p.key, p.label]))

/** 开发循环中时，卡片把「功能完成」格标成当前（运行中）。 */
export function displayTracePhase(phase) {
  return phase === 'feature-loop' ? 'feature-done' : phase
}

/** flow_profile 明确跳过的阶段 → 卡片上对应格子。mastergo/scaffold 不占 stepper。 */
export const SKIP_STAGE_PHASES = {
  prd_parse: ['prd-parsing', 'prd-parsed', 'prd-clarified'],
  feature_plan: ['proposal-approved', 'feature-planned'],
}

export function skippedPhaseSet(skippedStages) {
  const set = new Set()
  for (const s of skippedStages || []) {
    for (const k of SKIP_STAGE_PHASES[s] || []) set.add(k)
  }
  return set
}

export function currentPhase(phases) {
  if (!phases?.length) return 'waiting-tech'
  let max = -1, best = 'waiting-tech'
  for (const p of phases) {
    const o = PHASE_ORDER[p.phase] ?? -1
    if (o > max) { max = o; best = p.phase }
  }
  return best
}

export function currentTracePhase(phases) {
  if (!phases?.length) return 'init'
  let max = -1, best = 'init'
  for (const p of phases) {
    const o = TRACE_PHASE_ORDER[p.phase] ?? -1
    if (o > max) { max = o; best = p.phase }
  }
  return best
}

export function featureSummary(features) {
  const s = { total: 0, done: 0, in_progress: 0, pending: 0, failed: 0, skipped: 0 }
  if (!features?.length) return s
  const latest = {}
  for (const f of features) {
    if (!latest[f.id] || f.ts > latest[f.id].ts) latest[f.id] = f
  }
  s.total = Object.keys(latest).length
  for (const f of Object.values(latest)) {
    const st = f.status || 'pending'
    if (st in s) s[st]++
  }
  return s
}

/**
 * 卡片格子耗时 = 到达本阶段花了多久（本格 ts − 上一格真实打点）。
 * 缺中间格不向后借：规划格不会吞掉开发时间。
 * 同一 phase 多次出现取最后一次。
 */
export function phaseDurations(phases) {
  const last = {}
  for (const p of Array.isArray(phases) ? phases : []) {
    if (p && p.phase && p.ts != null && TRACE_PHASE_ORDER[p.phase] != null) last[p.phase] = p.ts
  }
  const sorted = Object.keys(last)
    .map((phase) => ({ phase, ts: last[phase] }))
    .sort((a, b) => TRACE_PHASE_ORDER[a.phase] - TRACE_PHASE_ORDER[b.phase])
  const out = {}
  for (let i = 1; i < sorted.length; i++) {
    const dur = sorted[i].ts - sorted[i - 1].ts
    if (dur > 0) out[sorted[i].phase] = dur
  }
  return out
}

export function phaseTotalDuration(phases) {
  const d = phaseDurations(phases)
  return Object.values(d).reduce((s, v) => s + v, 0)
}

/**
 * 四大业务章节（按状态机间隔归并；起点=进入 from 的 ts，终点=进入 to 的 ts，即同一
 * 时间戳既是上一章终点也是下一章起点，无重复计数）：
 *   PRD处理 = prd-parsing → prd-clarified（裁剪+澄清）
 *   方案生成 = prd-specing → proposal-approved（规格+proposal）
 *   功能规划 = proposal-approved → feature-planned（功能拆分）
 *   功能开发 = feature-planned → done（开发循环+归档）
 * 启动等待（init→prd-parsing）与澄清后等待（prd-clarified→prd-specing）不计入任何章节。
 */
export const TRACE_CHAPTERS = [
  { key: 'prd', label: 'PRD处理', from: 'prd-parsing', to: 'prd-clarified' },
  { key: 'spec', label: '方案生成', from: 'prd-specing', to: 'proposal-approved' },
  { key: 'plan', label: '功能规划', from: 'proposal-approved', to: 'feature-planned' },
  { key: 'dev', label: '功能开发', from: 'feature-planned', to: 'done' },
]

/**
 * 计算单需求的章节耗时（毫秒），返回 { 章节key: durationMs }。
 * 口径：章节真正完成（from/to 两个边界 ts 都存在）才计入；进行中/未到的章节无值。
 * 同一 phase 多次出现（回滚重走）取最后一次，代表最终那一遍的边界。
 */
export function chapterDurations(phases) {
  const ts = {}
  for (const p of Array.isArray(phases) ? phases : []) {
    if (p && p.phase && p.ts != null) ts[p.phase] = p.ts // 后写覆盖 = 取最后一次
  }
  const out = {}
  for (const c of TRACE_CHAPTERS) {
    const s = ts[c.from], e = ts[c.to]
    if (s != null && e != null && e > s) out[c.key] = e - s
  }
  return out
}

/** 四章节耗时之和（纯工作时间，不含启动/澄清间等待）；无完成章节返回 0。 */
export function chapterTotalDuration(phases) {
  const d = chapterDurations(phases)
  return TRACE_CHAPTERS.reduce((s, c) => s + (d[c.key] || 0), 0)
}
