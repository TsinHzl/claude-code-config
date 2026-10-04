/** 概览折线图布局：少需求铺满容器，过密时按最小步长撑开并横向滚动。 */

export const DUR_CHART_H = 240
export const DUR_CHART_PAD = { l: 48, r: 52, t: 16, b: 36 }
export const DUR_CHART_MIN_STEP = 96
/** 超过这个墙钟时长的点当闲置：不拉高纵轴，画在轴顶并标出来。 */
export const DUR_CHART_IDLE_MS = 2 * 86_400_000

/**
 * @param {number} n 需求点数
 * @param {number} containerW 滚动容器可见宽度
 * @returns {{ W: number, step: number, PAD: typeof DUR_CHART_PAD, H: number, plotW: number, plotH: number, xs: number[] }}
 */
export function durChartLayout(n, containerW) {
  const PAD = DUR_CHART_PAD
  const H = DUR_CHART_H
  const avail = Math.max(Math.floor(containerW) || 0, 320)
  const plotH = H - PAD.t - PAD.b
  const plotAvail = Math.max(avail - PAD.l - PAD.r, 80)
  if (n <= 1) {
    return { W: avail, step: plotAvail, PAD, H, plotW: plotAvail, plotH, xs: n === 1 ? [PAD.l] : [] }
  }
  const fillStep = plotAvail / (n - 1)
  const step = fillStep >= DUR_CHART_MIN_STEP ? fillStep : DUR_CHART_MIN_STEP
  const plotW = (n - 1) * step
  const W = PAD.l + PAD.r + plotW
  const xs = Array.from({ length: n }, (_, i) => PAD.l + i * step)
  return { W, step, PAD, H, plotW, plotH, xs }
}

export function niceCeil(v) {
  if (!(v > 0)) return 1
  const pow = 10 ** Math.floor(Math.log10(v))
  const n = v / pow
  const nice = n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10
  return nice * pow
}

const MS_M = 60_000
const MS_H = 3_600_000
const MS_D = 86_400_000

/** 左轴：把毫秒换成 m/h/天，并向上取整到好看的刻度。 */
export function durAxisScale(maxMs) {
  let unit = MS_M
  let suffix = 'm'
  if (maxMs >= MS_D) { unit = MS_D; suffix = '天' }
  else if (maxMs >= MS_H) { unit = MS_H; suffix = 'h' }
  const nice = niceCeil(Math.max(maxMs, 1) / unit)
  const maxNiceMs = nice * unit
  const ticks = 4
  const out = []
  for (let i = 0; i <= ticks; i++) {
    const u = nice * i / ticks
    const label = Number.isInteger(u) ? `${u}${suffix}` : `${parseFloat(u.toFixed(1))}${suffix}`
    out.push({ v: (maxNiceMs * i) / ticks, label })
  }
  return { maxMs: maxNiceMs, ticks: out }
}

export function codeAxisScale(maxCode) {
  const nice = niceCeil(Math.max(maxCode, 1))
  const ticks = 4
  const out = []
  for (let i = 0; i <= ticks; i++) {
    out.push({ v: Math.round((nice * i) / ticks), label: String(Math.round((nice * i) / ticks)) })
  }
  return { max: nice, ticks: out }
}

/** 用「非闲置」最大值定轴，避免一两个搁置几天的点把其余耗时压成一条底边。 */
export function durAxisScaleFromValues(valuesMs, idleMs = DUR_CHART_IDLE_MS) {
  const positive = (valuesMs || []).filter((v) => v > 0)
  const visible = positive.filter((v) => v < idleMs)
  const src = visible.length ? Math.max(...visible) : Math.max(...positive, 1)
  return durAxisScale(src)
}

export function isIdleDuration(ms, idleMs = DUR_CHART_IDLE_MS) {
  return ms >= idleMs
}

export const GROUP_BAR_W = 8
export const GROUP_BAR_GAP = 2
export const GROUP_MIN_STEP = 78
export const GROUP_CHART_H = 280
export const GROUP_CHART_PAD = { l: 58, r: 16, t: 18, b: 42 }
/** 分组柱：≥24h 仍从 0 画到顶，最上档加宽表示超长，不拉高下面的线性轴。 */
export const GROUP_IDLE_MS = 24 * 3_600_000
/** 最上「≥24h」档占绘图区高度的比例，略宽于普通刻度间隔。 */
export const GROUP_IDLE_BAND_RATIO = 0.22

/**
 * 分组柱布局：每个需求一组细柱。少需求铺满，过密按组宽撑开并横向滚动。
 * xs 是每组中心点。
 */
export function groupedBarLayout(n, barCount, containerW) {
  const PAD = GROUP_CHART_PAD
  const H = GROUP_CHART_H
  const bars = Math.max(barCount, 1)
  const groupW = bars * GROUP_BAR_W + (bars - 1) * GROUP_BAR_GAP
  const minStep = Math.max(GROUP_MIN_STEP, groupW + 22)
  const avail = Math.max(Math.floor(containerW) || 0, 320)
  const plotH = H - PAD.t - PAD.b
  const plotAvail = Math.max(avail - PAD.l - PAD.r, 80)
  if (n <= 0) return { W: avail, H, PAD, step: plotAvail, groupW, plotH, xs: [] }
  const fillStep = plotAvail / n
  const step = Math.max(minStep, fillStep)
  const plotW = n * step
  const W = Math.max(avail, PAD.l + PAD.r + plotW)
  const xs = Array.from({ length: n }, (_, i) => PAD.l + i * step + step / 2)
  return { W, H, PAD, step, groupW, plotH, xs }
}

/** 未完成章节（0）不占点，有值的点连成一条线（中间缺章节就跨过去，避免短短续续）。 */
export function connectedPoints(xs, values) {
  const pts = []
  for (let i = 0; i < xs.length; i++) {
    if (values[i] > 0) pts.push({ x: xs[i], v: values[i], i })
  }
  return pts
}

/** 柱形几何：以横轴点为中心，宽度随步长但封顶，避免铺满整格。 */
export function barGeom(cx, step, baseY, topY) {
  const w = Math.max(8, Math.min(32, step * 0.42))
  const y = Math.min(topY, baseY)
  return { x: cx - w / 2, y, w, h: Math.max(0, baseY - y) }
}

export function shortReqLabel(name, max = 8) {
  const s = String(name || '')
  return s.length <= max ? s : `${s.slice(0, max)}…`
}

export function escSvg(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}
