import { orderedVersionGroups, reqVersionRank, currentVersionReqNames } from './version'
import { currentPhase } from './phase'

// 人员视图需求卡片与绑定弹窗候选列表共用的显示顺序：dac 需求置顶 → 当前版本置顶 →
// 已上线沉底 → 版本序。同一份需求在两处出现时先后必须一致，故规则只在此处定义一次。
// dac 判定以 req_name 集合由调用方传入：两处数据源不同（人员视图用成员需求对象、
// 绑定弹窗用 requirements_index 条目，后者不带 workflow_session_ids），集合口径统一
// 由 computeMemberAiStats 产出。
// 当前版本置顶优先于已上线沉底 —— 当前版本按发布时间 ≥ 今天判定，正常不会已上线，
// 边界情况下也让它留在分组顶部的当前版本区内部沉底，避免「当前版本」卡片被打散到末尾。
export function sortReqsByDisplayOrder(reqs, { requirementsIndex, todayStr, dacReqNames, committers = [] }) {
  const { ordered, currentGroupIndex } = orderedVersionGroups(requirementsIndex, todayStr, committers)
  const vrank = reqVersionRank(ordered)
  const curVerSet = currentVersionReqNames(currentGroupIndex >= 0 ? ordered[currentGroupIndex] : null)
  const dac = dacReqNames || new Set()
  const RANK_LAST = Number.MAX_SAFE_INTEGER
  const inSet = (r, set) => (set.has(r.req_name) ? 0 : 1)
  const released = r => (!!r.ddp && currentPhase(r.phases) === 'released' ? 1 : 0)
  const vr = r => (vrank.has(r.req_name) ? vrank.get(r.req_name) : RANK_LAST)
  const sorted = [...reqs].sort((a, b) =>
    (inSet(a, dac) - inSet(b, dac))
    || (inSet(a, curVerSet) - inSet(b, curVerSet))
    || (released(a) - released(b))
    || (vr(a) - vr(b)))
  return { sorted, curVerSet }
}
