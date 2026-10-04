import { describe, it, expect } from 'vitest'
import { phaseDurations, phaseTotalDuration, chapterDurations, chapterTotalDuration, skippedPhaseSet } from '../utils/phase'

describe('phaseDurations', () => {
  it('格子耗时=到达本格，不是停留到下一格', () => {
    const phases = [
      { phase: 'prd-parsed', ts: 120000 },
      { phase: 'init', ts: 0 },
      { phase: 'prd-parsing', ts: 60000 },
    ]
    const d = phaseDurations(phases)
    expect(d.init).toBeUndefined()
    expect(d['prd-parsing']).toBe(60000)
    expect(d['prd-parsed']).toBe(60000)
  })

  it('缺方案通过：规划格只算到 feature-planned，不吞开发', () => {
    const d = phaseDurations([
      { phase: 'prd-speced', ts: 0 },
      { phase: 'feature-planned', ts: 13 * 60000 },
      { phase: 'feature-loop', ts: 14 * 60000 },
      { phase: 'feature-done', ts: 8 * 86400000 },
      { phase: 'done', ts: 8 * 86400000 + 27000 },
    ])
    expect(d['feature-planned']).toBe(13 * 60000)
    expect(d['feature-done']).toBe(8 * 86400000 - 14 * 60000)
    expect(d.done).toBe(27000)
  })

  it('乱序 / 含 null / 未知 phase 均容错', () => {
    const d = phaseDurations([
      { phase: 'init', ts: 0 },
      { phase: 'unknown', ts: 5 },
      null,
      { phase: 'prd-parsing', ts: 1000 },
    ])
    expect(d.init).toBeUndefined()
    expect(d['prd-parsing']).toBe(1000)
  })

  it('空数组 / 非法输入返回空对象', () => {
    expect(phaseDurations([])).toEqual({})
    expect(phaseDurations(null)).toEqual({})
    expect(phaseDurations(undefined)).toEqual({})
  })
})

describe('phaseTotalDuration', () => {
  it('汇总到达各格的耗时', () => {
    const phases = [
      { phase: 'init', ts: 0 },
      { phase: 'prd-parsing', ts: 60000 },
      { phase: 'prd-parsed', ts: 120000 },
    ]
    expect(phaseTotalDuration(phases)).toBe(120000)
  })

  it('无完成阶段返回 0', () => {
    expect(phaseTotalDuration([{ phase: 'init', ts: 0 }])).toBe(0)
  })
})

describe('skippedPhaseSet', () => {
  it('prd_parse 映射到澄清前三格；未声明的 stage 忽略', () => {
    expect([...skippedPhaseSet(['prd_parse', 'mastergo'])].sort()).toEqual(
      ['prd-clarified', 'prd-parsed', 'prd-parsing'])
  })
})

describe('chapterDurations（四大业务章节）', () => {
  // 完整走完的状态机时间线（ms）：
  // init@0 → parsing@8h → parsed@8h+10m → clarified@8h+40m → specing@9h → speced@10h → approved@11h → planned@12h → feature-done@20h → done@21h
  const H = 3600000, M = 60000
  const full = [
    { phase: 'init', ts: 0 },
    { phase: 'prd-parsing', ts: 8 * H },
    { phase: 'prd-parsed', ts: 8 * H + 10 * M },
    { phase: 'prd-clarified', ts: 8 * H + 40 * M },
    { phase: 'prd-specing', ts: 9 * H },
    { phase: 'prd-speced', ts: 10 * H },
    { phase: 'proposal-approved', ts: 11 * H },
    { phase: 'feature-planned', ts: 12 * H },
    { phase: 'feature-done', ts: 20 * H },
    { phase: 'done', ts: 21 * H },
  ]

  it('四章节按边界 ts 差计算,不含启动/澄清间等待', () => {
    const d = chapterDurations(full)
    expect(d.prd).toBe(40 * M)        // parsing → clarified
    expect(d.spec).toBe(2 * H)        // specing → approved
    expect(d.plan).toBe(1 * H)        // approved → planned
    expect(d.dev).toBe(9 * H)         // planned → done
  })

  it('进行中章节(缺边界 ts)不计入', () => {
    const d = chapterDurations(full.slice(0, 7)) // 只到 proposal-approved
    expect(d.prd).toBeDefined()
    expect(d.spec).toBeDefined()
    expect(d.plan).toBeUndefined()    // 缺 feature-planned
    expect(d.dev).toBeUndefined()
  })

  it('回滚重走取最后一次出现的 ts', () => {
    const rolled = [...full, { phase: 'prd-parsing', ts: 30 * H }, { phase: 'prd-clarified', ts: 31 * H }]
    const d = chapterDurations(rolled)
    expect(d.prd).toBe(1 * H)         // 用最后一次 parsing→clarified
  })

  it('chapterTotalDuration = 四章节之和(不含等待)', () => {
    expect(chapterTotalDuration(full)).toBe(40 * M + 2 * H + 1 * H + 9 * H)
  })

  it('非法输入返回空对象 / 0', () => {
    expect(chapterDurations(null)).toEqual({})
    expect(chapterTotalDuration(null)).toBe(0)
  })
})
