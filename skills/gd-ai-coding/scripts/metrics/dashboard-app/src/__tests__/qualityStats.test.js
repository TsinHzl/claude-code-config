import { describe, it, expect } from 'vitest'
import { avgRounds, avgAttempts, filterQualityRows, reqQualityItems, autoGenPct } from '../utils/qualityStats'

const stats = [
  { req_name: 'a', clarify_rounds: 1, proposal_rounds: 2, feature_plan_rounds: 3,
    codegen_feats_total: 4, codegen_check_times: 7, cr_feats_total: 4, cr_check_times: 4 },
  { req_name: 'b', clarify_rounds: 2, proposal_rounds: 0, feature_plan_rounds: 1,
    codegen_feats_total: 6, codegen_check_times: 9, cr_feats_total: 5, cr_check_times: 8 },
  { req_name: 'c', clarify_rounds: 0, proposal_rounds: 0, feature_plan_rounds: 0,
    codegen_feats_total: 0, codegen_check_times: 0, cr_feats_total: 0, cr_check_times: 0 },
]

describe('filterQualityRows', () => {
  it('按需求名集合过滤', () => {
    expect(filterQualityRows(stats, ['a']).map((r) => r.req_name)).toEqual(['a'])
  })
  it('null 返回全部；空数组是空范围不是全局', () => {
    expect(filterQualityRows(stats, [])).toHaveLength(0)
    expect(filterQualityRows(stats, null)).toHaveLength(3)
    expect(filterQualityRows(stats, undefined)).toHaveLength(3)
  })
})

describe('avgRounds', () => {
  it('该门无事件(0)按 1 轮参与平均,不当 0 也不剔除', () => {
    expect(avgRounds(stats, null, 'clarify_rounds')).toBe(1.3)
    expect(avgRounds(stats, null, 'proposal_rounds')).toBe(1.3)
  })
  it('子集内全部无事件 → 按 1 轮计(不是 null)', () => {
    expect(avgRounds(stats, ['c'], 'clarify_rounds')).toBe(1)
  })
  it('按需求子集聚合', () => {
    expect(avgRounds(stats, ['b'], 'clarify_rounds')).toBe(2)
  })
  it('无任何行返回 null', () => {
    expect(avgRounds([], null, 'clarify_rounds')).toBeNull()
  })
})

describe('avgAttempts', () => {
  it('按 feat 加权：Σ次数 / Σ feat 数', () => {
    // a 7/4, b 9/6, c 0 → 16/10 = 1.6
    expect(avgAttempts(stats, null, 'codegen_check_times', 'codegen_feats_total')).toBe(1.6)
  })
  it('全无结果返回 null', () => {
    expect(avgAttempts([{ req_name: 'x', codegen_feats_total: 0, codegen_check_times: 0 }], null,
      'codegen_check_times', 'codegen_feats_total')).toBeNull()
  })
  it('空范围不回退到全局', () => {
    expect(avgAttempts(stats, [], 'codegen_check_times', 'codegen_feats_total')).toBeNull()
    expect(avgRounds(stats, [], 'clarify_rounds')).toBeNull()
  })
})

describe('reqQualityItems', () => {
  it('无名不造徽章', () => {
    expect(reqQualityItems(stats, '')).toEqual([])
  })
  it('无行仍出方案/功能 1 轮，不造机器门', () => {
    expect(reqQualityItems(stats, 'missing').map((i) => i.text)).toEqual(['方案 1 轮', '功能 1 轮'])
  })
  it('用户门 0 按 1 轮；机器门按 feat 平均', () => {
    const items = reqQualityItems(stats, 'a')
    expect(items.map((i) => i.text)).toEqual(['方案 2 轮', '功能 3 轮', '代码检查 1.8 次', 'CR 1 次'])
    expect(items.find((i) => i.key === 'cr').cls).toBe('ep-ok')
  })
  it('无 feat 不展示机器门', () => {
    const items = reqQualityItems(stats, 'c')
    expect(items.map((i) => i.text)).toEqual(['方案 1 轮', '功能 1 轮'])
  })
  it('忽略大小写，且可用备用名命中', () => {
    const items = reqQualityItems(stats, 'reward-push', ['A'])
    expect(items.map((i) => i.text)).toEqual(['方案 2 轮', '功能 3 轮', '代码检查 1.8 次', 'CR 1 次'])
  })
})

describe('autoGenPct', () => {
  it('按 codegen/dac 加权，缺字段当 0 不当 100%', () => {
    const reqs = [
      { req_name: 'a', lines_added: 100, codegen_lines_added: 40 },
      { req_name: 'b', lines_added: 100 },
    ]
    expect(autoGenPct(reqs, null)).toBe(20)
    expect(autoGenPct(reqs, ['a'])).toBe(40)
    expect(autoGenPct(reqs, ['b'])).toBe(0)
  })
  it('codegen 超过 dac 时封顶 100%；无 dac 行返回 null', () => {
    expect(autoGenPct([{ req_name: 'a', lines_added: 50, codegen_lines_added: 80 }], null)).toBe(100)
    expect(autoGenPct([{ req_name: 'a', lines_added: 0, codegen_lines_added: 10 }], null)).toBeNull()
    expect(autoGenPct([], null)).toBeNull()
    expect(autoGenPct([{ req_name: 'a', lines_added: 10, codegen_lines_added: 4 }], [])).toBeNull()
  })
})
