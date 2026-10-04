import { describe, it, expect } from 'vitest'
import { enrichReq, getDdpToTrace } from '../utils/enrich'

describe('enrichReq', () => {
  it('直连场景：ddp 需求自带非空 workflow_session_ids 时应回填 _boundTrace 等字段', () => {
    const req = {
      req_name: 'T-IBT-621678',
      ddp: { title: '日本司机端文案问题修改' },
      workflow_session_ids: ['s1'],
      committers: ['luowencheng_i@didiglobal.com'],
      phases: [{ name: '开发中', ts: '2026-08-01' }],
      features: ['feat-a'],
      last_commit_ts: '2026-08-01T00:00:00.000Z',
      reported_at: '2026-08-01T00:00:00.000Z',
      commit_count: 7,
      lines_added: 761,
    }
    const result = enrichReq(req, 'luowencheng_i@didiglobal.com', {}, [])
    expect(result._boundTrace).toBe('T-IBT-621678')
    expect(result._tracePhases).toBe(req.phases)
    expect(result._traceFeatures).toBe(req.features)
    expect(result._traceCommitCount).toBe(7)
    expect(result._traceLinesAdded).toBe(761)
  })

  it('手动绑定场景：仍按 bindings + committers 匹配才回填 _boundTrace（回归）', () => {
    const req = { req_name: 'T-IBT-999', ddp: { title: '未绑定 trace 的需求' } }
    const bindings = { 'trace-name-a': 'T-IBT-999' }
    const requirementsIndex = [
      { req_name: 'trace-name-a', committers: ['other@didiglobal.com'], workflow_session_ids: ['s2'] },
    ]
    const ddpToTrace = getDdpToTrace(bindings)
    const result = enrichReq(req, 'me@didiglobal.com', bindings, requirementsIndex, ddpToTrace)
    expect(result._boundTrace).toBeUndefined()
    expect(result).toBe(req)
  })

  it('手动绑定场景：committers 命中本人时正常回填', () => {
    const req = { req_name: 'T-IBT-999', ddp: { title: '未绑定 trace 的需求' } }
    const bindings = { 'trace-name-a': 'T-IBT-999' }
    const requirementsIndex = [
      { req_name: 'trace-name-a', committers: ['me@didiglobal.com'], workflow_session_ids: ['s2'], commit_count: 3, lines_added: 10 },
    ]
    const ddpToTrace = getDdpToTrace(bindings)
    const result = enrichReq(req, 'me@didiglobal.com', bindings, requirementsIndex, ddpToTrace)
    expect(result._boundTrace).toBe('trace-name-a')
    expect(result.workflow_session_ids).toEqual(['s2'])
  })

  it('无任何匹配时原样返回 req', () => {
    const req = { req_name: 'T-IBT-000', ddp: { title: '无关联' } }
    const result = enrichReq(req, 'me@didiglobal.com', {}, [])
    expect(result).toBe(req)
  })
})
