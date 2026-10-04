import { PARTICIPANT_EXCLUDED_NAMES } from './participants'
import { nameForEmail } from './people'
import { currentPhase } from './phase'
import { getDdpToTrace, enrichReq } from './enrich'

function estimatedHalfMonthBucket(expectedRelease) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(expectedRelease || '')
  if (!m) return null
  const [, yyyy, mm, dd] = m
  const mmNum = parseInt(mm, 10)
  const ddNum = parseInt(dd, 10)
  if (mmNum < 1 || mmNum > 12 || ddNum < 1 || ddNum > 31) return null
  const half = ddNum <= 15 ? 'H1' : 'H2'
  return {
    key: `${yyyy}-${mm}-${half}`,
    time: `${yyyy}-${mm}-${half === 'H1' ? '01' : '16'}`,
    name: `${yyyy}-${mm} ${half === 'H1' ? '上半月' : '下半月'}`,
  }
}

// 版本视图仅展示司机端版本；非司机端版本（乘客端 / 99 Pay / DiDi Food / Fleet端）的需求在此视图隐藏，
// 但仍保留在人员视图 / 需求视图与顶部计数（本部门人员参与的需求不从数据中移除）
const NON_DRIVER_VERSION_KEYWORDS = ['Global乘客端', '99 Pay', 'DiDi Food', 'Fleet端']
export function isNonDriverVersion(name) {
  return NON_DRIVER_VERSION_KEYWORDS.some(k => (name || '').includes(k))
}

// 备注排除：剔除需求备注勾选「排除统计」（excluded_from_stats）的需求，技术类需求（is_technical）
// 不在此层剔除——是否剔除技术需求由消费方语义决定：统计侧经 filterExcludedFromStats 继续剔除，
// 榜单/详情展示侧（如 CurVersionTab 成员榜单）需保留技术需求（仅参与技术需求的成员仍须入选、
// 其技术卡可达），故只剔除备注排除项。group 为空时原样返回（保留 null 语义，不强行转换成空分组）。
export function filterRemarksExcluded(group, remarks) {
  if (!group) return group
  return {
    ...group,
    items: (group.items || []).filter(({ r }) => !remarks?.[r?.req_name]?.excluded_from_stats),
  }
}

// 排除统计：需求备注勾选 excluded_from_stats 或技术类需求（is_technical）命中后，该需求仍在
// 所有视图正常展示（不隐藏），但不计入任何统计口径（需求数、dac 需求数、成员维度统计、趋势图）。
// 所有消费版本分组统计的调用方（概览/当前版本/趋势图）统一通过本函数得到过滤后的分组，避免
// 各处重复实现过滤表达式导致口径漂移。group 为空时原样返回（保留 null 语义，不强行转换成空分组）。
export function filterExcludedFromStats(group, remarks) {
  const g = filterRemarksExcluded(group, remarks)
  if (!g) return g
  return {
    ...g,
    items: (g.items || []).filter(({ r }) => !r?.is_technical),
  }
}

/**
 * 版本组 items 是 DDP 需求；质量卡 / 折线要用 DAC 工作流名。
 * 直连（本身带 workflow_session_ids）收自身；其余经 ddpToTrace 映射。
 * group 为空返回 []（调用方用 null 表示「全局」，不要把空数组当全局）。
 */
export function groupTraceReqNames(group, ddpToTrace) {
  if (!group) return []
  const names = new Set()
  const map = ddpToTrace || {}
  for (const item of group.items || []) {
    const r = item?.r
    if (!r) continue
    if ((r.workflow_session_ids || []).length > 0) names.add(r.req_name)
    if (r.ddp) {
      for (const n of (map[r.req_name] || [])) names.add(n)
    }
  }
  return [...names]
}

function dateKey(s) {
  const m = /^(\d{4}-\d{2}-\d{2})/.exec(s || '')
  return m ? m[1] : ''
}

export function groupReqsByVersion(requirementsIndex, committers = []) {
  const idx = requirementsIndex || []
  const groupMap = new Map()
  const timeToNamed = new Map()
  idx.forEach(r => {
    const d = r.ddp; if (!d) return
    const nm = d.release_version_name || '', tk = dateKey(d.release_version_time)
    if (nm && tk && isCanonicalDriverVersion(nm) && !timeToNamed.has(tk)) timeToNamed.set(tk, { name: nm, time: d.release_version_time })
  })
  idx.forEach(r => {
    if (!r.ddp) return
    if (isNonDriverVersion(r.ddp.release_version_name)) return
    if (reqCommitterNames(r, committers) === '' && !(r.workflow_session_ids || []).length) return
    const name = r.ddp.release_version_name || ''
    let key, groupInit
    if (name) {
      key = name
      groupInit = { name, time: r.ddp.release_version_time || '', isUnassigned: false, isEstimated: false }
    } else {
      const mapped = timeToNamed.get(dateKey(r.ddp.expected_release))
      const bucket = estimatedHalfMonthBucket(r.ddp.expected_release)
      if (mapped) {
        key = mapped.name
        groupInit = { name: mapped.name, time: mapped.time, isUnassigned: false, isEstimated: false }
      } else if (bucket) {
        key = bucket.key
        groupInit = { name: bucket.name, time: bucket.time, isUnassigned: false, isEstimated: true }
      } else {
        key = '__unassigned__'
        groupInit = { name: '未分配版本', time: '', isUnassigned: true, isEstimated: false }
      }
    }
    if (!groupMap.has(key)) groupMap.set(key, { ...groupInit, items: [] })
    const g = groupMap.get(key)
    g.items.push({ r })
    if (name) {
      if (!g._timeVotes) g._timeVotes = {}
      const t = r.ddp.release_version_time
      if (t) g._timeVotes[t] = (g._timeVotes[t] || 0) + 1
    }
  })
  groupMap.forEach(g => {
    if (!g._timeVotes) return
    let best = g.time, bestN = -1
    for (const [t, n] of Object.entries(g._timeVotes)) {
      if (n > bestN) { best = t; bestN = n }
    }
    g.time = best
    delete g._timeVotes
  })
  return Array.from(groupMap.values())
}

function versionNumParts(name) {
  const m = (name || '').match(/(\d+(?:\.\d+)*)\s*$/)
  return m ? m[1].split('.').map(Number) : null
}

export function shortVersionLabel(name) {
  const m = (name || '').match(/(\d+(?:\.\d+)*)\s*$/)
  return m ? m[1] : (name || '')
}

export function compareVersionDesc(a, b) {
  const pa = versionNumParts(a), pb = versionNumParts(b)
  if (!pa && !pb) return 0
  if (!pa) return 1
  if (!pb) return -1
  const len = Math.max(pa.length, pb.length)
  for (let i = 0; i < len; i++) {
    const x = pa[i] || 0, y = pb[i] || 0
    if (x !== y) return y - x
  }
  return 0
}

// 当前版本仅能是规范的「Global司机端」正式版本，排除 DVM_Global司机端、
// [区间]Global司机端 等变体（含"Global司机端"子串但非正式发布版本）
export function isCanonicalDriverVersion(name) {
  return /^Global司机端\d/.test(name || '')
}

export function orderVersionGroups(groups, todayStr) {
  const unassigned = groups.filter(g => g.isUnassigned)
  const estimated = groups.filter(g => g.isEstimated)
  const named = groups.filter(g => !g.isUnassigned && !g.isEstimated)

  const futureOrToday = named.filter(g => g.time && g.time >= todayStr && isCanonicalDriverVersion(g.name))
  const currentGroup = futureOrToday.length
    ? futureOrToday.reduce((min, g) => (g.time < min.time ? g : min))
    : null

  const rest = named.filter(g => g !== currentGroup)
  rest.sort((a, b) => compareVersionDesc(a.name, b.name))

  estimated.sort((a, b) => b.time.localeCompare(a.time))

  const ordered = []
  if (currentGroup) ordered.push(currentGroup)
  ordered.push(...rest)
  ordered.push(...estimated)
  ordered.push(...unassigned)

  const currentGroupIndex = currentGroup ? ordered.indexOf(currentGroup) : -1
  return { ordered, currentGroupIndex }
}

// 共享：与版本视图左栏完全同序的分组+排序。todayStr 由调用方传入（一般取 new Date()），
// 避免工具函数内部隐式依赖当前时间，便于测试与复用。
export function orderedVersionGroups(requirementsIndex, todayStr, committers = []) {
  return orderVersionGroups(groupReqsByVersion(requirementsIndex, committers), todayStr)
}

export function reqVersionRank(ordered) {
  const rank = new Map()
  ;(ordered || []).forEach((g, i) => (g.items || []).forEach(({ r }) => {
    if (r && r.req_name != null && !rank.has(r.req_name)) rank.set(r.req_name, i)
  }))
  return rank
}

export function currentVersionGroup(requirementsIndex, todayStr, committers = []) {
  const { ordered, currentGroupIndex } = orderedVersionGroups(requirementsIndex, todayStr, committers)
  return currentGroupIndex >= 0 ? ordered[currentGroupIndex] : null
}

export function currentVersionReqNames(curGroup) {
  return new Set((curGroup?.items || []).map(({ r }) => r && r.req_name).filter(Boolean))
}

// 「正式版本窗口」：仅保留规范命名版本，按版本号升序排列后以当前版本为锚点，向前取 before 个、
// 向后取 after 个，供趋势图从左到右绘制。当前版本前后不足时按实际数量返回，不回填。
// 当前版本在结果中的位置不固定（截取后可能落在数组中间甚至末尾之外无未来版本时才在末尾），
// 因此每个返回项都显式带上 isCurrent 标记，下游禁止再假设"末位 = 当前版本"。
export function recentCanonicalVersions(requirementsIndex, todayStr, before = 3, after = 3, committers = []) {
  const { ordered, currentGroupIndex } = orderedVersionGroups(requirementsIndex, todayStr, committers)
  const named = ordered.filter(g => isCanonicalDriverVersion(g.name))
  const ascending = [...named].sort((a, b) => -compareVersionDesc(a.name, b.name))
  const curGroup = currentGroupIndex >= 0 ? ordered[currentGroupIndex] : null
  const curIdx = curGroup ? ascending.indexOf(curGroup) : -1
  const sliced = curIdx === -1
    ? ascending.slice(-(before + after + 1))
    : ascending.slice(Math.max(0, curIdx - before), Math.min(ascending.length, curIdx + after + 1))
  return sliced.map(g => ({ ...g, isCurrent: g === curGroup }))
}

// 不活跃需求 Top N：当前版本内完全未使用 dac trace 的 DDP 需求（绑定的 trace 必须真实存在于
// requirementsIndex 才算已使用，口径与 versionDacCount 一致），且至少有 1 位有效司机端参与 RD
// （经 PARTICIPANT_EXCLUDED_NAMES 过滤后非空），按 last_commit_ts（缺失回退 reported_at）
// 升序取前 limit 个（最久未动的排前面）。技术类需求（is_technical）不进入不活跃榜单：
// 与 filterExcludedFromStats 的统计口径一致，技术需求不参与任何统计聚合（其本身无 dac 采用
// 语义，列入不活跃只会制造噪音），但仍保留在版本/人员视图的展示侧。
export function inactiveRequirements(g, requirementsIndex, bindings, limit = 5, committers = []) {
  if (!g) return []
  const reqIdx = requirementsIndex || []
  const ddpToTrace = getDdpToTrace(bindings)
  return g.items.filter(({ r }) => !r?.is_technical)
    .filter(({ r }) => !(ddpToTrace[r.req_name] || []).some(n => reqIdx.some(x => x.req_name === n)))
    .filter(({ r }) => reqCommitterNames(r, committers) !== '')
    .map(({ r }) => ({ r, ts: r.last_commit_ts || r.reported_at || null }))
    .filter(x => x.ts)
    .sort((a, b) => a.ts - b.ts)
    .slice(0, limit)
    .map(x => x.r)
}

// 需求对应的所有 RD 姓名：r.rd_list（全部参与 RD）与 r.committers（RD Owner）取并集去重后
// 映射为姓名（未在 committers 名单中的 fallback 为邮箱前缀，与 nameForEmail 其他调用处保持一致），
// 用「、」拼接。与 ReqsTab.vue 的 ddpOwnerRows 采用同一并集口径，避免只指定了 rd_list、未指定
// RD Owner 的需求显示为空。
export function reqCommitterNames(r, committers) {
  const emails = [...new Set([...(r.rd_list || []), ...(r.committers || [])])]
  return emails
    .map(email => nameForEmail(email, committers))
    .filter(name => name && !PARTICIPANT_EXCLUDED_NAMES.has(name))
    .join('、')
}


// 指定版本分组「有 dac trace 数据的人员」：以绑定到该版本 DDP 需求的 trace 的 committers 为准
// 认定 dac 成员，reqs 收录该成员在该版本参与的全部 DDP 需求（dac 绑定需求 + rd_list 参与但未绑
// trace 的需求）；dacReqSet 单独记录 dac 绑定需求供「N 个 dac 需求」计数。g 为空返回 []。
export function versionDacMembers(g, requirementsIndex, committers, bindings) {
  if (!g) return []
  const idx = requirementsIndex || []
  const ddpToTrace = getDdpToTrace(bindings)
  const map = new Map()
  ;(g.items || []).forEach(({ r }) => {
    // 技术类需求（is_technical）不产生 dac 成员身份，其 trace 也不计入任何 dac 统计（行数/提交/
    // dacReqCount/reqCount）；其参与关系仅经下方 rd_list 循环收进既有 dac 成员的 reqs 供详情卡展示。
    if (r.is_technical) return
    const boundTraces = (ddpToTrace[r.req_name] || [])
      .flatMap(n => idx.filter(x => x.req_name === n))
    boundTraces.forEach(t => (t.committers || []).filter(Boolean).forEach(email => {
      const name = nameForEmail(email, committers)
      if (PARTICIPANT_EXCLUDED_NAMES.has(name)) return
      let m = map.get(name)
      if (!m) { m = { name, email, reqs: new Map(), dacReqSet: new Set(), traceSet: new Set(), lines: 0, commits: 0, statReqCount: 0 }; map.set(name, m) }
      if (!m.reqs.has(r.req_name)) { m.reqs.set(r.req_name, email); m.statReqCount++ }
      m.dacReqSet.add(r.req_name)
      if (!m.traceSet.has(t.req_name)) {
        m.traceSet.add(t.req_name)
        m.lines += (t.lines_added || 0)
        m.commits += (t.commit_count || 0)
      }
    }))
  })
  ;(g.items || []).forEach(({ r }) => {
    (r.rd_list || []).filter(Boolean).forEach(email => {
      const m = map.get(nameForEmail(email, committers))
      if (!m) return
      // reqs 全量收录（含技术需求，供成员详情卡反查出技术卡）；但仅非技术需求计入 reqCount。
      if (!m.reqs.has(r.req_name)) { m.reqs.set(r.req_name, email); if (!r.is_technical) m.statReqCount++ }
    })
  })
  return [...map.values()]
    .map(m => ({ ...m, dacReqCount: m.dacReqSet.size, reqCount: m.statReqCount }))
    .sort((a, b) => (b.dacReqCount - a.dacReqCount) || (b.lines - a.lines) || (b.commits - a.commits) || a.name.localeCompare(b.name))
}

// 指定版本分组「参与但未使用 dac trace 的人员」：以绑定到该版本 DDP 需求的司机端参与 RD（rd_list）
// 为全集，减去已在 dac 成员列表（dacNames）中的人。
export function versionNonDacMembers(g, dacNames, committers) {
  if (!g) return []
  const excluded = dacNames instanceof Set ? dacNames : new Set(dacNames || [])
  const map = new Map()
  ;(g.items || []).forEach(({ r }) => {
    (r.rd_list || []).filter(Boolean).forEach(email => {
      const name = nameForEmail(email, committers)
      if (PARTICIPANT_EXCLUDED_NAMES.has(name)) return
      if (excluded.has(name)) return
      let m = map.get(name)
      if (!m) { m = { name, email, reqs: new Map(), doneCount: 0, statReqCount: 0 }; map.set(name, m) }
      if (m.reqs.has(r.req_name)) return
      // reqs 全量收录（含技术需求：仅参与技术需求的成员据此仍入选榜单、详情卡可达），但技术需求
      // 不计 reqCount/doneCount（成员 badge 保持非技术口径，可呈现「0 个需求」）。
      m.reqs.set(r.req_name, email)
      if (r.is_technical) return
      m.statReqCount++
      if (currentPhase(r.phases) === 'released') m.doneCount++
    })
  })
  return [...map.values()]
    .map(m => ({ ...m, isNonDac: true, reqCount: m.statReqCount, dacReqCount: 0, lines: 0, commits: 0 }))
    .sort((a, b) => (b.reqCount - a.reqCount) || (b.doneCount - a.doneCount) || a.name.localeCompare(b.name))
}

// 版本内全部参与者（dac trace committers + rd_list 参与者）及各自在当前版本内的最后 dac 活跃时间
// （绑定 trace 的 last_commit_ts 缺失时回退 reported_at，多条取最大值），仅在 rd_list 出现、
// 当前版本无 trace 的人 ts 为 null
// （排除 PARTICIPANT_EXCLUDED_NAMES）。刻意不引入 personalTotals —— vibe 个人总量是跨仓库全局口径，
// 与「当前版本是否用过 dac」无关，混入会让同一个人同时出现在活跃/不活跃两张卡片。email 记录该成员
// 的邮箱（供跳转定位）；hasDacTrace 标记是否在当前版本留下过任意 dac trace（与 ts 独立：trace 的
// last_commit_ts 与 reported_at 可能同时缺失）；reqCount 为该成员在当前版本参与的 DDP 需求去重数（dac 绑定需求 +
// rd_list 参与需求，口径与 versionNonDacMembers.reqCount 一致）；dacReqCount 为其中已绑定 dac
// trace 的需求数（reqCount 的子集，口径与 versionDacMembers.dacReqCount 一致）。
// 供 versionInactiveMembers / versionActiveMembers 共用采集逻辑，各自再过滤排序截取。g 为空返回 []。
function versionMemberTimes(g, requirementsIndex, committers, bindings) {
  if (!g) return []
  const idx = requirementsIndex || []
  const ddpToTrace = getDdpToTrace(bindings)
  const registered = new Map()
  const ensure = (name, email) => {
    if (!name || PARTICIPANT_EXCLUDED_NAMES.has(name)) return
    const cur = registered.get(name)
    if (!cur) registered.set(name, { email: email || null, ts: null, hasDacTrace: false, reqs: new Set(), dacReqs: new Set() })
    else if (email && !cur.email) registered.set(name, { ...cur, email })
  }
  const addReq = (name, reqName, isDac) => {
    if (!name || !reqName || PARTICIPANT_EXCLUDED_NAMES.has(name)) return
    const cur = registered.get(name)
    if (!cur) return
    cur.reqs.add(reqName)
    if (isDac) cur.dacReqs.add(reqName)
  }
  const markDacTrace = (name) => {
    if (!name || PARTICIPANT_EXCLUDED_NAMES.has(name)) return
    const cur = registered.get(name)
    if (cur && !cur.hasDacTrace) registered.set(name, { ...cur, hasDacTrace: true })
  }
  const consider = (name, ts) => {
    if (!name || !ts || PARTICIPANT_EXCLUDED_NAMES.has(name)) return
    const cur = registered.get(name)
    if (!cur) return
    if (!cur.ts || ts > cur.ts) registered.set(name, { ...cur, ts })
  }
  ;(g.items || []).forEach(({ r }) => {
    const boundTraces = (ddpToTrace[r.req_name] || []).flatMap(n => idx.filter(x => x.req_name === n))
    boundTraces.forEach(t => (t.committers || []).filter(Boolean).forEach(email => {
      const name = nameForEmail(email, committers)
      ensure(name, email)
      markDacTrace(name)
      addReq(name, r.req_name, true)
      // 用 dac 写过但还没 git commit 的成员 last_commit_ts 为空（commit-stats 链路未推进），
      // 回退到 reported_at（/report 实时上报时间），口径与 peopleStats / inactiveRequirements 一致
      consider(name, t.last_commit_ts || t.reported_at)
    }))
    ;(r.rd_list || []).filter(Boolean).forEach(email => {
      const name = nameForEmail(email, committers)
      ensure(name, email)
      addReq(name, r.req_name, false)
    })
  })
  return [...registered.entries()]
    .map(([name, info]) => ({ name, email: info.email, ts: info.ts, hasDacTrace: info.hasDacTrace, reqCount: info.reqs.size, dacReqCount: info.dacReqs.size }))
}

// 版本内不活跃成员 Top N：仅保留从未在当前版本留下过 dac trace 记录的成员。刻意不传
// personalTotals —— vibe 个人总量是跨仓库全局口径，与「当前版本是否用过 dac」无关，一旦参与
// 取值会让这些人显示出近期活跃时间，与「不活跃」语义冲突；因此这里 ts 恒为 null（概览卡片
// 也不再展示时间列，只展示 reqCount），按姓名排序取前 limit 个。g 为空返回 []。
export function versionInactiveMembers(g, requirementsIndex, committers, bindings, limit = 5) {
  return versionMemberTimes(g, requirementsIndex, committers, bindings)
    .filter(m => !m.hasDacTrace)
    .sort((a, b) => a.name.localeCompare(b.name))
    .slice(0, limit)
}

// 版本内活跃成员 Top N：仅保留在当前版本留下过 dac trace 记录的成员，与 versionInactiveMembers
// 互为补集（同一人不会同时出现在两张卡片），按当前版本内最后 dac 活跃时间降序（ts 缺失的 trace
// 排最后）取前 limit 个。g 为空返回 []。
export function versionActiveMembers(g, requirementsIndex, committers, bindings, limit = 5) {
  return versionMemberTimes(g, requirementsIndex, committers, bindings)
    .filter(m => m.hasDacTrace)
    .sort((a, b) => (b.ts ?? 0) - (a.ts ?? 0) || a.name.localeCompare(b.name))
    .slice(0, limit)
}

// 统计某版本分组内「使用 dac（AI 写）」的需求数：该 DDP 需求绑定了至少一个存在于 requirementsIndex
// 的 trace 即算。ddpToTrace 由调用方在循环外构建一次后传入。
export function versionDacCount(g, requirementsIndex, ddpToTrace) {
  const reqIdx = requirementsIndex || []
  return g.items.filter(({ r }) =>
    (ddpToTrace[r.req_name] || []).some(n => reqIdx.some(x => x.req_name === n))
  ).length
}

// 版本级「dac 行数」聚合：对 versionDacMembers(g) 返回数组各成员的 lines 字段求和。
export function versionDacLines(g, requirementsIndex, committers, bindings) {
  return versionDacMembers(g, requirementsIndex, committers, bindings).reduce((sum, m) => sum + (m.lines || 0), 0)
}

// 版本级「dac 成员渗透率」：使用 dac trace 的成员数 / 该版本总参与人数（dac+非 dac），
// 与首页环形图「工作流使用成员占比」同口径。g 为空返回 0。
export function versionMemberPct(g, requirementsIndex, committers, bindings) {
  if (!g) return 0
  const dac = versionDacMembers(g, requirementsIndex, committers, bindings)
  const nonDac = versionNonDacMembers(g, new Set(dac.map(m => m.name)), committers)
  const total = dac.length + nonDac.length
  return total > 0 ? toPercent(dac.length / total) : 0
}

// 「较上版对比」：在 recentVersions（由 recentCanonicalVersions 返回，每项带 isCurrent 标记）中
// 定位当前版本及其紧邻的前一项，后者减前者得到 dac 成员数 / dac 行数的绝对差值；当前版本不存在
// 或已是序列首项（没有更早的一项可比）时返回 null。
export function versionComparison(recentVersions, requirementsIndex, committers, bindings) {
  if (!recentVersions || recentVersions.length < 2) return null
  const curIdx = recentVersions.findIndex(g => g.isCurrent)
  if (curIdx <= 0) return null
  const prev = recentVersions[curIdx - 1]
  const cur = recentVersions[curIdx]
  const ddpToTrace = getDdpToTrace(bindings)
  return {
    memberDiff: versionDacMembers(cur, requirementsIndex, committers, bindings).length - versionDacMembers(prev, requirementsIndex, committers, bindings).length,
    linesDiff: versionDacLines(cur, requirementsIndex, committers, bindings) - versionDacLines(prev, requirementsIndex, committers, bindings),
    reqDiff: versionDacCount(cur, requirementsIndex, ddpToTrace) - versionDacCount(prev, requirementsIndex, ddpToTrace),
  }
}

// 渗透率百分数换算：以上函数的比例结果均为 [0,1] 小数，趋势图 Y 轴按百分数点绘制前统一 ×100。
export function toPercent(ratio) {
  return ratio * 100
}

// 历年累计 dac 使用统计（口径：不区分版本，覆盖全部历史需求/成员）；供顶部统计栏与概览页
// 「历年累计」环形图复用，避免两处各自实现导致口径漂移。
export function globalDacStats(committers, requirementsIndex, bindings) {
  const cms = committers || []
  const idx = requirementsIndex || []
  const people = cms.length
  const ddpToTrace = getDdpToTrace(bindings)
  const aiPeople = cms.filter(c =>
    (c.requirements || []).filter(r => r.req_name !== '__dac_file_proof__')
      .map(r => enrichReq(r, c.committer, bindings, idx, ddpToTrace))
      .some(r => (r.workflow_session_ids || []).length > 0)
  ).length
  const boundTraceSet = new Set(Object.keys(bindings || {}))
  // 技术类需求（is_technical）不计入需求总数与 dac 需求数：与统一入口
  // filterExcludedFromStats 的「统计排除 = 备注 ∪ 技术」口径保持一致，但本函数消费原始
  // requirementsIndex（非分组），故独立在 validIdx 阶段按 r.is_technical 过滤。
  const validIdx = idx.filter(r => {
    if (r?.is_technical) return false
    if (!r.ddp) return true
    return reqCommitterNames(r, cms) !== '' || (ddpToTrace[r.req_name] || []).length > 0
  })
  const dacReqCount = validIdx.filter(r => {
    if (!r.ddp) return (r.workflow_session_ids || []).length > 0 && !boundTraceSet.has(r.req_name)
    return (ddpToTrace[r.req_name] || []).length > 0
  }).length
  const reqs = validIdx.length - boundTraceSet.size
  return { aiPeople, people, dacReqCount, reqs }
}
