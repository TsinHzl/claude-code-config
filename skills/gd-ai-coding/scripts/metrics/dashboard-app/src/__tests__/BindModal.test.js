import { describe, it, expect, beforeEach, vi } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import BindModal from '../components/modals/BindModal.vue'
import { store, showBindModal } from '../store/dashboard'
import { postBind } from '../api/bindings'

vi.mock('../api/bindings', () => ({
  postBind: vi.fn(),
}))

function seedData() {
  store.data = {
    committers: [
      {
        committer: 'user-alpha',
        requirements: [
          { req_name: 'REQ-1', ddp: { title: '需求一号' } },
          { req_name: 'REQ-2', ddp: { title: '需求二号' } },
        ],
      },
    ],
    requirements_index: [
      { req_name: 'REQ-1', ddp: { title: '需求一号' } },
      { req_name: 'REQ-2', ddp: { title: '需求二号' } },
    ],
  }
  store.bindings = {}
}

describe('BindModal 绑定 DDP 需求弹窗', () => {
  beforeEach(() => {
    seedData()
    showBindModal('TRACE-1', ['user-alpha'])
    postBind.mockReset()
  })

  it('搜索过滤仅显示标题命中的候选需求，其余隐藏', async () => {
    const wrapper = mount(BindModal, { attachTo: document.body })

    await wrapper.find('.bind-search').setValue('一号')
    await flushPromises()

    const items = wrapper.findAll('.bind-item')
    const visible = items.filter((i) => i.element.style.display !== 'none')
    const hidden = items.filter((i) => i.element.style.display === 'none')
    expect(visible.some((i) => i.text().includes('需求一号'))).toBe(true)
    expect(hidden.some((i) => i.text().includes('需求二号'))).toBe(true)

    wrapper.unmount()
  })

  it('候选项展示版本号与上线时间，缺失时按 expected_release / 未排期 兜底', async () => {
    store.data.requirements_index = [
      { req_name: 'REQ-1', ddp: { title: '需求一号', release_version_name: 'Global司机端7.10.42', release_version_time: '2026-08-30' } },
      { req_name: 'REQ-2', ddp: { title: '需求二号', expected_release: '2026-09-15' } },
      { req_name: 'REQ-3', ddp: { title: '需求三号' } },
    ]
    store.data.committers[0].requirements.push({ req_name: 'REQ-3', ddp: { title: '需求三号' } })
    const wrapper = mount(BindModal, { attachTo: document.body })

    const items = wrapper.findAll('.bind-item')
    const itemText = (title) => items.find((i) => i.text().includes(title)).text()
    expect(itemText('需求一号')).toContain('Global司机端7.10.42')
    expect(itemText('需求一号')).toContain('2026-08-30')
    expect(itemText('需求二号')).toContain('预计 2026-09-15')
    expect(itemText('需求三号')).toContain('未排期')

    // 徽章文本不参与搜索：过滤读的是 data-search（标题 + 需求 ID），非 textContent
    await wrapper.find('.bind-search').setValue('7.10.42')
    await flushPromises()
    expect(items.filter((i) => i.element.style.display !== 'none')).toHaveLength(0)

    wrapper.unmount()
  })

  it('候选项顺序与人员视图需求卡片一致：dac 置顶 → 当前版本置顶 → 已上线沉底 → 版本序', () => {
    // fixture 与 PeopleTab.test.js「需求明细排序」同款，期望数组亦完全相同
    const makeReq = (name, version, time, { dac = false, released = false } = {}) => ({
      req_name: name,
      ddp: { title: name, release_version_name: version, release_version_time: time },
      phases: [{ phase: released ? 'released' : 'developing' }],
      ...(dac ? { workflow_session_ids: ['s-' + name], committers: ['user-alpha'] } : {}),
    })
    const reqs = [
      makeReq('v42-dac', 'Global司机端7.10.42', '2026-07-30', { dac: true, released: true }),
      makeReq('v38-dac', 'Global司机端7.10.38', '2026-06-30', { dac: true }),
      makeReq('cur-dac', 'Global司机端7.10.60', '2099-01-01', { dac: true }),
      makeReq('v42-non', 'Global司机端7.10.42', '2026-07-30', { released: true }),
      makeReq('v38-non', 'Global司机端7.10.38', '2026-06-30'),
    ]
    store.data = {
      committers: [{ committer: 'user-alpha', requirements: reqs }],
      requirements_index: reqs,
    }
    const wrapper = mount(BindModal, { attachTo: document.body })

    expect(wrapper.findAll('.bind-item-title').map(n => n.text()))
      .toEqual(['cur-dac', 'v38-dac', 'v42-dac', 'v38-non', 'v42-non'])

    wrapper.unmount()
  })

  it('选中候选项并确认绑定后，写入新绑定关系并关闭弹窗', async () => {
    postBind.mockResolvedValue({ 'TRACE-1': 'REQ-2' })
    const wrapper = mount(BindModal, { attachTo: document.body })

    const items = wrapper.findAll('.bind-item')
    const target = items.find((i) => i.text().includes('需求二号'))
    await target.trigger('click')
    await wrapper.find('#bind-confirm').trigger('click')
    await flushPromises()

    expect(postBind).toHaveBeenCalledWith('TRACE-1', 'REQ-2')
    expect(store.bindings).toEqual({ 'TRACE-1': 'REQ-2' })
    expect(store.bindModalVisible).toBe(false)

    wrapper.unmount()
  })
})
