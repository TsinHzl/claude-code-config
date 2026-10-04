import { describe, it, expect } from 'vitest'
import { computeMemberAiStats, rankedMembersWithAiStats } from '../utils/peopleStats'

// 成员维度口径：技术类需求（is_technical）保留在 reqs/卡片展示中，仅从计数口径
// （reqCount/doneCount/dacReqList 及其派生的 dac 分类/统计）剔除，避免让参与者被误判为
// 「使用 dac 成员」。与 utils/version.js 的 filterExcludedFromStats 口径一致。
const member = {
  committer: 'dev1@didiglobal.com',
  committer_name: 'Dev1',
  requirements: [
    // 技术 DDP，已直连 dac trace（workflow_session_ids 由服务端写入自身）：不计入任何计数
    {
      req_name: 'TECH-1', ddp: { title: '技术需求' }, is_technical: true,
      workflow_session_ids: ['s-t'], phases: [{ phase: 'released' }], features: [],
      committers: ['dev1@didiglobal.com'], rd_list: ['dev1@didiglobal.com'], last_commit_ts: 1000,
    },
    // 业务 DDP，已直连 dac trace：dac 计数基线
    {
      req_name: 'BIZ-1', ddp: { title: '业务需求' },
      workflow_session_ids: ['s-b'], phases: [], features: [],
      committers: ['dev1@didiglobal.com'], rd_list: ['dev1@didiglobal.com'], last_commit_ts: 900,
    },
    // 业务 DDP 已上线未用 dac：计入需求数/完成数，但不入 dac
    {
      req_name: 'BIZ-2', ddp: { title: '业务需求2' },
      phases: [{ phase: 'released' }], features: [], rd_list: ['dev1@didiglobal.com'],
    },
  ],
}

describe('computeMemberAiStats 技术需求计数排除', () => {
  it('reqs 保留全量（含技术需求，供成员详情卡展示），reqCount 不含技术', () => {
    const s = computeMemberAiStats(member, {}, [], {})
    expect(s.reqs.map(r => r.req_name)).toEqual(['TECH-1', 'BIZ-1', 'BIZ-2'])
    expect(s.reqCount).toBe(2)
  })

  it('doneCount 不含技术需求（技术已上线不计完成）', () => {
    const s = computeMemberAiStats(member, {}, [], {})
    // TECH-1 虽 released 但为技术需求被排除；仅 BIZ-2 released 计入
    expect(s.doneCount).toBe(1)
  })

  it('dacReqList/dacReqs 不含技术需求（技术直连 trace 不计使用 dac）', () => {
    const s = computeMemberAiStats(member, {}, [], {})
    expect(s.dacReqList.map(r => r.req_name)).toEqual(['BIZ-1'])
    expect(s.dacReqs).toBe(1)
  })

  it('仅参与技术需求的成员 hasAi=false、dacReqs=0，不被误判为「使用 dac」', () => {
    const techOnly = {
      committer: 'tech@didiglobal.com',
      committer_name: 'Tech',
      requirements: [
        {
          req_name: 'TECH-2', ddp: { title: '技术需求2' }, is_technical: true,
          workflow_session_ids: ['s-t2'], phases: [{ phase: 'released' }], features: [],
          committers: ['tech@didiglobal.com'], rd_list: ['tech@didiglobal.com'], last_commit_ts: 500,
        },
      ],
    }
    const list = rankedMembersWithAiStats([techOnly], {}, [], [], 'dac', {})
    expect(list).toHaveLength(1)
    expect(list[0].reqs.map(r => r.req_name)).toEqual(['TECH-2']) // 展示仍保留
    expect(list[0].reqCount).toBe(0)
    expect(list[0].dacReqs).toBe(0)
    expect(list[0].hasAi).toBe(false)
  })
})
