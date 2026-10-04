import { describe, it, expect } from 'vitest'
import {
  lastTraceTs, uniqueDacTraces, median, mean, fmtShortDur,
  buildFunnel, buildSkipContrast, buildPassTable, buildStageRelation,
  buildReqChartRows, buildVersionTrend, versionOfTrace,
} from '../utils/workflowViews'

const H = 3_600_000
function ph(list) {
  return list.map(([phase, ts]) => ({ phase, ts }))
}

describe('uniqueDacTraces / lastTraceTs', () => {
  it('只收带 TRACE 阶段的需求，同名去重，ts 后写覆盖', () => {
    const idx = [
      { req_name: 'a', phases: ph([['prd-parsing', 1], ['prd-clarified', 2]]) },
      { req_name: 'a', phases: ph([['prd-parsing', 9]]) },
      { req_name: 'b', phases: [{ phase: 'waiting-tech', ts: 1 }] },
      { req_name: 'c', phases: ph([['init', 0], ['prd-parsing', 10], ['prd-parsing', 20]]) },
    ]
    expect(uniqueDacTraces(idx).map((r) => r.req_name)).toEqual(['a', 'c'])
    expect(lastTraceTs(idx[3].phases)['prd-parsing']).toBe(20)
  })
})

describe('median / mean / fmtShortDur', () => {
  it('偶数取中位均值，空为 null', () => {
    expect(median([1, 3, 2])).toBe(2)
    expect(median([1, 3])).toBe(2)
    expect(median([])).toBeNull()
    expect(mean([2, 4])).toBe(3)
    expect(fmtShortDur(3 * 60_000)).toBe('3m')
    expect(fmtShortDur(2.4 * H)).toBe('2.4h')
  })
})

describe('buildFunnel', () => {
  it('到达/完成按阶段打点计数，中位耗时只用封闭章节', () => {
    const traces = [
      { req_name: 'x', phases: ph([['prd-parsing', 0], ['prd-clarified', H], ['prd-specing', 2 * H], ['proposal-approved', 3 * H], ['feature-planned', 4 * H], ['feature-done', 5 * H], ['done', 6 * H]]) },
      { req_name: 'y', phases: ph([['prd-parsing', 0], ['prd-clarified', 2 * H]]) },
    ]
    const f = buildFunnel(traces)
    expect(f.total).toBe(2)
    const by = Object.fromEntries(f.steps.map((s) => [s.key, s]))
    expect(by.enter.reach).toBe(2)
    expect(by.prd.reach).toBe(2)
    expect(by.prd.done).toBe(2)
    expect(by.prd.med).toBe(1.5 * H)
    expect(by.spec.reach).toBe(1)
    expect(by.spec.done).toBe(1)
    expect(by.done.done).toBe(1)
  })
})

describe('buildSkipContrast', () => {
  it('无 proposal-approved 但有 feature-planned 算跳过侧', () => {
    const skip = { req_name: 's', phases: ph([['feature-planned', 0], ['done', 2 * H]]) }
    const thru = { req_name: 't', phases: ph([['proposal-approved', 0], ['feature-planned', H], ['done', 4 * H]]) }
    const qs = [
      { req_name: 's', codegen_feats_total: 1, codegen_check_times: 2, cr_feats_total: 0, cr_check_times: 0 },
      { req_name: 't', codegen_feats_total: 1, codegen_check_times: 4, cr_feats_total: 1, cr_check_times: 2 },
    ]
    const c = buildSkipContrast([skip, thru], qs)
    expect(c.skipN).toBe(1)
    expect(c.thruN).toBe(1)
    expect(c.metrics[0].skip.v).toBe(2)
    expect(c.metrics[0].thru.v).toBe(4)
    expect(c.metrics[2].skip.v).toBe(2 * H)
    expect(c.metrics[2].thru.v).toBe(3 * H)
  })
})

describe('buildPassTable', () => {
  it('0 轮当 1，代码检查按 feat 均次分桶', () => {
    const qs = [
      { req_name: 'a', clarify_rounds: 0, proposal_rounds: 2, feature_plan_rounds: 3, codegen_feats_total: 1, codegen_check_times: 2, cr_feats_total: 1, cr_check_times: 2 },
      { req_name: 'b', clarify_rounds: 1, proposal_rounds: 1, feature_plan_rounds: 1, codegen_feats_total: 0, codegen_check_times: 0, cr_feats_total: 0, cr_check_times: 0 },
    ]
    const table = buildPassTable(qs, [])
    expect(table[0].b).toEqual([2, 0, 0])
    expect(table[1].b).toEqual([1, 1, 0])
    expect(table[2].b).toEqual([1, 0, 1])
    expect(table[3].n).toBe(1)
    expect(table[3].b).toEqual([0, 1, 0])
  })

  it('当前版本无质量行的需求按 1 轮计入用户门，机器门仍只计有 feat 的', () => {
    const traces = [
      { req_name: 'a', phases: [] },
      { req_name: 'b', phases: [] },
    ]
    const qs = [
      { req_name: 'a', clarify_rounds: 2, proposal_rounds: 1, feature_plan_rounds: 1, codegen_feats_total: 1, codegen_check_times: 1, cr_feats_total: 0, cr_check_times: 0 },
    ]
    const table = buildPassTable(qs, traces)
    expect(table[0].n).toBe(2)
    expect(table[0].b).toEqual([1, 1, 0])
    expect(table[3].n).toBe(1)
  })

  it('质量事件记在 DDP 名上时通过 aliasMap 对上 TRACE', () => {
    const traces = [{ req_name: 'TRACE-1', phases: [] }]
    const qs = [{ req_name: 'DDP-1', clarify_rounds: 3, proposal_rounds: 1, feature_plan_rounds: 1, codegen_feats_total: 0, codegen_check_times: 0, cr_feats_total: 0, cr_check_times: 0 }]
    const table = buildPassTable(qs, traces, undefined, { 'TRACE-1': 'DDP-1' })
    expect(table[0].n).toBe(1)
    expect(table[0].b).toEqual([0, 0, 1])
  })
})

describe('buildStageRelation / buildReqChartRows', () => {
  it('当前版本行用绑定 trace 的章节 max，关系图用平均耗时+轮次', () => {
    const group = {
      items: [{ r: { req_name: 'DDP-1', ddp: { title: '需求甲' } } }],
    }
    const idx = [
      { req_name: 'DDP-1', ddp: { title: '需求甲' } },
      { req_name: 'tr-1', phases: ph([['prd-parsing', 0], ['prd-clarified', 2 * H]]), lines_added: 10 },
    ]
    const { rows, traceNames } = buildReqChartRows(group, idx, { 'tr-1': 'DDP-1' })
    expect(traceNames).toEqual(['tr-1'])
    expect(rows[0].name).toBe('需求甲')
    expect(rows[0].prd).toBe(2 * H)
    expect(rows[0].dac).toBe(10)
    expect(rows[0].total).toBe(2 * H)
    expect(rows[0].skip.size).toBe(0)
    const rel = buildStageRelation(rows, [
      { req_name: 'tr-1', clarify_rounds: 0, proposal_rounds: 2, feature_plan_rounds: 1, codegen_feats_total: 0, codegen_check_times: 0 },
    ], ['tr-1'])
    expect(rel[0].dur).toBe(2 * H)
    expect(rel[0].rnd).toBe(1)
    expect(rel[1].rnd).toBe(2)
  })

  it('skipped_stages 映射到分组柱的 skip', () => {
    const group = { items: [{ r: { req_name: 't', workflow_session_ids: ['s'], phases: ph([['prd-parsing', 0], ['prd-clarified', H]]), skipped_stages: ['feature_plan'] } }] }
    const { rows } = buildReqChartRows(group, group.items.map((x) => x.r), {})
    expect([...rows[0].skip].sort()).toEqual(['plan', 'spec'])
  })
})

describe('buildVersionTrend', () => {
  it('按绑定 DDP 的正式版本聚合，标记当前版本', () => {
    const traces = [
      { req_name: 't1', phases: ph([['prd-parsing', 0], ['prd-clarified', H]]) },
      { req_name: 't2', phases: ph([['prd-parsing', 0], ['prd-clarified', 3 * H]]) },
    ]
    const idx = [
      { req_name: 'D1', ddp: { release_version_name: 'Global司机端7.10.50', release_version_time: '2026-08-27' } },
      { req_name: 'D2', ddp: { release_version_name: 'Global司机端7.10.54', release_version_time: '2026-09-10' } },
    ]
    const trend = buildVersionTrend(traces, { t1: 'D1', t2: 'D2' }, idx, 'Global司机端7.10.54')
    expect(trend.map((r) => r.w)).toEqual(['7.10.50', '7.10.54'])
    expect(trend[0].prd).toBe(H)
    expect(trend[1].cur).toBe(true)
    expect(trend[0].cur).toBe(false)
  })

  it('trace 自身带 ddp 版本时不必走绑定', () => {
    const v = versionOfTrace(
      { req_name: 'x', ddp: { release_version_name: 'Global司机端1', release_version_time: 't' } },
      {},
      new Map(),
    )
    expect(v.name).toBe('Global司机端1')
  })
})
