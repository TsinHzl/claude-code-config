// 工作流质量统计聚合：从 store.data.quality_stats（后端 /events/stats 的 per-req 预聚合）
// 按作用域（全局 = 全部 req；版本 = 该版本下 req 集合）二次聚合出 KPI 展示值。
//
// quality_stats 元素结构（后端 WorkflowEventStatsResponse，snake_case）：
//   { req_name, clarify_rounds, proposal_rounds, feature_plan_rounds,
//     codegen_feats_total, codegen_check_times, cr_feats_total, cr_check_times }
// 用户门轮次：rejected/adjusted + 1；无该门事件的 req 该值为 0（前端按 1 轮）。
// 机器门次数：该 feat 失败/有问题次数 + 1；times 是各 feat 次数之和，total 是 feat 数。

/** 从 stats 数组里筛出指定需求子集。reqNames 为 null/undefined = 全部；[] = 空范围（不是全局）。 */
export function filterQualityRows(stats, reqNames) {
  if (!Array.isArray(stats)) return []
  if (reqNames == null) return stats
  if (reqNames.length === 0) return []
  const set = new Set(reqNames)
  return stats.filter((r) => set.has(r.req_name))
}

/**
 * 某用户门的平均轮次（保留 1 位小数）。
 * 口径：分母 = 有过任何工作流事件上报的需求（quality_stats 里出现的行）；
 * 该门无事件（rounds=0）= 一次通过，按 1 轮参与平均——不当 0 算、也不剔除
 * （历史需求未埋点确实是一次过，计 1 即真实值）。全无行返回 null（显示 —）。
 */
export function avgRounds(stats, reqNames, key) {
  const rows = filterQualityRows(stats, reqNames)
  if (!rows.length) return null
  const vals = rows.map((r) => (typeof r[key] === 'number' && r[key] > 0 ? r[key] : 1))
  return Math.round((vals.reduce((a, b) => a + b, 0) / vals.length) * 10) / 10
}

/**
 * 机器门平均次数（保留 1 位小数）= Σ(失败次数+1) / 有结果事件的 feat 数。
 * 无 feat 返回 null。
 */
export function avgAttempts(stats, reqNames, timesKey, totalKey) {
  const rows = filterQualityRows(stats, reqNames)
  const total = rows.reduce((s, r) => s + (r[totalKey] || 0), 0)
  const times = rows.reduce((s, r) => s + (r[timesKey] || 0), 0)
  if (!total) return null
  return Math.round((times / total) * 10) / 10
}

/**
 * 代码自动生成比例（整数百分比）= Σ min(codegen_lines_added, lines_added) / Σ lines_added。
 * 未结算（缺字段或 0）按 0 计入分子，不按 100% 兜底。
 * reqNames 为 null = 全部；[] = 空范围。无 dac 行返回 null。
 */
export function autoGenPct(reqs, reqNames) {
  const scope = reqNames == null ? null : new Set(reqNames)
  let codegenSum = 0
  let dacSum = 0
  for (const r of Array.isArray(reqs) ? reqs : []) {
    if (scope && !scope.has(r.req_name)) continue
    const dac = r.lines_added || 0
    if (!dac) continue
    const codegen = r.codegen_lines_added || 0
    codegenSum += Math.min(codegen, dac)
    dacSum += dac
  }
  return dacSum > 0 ? Math.round((codegenSum / dacSum) * 100) : null
}

function gateCls(n) {
  if (n == null) return ''
  if (n <= 1) return 'ep-ok'
  if (n >= 3) return 'ep-danger'
  return 'ep-info'
}

function findQualityRow(stats, names) {
  const keys = (Array.isArray(names) ? names : [names])
    .filter(Boolean)
    .map((n) => String(n).toLowerCase())
  if (!keys.length || !Array.isArray(stats)) return null
  const byName = new Map()
  for (const r of stats) {
    if (r?.req_name) byName.set(String(r.req_name).toLowerCase(), r)
  }
  for (const k of keys) {
    const hit = byName.get(k)
    if (hit) return hit
  }
  return null
}

/**
 * 单条 DAC 工作流卡片徽章。
 * 无 quality_stats 行也出方案/功能（按 1 轮，与 KPI「无事件 = 一次通过」一致），
 * 否则整行消失，多数未埋点需求卡片会看起来像没做。
 * 机器门无 feat 不展示该项。names 可传 DAC 名 + DDP 名（事件可能记成 T-IBT-xxx）。
 */
export function reqQualityItems(stats, reqName, extraNames) {
  if (!reqName) return []
  const row = findQualityRow(stats, [reqName, ...(extraNames || [])])
  const proposal = row && typeof row.proposal_rounds === 'number' && row.proposal_rounds > 0 ? row.proposal_rounds : 1
  const plan = row && typeof row.feature_plan_rounds === 'number' && row.feature_plan_rounds > 0 ? row.feature_plan_rounds : 1
  const items = [
    { key: 'proposal', text: `方案 ${proposal} 轮`, cls: gateCls(proposal) },
    { key: 'plan', text: `功能 ${plan} 轮`, cls: gateCls(plan) },
  ]
  if (row && row.codegen_feats_total > 0) {
    const n = Math.round((row.codegen_check_times / row.codegen_feats_total) * 10) / 10
    items.push({ key: 'codegen', text: `代码检查 ${n} 次`, cls: gateCls(n) })
  }
  if (row && row.cr_feats_total > 0) {
    const n = Math.round((row.cr_check_times / row.cr_feats_total) * 10) / 10
    items.push({ key: 'cr', text: `CR ${n} 次`, cls: gateCls(n) })
  }
  return items
}
