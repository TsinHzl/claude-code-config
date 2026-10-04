import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { fetchConfig } from '../api/data'

describe('fetchConfig', () => {
  afterEach(() => {
    window.__STATIC_DATA__ = undefined
    vi.unstubAllGlobals()
  })

  it('静态模式（window.__STATIC_DATA__ 非空）下不请求 /api/config，固定返回 vibeVisible:false', async () => {
    window.__STATIC_DATA__ = { committers: [] }
    const fetchSpy = vi.fn()
    vi.stubGlobal('fetch', fetchSpy)

    const config = await fetchConfig()

    expect(config).toEqual({ vibeVisible: false })
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it('非静态模式下请求 /api/config 并返回响应体', async () => {
    window.__STATIC_DATA__ = undefined
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ vibeVisible: true }),
    }))

    const config = await fetchConfig()

    expect(config).toEqual({ vibeVisible: true })
  })
})
