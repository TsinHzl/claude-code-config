import { describe, it, expect, beforeEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import ReqsTab from '../components/tabs/ReqsTab.vue'
import { store, setActiveTab, setReqsFilterText, selectReqsOverview } from '../store/dashboard'

function seedData() {
  store.bindings = {}
  store.data = {
    committers: [
      { committer: 'a@x.com', committer_name: 'Alice' },
      { committer: 'b@x.com', committer_name: 'Bob' },
    ],
    requirements_index: [
      { req_name: 'REQ-100', ddp: { title: '订单模块优化' }, phases: [], features: [], committers: ['a@x.com'] },
      { req_name: 'REQ-200', ddp: { title: '登录页重构' }, phases: [], features: [], committers: ['b@x.com'] },
    ],
  }
}

describe('ReqsTab 需求视图名称/ID 过滤', () => {
  beforeEach(() => {
    setActiveTab('tab-reqs')
    setReqsFilterText('')
    selectReqsOverview()
    seedData()
  })

  it('输入过滤词后仅显示名称或 ID 命中的需求卡片，其余隐藏', async () => {
    const wrapper = mount(ReqsTab, { attachTo: document.body })
    await flushPromises()

    await wrapper.find('.ep-search input').setValue('订单')
    await flushPromises()

    const items = wrapper.findAll('.ep-req-li')
    const visibleTexts = items.filter((i) => i.element.style.display !== 'none').map((i) => i.text())
    const hiddenTexts = items.filter((i) => i.element.style.display === 'none').map((i) => i.text())
    expect(visibleTexts.some((t) => t.includes('订单模块优化'))).toBe(true)
    expect(hiddenTexts.some((t) => t.includes('登录页重构'))).toBe(true)

    wrapper.unmount()
  })

  it('按 ID 过滤同样生效（大小写不敏感）', async () => {
    const wrapper = mount(ReqsTab, { attachTo: document.body })
    await flushPromises()

    await wrapper.find('.ep-search input').setValue('req-200')
    await flushPromises()

    const items = wrapper.findAll('.ep-req-li')
    const visible = items.filter((i) => i.element.style.display !== 'none')
    expect(visible).toHaveLength(1)
    expect(visible[0].text()).toContain('登录页重构')

    wrapper.unmount()
  })

  it('清空输入后恢复全部显示', async () => {
    const wrapper = mount(ReqsTab, { attachTo: document.body })
    await flushPromises()

    await wrapper.find('.ep-search input').setValue('订单')
    await flushPromises()
    await wrapper.find('.ep-search input').setValue('')
    await flushPromises()

    const items = wrapper.findAll('.ep-req-li')
    expect(items.every((i) => i.element.style.display !== 'none')).toBe(true)

    wrapper.unmount()
  })
})

describe('ReqsTab 需求列表按活跃时间排序', () => {
  beforeEach(() => {
    setActiveTab('tab-reqs')
    setReqsFilterText('')
    selectReqsOverview()
  })

  it('按 last_commit_ts 降序排列，缺失时回退 reported_at，同为空时保持原索引顺序', async () => {
    store.bindings = {}
    store.data = {
      committers: [
        { committer: 'dev@x.com', committer_name: 'Dev' },
      ],
      requirements_index: [
        { req_name: 'REQ-OLD', ddp: { title: '较早活跃需求' }, phases: [], features: [], committers: ['dev@x.com'], last_commit_ts: 1000 },
        { req_name: 'REQ-NEW', ddp: { title: '最近活跃需求' }, phases: [], features: [], committers: ['dev@x.com'], last_commit_ts: 3000 },
        { req_name: 'REQ-FALLBACK', ddp: { title: '回退需求' }, phases: [], features: [], committers: ['dev@x.com'], reported_at: 2000 },
      ],
    }

    const wrapper = mount(ReqsTab, { attachTo: document.body })
    await flushPromises()

    const texts = wrapper.findAll('.ep-req-li').map((i) => i.text())
    const order = ['最近活跃需求', '回退需求', '较早活跃需求'].map((t) => texts.findIndex((x) => x.includes(t)))
    expect(order[0]).toBeLessThan(order[1])
    expect(order[1]).toBeLessThan(order[2])

    wrapper.unmount()
  })
})

describe('ReqsTab 概览态', () => {
  beforeEach(() => {
    setActiveTab('tab-reqs')
    setReqsFilterText('')
    selectReqsOverview()
    seedData()
  })

  it('默认打开为概览态，不自动选中任意需求', () => {
    const wrapper = mount(ReqsTab, { attachTo: document.body })
    expect(wrapper.findAll('.ep-li')[0].classes()).toContain('sel-ok')
    expect(wrapper.find('.ep-stat-card').exists()).toBe(true)
    expect(wrapper.text()).not.toContain('选择一个需求查看详情')
    wrapper.unmount()
  })

  it('点击概览网格卡片进入对应需求详情态', async () => {
    const wrapper = mount(ReqsTab, { attachTo: document.body })
    await wrapper.find('.ep-chip').trigger('click')
    await flushPromises()

    expect(wrapper.find('.ep-stat-card').exists()).toBe(false)
    expect(wrapper.find('.ep-dh-badges').exists()).toBe(true)
    wrapper.unmount()
  })

  it('详情态下点击 sidebar 概览入口可返回概览态', async () => {
    const wrapper = mount(ReqsTab, { attachTo: document.body })
    await wrapper.findAll('.ep-req-li')[0].trigger('click')
    await flushPromises()
    expect(wrapper.find('.ep-stat-card').exists()).toBe(false)

    await wrapper.findAll('.ep-li')[0].trigger('click')
    await flushPromises()
    expect(wrapper.find('.ep-stat-card').exists()).toBe(true)
    wrapper.unmount()
  })

  it('选中需求从 visible 消失后自动回退概览态', async () => {
    const wrapper = mount(ReqsTab, { attachTo: document.body })
    await wrapper.findAll('.ep-req-li')[0].trigger('click')
    await flushPromises()
    expect(wrapper.find('.ep-stat-card').exists()).toBe(false)

    store.data = {
      ...store.data,
      requirements_index: store.data.requirements_index.filter((r) => r.req_name !== 'REQ-100'),
    }
    await flushPromises()

    expect(wrapper.find('.ep-stat-card').exists()).toBe(true)
    wrapper.unmount()
  })

  it('过滤掉无有效司机端参与人员且无 trace 的幽灵需求', async () => {
    store.data = {
      committers: [
        { committer: 'a@x.com', committer_name: 'Alice' },
        { committer: 'tianxiao@didiglobal.com', committer_name: '田啸' },
      ],
      requirements_index: [
        { req_name: 'REQ-VALID', ddp: { title: '有效需求' }, phases: [], features: [], committers: ['a@x.com'], rd_list: ['a@x.com'] },
        { req_name: 'REQ-TIANXIAO', ddp: { title: '田啸单人需求' }, phases: [], features: [], committers: ['tianxiao@didiglobal.com'], rd_list: ['tianxiao@didiglobal.com'] },
        { req_name: 'REQ-EMPTY', ddp: { title: '无负责人需求' }, phases: [], features: [], committers: [], rd_list: [] },
      ],
    }
    const wrapper = mount(ReqsTab, { attachTo: document.body })
    await flushPromises()

    const items = wrapper.findAll('.ep-req-li')
    const visibleTexts = items.map((i) => i.text())
    expect(visibleTexts.some((t) => t.includes('有效需求'))).toBe(true)
    expect(visibleTexts.some((t) => t.includes('田啸单人需求'))).toBe(false)
    expect(visibleTexts.some((t) => t.includes('无负责人需求'))).toBe(false)

    wrapper.unmount()
  })
})
