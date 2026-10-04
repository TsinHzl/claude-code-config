import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { store } from '../store/dashboard'
import { startStream } from '../services/refresh'
import { fetchData, fetchBindings, fetchConfig } from '../api/data'
import { fetchRemarks } from '../api/remarks'

vi.mock('../api/data', () => ({
  fetchData: vi.fn(),
  fetchBindings: vi.fn(),
  fetchConfig: vi.fn(),
}))

vi.mock('../api/remarks', () => ({
  fetchRemarks: vi.fn(),
}))

class MockEventSource {
  constructor(url) {
    this.url = url
    this.readyState = 0
    this.onmessage = null
    this.onerror = null
    MockEventSource.instances.push(this)
  }
  close() {
    this.readyState = MockEventSource.CLOSED
  }
}
MockEventSource.CLOSED = 2
MockEventSource.instances = []

describe('refresh.js 刷新数据流', () => {
  beforeEach(() => {
    MockEventSource.instances = []
    global.EventSource = MockEventSource
    window.__STATIC_DATA__ = undefined
    store.data = null
    store.bindings = null
    fetchData.mockReset()
    fetchBindings.mockReset()
    fetchConfig.mockReset()
  })

  afterEach(() => {
    window.__STATIC_DATA__ = undefined
  })

  it('收到 backend_snapshot 消息后写入最新数据，收到 done 消息后重新拉取绑定与个人总量', async () => {
    fetchBindings.mockResolvedValue({ 'TRACE-1': 'REQ-1' })
    fetchData.mockResolvedValue({ personal_totals: [{ committer: 'user-x', total_lines: 10 }] })

    startStream()
    const es = MockEventSource.instances[0]
    expect(es).toBeTruthy()

    await es.onmessage({
      data: JSON.stringify({ type: 'backend_snapshot', committers: [{ committer: 'user-x' }], requirements_index: [], generatedAt: 't1' }),
    })
    expect(store.data.committers).toHaveLength(1)

    await es.onmessage({ data: JSON.stringify({ type: 'done' }) })

    expect(fetchBindings).toHaveBeenCalled()
    expect(fetchData).toHaveBeenCalled()
    expect(store.bindings).toEqual({ 'TRACE-1': 'REQ-1' })
    expect(store.data.personal_totals).toEqual([{ committer: 'user-x', total_lines: 10 }])
  })

  it('静态模式（window.__STATIC_DATA__ 已存在）下不建立数据流连接', () => {
    window.__STATIC_DATA__ = { committers: [] }
    startStream()
    expect(MockEventSource.instances).toHaveLength(0)
  })

  it('收到 error 消息后关闭连接并提示加载失败', async () => {
    startStream()
    const es = MockEventSource.instances[0]

    await es.onmessage({ data: JSON.stringify({ type: 'error', message: '后端异常' }) })

    expect(es.readyState).toBe(MockEventSource.CLOSED)
    expect(store.refreshTipVisible).toBe(true)
    expect(store.refreshTipText).toContain('后端异常')
  })
})
