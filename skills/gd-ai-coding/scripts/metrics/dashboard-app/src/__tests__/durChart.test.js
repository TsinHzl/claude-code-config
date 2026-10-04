import { describe, it, expect } from 'vitest'
import {
  durChartLayout, DUR_CHART_MIN_STEP, DUR_CHART_PAD,
  niceCeil, durAxisScale, durAxisScaleFromValues, connectedPoints, shortReqLabel, barGeom,
  groupedBarLayout, GROUP_MIN_STEP, GROUP_IDLE_MS,
} from '../utils/durChart'

describe('durChartLayout', () => {
  it('需求少时铺满容器宽度', () => {
    const { W, step, xs } = durChartLayout(8, 1200)
    expect(W).toBe(1200)
    expect(step).toBeGreaterThan(DUR_CHART_MIN_STEP)
    expect(xs[0]).toBe(DUR_CHART_PAD.l)
    expect(xs[7]).toBeCloseTo(1200 - DUR_CHART_PAD.r, 5)
  })

  it('过密时按最小步长撑开，宽度超过容器以便横向滚动', () => {
    const { W, step } = durChartLayout(40, 800)
    expect(step).toBe(DUR_CHART_MIN_STEP)
    expect(W).toBeGreaterThan(800)
  })
})

describe('durAxisScale', () => {
  it('毫秒换成分钟/小时刻度，不再露出百万级原值', () => {
    const scale = durAxisScale(15_742_533) // ≈ 4.4h
    expect(scale.maxMs).toBeGreaterThanOrEqual(15_742_533)
    expect(scale.ticks[0].label).toMatch(/0/)
    expect(scale.ticks.every((t) => !/^\d{7,}$/.test(t.label))).toBe(true)
    expect(scale.ticks.at(-1).label).toMatch(/h|天|m/)
  })
})

describe('niceCeil', () => {
  it('向上取整到 1/2/2.5/5/10', () => {
    expect(niceCeil(4.37)).toBe(5)
    expect(niceCeil(1.2)).toBe(2)
  })
})

describe('durAxisScaleFromValues', () => {
  it('闲置超长点不拉高纵轴', () => {
    const hour = 3_600_000
    const day = 86_400_000
    const scale = durAxisScaleFromValues([0.5 * hour, 2 * hour, 8 * day])
    expect(scale.maxMs).toBeLessThan(2 * day)
    expect(scale.maxMs).toBeGreaterThanOrEqual(2 * hour)
  })
})

describe('connectedPoints', () => {
  it('跳过 0，其余连成一条', () => {
    const pts = connectedPoints([0, 10, 20, 30], [5, 0, 8, 9])
    expect(pts.map((p) => p.v)).toEqual([5, 8, 9])
  })
})

describe('shortReqLabel', () => {
  it('超长截断', () => {
    expect(shortReqLabel('abcdefghijklmnop', 8)).toBe('abcdefgh…')
    expect(shortReqLabel('short')).toBe('short')
  })
})

describe('groupedBarLayout', () => {
  it('过密时按组宽撑开以便横向滚动', () => {
    const { W, step, xs } = groupedBarLayout(20, 5, 400)
    expect(step).toBeGreaterThanOrEqual(GROUP_MIN_STEP)
    expect(W).toBeGreaterThan(400)
    expect(xs).toHaveLength(20)
  })
})

describe('durAxisScaleFromValues idleMs', () => {
  it('可指定 24h 墙，超长点不拉轴', () => {
    const hour = 3_600_000
    const scale = durAxisScaleFromValues([2 * hour, 30 * hour], GROUP_IDLE_MS)
    expect(scale.maxMs).toBeLessThan(GROUP_IDLE_MS)
    expect(scale.maxMs).toBeGreaterThanOrEqual(2 * hour)
  })
})

describe('barGeom', () => {
  it('以中心点对称，高度为基线到顶', () => {
    const g = barGeom(100, 96, 200, 80)
    expect(g.x + g.w / 2).toBeCloseTo(100)
    expect(g.y).toBe(80)
    expect(g.h).toBe(120)
    expect(g.w).toBeLessThanOrEqual(32)
  })
})
