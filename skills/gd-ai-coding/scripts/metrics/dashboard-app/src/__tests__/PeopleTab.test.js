import { describe, it, expect, beforeEach, vi } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import PeopleTab from '../components/tabs/PeopleTab.vue'
import { store, setActiveTab, selectPeopleOverview, selectPerson } from '../store/dashboard'

function seedData() {
  store.bindings = {}
  store.data = {
    committers: [
      { committer: 'user-alpha', committer_name: 'Alpha', requirements: [] },
      { committer: 'user-beta', committer_name: 'Beta', requirements: [] },
    ],
  }
}

describe('PeopleTab 人员卡片点击定位', () => {
  beforeEach(() => {
    setActiveTab('tab-people')
    selectPeopleOverview()
    store.selectedPersonEmail = null
    seedData()
    Element.prototype.scrollIntoView = vi.fn()
  })

  it('点击侧边栏成员卡片后进入详情态，选中项高亮并触发滚动定位', async () => {
    const wrapper = mount(PeopleTab, { attachTo: document.body })

    // 列表首项为「团队概览」入口，成员项从第 2 项起
    const items = wrapper.findAll('.ep-li').slice(1)
    expect(items).toHaveLength(2)

    await items[1].trigger('click')
    await flushPromises()

    expect(store.peopleViewMode).toBe('member')
    expect(store.selectedPersonEmail).toBe('user-beta')
    expect(wrapper.findAll('.ep-li').slice(1)[1].classes()).toContain('sel')
    expect(Element.prototype.scrollIntoView).toHaveBeenCalledWith({ block: 'nearest' })

    wrapper.unmount()
  })

  it('点击团队概览中的成员卡片同样进入详情态', async () => {
    const wrapper = mount(PeopleTab, { attachTo: document.body })

    const cards = wrapper.findAll('.ep-chip')
    expect(cards.length).toBeGreaterThan(0)

    await cards[0].trigger('click')
    await flushPromises()

    expect(store.peopleViewMode).toBe('member')
    expect(store.selectedPersonEmail).not.toBeNull()

    wrapper.unmount()
  })
})

describe('PeopleTab 排序切换', () => {
  beforeEach(() => {
    setActiveTab('tab-people')
    selectPeopleOverview()
    store.selectedPersonEmail = null
    store.peopleSortMode = 'activity'
    store.bindings = {}
    store.data = {
      committers: [
        {
          committer: 'user-alpha', committer_name: 'Alpha',
          requirements: [
            { req_name: 'r1', workflow_session_ids: ['s1'], last_commit_ts: '2025-01-01T00:00:00.000Z' },
            { req_name: 'r2', workflow_session_ids: ['s2'], last_commit_ts: '2025-01-02T00:00:00.000Z' },
          ],
        },
        {
          committer: 'user-beta', committer_name: 'Beta',
          requirements: [
            { req_name: 'r3', workflow_session_ids: ['s3'], last_commit_ts: '2026-08-10T00:00:00.000Z' },
          ],
        },
      ],
    }
  })

  it('默认按最近活跃时间排序，点击按钮后切换为按 dac 使用量排序', async () => {
    const wrapper = mount(PeopleTab, { attachTo: document.body })

    expect(store.peopleSortMode).toBe('activity')
    let names = wrapper.findAll('.ep-li .ep-li-name').slice(1).map(n => n.text())
    expect(names[0]).toBe('Beta')

    await wrapper.find('.people-sort-toggle').trigger('click')
    await flushPromises()

    expect(store.peopleSortMode).toBe('dac')
    names = wrapper.findAll('.ep-li .ep-li-name').slice(1).map(n => n.text())
    expect(names[0]).toBe('Alpha')

    wrapper.unmount()
  })
})

describe('PeopleTab vibe coding 可见性信号', () => {
  beforeEach(() => {
    setActiveTab('tab-people')
    selectPeopleOverview()
    store.selectedPersonEmail = null
    store.bindings = {}
    store.data = {
      committers: [
        { committer: 'user-alpha', committer_name: 'Alpha', requirements: [] },
      ],
      personal_totals: [{ committer: 'user-alpha', total_lines: 123, last_reported_at: null }],
    }
  })

  it('config.vibeVisible 为 false 时不展示 vibe coding 徽章', () => {
    store.config = { vibeVisible: false }
    const wrapper = mount(PeopleTab, { attachTo: document.body })

    expect(wrapper.find('.ep-li-badges .ep-bd.ep-info').exists()).toBe(false)

    wrapper.unmount()
  })

  it('config.vibeVisible 为 true 时展示 vibe coding 徽章及行数', () => {
    store.config = { vibeVisible: true }
    const wrapper = mount(PeopleTab, { attachTo: document.body })

    const badge = wrapper.find('.ep-li-badges .ep-bd.ep-info')
    expect(badge.exists()).toBe(true)
    expect(badge.text()).toContain('123')

    wrapper.unmount()
  })

  it('vibeKpiVisible 为 false 时概览只有两个 KPI 卡且用 ep-stat-row 布局', () => {
    store.config = { vibeVisible: false }
    const wrapper = mount(PeopleTab, { attachTo: document.body })

    expect(wrapper.findAll('.ep-kpi-box')).toHaveLength(2)
    expect(wrapper.find('.ep-stat-row').exists()).toBe(true)
    expect(wrapper.find('.ep-kpi-row').exists()).toBe(false)
    expect(wrapper.text()).not.toContain('vibe coding 总量')

    wrapper.unmount()
  })

  it('vibeKpiVisible 为 true 时概览追加第三个 KPI 卡并用 ep-kpi-row 布局', () => {
    store.config = { vibeVisible: true }
    const wrapper = mount(PeopleTab, { attachTo: document.body })

    expect(wrapper.findAll('.ep-kpi-box')).toHaveLength(3)
    expect(wrapper.find('.ep-kpi-row').exists()).toBe(true)
    expect(wrapper.find('.ep-stat-row').exists()).toBe(false)
    expect(wrapper.text()).toContain('vibe coding 总量')

    wrapper.unmount()
  })

  it('personal_totals 缺失时 vibe KPI 卡不渲染（vibeTotal 为 null）', () => {
    store.config = { vibeVisible: true }
    store.data = { committers: [{ committer: 'user-alpha', committer_name: 'Alpha', requirements: [] }] }
    const wrapper = mount(PeopleTab, { attachTo: document.body })

    expect(wrapper.findAll('.ep-kpi-box')).toHaveLength(2)
    expect(wrapper.text()).not.toContain('vibe coding 总量')

    wrapper.unmount()
  })
})

describe('PeopleTab 需求明细排序', () => {
  // 版本时间取远期固定值，避免「当前版本 = 发布时间 ≥ 今天」的判定随真实日期漂移
  function makeReq(name, version, time, { dac = false, released = false } = {}) {
    return {
      req_name: name,
      ddp: { title: name, release_version_name: version, release_version_time: time },
      phases: [{ phase: released ? 'released' : 'developing' }],
      ...(dac ? { workflow_session_ids: ['s-' + name], committers: ['user-alpha'] } : {}),
    }
  }

  beforeEach(() => {
    setActiveTab('tab-people')
    store.config = { vibeVisible: false }
    store.bindings = {}
    const reqs = [
      makeReq('v42-dac', 'Global司机端7.10.42', '2026-07-30', { dac: true, released: true }),
      makeReq('v38-dac', 'Global司机端7.10.38', '2026-06-30', { dac: true }),
      makeReq('cur-dac', 'Global司机端7.10.60', '2099-01-01', { dac: true }),
      makeReq('v42-non', 'Global司机端7.10.42', '2026-07-30', { released: true }),
      makeReq('v38-non', 'Global司机端7.10.38', '2026-06-30'),
    ]
    store.data = {
      committers: [{ committer: 'user-alpha', committer_name: 'Alpha', requirements: reqs }],
      requirements_index: reqs,
    }
    selectPerson('user-alpha')
  })

  it('dac / 非 dac 两组内均将已上线需求排到末尾，当前版本需求置顶', () => {
    const wrapper = mount(PeopleTab, { attachTo: document.body })

    expect(wrapper.findAll('.ep-req-title').map(n => n.text()))
      .toEqual(['cur-dac', 'v38-dac', 'v42-dac', 'v38-non', 'v42-non'])

    wrapper.unmount()
  })

  it('当前版本需求即使已上线仍留在分组顶部，只在当前版本区内部沉底', () => {
    const reqs = [
      makeReq('cur-dac-released', 'Global司机端7.10.60', '2099-01-01', { dac: true, released: true }),
      makeReq('v42-dac', 'Global司机端7.10.42', '2026-07-30', { dac: true }),
      makeReq('cur-dac', 'Global司机端7.10.60', '2099-01-01', { dac: true }),
    ]
    store.data = {
      committers: [{ committer: 'user-alpha', committer_name: 'Alpha', requirements: reqs }],
      requirements_index: reqs,
    }
    const wrapper = mount(PeopleTab, { attachTo: document.body })

    expect(wrapper.findAll('.ep-req-title').map(n => n.text()))
      .toEqual(['cur-dac', 'cur-dac-released', 'v42-dac'])

    wrapper.unmount()
  })
})

describe('PeopleTab 顶栏汇总与比例边界', () => {
  beforeEach(() => {
    setActiveTab('tab-people')
    selectPeopleOverview()
    store.selectedPersonEmail = null
    store.config = { vibeVisible: false }
    store.bindings = {}
    store.data = null
  })

  it('数据未返回时顶栏人数为占位符而非 0', () => {
    const wrapper = mount(PeopleTab, { attachTo: document.body })

    expect(wrapper.find('.ep-top-meta').text()).toBe('共 — 人')

    wrapper.unmount()
  })

  it('数据返回后顶栏展示人数，带 generatedAt 时追加更新时间', () => {
    store.data = {
      committers: [
        { committer: 'user-alpha', committer_name: 'Alpha', requirements: [] },
        { committer: 'user-beta', committer_name: 'Beta', requirements: [] },
      ],
      generatedAt: '2026-08-17 10:00',
    }
    const wrapper = mount(PeopleTab, { attachTo: document.body })

    expect(wrapper.find('.ep-top-meta').text()).toBe('共 2 人 · 更新时间: 2026-08-17 10:00')

    wrapper.unmount()
  })

  it('全员无需求时 dac 需求占比与渗透率均为 0%，进度条宽度不为 NaN', () => {
    store.data = {
      committers: [
        { committer: 'user-alpha', committer_name: 'Alpha', requirements: [] },
        { committer: 'user-beta', committer_name: 'Beta', requirements: [] },
      ],
    }
    const wrapper = mount(PeopleTab, { attachTo: document.body })

    const fills = wrapper.findAll('.ep-kpi-fill')
    expect(fills).toHaveLength(2)
    for (const f of fills) expect(f.attributes('style')).toContain('width: 0%')
    expect(wrapper.find('.ep-stat-sub').text()).toContain('占团队 2 位成员的 0%')

    wrapper.unmount()
  })
})

describe('PeopleTab 排除统计', () => {
  beforeEach(() => {
    setActiveTab('tab-people')
    selectPeopleOverview()
    store.selectedPersonEmail = null
    store.peopleSortMode = 'dac'
    store.bindings = {}
    store.remarks = {}
    store.data = {
      committers: [
        {
          committer: 'user-alpha', committer_name: 'Alpha',
          requirements: [
            { req_name: 'r1', workflow_session_ids: ['s1'], last_commit_ts: '2025-01-01T00:00:00.000Z' },
          ],
        },
        { committer: 'user-beta', committer_name: 'Beta', requirements: [] },
      ],
    }
  })

  it('唯一 dac 需求被勾选排除统计后，该成员从「使用 dac 成员」名单中消失', () => {
    const before = mount(PeopleTab, { attachTo: document.body })
    expect(before.text()).toContain('使用 dac 成员（1）')
    expect(before.text()).toContain('Alpha')
    before.unmount()

    store.remarks = {
      r1: { reason_tag: '仅改配置', note: '配置调整', author: 'Alpha', excluded_from_stats: true },
    }
    const after = mount(PeopleTab, { attachTo: document.body })
    expect(after.text()).not.toContain('使用 dac 成员（1）')
    expect(after.text()).toContain('团队暂无成员使用 dac')

    after.unmount()
  })
})
