import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import App from '../App.vue'
import { setActiveTab } from '../store/dashboard'

vi.mock('../services/refresh', () => ({
  initialLoad: vi.fn(),
  startStream: vi.fn(),
}))

describe('App.vue Tab 切换与初始渲染', () => {
  beforeEach(() => {
    setActiveTab('tab-overview')
  })

  it('首次加载完成后默认展示概览 tab，其余 tab 内容隐藏', () => {
    const wrapper = mount(App)
    expect(wrapper.find('#tab-overview').classes()).toContain('active')
    expect(wrapper.find('#tab-current').classes()).not.toContain('active')
    expect(wrapper.find('#tab-people').classes()).not.toContain('active')
    expect(wrapper.find('#tab-version').classes()).not.toContain('active')
    expect(wrapper.find('#tab-reqs').classes()).not.toContain('active')
  })

  it('点击顶部导航切换 tab，对应内容激活、其余隐藏，导航按钮激活态同步更新', async () => {
    const wrapper = mount(App)
    const peopleBtn = wrapper.findAll('.tab-btn').find((b) => b.text().includes('人员视图'))
    await peopleBtn.trigger('click')

    expect(wrapper.find('#tab-people').classes()).toContain('active')
    expect(wrapper.find('#tab-overview').classes()).not.toContain('active')
    expect(peopleBtn.classes()).toContain('active')
    const overviewBtn = wrapper.findAll('.tab-btn').find((b) => b.text().includes('概览'))
    expect(overviewBtn.classes()).not.toContain('active')
  })

  // 主题切换按钮与导航项同为 <button>，若误带 tab-btn 类会被 .nav-rail .tab-btn 样式
  // 与上面按文案定位的用例双重污染（findAll('.tab-btn') 会多出一项）。
  // 上面两个用例按文案筛选，捕获不到这个回归，故此断言不可省。
  it('主题切换按钮存在于侧边栏，且不带 tab-btn 类（避免污染导航项选择器）', () => {
    const wrapper = mount(App)
    const themeBtn = wrapper.find('.nav-theme-btn')
    expect(themeBtn.exists()).toBe(true)
    expect(themeBtn.classes()).not.toContain('active')
    expect(themeBtn.classes()).not.toContain('tab-btn')
    expect(wrapper.findAll('.nav-rail .tab-btn')).toHaveLength(6)
  })
})
