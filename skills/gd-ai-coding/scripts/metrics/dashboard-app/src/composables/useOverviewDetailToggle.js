import { nextTick, watch } from 'vue'

// 人员视图 / 当前版本 / 版本视图三个 tab 共用的「概览态 ↔ 详情态切换 + 选中项滚动定位」逻辑
// （design.md 决策 1 实施约束）。选中项失效时自动回退概览态对三个 tab 都适用；滚动定位仅
// 人员视图与当前版本 tab 需要（版本视图 tab 概览卡片无点击跳转详情行为），不传
// selectionKey/isValidKey 即可只复用「回退概览态」这部分。
export function useOverviewDetailToggle({ list, isDetailMode, isSelected, toOverview, selectionKey, isValidKey }) {
  watch(list, () => {
    if (isDetailMode() && !list.value.some(isSelected)) toOverview()
  })

  const itemRefs = new Map()
  function setItemRef(key, el) {
    if (el) itemRefs.set(key, el)
    else itemRefs.delete(key)
  }

  if (selectionKey) {
    watch(selectionKey, async (key) => {
      if (!isDetailMode() || !isValidKey(key)) return
      await nextTick()
      itemRefs.get(key)?.scrollIntoView({ block: 'nearest' })
    })
  }

  return { setItemRef }
}
