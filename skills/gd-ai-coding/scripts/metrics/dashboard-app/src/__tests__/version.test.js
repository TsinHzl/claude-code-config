import { describe, it, expect } from 'vitest'
import {
  recentCanonicalVersions, versionComparison, inactiveRequirements, reqCommitterNames,
  versionInactiveMembers, versionActiveMembers, groupReqsByVersion, orderedVersionGroups, globalDacStats,
  groupTraceReqNames, filterExcludedFromStats, filterRemarksExcluded,
} from '../utils/version'

function reqFor(i, versionName, time) {
  return {
    req_name: `REQ-${i}`,
    phases: [],
    features: [],
    committers: [`dev${i}@didiglobal.com`],
    ddp: { title: `需求${i}`, release_version_name: versionName, release_version_time: time },
  }
}

// 7 个正式版本，版本号与时间均升序对齐：10 ~ 16
const SEVEN_VERSIONS = [
  ['Global司机端10', '2020-01-01'],
  ['Global司机端11', '2020-02-01'],
  ['Global司机端12', '2020-03-01'],
  ['Global司机端13', '2020-04-01'],
  ['Global司机端14', '2020-05-01'],
  ['Global司机端15', '2020-06-01'],
  ['Global司机端16', '2020-07-01'],
]

function buildRequirementsIndex(versions) {
  return versions.map(([name, time], i) => reqFor(i, name, time))
}

describe('recentCanonicalVersions', () => {
  it('当前版本居中时，返回当前版本 + 前 3 个 + 后 3 个（共 7 个），isCurrent 标记在中间项', () => {
    const idx = buildRequirementsIndex(SEVEN_VERSIONS)
    const result = recentCanonicalVersions(idx, '2020-04-01', 3, 3)

    expect(result.map(g => g.name)).toEqual([
      'Global司机端10', 'Global司机端11', 'Global司机端12', 'Global司机端13',
      'Global司机端14', 'Global司机端15', 'Global司机端16',
    ])
    expect(result.filter(g => g.isCurrent)).toHaveLength(1)
    expect(result[3].name).toBe('Global司机端13')
    expect(result[3].isCurrent).toBe(true)
  })

  it('当前版本是最早的一个时，只向后取够 3 个，不做回填', () => {
    const idx = buildRequirementsIndex(SEVEN_VERSIONS.slice(3)) // 只剩 13~16，当前=13
    const result = recentCanonicalVersions(idx, '2020-04-01', 3, 3)

    expect(result.map(g => g.name)).toEqual(['Global司机端13', 'Global司机端14', 'Global司机端15', 'Global司机端16'])
    expect(result[0].isCurrent).toBe(true)
  })

  it('当前版本是最晚的一个时，只向前取够 3 个，不做回填', () => {
    const idx = buildRequirementsIndex(SEVEN_VERSIONS.slice(0, 4)) // 只剩 10~13，当前=13
    const result = recentCanonicalVersions(idx, '2020-04-01', 3, 3)

    expect(result.map(g => g.name)).toEqual(['Global司机端10', 'Global司机端11', 'Global司机端12', 'Global司机端13'])
    expect(result[3].isCurrent).toBe(true)
  })

  it('所有版本均已发布（不存在当前版本）时，取末尾 limit 个且均不标记 isCurrent', () => {
    const idx = buildRequirementsIndex(SEVEN_VERSIONS)
    const result = recentCanonicalVersions(idx, '2099-01-01', 3, 3)

    expect(result).toHaveLength(7)
    expect(result.every(g => !g.isCurrent)).toBe(true)
  })

  it('before=3, after=1 时只返回 5 个点（前 3 + 当前 + 后 1）', () => {
    const idx = buildRequirementsIndex(SEVEN_VERSIONS)
    const result = recentCanonicalVersions(idx, '2020-04-01', 3, 1)

    expect(result.map(g => g.name)).toEqual([
      'Global司机端10', 'Global司机端11', 'Global司机端12', 'Global司机端13', 'Global司机端14',
    ])
    expect(result[3].name).toBe('Global司机端13')
    expect(result[3].isCurrent).toBe(true)
  })
})

describe('versionComparison', () => {
  const g = (name, isCurrent, items = []) => ({ name, items, isCurrent })

  it('当前版本存在且非首项时，返回当前版本与其前一项的差值', () => {
    const list = [g('v1', false), g('v2', false), g('v3', true), g('v4', false)]
    expect(versionComparison(list, [], [], {})).toEqual({ memberDiff: 0, linesDiff: 0, reqDiff: 0 })
  })

  it('reqDiff 反映当前版本与上一版本的 dac 需求数差值', () => {
    const prevItems = [{ r: { req_name: 'REQ-1' } }]
    const curItems = [{ r: { req_name: 'REQ-2' } }, { r: { req_name: 'REQ-3' } }]
    const list = [g('v1', false, prevItems), g('v2', true, curItems)]
    const requirementsIndex = [{ req_name: 'trace-2' }]
    const bindings = { 'trace-2': 'REQ-2' }
    expect(versionComparison(list, requirementsIndex, [], bindings).reqDiff).toBe(1)
  })

  it('当前版本是序列首项（没有更早版本可比）时返回 null', () => {
    const list = [g('v1', true), g('v2', false)]
    expect(versionComparison(list, [], [], {})).toBeNull()
  })

  it('序列中不存在当前版本时返回 null', () => {
    const list = [g('v1', false), g('v2', false)]
    expect(versionComparison(list, [], [], {})).toBeNull()
  })

  it('序列长度 < 2 或为空时返回 null', () => {
    expect(versionComparison([g('v1', true)], [], [], {})).toBeNull()
    expect(versionComparison([], [], [], {})).toBeNull()
    expect(versionComparison(null, [], [], {})).toBeNull()
  })
})

describe('inactiveRequirements', () => {
  const requirementsIndex = [{ req_name: 'trace-1' }]
  const bindings = { 'trace-1': 'DDP-1' }
  const testCommitters = [{ committer: 'dev@didiglobal.com', committer_name: 'Dev' }, { committer: 'tianxiao@didiglobal.com', committer_name: '田啸' }]
  const reqs = [
    { req_name: 'DDP-1', ddp: { title: '需求1' }, committers: ['dev@didiglobal.com'], last_commit_ts: 3000 }, // 绑定了有效 trace，已使用 dac
    { req_name: 'DDP-2', ddp: { title: '需求2' }, committers: ['dev@didiglobal.com'], last_commit_ts: 1000 }, // 未绑定，未使用 dac
    { req_name: 'DDP-3', ddp: { title: '需求3' }, committers: ['dev@didiglobal.com'], last_commit_ts: 2000 }, // 未绑定，未使用 dac
  ]
  const groupOf = list => ({ items: list.map(r => ({ r })) })

  it('已绑定有效 trace（使用了 dac）的需求排除，剩余按最后活跃时间升序排列', () => {
    const result = inactiveRequirements(groupOf(reqs), requirementsIndex, bindings, 5, testCommitters)
    expect(result.map(r => r.req_name)).toEqual(['DDP-2', 'DDP-3'])
  })

  it('绑定的 trace 不存在于 requirementsIndex（失效绑定）时，仍视为未使用 dac，纳入结果', () => {
    const staleBindings = { 'trace-stale': 'DDP-1' }
    const result = inactiveRequirements(groupOf(reqs), requirementsIndex, staleBindings, 5, testCommitters)
    expect(result.map(r => r.req_name)).toEqual(['DDP-2', 'DDP-3', 'DDP-1'])
  })

  it('无有效司机端参与人员（committers/rd_list 均为空或仅含排除人员）的需求被排除', () => {
    const reqsWithGhost = [
      ...reqs,
      { req_name: 'DDP-GHOST-1', ddp: { title: '幽灵需求1' }, committers: [], rd_list: [], last_commit_ts: 500 },
      { req_name: 'DDP-GHOST-2', ddp: { title: '田啸需求' }, committers: ['tianxiao@didiglobal.com'], last_commit_ts: 600 },
    ]
    const result = inactiveRequirements(groupOf(reqsWithGhost), requirementsIndex, bindings, 10, testCommitters)
    expect(result.map(r => r.req_name)).toEqual(['DDP-2', 'DDP-3'])
  })

  it('当前版本不存在（g 为 null）时返回空数组', () => {
    expect(inactiveRequirements(null, requirementsIndex, bindings, 5, testCommitters)).toEqual([])
  })
})

describe('reqCommitterNames', () => {
  const committers = [{ committer: 'alice-id', committer_name: 'Alice' }, { committer: 'bob-id', committer_name: 'Bob' }]

  it('多个 committers 映射为姓名后用「、」拼接', () => {
    expect(reqCommitterNames({ committers: ['alice-id', 'bob-id'] }, committers)).toBe('Alice、Bob')
  })

  it('committers 为空数组时返回空字符串', () => {
    expect(reqCommitterNames({ committers: [] }, committers)).toBe('')
  })

  it('排除名单中的成员不出现在结果中', () => {
    const excludedCommitters = [{ committer: 'excluded-id', committer_name: '田啸' }, { committer: 'bob-id', committer_name: 'Bob' }]
    expect(reqCommitterNames({ committers: ['excluded-id', 'bob-id'] }, excludedCommitters)).toBe('Bob')
  })

  it('未指定 committers（RD Owner）但有 rd_list 时，仍能取到 rd_list 中的姓名', () => {
    expect(reqCommitterNames({ committers: [], rd_list: ['alice-id'] }, committers)).toBe('Alice')
  })

  it('rd_list 与 committers 取并集并去重', () => {
    expect(reqCommitterNames({ committers: ['bob-id'], rd_list: ['alice-id', 'bob-id'] }, committers)).toBe('Alice、Bob')
  })
})

describe('versionActiveMembers', () => {
  const committers = [{ committer: 'alice-id', committer_name: 'Alice' }, { committer: 'bob-id', committer_name: 'Bob' }, { committer: 'carol-id', committer_name: 'Carol' }]
  const bindings = { 'trace-1': 'DDP-1', 'trace-2': 'DDP-2' }
  const requirementsIndex = [
    { req_name: 'trace-1', ddp: null, committers: ['alice-id'], last_commit_ts: 1000 },
    { req_name: 'trace-2', ddp: null, committers: ['bob-id'], last_commit_ts: 3000 },
  ]
  const g = {
    items: [
      { r: { req_name: 'DDP-1', rd_list: ['alice-id'] } },
      { r: { req_name: 'DDP-2', rd_list: ['bob-id', 'carol-id'] } },
    ],
  }

  it('只保留当前版本有 dac trace 的成员，按最后 dac 活跃时间降序排列', () => {
    const result = versionActiveMembers(g, requirementsIndex, committers, bindings, 5)
    expect(result).toEqual([
      { name: 'Bob', email: 'bob-id', ts: 3000, hasDacTrace: true, reqCount: 1, dacReqCount: 1 },
      { name: 'Alice', email: 'alice-id', ts: 1000, hasDacTrace: true, reqCount: 1, dacReqCount: 1 },
    ])
  })

  it('dacReqCount 只计已绑定 dac trace 的需求，仅 rd_list 参与的需求只计入 reqCount', () => {
    const gExtra = {
      items: [
        { r: { req_name: 'DDP-2', rd_list: ['bob-id'] } },
        { r: { req_name: 'DDP-3', rd_list: ['bob-id'] } },
      ],
    }
    const result = versionActiveMembers(gExtra, requirementsIndex, committers, bindings, 5)
    expect(result).toEqual([
      { name: 'Bob', email: 'bob-id', ts: 3000, hasDacTrace: true, reqCount: 2, dacReqCount: 1 },
    ])
  })

  it('仅在 rd_list 出现、当前版本无 dac trace 的参与者不纳入活跃成员', () => {
    const result = versionActiveMembers(g, requirementsIndex, committers, bindings, 5)
    expect(result.map(m => m.name)).not.toContain('Carol')
  })

  it('trace 缺失 last_commit_ts 时仍算活跃，ts 为 null 且排在有时间的成员之后', () => {
    const idxNoTs = [{ req_name: 'trace-1', ddp: null, committers: ['alice-id'], last_commit_ts: null }, requirementsIndex[1]]
    const result = versionActiveMembers(g, idxNoTs, committers, bindings, 5)
    expect(result).toEqual([
      { name: 'Bob', email: 'bob-id', ts: 3000, hasDacTrace: true, reqCount: 1, dacReqCount: 1 },
      { name: 'Alice', email: 'alice-id', ts: null, hasDacTrace: true, reqCount: 1, dacReqCount: 1 },
    ])
  })

  it('trace 缺失 last_commit_ts 时回退 reported_at 作为活跃时间', () => {
    const idxReported = [
      { req_name: 'trace-1', ddp: null, committers: ['alice-id'], last_commit_ts: null, reported_at: 5000 },
      requirementsIndex[1],
    ]
    const result = versionActiveMembers(g, idxReported, committers, bindings, 5)
    expect(result).toEqual([
      { name: 'Alice', email: 'alice-id', ts: 5000, hasDacTrace: true, reqCount: 1, dacReqCount: 1 },
      { name: 'Bob', email: 'bob-id', ts: 3000, hasDacTrace: true, reqCount: 1, dacReqCount: 1 },
    ])
  })

  it('排除名单中的成员不出现在结果中', () => {
    const excludedCommitters = [{ committer: 'excluded-id', committer_name: '田啸' }]
    const gExcluded = { items: [{ r: { req_name: 'DDP-1', rd_list: ['excluded-id'] } }] }
    expect(versionActiveMembers(gExcluded, [], excludedCommitters, {}, 5)).toEqual([])
  })

  it('g 为空时返回空数组', () => {
    expect(versionActiveMembers(null, requirementsIndex, committers, bindings, 5)).toEqual([])
  })
})

describe('versionInactiveMembers', () => {
  const committers = [{ committer: 'alice-id', committer_name: 'Alice' }, { committer: 'bob-id', committer_name: 'Bob' }, { committer: 'carol-id', committer_name: 'Carol' }]
  const bindings = { 'trace-1': 'DDP-1', 'trace-2': 'DDP-2' }
  const requirementsIndex = [
    { req_name: 'trace-1', ddp: null, committers: ['alice-id'], last_commit_ts: 1000 },
    { req_name: 'trace-2', ddp: null, committers: ['bob-id'], last_commit_ts: 3000 },
  ]
  const g = {
    items: [
      { r: { req_name: 'DDP-1', rd_list: ['alice-id'] } },
      { r: { req_name: 'DDP-2', rd_list: ['bob-id', 'carol-id'] } },
    ],
  }

  it('只保留从未有过 dac trace 记录的成员，曾经有 dac trace 的成员即使很久没动也不纳入', () => {
    const result = versionInactiveMembers(g, requirementsIndex, committers, bindings, 5)
    expect(result).toEqual([
      { name: 'Carol', email: 'carol-id', ts: null, hasDacTrace: false, reqCount: 1, dacReqCount: 0 },
    ])
  })

  it('reqCount 为该成员在当前版本参与的 DDP 需求去重数（同一需求重复出现只计一次）', () => {
    const gMulti = {
      items: [
        { r: { req_name: 'DDP-2', rd_list: ['carol-id', 'carol-id'] } },
        { r: { req_name: 'DDP-3', rd_list: ['carol-id'] } },
      ],
    }
    const result = versionInactiveMembers(gMulti, requirementsIndex, committers, bindings, 5)
    expect(result).toEqual([
      { name: 'Carol', email: 'carol-id', ts: null, hasDacTrace: false, reqCount: 2, dacReqCount: 0 },
    ])
  })

  it('不接收 personalTotals：当前版本无 dac trace 的成员 ts 恒为 null（一律视为从未活跃）', () => {
    // 第 5 个实参是 limit 而非 personalTotals，vibe 全局活跃时间不参与不活跃成员的时间取值
    const result = versionInactiveMembers(g, requirementsIndex, committers, bindings, 5)
    expect(result.every(m => m.ts === null)).toBe(true)
  })

  it('排除名单中的成员不出现在结果中', () => {
    const excludedCommitters = [{ committer: 'excluded-id', committer_name: '田啸' }]
    const gExcluded = { items: [{ r: { req_name: 'DDP-1', rd_list: ['excluded-id'] } }] }
    expect(versionInactiveMembers(gExcluded, [], excludedCommitters, {}, 5)).toEqual([])
  })

  it('g 为空时返回空数组', () => {
    expect(versionInactiveMembers(null, requirementsIndex, committers, bindings, 5)).toEqual([])
  })

  it('曾有 dac trace 记录的成员不纳入不活跃成员列表', () => {
    const result = versionInactiveMembers(g, requirementsIndex, committers, bindings, 5)
    expect(result.map(m => m.name)).not.toContain('Alice')
    expect(result.map(m => m.name)).not.toContain('Bob')
  })
})

describe('groupReqsByVersion & globalDacStats 过滤无有效司机端参与人员需求', () => {
  const committers = [
    { committer: 'dev1@didiglobal.com', committer_name: 'Dev1' },
    { committer: 'tianxiao@didiglobal.com', committer_name: '田啸' },
  ]
  const requirements = [
    {
      req_name: 'VALID-1',
      ddp: { title: '正常司机端需求', release_version_name: 'Global司机端10', release_version_time: '2020-01-01' },
      committers: ['dev1@didiglobal.com'],
      rd_list: ['dev1@didiglobal.com'],
      phases: [],
      features: [],
    },
    {
      req_name: 'GHOST-TIANXIAO',
      ddp: { title: '田啸单人需求', release_version_name: 'Global司机端10', release_version_time: '2020-01-01' },
      committers: ['tianxiao@didiglobal.com'],
      rd_list: ['tianxiao@didiglobal.com'],
      phases: [],
      features: [],
    },
    {
      req_name: 'GHOST-EMPTY',
      ddp: { title: '无负责人需求', release_version_name: 'Global司机端10', release_version_time: '2020-01-01' },
      committers: [],
      rd_list: [],
      phases: [],
      features: [],
    },
  ]

  it('groupReqsByVersion 过滤掉 committers / rd_list 均无有效司机端人员的需求', () => {
    const groups = groupReqsByVersion(requirements, committers)
    expect(groups).toHaveLength(1)
    const items = groups[0].items.map(x => x.r.req_name)
    expect(items).toContain('VALID-1')
    expect(items).not.toContain('GHOST-TIANXIAO')
    expect(items).not.toContain('GHOST-EMPTY')
  })

  it('globalDacStats 统计需求总数时过滤掉幽灵需求', () => {
    const stats = globalDacStats(committers, requirements, {})
    expect(stats.reqs).toBe(1)
  })

  it('globalDacStats 需求数与 dac 需求数均排除技术类需求（is_technical）', () => {
    // 纯 dac trace（无 ddp）条目：业务与技术各一条直连。技术条目须同时不占 reqs 与 dacReqCount。
    const reqs = [
      { req_name: 'trace-biz', workflow_session_ids: ['s-b'], phases: [], features: [], committers: ['dev1@didiglobal.com'] },
      { req_name: 'trace-tech', workflow_session_ids: ['s-t'], phases: [], features: [], committers: ['dev1@didiglobal.com'], is_technical: true },
    ]
    const stats = globalDacStats(committers, reqs, {})
    expect(stats.reqs).toBe(1)
    expect(stats.dacReqCount).toBe(1)
  })
})

describe('groupTraceReqNames', () => {
  it('直连 DAC 条目收自身，DDP 经映射收 trace 名，去重', () => {
    const group = {
      items: [
        { r: { req_name: 'DDP-1', ddp: { title: 't' }, workflow_session_ids: [] } },
        { r: { req_name: 'trace-direct', workflow_session_ids: ['s1'] } },
        { r: { req_name: 'DDP-1', ddp: { title: 't' }, workflow_session_ids: [] } },
      ],
    }
    const names = groupTraceReqNames(group, { 'DDP-1': ['trace-a', 'trace-b'] })
    expect(names).toEqual(expect.arrayContaining(['trace-a', 'trace-b', 'trace-direct']))
    expect(names).toHaveLength(3)
  })
  it('group 为空返回空数组', () => {
    expect(groupTraceReqNames(null, {})).toEqual([])
  })
})

describe('filterExcludedFromStats', () => {
  const group = {
    name: 'Global司机端100',
    isCurrent: true,
    items: [
      { r: { req_name: 'REQ-1' } },
      { r: { req_name: 'REQ-2' } },
    ],
  }

  it('剔除 remarks 中标记 excluded_from_stats 的需求，保留其余字段（如 isCurrent）不变', () => {
    const remarks = { 'REQ-1': { excluded_from_stats: true } }
    const filtered = filterExcludedFromStats(group, remarks)
    expect(filtered.items.map(x => x.r.req_name)).toEqual(['REQ-2'])
    expect(filtered.isCurrent).toBe(true)
    expect(filtered.name).toBe('Global司机端100')
  })

  it('remarks 为空或无匹配条目时原样保留全部 items', () => {
    expect(filterExcludedFromStats(group, {}).items).toHaveLength(2)
    expect(filterExcludedFromStats(group, null).items).toHaveLength(2)
  })

  it('group 为空原样返回（保留 null 语义，不强行转换成空分组）', () => {
    expect(filterExcludedFromStats(null, {})).toBeNull()
  })

  it('剔除 is_technical 技术类需求（统计排除 = 备注排除 ∪ 技术需求）', () => {
    const groupTech = {
      name: 'Global司机端100',
      isCurrent: true,
      items: [
        { r: { req_name: 'REQ-T', is_technical: true } },
        { r: { req_name: 'REQ-B' } },
      ],
    }
    const filtered = filterExcludedFromStats(groupTech, {})
    expect(filtered.items.map(x => x.r.req_name)).toEqual(['REQ-B'])
    expect(filtered.isCurrent).toBe(true)
  })
})

describe('filterRemarksExcluded', () => {
  const group = {
    name: 'Global司机端100',
    isCurrent: true,
    items: [
      { r: { req_name: 'REQ-1' } },
      { r: { req_name: 'REQ-2', is_technical: true } },
    ],
  }

  it('仅剔除 remarks 排除项，技术需求保留（供榜单/详情展示侧成员推导）', () => {
    const remarks = { 'REQ-1': { excluded_from_stats: true } }
    const filtered = filterRemarksExcluded(group, remarks)
    expect(filtered.items.map(x => x.r.req_name)).toEqual(['REQ-2'])
    expect(filtered.items[0].r.is_technical).toBe(true)
    expect(filtered.isCurrent).toBe(true)
  })

  it('remarks 为空或无匹配条目时原样保留全部 items', () => {
    expect(filterRemarksExcluded(group, {}).items).toHaveLength(2)
    expect(filterRemarksExcluded(group, null).items).toHaveLength(2)
  })

  it('group 为空原样返回', () => {
    expect(filterRemarksExcluded(null, {})).toBeNull()
  })
})
