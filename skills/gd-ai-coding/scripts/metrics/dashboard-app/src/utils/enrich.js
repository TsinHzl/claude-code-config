function normEmail(s) {
  return (s || '').trim().toLowerCase()
}

export function getDdpToTrace(bindings) {
  const m = {}
  for (const [t, d] of Object.entries(bindings || {})) (m[d] ||= []).push(t)
  return m
}

// 同一 DDP 需求可能绑定多个 trace（多人协作各自绑定自己的 trace），也可能有多个
// rdOwner，但每个 trace 只属于实际执行 dac 工作流的那个人——必须显式传入
// committerEmail 并与候选 trace 的 committers 匹配才附加数据；未传参或匹配不到
// 任何候选时一律 fail-closed（视为不匹配），避免协作者被误标记为"已使用 dac"
export function enrichReq(req, committerEmail, bindings, requirementsIndex, precomputedDdpToTrace) {
  if (!req || !req.ddp) return req
  // 直连场景：trace req_name 与 DDP req_name 相同，服务端已按本人 committer 直接把
  // workflow_session_ids 写入这条需求本身（天然本人专属，无需 /dac-bind）。此时下方
  // bindings 匹配分支走不到（ddpToTrace 里没有这条直连关系），必须在此单独补齐 _trace*
  // 字段，否则 ReqCard 的 isMerged 判定漏标，导致统计计数与卡片展示口径分裂。
  if ((req.workflow_session_ids || []).length > 0 && !req._boundTrace) {
    if (!committerEmail) return req
    const emailNorm = normEmail(committerEmail)
    if (!(Array.isArray(req.committers) && req.committers.map(normEmail).includes(emailNorm))) return req
    return {
      ...req,
      _boundTrace: req.req_name,
      _tracePhases: req.phases,
      _traceFeatures: req.features,
      _traceSkippedStages: req.skipped_stages || [],
      _traceLastCommitTs: req.last_commit_ts,
      _traceReportedAt: req.reported_at,
      _traceCommitCount: req.commit_count || 0,
      _traceLinesAdded: req.lines_added || 0,
    }
  }
  const ddpToTrace = precomputedDdpToTrace || getDdpToTrace(bindings)
  const traceReqNames = ddpToTrace[req.req_name] || []
  if (!traceReqNames.length) return req
  if (!committerEmail) return req
  const emailNorm = normEmail(committerEmail)
  // 同一 trace req_name 在 requirements_index 中可能存在多条（多人协作各自一条，orphan 注入
  // 按 committer 逐条追加）。必须一次性按「名 ∈ 绑定集 且 committers 含本人」查找，不能先按名
  // 取第一条再按人过滤——否则第一条属于他人时整链落空，本人 trace 数据被漏掉。
  const traceReq = (requirementsIndex || []).find(r =>
    r && traceReqNames.includes(r.req_name)
    && Array.isArray(r.committers) && r.committers.map(normEmail).includes(emailNorm))
  if (!traceReq) return req
  return {
    ...req,
    _boundTrace: traceReq.req_name,
    workflow_session_ids: traceReq.workflow_session_ids || [],
    _tracePhases: traceReq.phases,
    _traceFeatures: traceReq.features,
    _traceSkippedStages: traceReq.skipped_stages || [],
    _traceLastCommitTs: traceReq.last_commit_ts,
    _traceReportedAt: traceReq.reported_at,
    _traceCommitCount: traceReq.commit_count || 0,
    _traceLinesAdded: traceReq.lines_added || 0,
  }
}

// 已绑定到 DDP 的 trace 需求：仅当对应 DDP 记录也在本人列表里时才隐藏，
// 避免同一条 dac 需求被同时计为原始 trace 需求和融合后的 DDP 需求
export function visibleReqs(c, bindings) {
  const rawReqs = c.requirements || []
  const ddpReqNamesInList = new Set(rawReqs.filter(r => r.ddp).map(r => r.req_name))
  return rawReqs.filter(r => {
    if (r.ddp) return true
    const boundDdp = (bindings || {})[r.req_name]
    return !(boundDdp && ddpReqNamesInList.has(boundDdp))
  })
}
