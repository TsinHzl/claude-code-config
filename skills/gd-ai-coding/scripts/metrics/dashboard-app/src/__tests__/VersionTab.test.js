import { describe, it, expect, beforeEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import VersionTab from '../components/tabs/VersionTab.vue'
import { store, setActiveTab, selectVersionOverview, setVersionFilterText } from '../store/dashboard'

function seedData() {
  store.bindings = {}
  store.data = {
    committers: [
      { committer: 'a@x.com', committer_name: 'Alice' },
      { committer: 'b@x.com', committer_name: 'Bob' },
    ],
    requirements_index: [
      {
        req_name: 'REQ-A1', phases: [], features: [], committers: ['a@x.com'], rd_list: ['a@x.com', 'b@x.com'],
        ddp: { title: '需求A1标题', release_version_name: 'Global司机端100', release_version_time: '2020-01-01' },
      },
      {
        req_name: 'REQ-A2', phases: [], features: [], committers: ['b@x.com'], rd_list: ['b@x.com'],
        ddp: { title: '需求A2标题', release_version_name: 'Global司机端100', release_version_time: '2020-01-01' },
      },
      {
        req_name: 'REQ-B1', phases: [], features: [], committers: ['a@x.com'], rd_list: ['a@x.com'],
        ddp: { title: '需求B1标题', release_version_name: 'Global司机端99', release_version_time: '2019-01-01' },
      },
    ],
  }
}

describe('VersionTab 版本视图名称/ID 过滤', () => {
  beforeEach(() => {
    setActiveTab('tab-version')
    selectVersionOverview()
    setVersionFilterText('')
    store.remarks = {}
    seedData()
  })

  it('概览态下搜索框隐藏', () => {
    const wrapper = mount(VersionTab, { attachTo: document.body })
    expect(wrapper.find('.ep-search').isVisible()).toBe(false)
    wrapper.unmount()
  })

  it('选中具体版本后搜索框显示，输入过滤词仅显示命中的需求卡片', async () => {
    const wrapper = mount(VersionTab, { attachTo: document.body })
    await wrapper.findAll('.ep-li')[1].trigger('click')
    await flushPromises()
    expect(wrapper.find('.ep-search').isVisible()).toBe(true)

    await wrapper.find('.ep-search input').setValue('A1')
    await flushPromises()

    const cards = wrapper.findAll('.ep-req-slot')
    const visible = cards.filter((c) => c.element.style.display !== 'none')
    const hidden = cards.filter((c) => c.element.style.display === 'none')
    expect(visible.some((c) => c.text().includes('需求A1标题'))).toBe(true)
    expect(hidden.some((c) => c.text().includes('需求A2标题'))).toBe(true)

    wrapper.unmount()
  })

  it('需求卡片右上角展示参与 RD 姓名，且位于进度文案左侧', async () => {
    const wrapper = mount(VersionTab, { attachTo: document.body })
    await wrapper.findAll('.ep-li')[1].trigger('click')
    await flushPromises()

    const card = wrapper.findAll('.ep-req-slot').find((c) => c.text().includes('需求A1标题'))
    const top = card.find('.ep-req-head')
    expect(top.text()).toContain('Alice、Bob')

    const kids = [...top.element.children]
    const rdIdx = kids.findIndex((el) => el.textContent.includes('Alice'))
    const badgeIdx = kids.findIndex((el) => el.querySelector('.ep-bd'))
    expect(rdIdx).toBeGreaterThanOrEqual(0)
    expect(badgeIdx).toBeGreaterThanOrEqual(0)
    expect(rdIdx).toBeLessThan(badgeIdx)

    wrapper.unmount()
  })

  it('切回版本概览时隐藏搜索框且不残留过滤状态影响概览渲染', async () => {
    const wrapper = mount(VersionTab, { attachTo: document.body })
    await wrapper.findAll('.ep-li')[1].trigger('click')
    await wrapper.find('.ep-search input').setValue('A1')
    await flushPromises()

    await wrapper.findAll('.ep-li')[0].trigger('click')
    await flushPromises()

    expect(wrapper.find('.ep-search').isVisible()).toBe(false)
    // 概览态渲染的是 .ep-stat-card 统计区块，不受残留过滤词影响
    expect(wrapper.find('.ep-stat-card').exists()).toBe(true)

    wrapper.unmount()
  })

  it('切换到另一个具体版本时保留过滤词，并对新版本需求重新应用过滤', async () => {
    const wrapper = mount(VersionTab, { attachTo: document.body })
    const versionItems = wrapper.findAll('.ep-li').slice(1)

    await versionItems[0].trigger('click')
    await wrapper.find('.ep-search input').setValue('需求')
    await flushPromises()

    await versionItems[1].trigger('click')
    await flushPromises()

    expect(wrapper.find('.ep-search input').element.value).toBe('需求')
    const cards = wrapper.findAll('.ep-req-slot')
    expect(cards.some((c) => c.text().includes('需求B1标题') && c.element.style.display !== 'none')).toBe(true)

    wrapper.unmount()
  })

  it('需求卡片排序：已使用 dac trace 排最前，已备注（未使用 dac）紧跟其后，未备注排最后', async () => {
    store.bindings = { 'TRACE-A2': 'REQ-A2' }
    store.data.requirements_index.push({
      req_name: 'TRACE-A2', committers: ['b@x.com'], workflow_session_ids: ['s1'], phases: [], features: [],
    })
    store.remarks = {
      'REQ-A1': { reason_tag: '仅改配置', note: '配置调整', author: 'Alice' },
    }
    const wrapper = mount(VersionTab, { attachTo: document.body })

    await wrapper.findAll('.ep-li')[1].trigger('click')
    await flushPromises()

    const titles = wrapper.findAll('.ep-req-slot').map((c) => c.text())
    const idxA2 = titles.findIndex((t) => t.includes('需求A2标题')) // 已用 dac
    const idxA1 = titles.findIndex((t) => t.includes('需求A1标题')) // 未用 dac，但已备注
    expect(idxA2).toBe(0)
    expect(idxA1).toBe(1)

    wrapper.unmount()
  })

  it('排除统计：已勾选排除统计的 dac 需求不计入版本需求数/dac 需求数，但需求卡片仍展示', async () => {
    store.bindings = { 'TRACE-A1': 'REQ-A1' }
    store.data.requirements_index.push({
      req_name: 'TRACE-A1', committers: ['a@x.com'], workflow_session_ids: ['s1'], phases: [], features: [],
      lines_added: 10, commit_count: 1,
    })
    const wrapper = mount(VersionTab, { attachTo: document.body })

    // 排除前：Global司机端100 唯一 dac 需求是 REQ-A1，版本落在左侧「使用 dac 版本」分组
    expect(wrapper.find('.ep-list-head-sub').text()).toContain('1 个使用 dac')
    expect(wrapper.text()).toContain('使用 dac 版本（1）')
    const dacVersionItem = wrapper.findAll('.ep-li.dac').find((c) => c.text().includes('Global司机端100'))
    expect(dacVersionItem).toBeTruthy()
    expect(dacVersionItem.text()).toContain('2 个需求')
    expect(dacVersionItem.text()).toContain('1 个 dac')

    await dacVersionItem.trigger('click')
    await flushPromises()

    // 排除前：REQ-A1（dac）+ REQ-A2 共 2 个需求，1 个 dac 需求，卡片均展示
    expect(wrapper.find('.ep-dh-badges').text()).toContain('2 个需求')
    expect(wrapper.find('.ep-dh-badges').text()).toContain('1 个 dac 需求')
    expect(wrapper.findAll('.ep-req-slot').length).toBe(2)

    store.remarks = {
      'REQ-A1': { reason_tag: '仅改配置', note: '配置调整', author: 'Alice', excluded_from_stats: true },
    }
    await flushPromises()

    // 排除后：需求数/dac 需求数各减 1，但需求卡片仍原样展示（不隐藏）
    expect(wrapper.find('.ep-dh-badges').text()).toContain('1 个需求')
    expect(wrapper.find('.ep-dh-badges').text()).not.toContain('dac 需求')
    expect(wrapper.findAll('.ep-req-slot').length).toBe(2)
    expect(wrapper.text()).toContain('需求A1标题')

    // 排除后：Global司机端100 不再有任何统计口径下的 dac 需求，版本应从「使用 dac 版本」
    // 分组迁移到「未使用 dac 版本」分组（左侧列表桶迁移）
    await wrapper.findAll('.ep-li')[0].trigger('click') // 切回概览态观察左侧分组变化
    await flushPromises()
    expect(wrapper.find('.ep-list-head-sub').text()).toContain('0 个使用 dac')
    expect(wrapper.text()).not.toContain('使用 dac 版本（1）')
    const nonDacVersionItem = wrapper.findAll('.ep-li').find((c) => !c.classes().includes('dac') && c.text().includes('Global司机端100'))
    expect(nonDacVersionItem).toBeTruthy()
    // 版本 badge 的需求数同样基于排除统计后的分组：REQ-A1 已被剔除，只剩 REQ-A2
    expect(nonDacVersionItem.text()).toContain('1 个需求')

    wrapper.unmount()
  })

  it('排除统计：版本概览态工作流质量卡为全局范围（不受排除统计影响）', async () => {
    store.bindings = { 'TRACE-A1': 'REQ-A1' }
    store.data.requirements_index.push({
      req_name: 'TRACE-A1', committers: ['a@x.com'], workflow_session_ids: ['s1'], phases: [], features: [],
    })
    const wrapper = mount(VersionTab, { attachTo: document.body })
    // 概览态：质量卡移入概览面板，作用域为全局（null），subtitle 为「全部需求累计」
    const card = wrapper.findComponent({ name: 'QualityStatsCard' })
    expect(card.exists()).toBe(true)
    expect(card.props('reqNames')).toBeNull()
    expect(card.props('subtitle')).toBe('全部需求累计')

    // 切到版本详情态：质量卡不再出现在本 Tab（仅在概览态展示）
    await wrapper.findAll('.ep-li')[1].trigger('click')
    await flushPromises()
    expect(wrapper.findComponent({ name: 'QualityStatsCard' }).exists()).toBe(false)

    wrapper.unmount()
  })
})
