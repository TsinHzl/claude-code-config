import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import ReqCard from '../components/shared/ReqCard.vue'
import { store, hideRemarkModal } from '../store/dashboard'

// 普通 DDP 需求（未绑定 dac trace）：验证「已排除统计」的排除统计标记功能已复制到版本视图/
// 人员视图共用的 ReqCard.vue（此前该按钮只存在于概览看板 OverviewTab.vue）。
function plainReq(overrides = {}) {
  return {
    req_name: 'REQ-100',
    phases: [],
    features: [],
    rd_list: ['bob-id'],
    ddp: { title: '需求100' },
    ...overrides,
  }
}

describe('ReqCard 备注功能（版本视图/人员视图复用概览看板同款备注按钮）', () => {
  beforeEach(() => {
    store.bindings = {}
    store.data = { committers: [{ committer: 'bob-id', committer_name: 'Bob' }], requirements_index: [] }
    store.remarks = {}
    hideRemarkModal()
  })

  it('无备注时展示「+ 备注」按钮，点击后唤起备注弹窗并带上默认填写人', async () => {
    const wrapper = mount(ReqCard, { props: { req: plainReq() } })

    const btn = wrapper.find('.ep-remark-btn')
    expect(btn.exists()).toBe(true)
    expect(btn.text()).toBe('+ 备注')
    expect(wrapper.find('.ep-remark-chip').exists()).toBe(false)

    await btn.trigger('click')

    expect(store.remarkModalVisible).toBe(true)
    expect(store.remarkModalReqName).toBe('REQ-100')
    expect(store.remarkModalReqTitle).toBe('需求100')
    expect(store.remarkModalDefaultAuthor).toBe('Bob')

    wrapper.unmount()
  })

  it('已备注时展示原因标签 chip 而非「+ 备注」按钮，点击 chip 同样唤起弹窗', async () => {
    store.remarks = {
      'REQ-100': { reason_tag: '仅改配置', note: '配置调整', author: 'Bob' },
    }
    const wrapper = mount(ReqCard, { props: { req: plainReq() } })

    const chip = wrapper.find('.ep-remark-chip')
    expect(chip.exists()).toBe(true)
    expect(chip.text()).toBe('仅改配置')
    expect(wrapper.find('.ep-remark-btn').exists()).toBe(false)

    await chip.trigger('click')
    expect(store.remarkModalVisible).toBe(true)
    expect(store.remarkModalReqName).toBe('REQ-100')

    wrapper.unmount()
  })

  it('excluded_from_stats 为 true 时展示「已排除统计」徽章', () => {
    store.remarks = {
      'REQ-100': { reason_tag: '仅改配置', excluded_from_stats: true },
    }
    const wrapper = mount(ReqCard, { props: { req: plainReq() } })

    expect(wrapper.text()).toContain('已排除统计')

    wrapper.unmount()
  })

  it('纯 dac trace（无 ddp）不展示备注入口——备注针对 DDP 需求，trace 本身没有对应的备注 key', () => {
    const traceReq = {
      req_name: 'TRACE-1',
      phases: [],
      features: [],
      workflow_session_ids: ['s1'],
      committers: ['bob-id'],
    }
    const wrapper = mount(ReqCard, { props: { req: traceReq, committerEmail: 'bob-id' } })

    expect(wrapper.find('.ep-remark-btn').exists()).toBe(false)
    expect(wrapper.find('.ep-remark-chip').exists()).toBe(false)

    wrapper.unmount()
  })

  it('已绑定 dac trace 的 DDP 需求（isMerged）不展示备注入口——已使用 dac 的需求不需要备注，但仍保留原有的「已排除统计」徽章', () => {
    const mergedReq = {
      req_name: 'REQ-100',
      phases: [],
      features: [],
      rd_list: ['bob-id'],
      ddp: { title: '需求100' },
      workflow_session_ids: ['s1'],
      committers: ['bob-id'],
    }
    store.remarks = {
      'REQ-100': { reason_tag: '仅改配置', excluded_from_stats: true },
    }
    const wrapper = mount(ReqCard, { props: { req: mergedReq, committerEmail: 'bob-id' } })

    expect(wrapper.find('.ep-remark-btn').exists()).toBe(false)
    expect(wrapper.find('.ep-remark-chip').exists()).toBe(false)
    expect(wrapper.text()).toContain('已排除统计')

    wrapper.unmount()
  })

  it('is_technical 普通 DDP 需求展示「技术」角标', () => {
    const wrapper = mount(ReqCard, { props: { req: plainReq({ is_technical: true }) } })

    const badge = wrapper.find('.ep-tech-badge')
    expect(badge.exists()).toBe(true)
    expect(badge.text()).toBe('技术')

    wrapper.unmount()
  })

  it('is_technical 需求已绑定 dac trace（isMerged）时角标与卡片 tech 强调均生效', () => {
    const mergedReq = plainReq({ is_technical: true, workflow_session_ids: ['s1'], committers: ['bob-id'] })
    const wrapper = mount(ReqCard, { props: { req: mergedReq, committerEmail: 'bob-id' } })

    expect(wrapper.find('.ep-tech-badge').text()).toBe('技术')
    expect(wrapper.find('.ep-req.tech').exists()).toBe(true)

    wrapper.unmount()
  })
})
