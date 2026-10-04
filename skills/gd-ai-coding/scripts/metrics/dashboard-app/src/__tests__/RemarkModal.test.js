import { describe, it, expect, beforeEach, vi } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import RemarkModal from '../components/modals/RemarkModal.vue'
import { store, showRemarkModal, hideRemarkModal } from '../store/dashboard'
import { postRemark } from '../api/remarks'

vi.mock('../api/remarks', () => ({
  postRemark: vi.fn(),
}))

describe('RemarkModal 不活跃需求备注弹窗', () => {
  beforeEach(() => {
    store.remarks = {}
    hideRemarkModal()
    postRemark.mockReset()
  })

  it('未激活时不渲染弹窗内容，激活时展示需求信息与填写人', async () => {
    const wrapper = mount(RemarkModal, { attachTo: document.body })
    expect(wrapper.find('#remark-overlay').exists()).toBe(false)

    showRemarkModal({ reqName: 'REQ-100', title: '司机端优化需求', defaultAuthor: '张三' })
    await flushPromises()

    expect(wrapper.find('#remark-overlay').exists()).toBe(true)
    expect(wrapper.text()).toContain('REQ-100')
    expect(wrapper.text()).toContain('司机端优化需求')
    // 默认填写人回填为已选 chip
    expect(wrapper.find('.author-placeholder').exists()).toBe(false)
    expect(wrapper.find('.author-chip').text()).toContain('张三')

    wrapper.unmount()
  })

  it('选择原因标签能够切换选中状态，并在输入后允许保存', async () => {
    showRemarkModal({ reqName: 'REQ-100', title: '需求100' })
    const wrapper = mount(RemarkModal, { attachTo: document.body })

    const saveBtn = wrapper.find('#remark-save')
    expect(saveBtn.attributes('disabled')).toBeDefined()

    const tagChips = wrapper.findAll('.tag-chip')
    const firstTag = tagChips[0]
    await firstTag.trigger('click')
    expect(firstTag.classes()).toContain('active')
    expect(saveBtn.attributes('disabled')).toBeUndefined()

    // 再次点击取消选中
    await firstTag.trigger('click')
    expect(firstTag.classes()).not.toContain('active')
    expect(saveBtn.attributes('disabled')).toBeDefined()

    wrapper.unmount()
  })

  it('提交备注调用 postRemark 成功后更新 store 并关闭弹窗', async () => {
    postRemark.mockResolvedValue({
      'REQ-100': { reason_tag: '非业务代码', note: '配置文件变动', author: '张三', updated_at: 1700000000000 },
    })

    showRemarkModal({ reqName: 'REQ-100', title: '需求100' })
    const wrapper = mount(RemarkModal, { attachTo: document.body })

    await wrapper.findAll('.tag-chip')[0].trigger('click') // 选中「非业务代码」
    await wrapper.find('textarea.remark-textarea').setValue('配置文件变动')
    // 填写人：打开下拉 → 点击候选 chip（多选）
    store.data = { committers: [{ committer: 'zhangsan@x', committer_name: '张三' }] }
    await wrapper.find('.author-box').trigger('click')
    await wrapper.findAll('.author-dropdown .tag-chip')[0].trigger('click')

    await wrapper.find('#remark-save').trigger('click')
    await flushPromises()

    expect(postRemark).toHaveBeenCalledWith({
      req_name: 'REQ-100',
      reason_tag: '非业务代码',
      note: '配置文件变动',
      author: '张三',
      excluded_from_stats: false,
      clear: false,
    })
    expect(store.remarks['REQ-100']).toBeDefined()
    expect(store.remarkModalVisible).toBe(false)

    wrapper.unmount()
  })

  it('存在既有备注时回填数据并支持清空备注', async () => {
    store.remarks = {
      'REQ-100': { reason_tag: '仅改配置', note: '历史备注说明', author: '李四', updated_at: 1700000000000 },
    }
    postRemark.mockResolvedValue({})

    showRemarkModal({ reqName: 'REQ-100', title: '需求100' })
    const wrapper = mount(RemarkModal, { attachTo: document.body })

    expect(wrapper.find('textarea.remark-textarea').element.value).toBe('历史备注说明')
    // 旧单值 author 回填为已选 chip
    expect(wrapper.find('.author-chip').text()).toContain('李四')
    expect(wrapper.find('#remark-clear').exists()).toBe(true)

    await wrapper.find('#remark-clear').trigger('click')
    await flushPromises()

    expect(postRemark).toHaveBeenCalledWith({
      req_name: 'REQ-100',
      clear: true,
    })
    expect(store.remarkModalVisible).toBe(false)

    wrapper.unmount()
  })

  it('填写人未选择时保存被拦截并提示，下拉支持多选与取消选中', async () => {
    store.data = {
      committers: [
        { committer: 'zhangsan@x', committer_name: '张三' },
        { committer: 'lisi@x', committer_name: '李四' },
      ],
    }
    showRemarkModal({ reqName: 'REQ-200', title: '需求200' })
    const wrapper = mount(RemarkModal, { attachTo: document.body })

    // 未选择填写人时点击保存 → alert 拦截，不调 postRemark（先选原因标签使按钮可点）
    await wrapper.findAll('.tag-chip')[0].trigger('click')
    const alertSpy = vi.spyOn(window, 'alert').mockImplementation(() => {})
    await wrapper.find('#remark-save').trigger('click')
    expect(alertSpy).toHaveBeenCalledWith('请至少选择一名填写人')
    expect(postRemark).not.toHaveBeenCalled()
    alertSpy.mockRestore()

    // 打开下拉，候选来自 committers
    await wrapper.find('.author-box').trigger('click')
    const opts = wrapper.findAll('.author-dropdown .tag-chip')
    expect(opts.map((c) => c.text().trim())).toEqual(['张三', '李四'])

    // 多选两人 → join('、')
    await opts[0].trigger('click')
    await opts[1].trigger('click')
    expect(wrapper.findAll('.author-chip').length).toBe(2)
    expect(wrapper.text()).toContain('张三 ✕')
    expect(wrapper.text()).toContain('李四 ✕')

    // 点击已选 chip 可取消选中
    await wrapper.find('.author-chip').trigger('click')
    expect(wrapper.findAll('.author-chip').length).toBe(1)
    wrapper.unmount()
  })

  it('含「、」的多值旧 author 回填为多个 chip，committer_name 缺失时回退为 committer', async () => {
    store.remarks = {
      'REQ-300': { reason_tag: '', note: '', author: '张三、李四', updated_at: 1700000000000 },
    }
    store.data = {
      committers: [
        { committer: 'zhangsan@x' },
        { committer: 'wangwu@x', committer_name: '' },
      ],
    }
    showRemarkModal({ reqName: 'REQ-300', title: '需求300' })
    const wrapper = mount(RemarkModal, { attachTo: document.body })

    const chips = wrapper.findAll('.author-chip').map((c) => c.text())
    expect(chips.length).toBe(2)
    expect(chips[0]).toContain('张三')
    expect(chips[1]).toContain('李四')

    // 打开下拉，committer_name 缺失/为空时回退为 committer
    await wrapper.find('.author-box').trigger('click')
    const opts = wrapper.findAll('.author-dropdown .tag-chip').map((c) => c.text().trim())
    expect(opts).toContain('zhangsan@x')
    expect(opts).toContain('wangwu@x')
    wrapper.unmount()
  })

  it('填写人合计超过 128 字符时保存被拦截并提示', async () => {
    store.data = {
      committers: [{ committer: 'averyverylongemailprefixname@x', committer_name: '长'.repeat(130) }],
    }
    showRemarkModal({ reqName: 'REQ-400', title: '需求400' })
    const wrapper = mount(RemarkModal, { attachTo: document.body })

    const alertSpy = vi.spyOn(window, 'alert').mockImplementation(() => {})
    await wrapper.findAll('.tag-chip')[0].trigger('click')
    await wrapper.find('.author-box').trigger('click')
    await wrapper.findAll('.author-dropdown .tag-chip')[0].trigger('click')

    await wrapper.find('#remark-save').trigger('click')
    await flushPromises()

    expect(alertSpy).toHaveBeenCalledWith('填写人合计超过 128 字符，请减少选择人数')
    expect(postRemark).not.toHaveBeenCalled()
    alertSpy.mockRestore()
    wrapper.unmount()
  })

  it('原因标签包含「工具/环境问题」', async () => {
    showRemarkModal({ reqName: 'REQ-200', title: '需求200' })
    const wrapper = mount(RemarkModal, { attachTo: document.body })
    const tagTexts = wrapper.findAll('.tag-chip').map((c) => c.text())
    expect(tagTexts).toContain('工具/环境问题')
    wrapper.unmount()
  })

  it('勾选排除统计并保存后，postRemark 请求体真实携带 excluded_from_stats: true', async () => {
    postRemark.mockResolvedValue({
      'REQ-100': { reason_tag: '非业务代码', note: '配置文件变动', author: '张三', excluded_from_stats: true, updated_at: 1700000000000 },
    })

    showRemarkModal({ reqName: 'REQ-100', title: '需求100' })
    const wrapper = mount(RemarkModal, { attachTo: document.body })

    store.data = { committers: [{ committer: 'zhangsan@x', committer_name: '张三' }] }
    await wrapper.findAll('.tag-chip')[0].trigger('click')
    await wrapper.find('textarea.remark-textarea').setValue('配置文件变动')
    await wrapper.find('.author-box').trigger('click')
    await wrapper.findAll('.author-dropdown .tag-chip')[0].trigger('click')
    await wrapper.find('input[type="checkbox"]').setValue(true)

    await wrapper.find('#remark-save').trigger('click')
    await flushPromises()

    expect(postRemark).toHaveBeenCalledWith({
      req_name: 'REQ-100',
      reason_tag: '非业务代码',
      note: '配置文件变动',
      author: '张三',
      excluded_from_stats: true,
      clear: false,
    })

    wrapper.unmount()
  })

  it('既有备注 excluded_from_stats 为 true 时，重新打开弹窗复选框应回填为勾选状态', async () => {
    store.remarks = {
      'REQ-100': { reason_tag: '仅改配置', note: '历史备注说明', author: '李四', excluded_from_stats: true, updated_at: 1700000000000 },
    }

    showRemarkModal({ reqName: 'REQ-100', title: '需求100' })
    const wrapper = mount(RemarkModal, { attachTo: document.body })

    expect(wrapper.find('input[type="checkbox"]').element.checked).toBe(true)

    wrapper.unmount()
  })
})
