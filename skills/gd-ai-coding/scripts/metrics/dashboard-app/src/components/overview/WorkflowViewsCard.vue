<template>
  <div class="card-block">
    <div class="card-title">
      各需求 章节耗时 vs 质量
      <span class="hint view-help">?<span class="tip">{{ currentMode.tip }}</span></span>
      <span class="card-title-sub">{{ currentMode.sub }}</span>
      <select class="view-select" v-model="chartMode">
        <option v-for="m in VIEW_MODES" :key="m.id" :value="m.id">{{ m.label }}</option>
      </select>
    </div>

    <template v-if="chartMode === 'req'">
      <div class="dur-scroll" ref="durScroll">
        <div v-if="!chartRows.length" class="empty-state">当前版本暂无 DAC 工作流耗时数据</div>
        <svg v-else id="dur-chart" ref="durChart" :width="durChartW" :height="durChartH" style="display:block;"></svg>
      </div>
      <div class="legend-row">
        <button v-for="s in GROUP_SERIES" :key="s.key" type="button" class="lg-toggle lg-req"
                :class="{ off: !onGroup[s.key] }" @click="toggleGroup(s.key)">
          <span class="lg-swatch lg-bar" :style="{ background: s.color }"></span>{{ s.label }}
        </button>
        <span class="lg-item">斜纹柱=≥24h（仍从 0 到顶） · 空心斜纹=已跳过</span>
      </div>
    </template>

    <template v-else-if="chartMode === 'combo'">
      <div class="phase-pills">
        <button v-for="s in CHAPTER_SERIES" :key="s.key" type="button" class="phase-pill"
                :class="{ on: chartPhase === s.key }"
                :style="{ '--pill-color': s.color }"
                @click="chartPhase = s.key">{{ s.label }}</button>
      </div>
      <div class="dur-scroll" ref="durScroll">
        <div v-if="!chartRows.length" class="empty-state">当前版本暂无 DAC 工作流耗时数据</div>
        <svg v-else id="dur-chart" ref="durChart" :width="durChartW" :height="durChartH" style="display:block;"></svg>
      </div>
      <div class="legend-row">
        <span class="lg-item">
          <span class="lg-swatch lg-bar" :style="{ background: selectedPhase.color }"></span>{{ selectedPhase.label }}
        </span>
        <span class="lg-item"><span class="lg-swatch lg-dash"></span>dac 行数(复杂度)</span>
        <span class="lg-item">淡色虚线柱=超 2 天，仍从底画到顶</span>
      </div>
    </template>

    <template v-else-if="chartMode === 'rel'">
      <svg ref="relChart" width="100%" height="280" viewBox="0 0 720 280"></svg>
      <div class="legend-row">
        <span class="lg-item"><span class="lg-swatch" style="background:#2563EB"></span>平均耗时（左轴）</span>
        <span class="lg-item"><span class="lg-swatch lg-dash-orange"></span>平均轮次（右轴）</span>
      </div>
    </template>

    <template v-else-if="chartMode === 'funnel'">
      <div v-if="!funnel.total" class="empty-state">当前版本暂无 DAC 工作流</div>
      <div v-else class="funnel">
        <div v-for="s in funnel.steps" :key="s.key" class="fn-row">
          <div class="fn-label">{{ s.label }}</div>
          <div class="fn-track">
            <div class="fn-reach" :style="{ width: barPct(s.reach, funnel.total) }"></div>
            <div class="fn-done" :style="{ width: barPct(s.done, funnel.total) }"></div>
          </div>
          <div class="fn-meta">
            到达 {{ s.reach }} 条 · 完成 {{ s.done }} 条<template v-if="s.reach > s.done"> · 未完成 {{ s.reach - s.done }}</template>
            <template v-if="s.med"><br>中位 {{ fmtShortDur(s.med) }}</template>
          </div>
        </div>
      </div>
      <div class="legend-row">
        <span class="lg-item"><span class="lg-swatch lg-bar" style="background:#93C5FD"></span>到达该阶段</span>
        <span class="lg-item"><span class="lg-swatch lg-bar" style="background:#2563EB"></span>完成该阶段</span>
      </div>
    </template>

    <template v-else-if="chartMode === 'pass'">
      <div v-if="!passTable.some((s) => s.n)" class="empty-state">当前版本暂无质量事件</div>
      <div v-else class="pass">
        <div v-for="s in passTable" :key="s.label" class="pass-row">
          <div class="fn-label">{{ s.label }}<div class="pass-meta">{{ s.n }} 个需求</div></div>
          <div class="pass-bar">
            <span :style="{ width: passW(s, 0), background: '#22C55E' }" :title="`一次通过（1轮）：${s.b[0]} 个需求`"></span>
            <span :style="{ width: passW(s, 1), background: '#F59E0B' }" :title="`2 轮：${s.b[1]} 个需求`"></span>
            <span :style="{ width: passW(s, 2), background: '#DC2626' }" :title="`≥3 轮：${s.b[2]} 个需求`"></span>
          </div>
          <div class="pass-meta">
            1轮 {{ s.b[0] }}个 · 2轮 {{ s.b[1] }}个 · ≥3轮 {{ s.b[2] }}个
            <template v-if="s.med"><br>中位耗时 {{ fmtShortDur(s.med) }}</template>
          </div>
        </div>
      </div>
      <div class="legend-row">
        <span class="lg-item"><span class="lg-swatch lg-bar" style="background:#22C55E"></span>一次通过（1 轮）</span>
        <span class="lg-item"><span class="lg-swatch lg-bar" style="background:#F59E0B"></span>2 轮</span>
        <span class="lg-item"><span class="lg-swatch lg-bar" style="background:#DC2626"></span>≥3 轮</span>
      </div>
    </template>

    <template v-else-if="chartMode === 'trend'">
      <div v-if="!versionTrend.length" class="empty-state">暂无正式版本的 DAC 耗时</div>
      <svg v-else ref="trendChart" width="100%" height="280" viewBox="0 0 720 280"></svg>
      <div class="legend-row">
        <button v-for="s in CHAPTER_SERIES" :key="s.key" type="button" class="lg-toggle"
                :class="{ off: !onTrend[s.key] }" @click="toggleTrend(s.key)">
          <span class="lg-swatch" :style="{ background: s.color }"></span>{{ s.label }}
        </button>
      </div>
    </template>
  </div>
</template>

<script setup>
import { computed, reactive, ref, watch, nextTick, onMounted, onUnmounted } from 'vue'
import { fmtDurationTiered } from '../../utils/format'
import {
  CHAPTER_SERIES, GROUP_SERIES, VIEW_MODES, fmtShortDur,
  uniqueDacTraces, buildReqChartRows, buildStageRelation,
  buildFunnel, buildPassTable, buildVersionTrend,
} from '../../utils/workflowViews'
import {
  groupedBarLayout, durChartLayout, durAxisScaleFromValues, durAxisScale, codeAxisScale,
  barGeom, shortReqLabel, escSvg, connectedPoints,
  GROUP_BAR_W, GROUP_BAR_GAP, GROUP_CHART_H, GROUP_IDLE_MS, GROUP_IDLE_BAND_RATIO,
  DUR_CHART_H, isIdleDuration,
} from '../../utils/durChart'

const props = defineProps({
  curGroup: { type: Object, default: null },
  requirementsIndex: { type: Array, default: () => [] },
  bindings: { type: Object, default: () => ({}) },
  qualityStats: { type: Array, default: () => [] },
  currentVersionName: { type: String, default: '' },
  active: { type: Boolean, default: true },
})

const chartMode = ref('combo')
const chartPhase = ref('prd')
const currentMode = computed(() => VIEW_MODES.find((m) => m.id === chartMode.value) || VIEW_MODES[0])
const selectedPhase = computed(() => CHAPTER_SERIES.find((s) => s.key === chartPhase.value) || CHAPTER_SERIES[0])

const reqBuilt = computed(() => buildReqChartRows(props.curGroup, props.requirementsIndex, props.bindings))
const chartRows = computed(() => reqBuilt.value.rows)
const dacTraces = computed(() => uniqueDacTraces(props.requirementsIndex))
const versionTraces = computed(() => {
  const names = new Set(reqBuilt.value.traceNames)
  return dacTraces.value.filter((t) => names.has(t.req_name))
})
const stageRelation = computed(() => buildStageRelation(chartRows.value, props.qualityStats, reqBuilt.value.traceNames))
const funnel = computed(() => buildFunnel(versionTraces.value))
const passTable = computed(() => buildPassTable(props.qualityStats, versionTraces.value, undefined, props.bindings))
const versionTrend = computed(() => buildVersionTrend(dacTraces.value, props.bindings, props.requirementsIndex, props.currentVersionName))

const onTrend = reactive(Object.fromEntries(CHAPTER_SERIES.map((s) => [s.key, true])))
function toggleTrend(key) { onTrend[key] = !onTrend[key] }
const onGroup = reactive(Object.fromEntries(GROUP_SERIES.map((s) => [s.key, true])))
function toggleGroup(key) { onGroup[key] = !onGroup[key] }

function barPct(n, total) {
  if (!total) return '0%'
  return `${Math.max(n ? 4 : 0, (n / total) * 100)}%`
}
function passW(s, i) {
  const t = s.b[0] + s.b[1] + s.b[2]
  if (!t) return '0%'
  return `${(s.b[i] / t) * 100}%`
}

const durChart = ref(null)
const durScroll = ref(null)
const relChart = ref(null)
const trendChart = ref(null)
const durChartW = ref(320)
const durChartH = computed(() => (chartMode.value === 'combo' ? DUR_CHART_H : GROUP_CHART_H))
const containerW = ref(0)
let durRo = null

function measureChart() {
  const el = durScroll.value
  if (!el) return 0
  const w = Math.floor(el.getBoundingClientRect().width)
  if (w > 0) containerW.value = w
  return w
}

function drawGroupChart() {
  const svg = durChart.value
  if (!svg) return
  const data = chartRows.value
  if (!data.length) { svg.innerHTML = ''; return }
  const avail = containerW.value || measureChart()
  if (avail < 240) return
  const active = GROUP_SERIES.filter((s) => onGroup[s.key])
  const layout = groupedBarLayout(data.length, active.length, avail)
  const { W, H, PAD, step, groupW, plotH, xs } = layout
  durChartW.value = W
  const base = H - PAD.b
  const idleBand = plotH * GROUP_IDLE_BAND_RATIO
  const yIdleTop = PAD.t
  const yIdleBot = PAD.t + idleBand
  const normals = []
  data.forEach((d) => active.forEach((s) => {
    if (s.key !== 'total' && d.skip?.has(s.key)) return
    const v = d[s.key] || 0
    if (v > 0 && v < GROUP_IDLE_MS) normals.push(v)
  }))
  const scale = durAxisScaleFromValues(normals.length ? normals : [1], GROUP_IDLE_MS)
  const yNorm = (v) => yIdleBot + (base - yIdleBot) * (1 - Math.min(v, scale.maxMs) / scale.maxMs)
  const ySkip = base - idleBand * 0.45
  let g = `<defs>
    <pattern id="pat-idle" width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(35)"><line x1="0" y1="0" x2="0" y2="5" stroke="#fff" stroke-width="2.2"/></pattern>
    <pattern id="pat-skip" width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(-35)"><line x1="0" y1="0" x2="0" y2="5" stroke="#94A3B8" stroke-width="1.4"/></pattern>
  </defs>`
  g += `<rect x="${PAD.l}" y="${yIdleTop}" width="${W - PAD.l - PAD.r}" height="${idleBand}" fill="#FEF2F2"/>`
  scale.ticks.forEach((t) => {
    g += `<line x1="${PAD.l}" y1="${yNorm(t.v)}" x2="${W - PAD.r}" y2="${yNorm(t.v)}" stroke="var(--chart-grid)"/>`
    g += `<text x="${PAD.l - 6}" y="${yNorm(t.v) + 3}" font-size="10" fill="var(--t4)" text-anchor="end">${escSvg(t.label)}</text>`
  })
  g += `<line x1="${PAD.l}" y1="${yIdleBot}" x2="${W - PAD.r}" y2="${yIdleBot}" stroke="#FECACA" stroke-dasharray="3 3"/>`
  g += `<text x="${PAD.l - 6}" y="${(yIdleTop + yIdleBot) / 2 + 3}" font-size="10" fill="#DC2626" text-anchor="end">≥24h</text>`
  data.forEach((d, i) => {
    const cx = xs[i]
    const x0 = cx - groupW / 2
    active.forEach((s, k) => {
      const x = x0 + k * (GROUP_BAR_W + GROUP_BAR_GAP)
      const skipped = s.key !== 'total' && d.skip?.has(s.key)
      const raw = d[s.key] || 0
      if (skipped) {
        g += `<rect x="${x}" y="${ySkip}" width="${GROUP_BAR_W}" height="${Math.max(1, base - ySkip)}" rx="1.5" fill="url(#pat-skip)" stroke="${s.color}" stroke-dasharray="2 2"><title>${escSvg(d.name)} · ${escSvg(s.label)}：当前阶段被跳过</title></rect>`
        return
      }
      if (!raw) return
      const idle = raw >= GROUP_IDLE_MS
      const top = idle ? yIdleTop : yNorm(raw)
      const barH = Math.max(idle ? 8 : 1, base - top)
      const tip = `${escSvg(d.name)} · ${escSvg(s.label)}：${idle ? '≥24h ' : ''}${fmtShortDur(raw)}`
      if (idle) {
        g += `<rect x="${x}" y="${top}" width="${GROUP_BAR_W}" height="${barH}" rx="1.5" fill="${s.color}"/>`
        g += `<rect x="${x}" y="${top}" width="${GROUP_BAR_W}" height="${barH}" rx="1.5" fill="url(#pat-idle)" stroke="${s.color}"><title>${tip}</title></rect>`
      } else {
        g += `<rect x="${x}" y="${top}" width="${GROUP_BAR_W}" height="${barH}" rx="1.5" fill="${s.color}" fill-opacity=".92"><title>${tip}</title></rect>`
      }
    })
    const maxChars = Math.max(4, Math.floor(step / 12))
    const label = escSvg(shortReqLabel(d.name, maxChars))
    g += `<text x="${cx}" y="${H - PAD.b + 16}" font-size="10" fill="var(--t3)" text-anchor="middle"><title>${escSvg(d.name)}</title>${label}</text>`
  })
  svg.innerHTML = g
}

function drawComboChart() {
  const svg = durChart.value
  if (!svg) return
  const data = chartRows.value
  if (!data.length) { svg.innerHTML = ''; return }
  const avail = containerW.value || measureChart()
  if (avail < 240) return
  const layout = durChartLayout(data.length, avail)
  const { W, PAD, H, plotH, xs, step } = layout
  durChartW.value = W
  const baseY = H - PAD.b
  const series = selectedPhase.value
  const durValues = data.map((d) => d[series.key])
  const durScale = durAxisScaleFromValues(durValues)
  const yDur = (v) => baseY - (Math.min(v, durScale.maxMs) / durScale.maxMs) * plotH
  const codeScale = codeAxisScale(Math.max(...data.map((d) => d.dac), 1))
  // dac 点定位：跟随所在章节柱顶（无柱章节才按右轴真实值定位），与额度分布图对齐
  const barTopY = new Map()
  data.forEach((d, i) => {
    const v = d[series.key]
    if (v > 0 && !isIdleDuration(v)) barTopY.set(i, barGeom(xs[i], step, baseY, yDur(v)).y)
  })
  const yCode = (v, i) => (barTopY.has(i) ? barTopY.get(i) : baseY - (v / codeScale.max) * plotH)

  let g = ''
  durScale.ticks.forEach((t) => {
    const y = yDur(t.v)
    g += `<line x1="${PAD.l}" y1="${y}" x2="${W - PAD.r}" y2="${y}" stroke="var(--chart-grid)"/>`
    g += `<text x="${PAD.l - 6}" y="${y + 3}" font-size="10" fill="var(--t4)" text-anchor="end">${escSvg(t.label)}</text>`
  })
  codeScale.ticks.forEach((t) => {
    g += `<text x="${W - PAD.r + 6}" y="${yCode(t.v) + 3}" font-size="10" fill="var(--t4)">${escSvg(t.label)}</text>`
  })
  const showEvery = step >= 56 ? 1 : Math.max(1, Math.ceil(56 / step))
  const maxChars = Math.max(4, Math.floor(step / 12))
  data.forEach((d, i) => {
    if (i % showEvery !== 0 && i !== data.length - 1) return
    const label = escSvg(shortReqLabel(d.name, maxChars))
    g += `<text x="${xs[i]}" y="${H - PAD.b + 16}" font-size="10" fill="var(--t3)" text-anchor="middle"><title>${escSvg(d.name)}</title>${label}</text>`
  })
  data.forEach((d, i) => {
    const v = d[series.key]
    if (!(v > 0)) return
    const idle = isIdleDuration(v)
    const { x, y, w, h } = barGeom(xs[i], step, baseY, yDur(v))
    if (h <= 0) return
    const t = fmtDurationTiered(v, { heavy: series.key === 'dev' })
    const tip = idle
      ? `${escSvg(series.label)}：${escSvg(t.text)}（${escSvg(t.title)}）· ${escSvg(d.name)}`
      : `${escSvg(series.label)}：${escSvg(t.title || t.text)} · ${escSvg(d.name)}`
    const op = idle ? 0.2 : 0.85
    const dash = idle ? ' stroke-dasharray="3 2"' : ''
    g += `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="3" fill="${series.color}" fill-opacity="${op}" stroke="${series.color}" stroke-width="1"${dash}><title>${tip}</title></rect>`
  })
  const codePts = connectedPoints(xs, data.map((d) => d.dac))
  if (codePts.length >= 2) {
    const line = codePts.map((p) => `${p.x},${yCode(p.v, p.i)}`).join(' ')
    g += `<polyline points="${line}" fill="none" stroke="#7C3AED" stroke-width="2" stroke-dasharray="5 4" stroke-linejoin="round"/>`
  }
  codePts.forEach((p) => {
    if (!p.v) return
    g += `<circle cx="${p.x}" cy="${yCode(p.v, p.i)}" r="3" fill="#7C3AED"><title>dac 行数：${p.v} · ${escSvg(data[p.i].name)}</title></circle>`
  })
  svg.innerHTML = g
}

function drawDurChart() {
  if (chartMode.value === 'combo') drawComboChart()
  else drawGroupChart()
}

function drawRelChart() {
  const svg = relChart.value
  if (!svg) return
  const stages = stageRelation.value
  const W = 720, H = 280, P = { l: 56, r: 48, t: 28, b: 40 }
  const plotW = W - P.l - P.r, plotH = H - P.t - P.b, base = H - P.b
  const xs = stages.map((_, i) => P.l + (stages.length === 1 ? 0 : i * plotW / (stages.length - 1)))
  const durs = stages.map((s) => s.dur || 0)
  const rnds = stages.map((s) => s.rnd || 0)
  const dScale = durAxisScale(Math.max(...durs, 1))
  const rMax = Math.max(3, ...rnds)
  const yD = (v) => base - (v / dScale.maxMs) * plotH
  const yR = (v) => base - (v / rMax) * plotH
  let g = `<text x="${P.l}" y="14" font-size="11" fill="#2563EB">平均耗时</text><text x="${W - P.r}" y="14" font-size="11" fill="#EA580C" text-anchor="end">平均轮次</text>`
  dScale.ticks.forEach((t) => {
    g += `<line x1="${P.l}" y1="${yD(t.v)}" x2="${W - P.r}" y2="${yD(t.v)}" stroke="var(--chart-grid)"/>`
    g += `<text x="${P.l - 6}" y="${yD(t.v) + 3}" font-size="10" fill="var(--t4)" text-anchor="end">${escSvg(t.label)}</text>`
  })
  for (let i = 0; i <= 4; i++) {
    const v = rMax * i / 4
    const lab = Number.isInteger(v) ? String(v) : v.toFixed(1)
    g += `<text x="${W - P.r + 6}" y="${yR(v) + 3}" font-size="10" fill="#EA580C">${lab}</text>`
  }
  const dLine = stages.map((s, i) => `${xs[i]},${yD(s.dur || 0)}`).join(' ')
  const rLine = stages.map((s, i) => `${xs[i]},${yR(s.rnd || 0)}`).join(' ')
  g += `<polyline points="${dLine}" fill="none" stroke="#2563EB" stroke-width="2.2" stroke-linejoin="round"/>`
  g += `<polyline points="${rLine}" fill="none" stroke="#EA580C" stroke-width="2.2" stroke-dasharray="5 4" stroke-linejoin="round"/>`
  stages.forEach((s, i) => {
    const yd = yD(s.dur || 0), yr = yR(s.rnd || 0)
    g += `<circle cx="${xs[i]}" cy="${yd}" r="4.5" fill="#2563EB"><title>${escSvg(s.label)} 平均耗时 ${fmtShortDur(s.dur)}</title></circle>`
    g += `<circle cx="${xs[i]}" cy="${yr}" r="4.5" fill="#fff" stroke="#EA580C" stroke-width="2"><title>${escSvg(s.label)} 平均轮次 ${s.rnd == null ? '—' : s.rnd}</title></circle>`
    g += `<text x="${xs[i]}" y="${yd - 10}" font-size="10" fill="#2563EB" text-anchor="middle">${fmtShortDur(s.dur)}</text>`
    g += `<text x="${xs[i]}" y="${yr + 16}" font-size="10" fill="#EA580C" text-anchor="middle">${s.rnd == null ? '—' : s.rnd}</text>`
    g += `<text x="${xs[i]}" y="${H - 14}" font-size="12" fill="var(--t2)" text-anchor="middle">${escSvg(s.label)}</text>`
  })
  svg.innerHTML = g
}

function drawTrendChart() {
  const svg = trendChart.value
  if (!svg) return
  const data = versionTrend.value
  const active = CHAPTER_SERIES.filter((s) => onTrend[s.key])
  const W = 720, H = 280, P = { l: 52, r: 16, t: 20, b: 48 }
  const plotW = W - P.l - P.r, plotH = H - P.t - P.b, base = H - P.b
  const xs = data.map((_, i) => P.l + (data.length === 1 ? 0 : i * plotW / (data.length - 1)))
  const vals = data.flatMap((d) => active.map((s) => d[s.key]).filter((v) => v > 0 && !isIdleDuration(v)))
  const scale = durAxisScaleFromValues(vals.length ? vals : [1])
  const y = (v) => base - (Math.min(v, scale.maxMs) / scale.maxMs) * plotH
  let g = ''
  scale.ticks.forEach((t) => {
    g += `<line x1="${P.l}" y1="${y(t.v)}" x2="${W - P.r}" y2="${y(t.v)}" stroke="var(--chart-grid)"/>`
    g += `<text x="${P.l - 6}" y="${y(t.v) + 3}" font-size="10" fill="var(--t4)" text-anchor="end">${escSvg(t.label)}</text>`
  })
  data.forEach((d, i) => {
    if (!d.cur) return
    g += `<line x1="${xs[i]}" y1="${P.t}" x2="${xs[i]}" y2="${base}" stroke="#FDBA74" stroke-dasharray="4 4"/>`
  })
  active.forEach((s) => {
    const pts = data.map((d, i) => (d[s.key] > 0 && !isIdleDuration(d[s.key]) ? [xs[i], y(d[s.key])] : null))
    for (let i = 1; i < pts.length; i++) {
      if (pts[i - 1] && pts[i]) g += `<line x1="${pts[i - 1][0]}" y1="${pts[i - 1][1]}" x2="${pts[i][0]}" y2="${pts[i][1]}" stroke="${s.color}" stroke-width="2.1"/>`
    }
    pts.forEach((p, i) => {
      if (!p) return
      g += `<circle cx="${p[0]}" cy="${p[1]}" r="${data[i].cur ? 5 : 4}" fill="${s.color}"><title>${escSvg(data[i].w)} ${escSvg(s.label)} ${fmtShortDur(data[i][s.key])} n=${data[i].n}</title></circle>`
    })
  })
  data.forEach((d, i) => {
    g += `<text x="${xs[i]}" y="${H - 20}" font-size="11" fill="${d.cur ? 'var(--t1)' : 'var(--t2)'}" font-weight="${d.cur ? 700 : 400}" text-anchor="middle">${escSvg(d.w)}${d.cur ? '(本)' : ''}</text>`
    g += `<text x="${xs[i]}" y="${H - 6}" font-size="10" fill="var(--t4)" text-anchor="middle">n=${d.n}</text>`
  })
  svg.innerHTML = g
}

function attachDurRo() {
  durRo?.disconnect()
  durRo = null
  const el = durScroll.value
  if (!el || typeof ResizeObserver === 'undefined') return
  durRo = new ResizeObserver((entries) => {
    const w = Math.floor(entries[0].contentRect.width)
    if (w && w !== containerW.value) containerW.value = w
  })
  durRo.observe(el)
}

function redraw() {
  if (chartMode.value === 'req' || chartMode.value === 'combo') nextTick(() => { attachDurRo(); measureChart(); drawDurChart() })
  else if (chartMode.value === 'rel') nextTick(drawRelChart)
  else if (chartMode.value === 'trend') nextTick(drawTrendChart)
}

watch([chartRows, containerW, onGroup, chartPhase], () => {
  if (chartMode.value === 'req' || chartMode.value === 'combo') nextTick(drawDurChart)
}, { deep: true })
watch([stageRelation, chartMode], () => { if (chartMode.value === 'rel') nextTick(drawRelChart) })
watch([versionTrend, chartMode, onTrend], () => { if (chartMode.value === 'trend') nextTick(drawTrendChart) }, { deep: true })
watch(() => props.active, (on) => { if (on) redraw() })
watch(chartMode, () => redraw())

onMounted(() => {
  redraw()
})
onUnmounted(() => { durRo?.disconnect() })
</script>

<style scoped>
.card-block {
  background: var(--card);
  border: 1px solid var(--card-line);
  border-radius: 14px;
  padding: 18px 22px;
  margin-bottom: 16px;
  box-shadow: var(--card-shadow);
}
.card-title {
  font-size: 14px;
  font-weight: 700;
  color: var(--t1);
  margin-bottom: 14px;
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}
.card-title-sub { font-size: 12px; color: var(--t4); font-weight: 500; }
.view-select {
  margin-left: auto;
  font-size: 12px;
  padding: 4px 8px;
  border: 1px solid var(--line);
  border-radius: 6px;
  background: var(--sub-bg);
  color: var(--t2);
}
.hint {
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 14px;
  height: 14px;
  border-radius: 50%;
  background: var(--chip-bg, #F1F5F9);
  color: var(--t3);
  font-size: 10px;
  font-weight: 700;
  cursor: help;
  flex-shrink: 0;
}
.hint:hover { background: var(--brand-bg, #FFF7ED); color: var(--brand-strong, #EA580C); }
.hint .tip {
  position: absolute;
  bottom: calc(100% + 6px);
  left: 50%;
  transform: translateX(-50%);
  background: #0F172A;
  color: #fff;
  font-size: 11px;
  font-weight: 400;
  line-height: 1.5;
  padding: 8px 10px;
  border-radius: 7px;
  width: 300px;
  text-align: left;
  white-space: normal;
  box-shadow: 0 4px 14px rgba(0,0,0,.2);
  opacity: 0;
  pointer-events: none;
  transition: opacity .12s;
  z-index: 20;
}
.hint .tip::after {
  content: "";
  position: absolute;
  top: 100%;
  left: 50%;
  transform: translateX(-50%);
  border: 6px solid transparent;
  border-top-color: #0F172A;
}
.hint:hover .tip { opacity: 1; }
.phase-pills { display: flex; flex-wrap: wrap; gap: 6px; margin: -4px 0 10px; }
.phase-pill {
  font-size: 12px;
  padding: 4px 10px;
  border: 1px solid var(--line);
  border-radius: 6px;
  background: var(--sub-bg);
  color: var(--t2);
  cursor: pointer;
}
.phase-pill.on {
  border-color: var(--pill-color, var(--brand));
  color: var(--t1);
  font-weight: 700;
  box-shadow: inset 0 -2px 0 var(--pill-color, var(--brand));
}
.legend-row { display: flex; flex-wrap: wrap; gap: 14px; align-items: center; margin-top: 12px; padding-top: 12px; border-top: 1px solid var(--line-soft); }
.lg-item { display: inline-flex; align-items: center; gap: 6px; font-size: 11px; color: var(--t3); }
.lg-swatch { width: 14px; height: 3px; border-radius: 2px; display: inline-block; }
.lg-swatch.lg-bar { width: 10px; height: 10px; border-radius: 2px; }
.lg-swatch.lg-dash {
  width: 16px;
  height: 0;
  border-top: 2px dashed #7C3AED;
  background: none;
  border-radius: 0;
}
.lg-swatch.lg-dash-orange {
  width: 16px;
  height: 0;
  border-top: 2px dashed #EA580C;
  background: none;
  border-radius: 0;
}
.lg-toggle {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: var(--t2);
  border: 1px solid var(--line);
  background: var(--sub-bg);
  padding: 4px 10px;
  border-radius: 6px;
  cursor: pointer;
}
.lg-toggle.off { opacity: .4; text-decoration: line-through; }
.dur-scroll { overflow-x: auto; overflow-y: hidden; }
.dur-scroll::-webkit-scrollbar { height: 8px; }
.dur-scroll::-webkit-scrollbar-thumb { background: var(--line); border-radius: 4px; }
.dur-scroll::-webkit-scrollbar-track { background: var(--line-soft); }

.funnel { display: flex; flex-direction: column; gap: 10px; padding: 4px 0 8px; }
.fn-row { display: grid; grid-template-columns: 88px 1fr 168px; gap: 10px; align-items: center; }
.fn-label { font-size: 12px; color: var(--t2); text-align: right; }
.fn-track { height: 22px; background: var(--sub-bg); border-radius: 6px; position: relative; overflow: hidden; }
.fn-reach { height: 100%; background: #93C5FD; border-radius: 6px; }
.fn-done { height: 100%; background: #2563EB; border-radius: 6px; position: absolute; left: 0; top: 0; }
.fn-meta { font-size: 11px; color: var(--t3); white-space: nowrap; }

.pass { display: flex; flex-direction: column; gap: 12px; padding: 6px 0; }
.pass-row { display: grid; grid-template-columns: 92px 1fr 150px; gap: 10px; align-items: center; }
.pass-bar { display: flex; height: 22px; border-radius: 6px; overflow: hidden; background: var(--sub-bg); }
.pass-bar span { height: 100%; display: block; }
.pass-meta { font-size: 11px; color: var(--t3); }

@media (max-width: 800px) {
  .fn-row, .pass-row { grid-template-columns: 72px 1fr; }
  .fn-meta, .pass-row .pass-meta:last-child { grid-column: 2; }
}
</style>
