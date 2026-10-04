// 备注功能（不活跃需求原因备注/排除统计）在概览看板、版本视图、人员视图三处入口共用同一套
// 格式化逻辑，下沉到此处避免各自维护导致行为漂移。

export function formatRemarkTitle(remark) {
  if (!remark) return ''
  const parts = []
  if (remark.reason_tag) parts.push(`[${remark.reason_tag}]`)
  if (remark.note) parts.push(remark.note)
  if (remark.author) parts.push(`by ${remark.author}`)
  return parts.join(' ')
}

// 打开备注弹窗时的默认填写人：取参与人员姓名字符串（形如「张三、李四」）的第一个姓名。
export function remarkDefaultAuthor(rdNames) {
  return rdNames ? rdNames.split(/[,/、\s]/)[0] : ''
}
