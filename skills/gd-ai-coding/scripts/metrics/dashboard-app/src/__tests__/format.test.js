import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { fmtRelTime, fmtDurationTiered } from '../utils/format'

describe('fmtRelTime', () => {
  const now = new Date('2026-08-12T10:00:00.000Z').getTime()

  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(now)
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('12～23 小时前应显示为「Xh前」，而非绝对时间（回归：曾因 diffHour<12 缺口落入 fmtTs）', () => {
    expect(fmtRelTime(now - 20 * 60 * 60 * 1000)).toBe('20h前')
  })

  it('不足 1 小时显示为「Xm前」', () => {
    expect(fmtRelTime(now - 41 * 60 * 1000)).toBe('41m前')
  })

  it('满 24 小时后显示为「N天前」', () => {
    expect(fmtRelTime(now - 25 * 60 * 60 * 1000)).toBe('1天前')
  })

  it('超过 7 天显示为绝对时间', () => {
    const ts = now - 9 * 24 * 60 * 60 * 1000
    expect(fmtRelTime(ts)).not.toMatch(/前$/)
  })
})

describe('fmtDurationTiered（三段分级时长）', () => {
  const H = 3600000, D = 86400000

  it('轻阶段：<2h 正常档，显示精确时间', () => {
    const r = fmtDurationTiered(30 * 60000)
    expect(r.tier).toBe('normal')
    expect(r.text).toBe('30m')
  })

  it('轻阶段：2h~24h 偏长档(warn)，仍显示精确时间', () => {
    const r = fmtDurationTiered(15 * H)
    expect(r.tier).toBe('warn')
    expect(r.text).toBe('15h')
  })

  it('轻阶段：>24h 超长档(idle)，文案转「数天未推进」，tooltip 保留精确值', () => {
    const r = fmtDurationTiered(73 * H)
    expect(r.tier).toBe('idle')
    expect(r.text).toBe('数天未推进')
    expect(r.title).toBe('3天1h')
  })

  it('重阶段：功能开发 2天内正常、2~7天偏长、>7天超长', () => {
    expect(fmtDurationTiered(1.5 * D, { heavy: true }).tier).toBe('normal')
    expect(fmtDurationTiered(3 * D, { heavy: true }).tier).toBe('warn')
    expect(fmtDurationTiered(8 * D, { heavy: true }).tier).toBe('idle')
  })

  it('同一时长在两套阈值下档位不同（重阶段放宽）', () => {
    // 3天：轻阶段=超长；重阶段=偏长
    expect(fmtDurationTiered(3 * D).tier).toBe('idle')
    expect(fmtDurationTiered(3 * D, { heavy: true }).tier).toBe('warn')
  })

  it('0/非法输入返回占位', () => {
    expect(fmtDurationTiered(0).text).toBe('—')
    expect(fmtDurationTiered(null).tier).toBe('normal')
  })
})
