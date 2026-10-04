import { visibleReqs, enrichReq, getDdpToTrace } from './enrich'
import { currentPhase } from './phase'
import { fmtNum } from './format'

// remarks: 备注表（req_name -> { excluded_from_stats, ... }），默认空对象向后兼容未传参调用方
// （如 BindModal.vue 仅用 dacReqList 做候选排序，非统计展示，不受本次过滤影响）。勾选过
// 「排除统计」的需求与技术类需求（is_technical）仍保留在 reqs/卡片展示中，仅从计数口径
// （reqCount/doneCount/dacReqList 及其派生的 dac 分类/统计）中剔除，避免该需求让参与者被误判为
// 「使用 dac 成员」，口径与 utils/version.js 的 filterExcludedFromStats 一致。
export function computeMemberAiStats(c, bindings, requirementsIndex, remarks = {}) {
  const reqs = visibleReqs(c, bindings)
  // reqs 保留全量（含技术类需求，供成员详情卡展示）；计数一律基于非技术需求。
  const statReqs = reqs.filter(r => !r.is_technical)
  const reqCount = statReqs.length
  const doneCount = statReqs.filter(r => currentPhase(r.phases) === 'released').length
  const ddpToTrace = getDdpToTrace(bindings)
  // __dac_file_proof__ 是统计口径兜底的合成占位记录，需与卡片渲染口径保持一致排除
  const dacReqList = statReqs
    .filter(r => r.req_name !== '__dac_file_proof__')
    .map(r => enrichReq(r, c.committer, bindings, requirementsIndex, ddpToTrace))
    .filter(r => (r.workflow_session_ids || []).length > 0)
    .filter(r => !remarks?.[r.req_name]?.excluded_from_stats)
  const dacReqs = dacReqList.length
  const hasAi = dacReqs > 0
  const dacCommits = dacReqList.reduce((s, r) => s + (r.commit_count || r._traceCommitCount || 0), 0)
  const dacLines = dacReqList.reduce((s, r) => s + (r.lines_added || r._traceLinesAdded || 0), 0)
  const dacStatsText = [
    dacCommits ? `${fmtNum(dacCommits)} 次提交` : '',
    dacLines ? `+${fmtNum(dacLines)} 行` : '',
  ].filter(Boolean).join(' · ')
  const dacTs = dacReqList.reduce((max, r) => {
    const ts = r.last_commit_ts || r._traceLastCommitTs || r.reported_at || r._traceReportedAt || null
    return ts && (!max || ts > max) ? ts : max
  }, null)
  return { reqs, reqCount, doneCount, dacReqList, dacReqs, hasAi, dacCommits, dacLines, dacStatsText, dacTs }
}

// 用 dac 的人排前面；同为使用者时按「dac 需求个数」→「提交代码行数」→「提交次数」从多到少排序，其余保持原相对顺序
function sortByDacUsage(a, b) {
  return (b.hasAi - a.hasAi) || (b.dacReqs - a.dacReqs) || (b.dacLines - a.dacLines) || (b.dacCommits - a.dacCommits) || (a.i - b.i)
}

// 使用 dac 的人排最前；同为使用者/同为未使用者时按最近活跃时间（dac trace 与 vibe coding 上报时间取最大值）从新到旧排序，无活跃记录排最后
function sortByActivity(a, b) {
  return (b.hasAi - a.hasAi) || (b.lastActiveTs || 0) - (a.lastActiveTs || 0) || (a.i - b.i)
}

function toEpochMs(ts) {
  const t = ts ? new Date(ts).getTime() : NaN
  return Number.isNaN(t) ? 0 : t
}

export function rankedMembersWithAiStats(committers, bindings, requirementsIndex, personalTotals = [], sortMode = 'dac', remarks = {}) {
  const list = (committers || []).map((c, i) => {
    const stats = computeMemberAiStats(c, bindings, requirementsIndex, remarks)
    const vibeTs = personalLastReportedAtFor(c.committer, personalTotals)
    const lastActiveTs = Math.max(toEpochMs(stats.dacTs), toEpochMs(vibeTs)) || null
    return { c, i, ...stats, lastActiveTs }
  })
  return list.sort(sortMode === 'activity' ? sortByActivity : sortByDacUsage)
}

// 个人总量管道（独立数据源）：personalTotals 缺失/非数组（后端未升级或拉取失败）时返回 null
export function personalTotalFor(committer, personalTotals) {
  if (!Array.isArray(personalTotals)) return null
  const rec = personalTotals.find(p => p.committer === committer)
  return rec ? (rec.total_lines || 0) : null
}

export function personalLastReportedAtFor(committer, personalTotals) {
  if (!Array.isArray(personalTotals)) return null
  const rec = personalTotals.find(p => p.committer === committer)
  return rec ? (rec.last_reported_at || null) : null
}

export function vibeTotalSum(personalTotals) {
  return Array.isArray(personalTotals) ? personalTotals.reduce((s, p) => s + (p.total_lines || 0), 0) : null
}
