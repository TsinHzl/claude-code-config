import { describe, it, expect, beforeEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import OverviewTab from '../components/tabs/OverviewTab.vue'
import { store, setActiveTab } from '../store/dashboard'

function seedData() {
  store.bindings = { 'TRACE-1': 'R-100' }
  store.remarks = {}
  store.data = {
    committers: [
      { committer: 'bob-id', committer_name: 'Bob' },
      { committer: 'carol-id', committer_name: 'Carol' },
    ],
    requirements_index: [
      { req_name: 'TRACE-1', committers: ['bob-id'], last_commit_ts: 1000 },
      {
        req_name: 'R-100', rd_list: ['bob-id'],
        ddp: { title: '需求100', release_version_name: 'Global司机端100', release_version_time: '2099-01-01' },
      },
      {
        req_name: 'CUSTOM-200', rd_list: ['carol-id'], last_commit_ts: 500,
        ddp: { title: '需求200', release_version_name: 'Global司机端100', release_version_time: '2099-01-01' },
      },
      {
        req_name: 'R-300', rd_list: ['carol-id'], last_commit_ts: 600,
        ddp: { title: '需求300', release_version_name: 'Global司机端100', release_version_time: '2099-01-01' },
      },
    ],
  }
}

describe('OverviewTab 概览卡片点击跳转', () => {
  beforeEach(() => {
    setActiveTab('tab-overview')
    store.selectedPersonEmail = null
    store.selectedCurPersonName = null
    seedData()
  })

  it('不活跃需求：有 DDP 链接的项渲染为 <a> 且带 target/rel，无链接的项渲染为不可点击的 <div>', () => {
    const wrapper = mount(OverviewTab)

    const items = wrapper.findAll('.overview-list-card')[0].findAll('.overview-list-item')
    const linkItem = items.find(i => i.element.tagName === 'A')
    const staticItem = items.find(i => i.element.tagName === 'DIV')

    expect(linkItem.attributes('href')).toContain('R-300')
    expect(linkItem.attributes('target')).toBe('_blank')
    expect(linkItem.attributes('rel')).toBe('noopener noreferrer')
    expect(staticItem.classes()).toContain('overview-list-item-static')
    expect(staticItem.attributes('href')).toBeUndefined()

    wrapper.unmount()
  })

  it('点击活跃成员跳转到人员 tab 并按 email 定位', async () => {
    const wrapper = mount(OverviewTab)

    const activeCard = wrapper.findAll('.overview-list-card')[2]
    const item = activeCard.find('.overview-list-item')
    expect(item.text()).toContain('Bob')
    expect(item.text()).toContain('1/1')

    await item.trigger('click')
    await flushPromises()

    expect(store.activeTab).toBe('tab-people')
    expect(store.selectedPersonEmail).toBe('bob-id')

    wrapper.unmount()
  })

  it('点击不活跃成员跳转到当前版本 tab 并按姓名定位', async () => {
    const wrapper = mount(OverviewTab)

    const inactiveCard = wrapper.findAll('.overview-list-card')[1]
    const item = inactiveCard.find('.overview-list-item')
    expect(item.text()).toContain('Carol')
    expect(item.text()).toContain('2 需求')

    await item.trigger('click')
    await flushPromises()

    expect(store.activeTab).toBe('tab-current')
    expect(store.selectedCurPersonName).toBe('Carol')

    wrapper.unmount()
  })

  it('不活跃需求备注：未备注时展示「+ 备注」按钮，已备注时展示备注标签，点击均可唤起弹窗', async () => {
    store.remarks = {
      'R-300': { reason_tag: '非业务代码', note: '底包升级', author: 'Carol' },
    }
    const wrapper = mount(OverviewTab)

    const items = wrapper.findAll('.overview-list-card')[0].findAll('.overview-list-item')
    const r300Item = items.find(i => i.text().includes('需求300'))
    const custom200Item = items.find(i => i.text().includes('需求200'))

    const chip = r300Item.find('.ov-remark-chip')
    expect(chip.exists()).toBe(true)
    expect(chip.text()).toBe('非业务代码')
    expect(chip.attributes('title')).toContain('[非业务代码] 底包升级 by Carol')

    const btn = custom200Item.find('.ov-remark-btn')
    expect(btn.exists()).toBe(true)
    expect(btn.text()).toBe('+ 备注')

    await chip.trigger('click')
    await flushPromises()
    expect(store.remarkModalVisible).toBe(true)
    expect(store.remarkModalReqName).toBe('R-300')
    expect(store.remarkModalReqTitle).toBe('需求300')

    wrapper.unmount()
  })

  it('不活跃需求排序：已添加备注的需求排在未添加备注的需求后面', () => {
    store.remarks = {
      'CUSTOM-200': { reason_tag: '非业务代码', note: '底包升级', author: 'Carol' },
    }
    const wrapper = mount(OverviewTab)

    const items = wrapper.findAll('.overview-list-card')[0].findAll('.overview-list-item')
    // 原本 CUSTOM-200 时间更早排在 R-300 前面，但因为 CUSTOM-200 已添加备注，所以被排序到后面
    expect(items[0].text()).toContain('需求300')
    expect(items[1].text()).toContain('需求200')

    wrapper.unmount()
  })

  it('排除统计：R-100 被排除后，两张趋势图（TrendChart 需求渗透率 / MemberTrendChart DAC 成员数）footer 同步减少（recentVersions 传给图表前已过滤）', () => {
    const before = mount(OverviewTab)
    expect(before.text()).toContain('指标: 需求渗透率 · 1/3 需求')
    expect(before.text()).toContain('DAC 成员 1人')
    before.unmount()

    store.remarks = {
      'R-100': { reason_tag: '仅改配置', note: '配置调整', author: 'Bob', excluded_from_stats: true },
    }
    const after = mount(OverviewTab)
    expect(after.text()).toContain('指标: 需求渗透率 · 0/2 需求')
    expect(after.text()).toContain('DAC 成员 0人')

    after.unmount()
  })

  it('排除统计：R-100 被排除后，需求数/dac 成员数/总人数三项统计同步减少，人员从榜单剔除', () => {
    const before = mount(OverviewTab)
    const heroFracsBefore = before.findAll('.hero-metric-frac').map(n => n.text())
    // R-100 绑定 TRACE-1（Bob），是当前版本唯一的 dac 需求；CUSTOM-200/R-300 为 Carol 的非 dac 需求
    expect(heroFracsBefore[0]).toBe('(1 / 3 个)') // 需求使用率：reqDac / reqTotal
    expect(heroFracsBefore[1]).toBe('(1 / 2 人)') // 成员使用率：dacMembers.length / pplTotal
    before.unmount()

    store.remarks = {
      'R-100': { reason_tag: '仅改配置', note: '配置调整', author: 'Bob', excluded_from_stats: true },
    }
    const after = mount(OverviewTab)
    const heroFracsAfter = after.findAll('.hero-metric-frac').map(n => n.text())
    expect(heroFracsAfter[0]).toBe('(0 / 2 个)') // R-100 排除后，reqTotal 3→2，reqDac 1→0
    expect(heroFracsAfter[1]).toBe('(0 / 1 人)') // Bob 的 dac 身份完全来自 R-100，排除后 dac 成员数 1→0，总人数 2→1（仅剩 Carol）

    after.unmount()
  })

  it('默认需求视图是柱+折线', () => {
    const wrapper = mount(OverviewTab)
    expect(wrapper.find('.view-select').element.value).toBe('combo')
    expect(wrapper.findAll('.phase-pill').map((b) => b.text())).toEqual(['PRD处理', '方案生成', '功能规划', '功能开发'])
    expect(wrapper.text()).toContain('dac 行数(复杂度)')
    wrapper.unmount()
  })

  it('工作流视图下拉含漏斗/一次通过/版本趋势，漏斗文案为当前版本', async () => {
    const wrapper = mount(OverviewTab)
    const select = wrapper.find('.view-select')
    expect(select.findAll('option').map((o) => o.text())).toEqual([
      '柱+折线（单章节）',
      '需求视图（分组柱）',
      '阶段关系',
      '阶段漏斗',
      '一次通过',
      '版本趋势',
    ])
    expect(wrapper.find('.view-help .tip').text()).toContain('dac 行数')
    expect(wrapper.findAll('.phase-pill').map((b) => b.text())).toEqual(['PRD处理', '方案生成', '功能规划', '功能开发'])
    await select.setValue('funnel')
    expect(wrapper.text()).toMatch(/当前版本/)
    await select.setValue('pass')
    expect(wrapper.find('.view-help .tip').text()).toContain('个需求')
    wrapper.unmount()
  })
})
