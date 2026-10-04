import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import EpIcon from '../components/shared/EpIcon.vue'

// 与 EpIcon.vue 的 ICONS 表一一对应（表内每个 name 都有实际使用点，无备用死图标）
const NAMES = [
  'bar', 'users', 'file',
  'user', 'cube', 'donut', 'star', 'check', 'search', 'clock', 'refresh',
  'link', 'scissors', 'trash', 'rocket', 'bot', 'tag', 'calendar', 'x', 'skip', 'alert',
]

describe('EpIcon', () => {
  it('图标表覆盖 21 个 name，每个都渲染出至少一个图形元素', () => {
    expect(NAMES).toHaveLength(21)

    for (const name of NAMES) {
      const wrapper = mount(EpIcon, { props: { name } })
      const svg = wrapper.find('svg')

      expect(svg.exists(), name).toBe(true)
      expect(svg.attributes('viewBox')).toBe('0 0 24 24')
      expect(svg.element.querySelectorAll('path, circle, rect, polyline').length, name).toBeGreaterThan(0)

      wrapper.unmount()
    }
  })

  it('默认描边模式：fill=none + stroke=currentColor，size / stroke 可覆盖', () => {
    const wrapper = mount(EpIcon, { props: { name: 'user', size: 20, stroke: 2.5 } })
    const svg = wrapper.find('svg')

    expect(svg.attributes('fill')).toBe('none')
    expect(svg.attributes('stroke')).toBe('currentColor')
    expect(svg.attributes('width')).toBe('20')
    expect(svg.attributes('height')).toBe('20')
    expect(svg.attributes('stroke-width')).toBe('2.5')

    wrapper.unmount()
  })

  it('star 为唯一实心图标：fill=currentColor 且不描边', () => {
    const wrapper = mount(EpIcon, { props: { name: 'star' } })
    const svg = wrapper.find('svg')

    expect(svg.attributes('fill')).toBe('currentColor')
    expect(svg.attributes('stroke')).toBe('none')

    wrapper.unmount()
  })

  it('未知 name 渲染空且不抛异常', () => {
    const wrapper = mount(EpIcon, { props: { name: 'not-an-icon' } })

    expect(wrapper.find('svg').exists()).toBe(false)
    expect(wrapper.html()).not.toContain('<svg')
    expect(wrapper.text()).toBe('')

    wrapper.unmount()
  })
})
