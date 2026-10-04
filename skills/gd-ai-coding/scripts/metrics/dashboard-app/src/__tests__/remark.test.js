import { describe, it, expect } from 'vitest'
import { formatRemarkTitle, remarkDefaultAuthor } from '../utils/remark'

describe('formatRemarkTitle', () => {
  it('拼接 reason_tag/note/author 三段，各段缺失时跳过', () => {
    expect(formatRemarkTitle({ reason_tag: '仅改配置', note: '配置调整', author: 'Bob' }))
      .toBe('[仅改配置] 配置调整 by Bob')
    expect(formatRemarkTitle({ reason_tag: '仅改配置' })).toBe('[仅改配置]')
    expect(formatRemarkTitle({})).toBe('')
  })

  it('remark 为空返回空字符串', () => {
    expect(formatRemarkTitle(null)).toBe('')
    expect(formatRemarkTitle(undefined)).toBe('')
  })
})

describe('remarkDefaultAuthor', () => {
  it('取参与人员姓名字符串的第一个姓名（支持逗号/斜杠/顿号/空白分隔）', () => {
    expect(remarkDefaultAuthor('张三、李四')).toBe('张三')
    expect(remarkDefaultAuthor('Alice,Bob')).toBe('Alice')
    expect(remarkDefaultAuthor('Alice')).toBe('Alice')
  })

  it('空字符串或未传入时返回空字符串', () => {
    expect(remarkDefaultAuthor('')).toBe('')
    expect(remarkDefaultAuthor(undefined)).toBe('')
  })
})
