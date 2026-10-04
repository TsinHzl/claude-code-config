// DDP 需求号 → 网页链接。R- 前缀=需求(requirement/story)，T- 前缀=任务(issue/story)；
// 其余（DAC trace 自定义名）无对应 DDP 页面，降级为纯文本，不误伤。
export function ddpUrl(id) {
  const s = String(id ?? '')
  if (s.startsWith('R-')) return 'https://ddp.intra.xiaojukeji.com/requirement/story/' + encodeURIComponent(s)
  if (s.startsWith('T-')) return 'https://ddp.intra.xiaojukeji.com/issue/story/' + encodeURIComponent(s)
  return ''
}
