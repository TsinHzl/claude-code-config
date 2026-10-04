export function fmtNum(n) {
  return Number(n).toLocaleString('en-US')
}

export function fmtLines(n) {
  return n >= 1000 ? (n / 1000).toFixed(1) + 'k' : String(n)
}

export function fmtTs(ts) {
  if (!ts) return ''
  const d = new Date(ts)
  return d.toLocaleString('zh-CN', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })
}

export function fmtRelTime(ts) {
  if (!ts) return ''
  const diffSec = Math.floor((Date.now() - ts) / 1000)
  if (diffSec < 0) return fmtTs(ts)
  if (diffSec < 60) return `${diffSec}s前`
  const diffMin = Math.floor(diffSec / 60)
  if (diffMin < 60) return `${diffMin}m前`
  const diffHour = Math.floor(diffMin / 60)
  if (diffHour < 24) return `${diffHour}h前`
  const diffDay = Math.floor(diffHour / 24)
  if (diffDay >= 1 && diffDay < 8) return `${diffDay}天前`
  return fmtTs(ts)
}

export function initials(name) {
  const s = (name || '?').replace(/[^A-Za-z一-龥]/g, '')
  return (s.slice(-2) || '??').toUpperCase()
}

/**
 * 三段分级时长展示（墙钟耗时含等审批/搁置，需按档位区分样式）：
 *   normal — 阈值内，正常显示精确时间
 *   warn   — 偏长，仍显示精确时间但染黄提醒
 *   idle   — 超长，不显示数字，中性文案「数天未推进」（不判责）
 * 阈值分两套：轻阶段/人工门 2h/24h；重阶段（功能开发等多 feature 循环）2天/7天。
 * 返回 { text, tier, title }：text 用于展示，title 供 tooltip 放精确时长。
 */
export function fmtDurationTiered(ms, { heavy = false } = {}) {
  if (!ms || ms <= 0) return { text: '—', tier: 'normal', title: '' }
  const H = 3600000, D = 86400000
  const warnAt = heavy ? 2 * D : 2 * H
  const idleAt = heavy ? 7 * D : 24 * H
  const exact = fmtDurationExact(ms)
  if (ms >= idleAt) return { text: '数天未推进', tier: 'idle', title: exact }
  if (ms >= warnAt) return { text: exact, tier: 'warn', title: exact }
  return { text: exact, tier: 'normal', title: exact }
}

/** 精确时长：45s / 3m20s / 3h20m / 2天3h */
export function fmtDurationExact(ms) {
  const s = Math.round(ms / 1000)
  if (s < 60) return `${s}s`
  const m = Math.floor(s / 60), ss = s % 60
  if (m < 60) return ss ? `${m}m${ss}s` : `${m}m`
  const h = Math.floor(m / 60), mm = m % 60
  if (h < 24) return mm ? `${h}h${mm}m` : `${h}h`
  const d = Math.floor(h / 24), hh = h % 24
  return hh ? `${d}天${hh}h` : `${d}天`
}
