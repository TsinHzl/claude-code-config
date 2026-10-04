import { describe, it, expect, beforeEach, vi } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import CurVersionTab from '../components/tabs/CurVersionTab.vue'
import { store, setActiveTab, selectCurOverview } from '../store/dashboard'

function seedData() {
  store.bindings = { 'TRACE-1': 'REQ-CUR1' }
  store.data = {
    committers: [
      { committer: 'alice@x.com', committer_name: 'Alice' },
      { committer: 'bob@x.com', committer_name: 'Bob' },
    ],
    requirements_index: [
      {
        req_name: 'REQ-CUR1', phases: [], features: [], rd_list: ['alice@x.com'],
        ddp: { title: '当前版本需求', release_version_name: 'Global司机端100', release_version_time: '2099-01-01' },
      },
      {
        req_name: 'TRACE-1', committers: ['alice@x.com'], workflow_session_ids: ['s1'],
        lines_added: 10, commit_count: 1,
      },
      // 技术类需求（sponsorId=3，is_technical）：Alice（dac）与 Bob（仅此技术需求参与）都在 rd_list
      {
        req_name: 'REQ-TECH', is_technical: true, phases: [], features: [], rd_list: ['alice@x.com', 'bob@x.com'],
        ddp: { title: '技术需求', release_version_name: 'Global司机端100', release_version_time: '2099-01-01' },
      },
    ],
  }
}

describe('CurVersionTab 人员卡片点击定位', () => {
  beforeEach(() => {
    setActiveTab('tab-current')
    selectCurOverview()
    store.selectedCurPersonName = null
    store.remarks = {}
    seedData()
    Element.prototype.scrollIntoView = vi.fn()
  })

  it('点击侧边栏成员卡片后进入详情态，选中项高亮并触发滚动定位', async () => {
    const wrapper = mount(CurVersionTab, { attachTo: document.body })

    const items = wrapper.findAll('.ep-li.dac')
    expect(items.length).toBeGreaterThan(0)

    await items[0].trigger('click')
    await flushPromises()

    expect(store.curPeopleViewMode).toBe('member')
    expect(store.selectedCurPersonName).toBe('Alice')
    expect(wrapper.findAll('.ep-li.dac')[0].classes()).toContain('sel')
    expect(Element.prototype.scrollIntoView).toHaveBeenCalledWith({ block: 'nearest' })

    wrapper.unmount()
  })

  it('点击版本概览中的成员卡片同样进入详情态', async () => {
    const wrapper = mount(CurVersionTab, { attachTo: document.body })

    const cards = wrapper.findAll('.ep-chip')
    expect(cards.length).toBeGreaterThan(0)

    await cards[0].trigger('click')
    await flushPromises()

    expect(store.curPeopleViewMode).toBe('member')
    expect(store.selectedCurPersonName).not.toBeNull()

    wrapper.unmount()
  })

  it('排除统计：REQ-CUR1 被排除后不再计入统计口径，但 Alice 仍在人员榜单中', async () => {
    const before = mount(CurVersionTab, { attachTo: document.body })
    expect(before.findAll('.ep-li.dac').length).toBe(1)
    // 概览态：排除前本版本 1 个需求已用 dac
    expect(before.find('#curpeople-detail').text()).toContain('1 个需求已用 dac')
    before.unmount()

    store.remarks = {
      'REQ-CUR1': { reason_tag: '仅改配置', note: '配置调整', author: 'Alice', excluded_from_stats: true },
    }
    const after = mount(CurVersionTab, { attachTo: document.body })
    // 榜单展示侧：Alice 仍保留在 dac 成员列表（排除统计不再隐藏成员/需求，只影响统计口径）
    expect(after.findAll('.ep-li.dac').length).toBe(1)
    // 统计口径：概览 donut 不再统计被排除需求（「暂无需求数据」）
    expect(after.find('#curpeople-detail').text()).toContain('暂无需求数据')

    // 详情态：Alice 的需求卡片中仍显示被排除的 REQ-CUR1（排除仅影响统计口径，不影响展示）
    const alice = after.findAll('.ep-li.dac')[0]
    await alice.trigger('click')
    await flushPromises()
    expect(after.find('#curpeople-detail').text()).toContain('当前版本需求')

    after.unmount()
  })

  it('技术类需求：成员仅技术参与仍入选榜单，badge 保持非技术口径', () => {
    const wrapper = mount(CurVersionTab, { attachTo: document.body })

    // dac 成员 Alice 参与 REQ-CUR1（非技术）+ REQ-TECH（技术）：badge「1 个需求」为纯非技术口径
    const alice = wrapper.findAll('.ep-li.dac')[0]
    expect(alice.text()).toContain('1 个需求')
    expect(alice.text()).toContain('1 个 dac 需求')

    // Bob 仅参与技术需求 REQ-TECH：仍在「未使用 dac 成员」组列出（非 dac 行），badge 为「0 个需求」
    const bob = wrapper.findAll('.ep-li').find(li => li.text().includes('Bob'))
    expect(bob).toBeTruthy()
    expect(bob.classes()).not.toContain('dac')
    expect(bob.text()).toContain('0 个需求')

    wrapper.unmount()
  })

  it('技术类需求：成员详情卡列表包含技术需求卡（Bob 仅技术参与 → 详情含技术卡）', async () => {
    const wrapper = mount(CurVersionTab, { attachTo: document.body })

    const bob = wrapper.findAll('.ep-li').find(li => li.text().includes('Bob'))
    await bob.trigger('click')
    await flushPromises()

    expect(store.curPeopleViewMode).toBe('member')
    expect(store.selectedCurPersonName).toBe('Bob')
    // memberCards 来自 Bob.reqs（含技术需求 REQ-TECH），详情区渲染出技术需求标题
    expect(wrapper.find('#curpeople-detail').text()).toContain('技术需求')

    wrapper.unmount()
  })
})
