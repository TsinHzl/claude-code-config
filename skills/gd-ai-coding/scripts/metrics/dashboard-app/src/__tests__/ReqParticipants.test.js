import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import ReqParticipants from '../components/shared/ReqParticipants.vue'
import { store } from '../store/dashboard'

describe('ReqParticipants', () => {
  beforeEach(() => {
    store.data = {
      committers: [
        { committer: 'a*@x.com', committer_name: 'Alice' },
        { committer: 'b*@x.com', committer_name: 'Bob' },
        { committer: 'x*@x.com', committer_name: '田啸' },
      ],
    }
  })

  it('inline 模式渲染为单行紧凑 span，姓名用「、」拼接且不渲染「参与人员」区块', () => {
    const wrapper = mount(ReqParticipants, {
      props: { inline: true, rdListEmails: ['a*@x.com', 'b*@x.com'], traceReqs: [] },
    })

    expect(wrapper.element.tagName).toBe('SPAN')
    expect(wrapper.text()).toBe('Alice、Bob')
    expect(wrapper.text()).not.toContain('参与人员')

    wrapper.unmount()
  })

  it('非 inline 模式渲染「参与人员（N）」区块与每人一个 chip', () => {
    const wrapper = mount(ReqParticipants, {
      props: { rdListEmails: ['a*@x.com', 'b*@x.com'], traceReqs: [] },
    })

    expect(wrapper.text()).toContain('参与人员（2）')
    expect(wrapper.findAll('.ep-bd')).toHaveLength(2)

    wrapper.unmount()
  })

  it('rd_list 与绑定 trace 的 committers 取并集去重', () => {
    const wrapper = mount(ReqParticipants, {
      props: {
        inline: true,
        rdListEmails: ['a*@x.com'],
        traceReqs: [{ committers: ['a*@x.com', 'b*@x.com'] }],
      },
    })

    expect(wrapper.text()).toBe('Alice、Bob')

    wrapper.unmount()
  })

  it('排除名单中的成员不出现；全部被排除时不渲染任何内容', () => {
    const wrapper = mount(ReqParticipants, {
      props: { inline: true, rdListEmails: ['x*@x.com', 'a*@x.com'], traceReqs: [] },
    })
    expect(wrapper.text()).toBe('Alice')
    wrapper.unmount()

    const empty = mount(ReqParticipants, {
      props: { inline: true, rdListEmails: ['x*@x.com'], traceReqs: [] },
    })
    expect(empty.find('span').exists()).toBe(false)
    empty.unmount()
  })
})
