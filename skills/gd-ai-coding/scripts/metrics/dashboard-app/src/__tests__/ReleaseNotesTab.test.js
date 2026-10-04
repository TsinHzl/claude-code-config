import { describe, it, expect, afterEach, vi } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import ReleaseNotesTab from '../components/tabs/ReleaseNotesTab.vue'

describe('ReleaseNotesTab', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('fetch 成功时渲染更新日志列表', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ([
        { date: '2026-08-07', groups: [{ title: '分组A', items: ['条目1', '条目2'] }] },
      ]),
    }))

    const wrapper = mount(ReleaseNotesTab)
    await flushPromises()

    expect(wrapper.find('.rn-state-loading').exists()).toBe(false)
    expect(wrapper.find('.rn-state-error').exists()).toBe(false)
    expect(wrapper.findAll('.ep-rn-entry')).toHaveLength(1)
    expect(wrapper.text()).toContain('分组A')
    expect(wrapper.text()).toContain('条目1')
    expect(wrapper.find('.ep-rn-new').exists()).toBe(true)

    wrapper.unmount()
  })

  it('过滤 groups 为空 / items 全空的占位条目', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ([
        { date: '2026-08-19', groups: [{ title: '分组A', items: ['条目1'] }] },
        { date: '2026-08-18', groups: [] },
        { date: '2026-08-17', groups: [{ title: '空分组', items: [] }] },
      ]),
    }))

    const wrapper = mount(ReleaseNotesTab)
    await flushPromises()

    expect(wrapper.findAll('.ep-rn-entry')).toHaveLength(1)
    expect(wrapper.text()).not.toContain('2026-08-18')
    expect(wrapper.text()).not.toContain('2026-08-17')
    // 汇总与页脚计数同步排除占位条目
    expect(wrapper.find('.ep-top-meta').text()).toBe('1 次发布 · 1 个模块 · 1 项变更')
    expect(wrapper.text()).toContain('共 1 次发布')

    wrapper.unmount()
  })

  it('全部条目均为占位条目时展示空态', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ([{ date: '2026-08-18', groups: [] }]),
    }))

    const wrapper = mount(ReleaseNotesTab)
    await flushPromises()

    expect(wrapper.find('.rn-state-empty').exists()).toBe(true)

    wrapper.unmount()
  })

  it('fetch 失败（响应非 ok）时展示错误态', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, status: 500 }))

    const wrapper = mount(ReleaseNotesTab)
    await flushPromises()

    expect(wrapper.find('.rn-state-error').exists()).toBe(true)
    expect(wrapper.text()).toContain('更新日志加载失败')

    wrapper.unmount()
  })

  it('返回空数组时展示空态', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ([]),
    }))

    const wrapper = mount(ReleaseNotesTab)
    await flushPromises()

    expect(wrapper.find('.rn-state-empty').exists()).toBe(true)
    expect(wrapper.text()).toContain('暂无更新记录')

    wrapper.unmount()
  })
})
