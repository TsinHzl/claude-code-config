<template>
  <div class="tab-content ep-page" :class="{ active: store.activeTab === 'tab-current' }" id="tab-current">
    <div class="ep-top-bar">
      <div class="ep-page-title-box">
        <span class="ep-dac-pill">DAC</span>
        <h2 class="ep-page-title">当前版本</h2>
        <span class="ep-crumb">/ <b>{{ curGroup ? curGroup.name : '无进行中的版本' }}</b> {{ crumbTail }}</span>
      </div>
      <div class="ep-top-meta">{{ topMeta }}</div>
    </div>

    <div class="ep-ws">
      <div class="ep-list-pane" id="curpeople-list">
        <div class="ep-list-head">
          <div class="ep-ic-box ep-brand"><EpIcon name="cube" /></div>
          <div class="ep-list-head-col">
            <div class="ep-list-head-title">{{ curGroup ? curGroup.name : '当前版本' }}</div>
            <div class="ep-list-head-sub">{{ listHeadSub }}</div>
          </div>
        </div>
        <div class="ep-list-body">
          <div v-if="!curGroup" class="ep-empty">当前无进行中的版本</div>
          <div v-else-if="!displayMembers.length" class="ep-empty">当前版本暂无参与人员</div>
          <template v-else>
            <div class="ep-li" :class="{ 'sel-ok': store.curPeopleViewMode === 'overview' }" @click="selectCurOverview()">
              <div class="ep-li-top">
                <div class="ep-ic-box" :class="{ 'ep-ok': store.curPeopleViewMode === 'overview' }"><EpIcon name="donut" /></div>
                <div class="ep-li-txt">
                  <div class="ep-li-name">概览</div>
                  <div class="ep-li-sub">本版本 dac 使用情况</div>
                </div>
              </div>
            </div>

            <template v-if="displayDacMembers.length">
              <div class="ep-group-label">
                <EpIcon name="star" :size="10" class="ep-spark" />使用 dac 成员（{{ displayDacMembers.length }}）
              </div>
              <div v-for="m in displayDacMembers" :key="m.name" class="ep-li dac"
                   :class="{ sel: isSelectedMember(m.name) }"
                   :ref="el => setItemRef(m.name, el)" @click="onSidebarClick(m.name)">
                <div class="ep-li-top">
                  <div class="ep-av" :class="isSelectedMember(m.name) ? 'ep-brand' : 'ep-ok'">{{ initials(m.name) }}</div>
                  <div class="ep-li-txt">
                    <div class="ep-li-name">{{ m.name }}</div>
                    <div class="ep-li-sub" :title="m.email">{{ m.email }}</div>
                  </div>
                </div>
                <div class="ep-li-badges">
                  <span class="ep-bd ep-brand">{{ m.reqCount }} 个需求</span>
                  <span class="ep-bd ep-ok"><EpIcon name="star" :size="9" />{{ m.dacReqCount }} 个 dac 需求</span>
                </div>
                <div v-if="statsText(m)" class="ep-li-stat">{{ statsText(m) }}</div>
              </div>
            </template>

            <template v-if="displayNonDacMembers.length">
              <div class="ep-group-label">
                <EpIcon name="user" :size="10" />未使用 dac 成员（{{ displayNonDacMembers.length }}）
              </div>
              <div v-for="m in displayNonDacMembers" :key="m.name" class="ep-li"
                   :class="{ sel: isSelectedMember(m.name) }"
                   :ref="el => setItemRef(m.name, el)" @click="onSidebarClick(m.name)">
                <div class="ep-li-top">
                  <div class="ep-av" :class="{ 'ep-brand': isSelectedMember(m.name) }">{{ initials(m.name) }}</div>
                  <div class="ep-li-txt">
                    <div class="ep-li-name">{{ m.name }}</div>
                    <div class="ep-li-sub" :title="m.email">{{ m.email }}</div>
                  </div>
                </div>
                <div class="ep-li-badges">
                  <span class="ep-bd ep-brand">{{ m.reqCount }} 个需求</span>
                  <span v-if="m.doneCount" class="ep-bd ep-ok">{{ m.doneCount }} 已完成</span>
                </div>
              </div>
            </template>
          </template>
        </div>
      </div>

      <div class="ep-detail-pane" id="curpeople-detail">
        <div v-if="!curGroup" class="ep-empty">当前无进行中的版本</div>
        <div v-else-if="!displayMembers.length" class="ep-empty">当前版本暂无参与人员</div>
        <template v-else-if="store.curPeopleViewMode === 'overview'">
          <QualityStatsCard :req-names="qualityScopeReqNames" :subtitle="curGroup ? curGroup.name : '当前版本'" />
          <div class="ep-stat-row">
            <div class="ep-stat-card">
              <svg class="ep-donut" viewBox="0 0 56 56">
                <circle :cx="donutGeo.cx" :cy="donutGeo.cy" :r="donutGeo.r" fill="none" stroke="var(--line)" stroke-width="6" />
                <circle :cx="donutGeo.cx" :cy="donutGeo.cy" :r="donutGeo.r" fill="none" stroke="var(--ok)" stroke-width="6"
                        :stroke-dasharray="`${memberDash.toFixed(1)} ${donutGeo.circumference.toFixed(1)}`" stroke-linecap="round"
                        :transform="`rotate(-90 ${donutGeo.cx} ${donutGeo.cy})`" />
                <text :x="donutGeo.cx" :y="donutGeo.cy" text-anchor="middle" dominant-baseline="central"
                      font-size="13" font-weight="800" fill="var(--ok)">{{ memberPct }}%</text>
              </svg>
              <div class="ep-stat-lines">
                <div class="ep-stat-primary"><em>{{ dacMembers.length }} 人使用 dac</em> · {{ nonDacMembers.length }} 人未使用</div>
                <div class="ep-stat-sub">占本版本 {{ members.length }} 人的 {{ memberPct }}%</div>
                <div class="ep-stat-sub">累计 dac 行数 {{ fmtLines(totalDacLines) }} · 人均 dac 需求 {{ avgDacReqs }}</div>
              </div>
              <div class="ep-stat-num">{{ dacMembers.length }}<span class="ep-stat-den">/{{ members.length }}</span></div>
            </div>

            <div class="ep-stat-card">
              <svg class="ep-donut" viewBox="0 0 56 56">
                <circle :cx="donutGeo.cx" :cy="donutGeo.cy" :r="donutGeo.r" fill="none" stroke="var(--line)" stroke-width="6" />
                <circle v-if="curReqTotal > 0" :cx="donutGeo.cx" :cy="donutGeo.cy" :r="donutGeo.r" fill="none" stroke="var(--ok)" stroke-width="6"
                        :stroke-dasharray="`${reqDash.toFixed(1)} ${donutGeo.circumference.toFixed(1)}`" stroke-linecap="round"
                        :transform="`rotate(-90 ${donutGeo.cx} ${donutGeo.cy})`" />
                <text :x="donutGeo.cx" :y="donutGeo.cy" text-anchor="middle" dominant-baseline="central"
                      font-size="13" font-weight="800" :fill="curReqTotal > 0 ? 'var(--ok)' : 'var(--t4)'">{{ curReqTotal > 0 ? reqPct + '%' : '—' }}</text>
              </svg>
              <div class="ep-stat-lines">
                <template v-if="curReqTotal > 0">
                  <div class="ep-stat-primary"><em>{{ curReqDac }} 个需求已用 dac</em> · {{ curReqTotal - curReqDac }} 个未用</div>
                  <div class="ep-stat-sub">占本版本 {{ curReqTotal }} 个需求的 {{ reqPct }}%</div>
                </template>
                <div v-else class="ep-stat-primary">暂无需求数据</div>
              </div>
              <div class="ep-stat-num" :style="curReqTotal > 0 ? '' : 'color:var(--t4)'">
                <template v-if="curReqTotal > 0">{{ curReqDac }}<span class="ep-stat-den">/{{ curReqTotal }}</span></template>
                <template v-else>—</template>
              </div>
            </div>
          </div>

          <div class="ep-sec-title">
            <EpIcon name="star" :size="12" class="ep-spark" />
            使用 dac <span class="ep-n">{{ dacMembers.length }} 人</span>
          </div>
          <div v-if="dacMembers.length" class="ep-chip-grid">
            <div v-for="m in dacMembers" :key="m.name" class="ep-chip dac" @click="onOverviewCardClick(m.name)">
              <div class="ep-av ep-ok sm">{{ initials(m.name) }}</div>
              <div class="ep-chip-txt">
                <div class="ep-chip-name">{{ m.name }}</div>
                <div class="ep-chip-stat">
                  <span class="ep-ok">{{ m.dacReqCount }} dac</span>{{ m.lines ? ' · +' + fmtNum(m.lines) + ' 行' : '' }}
                </div>
              </div>
            </div>
          </div>
          <div v-else class="ep-empty">本版本暂无成员使用 dac</div>

          <div class="ep-sec-title">
            <EpIcon name="user" :size="12" />
            未使用 dac <span class="ep-n">{{ nonDacMembers.length }} 人</span>
          </div>
          <div v-if="nonDacMembers.length" class="ep-chip-grid">
            <div v-for="m in nonDacMembers" :key="m.name" class="ep-chip" @click="onOverviewCardClick(m.name)">
              <div class="ep-av sm">{{ initials(m.name) }}</div>
              <div class="ep-chip-txt">
                <div class="ep-chip-name">{{ m.name }}</div>
                <div class="ep-chip-stat">未使用 dac</div>
              </div>
            </div>
          </div>
          <div v-else class="ep-empty">本版本成员均已使用 dac</div>
        </template>
        <template v-else-if="selectedMember">
          <div class="ep-card tight">
            <div class="ep-detail-head">
              <div class="ep-av lg" :class="selectedMember.isNonDac ? '' : 'ep-ok'">{{ initials(selectedMember.name) }}</div>
              <div style="flex:1;min-width:0">
                <div class="ep-dh-name">{{ selectedMember.name }}</div>
                <div class="ep-dh-mail">{{ selectedMember.email }}</div>
                <div class="ep-dh-badges">
                  <span class="ep-bd ep-brand">{{ selectedMember.reqCount }} 个需求</span>
                  <span v-if="selectedMember.isNonDac && selectedMember.doneCount" class="ep-bd ep-ok">{{ selectedMember.doneCount }} 已完成</span>
                  <span v-if="!selectedMember.isNonDac" class="ep-bd ep-ok"><EpIcon name="star" :size="9" />{{ selectedMember.dacReqCount }} 个 dac 需求</span>
                  <span v-if="statsText(selectedMember)" class="ep-bd">{{ statsText(selectedMember) }}</span>
                </div>
              </div>
            </div>
          </div>
          <template v-if="memberCards.length">
            <ReqCard v-for="item in memberCards" :key="item.reqName" :req="item.r" :committer-email="item.email" :is-current-version="true" />
          </template>
          <div v-else class="ep-empty">{{ selectedMember.isNonDac ? '暂无当前版本参与需求卡片' : '暂无当前版本 dac 需求卡片' }}</div>
        </template>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { store, selectCurPerson, selectCurPersonFromOverview, selectCurOverview } from '../../store/dashboard'
import { initials, fmtNum, fmtLines } from '../../utils/format'
import { currentVersionGroup, versionDacMembers, versionNonDacMembers, versionDacCount, groupTraceReqNames, filterExcludedFromStats } from '../../utils/version'
import { getDdpToTrace } from '../../utils/enrich'
import { useOverviewDetailToggle } from '../../composables/useOverviewDetailToggle'
import ReqCard from '../shared/ReqCard.vue'
import QualityStatsCard from '../shared/QualityStatsCard.vue'
import EpIcon from '../shared/EpIcon.vue'

const committers = computed(() => store.data?.committers || [])
const requirementsIndex = computed(() => store.data?.requirements_index || [])
const bindings = computed(() => store.bindings || {})
const todayStr = computed(() => new Date().toISOString().slice(0, 10))

const curGroup = computed(() => currentVersionGroup(requirementsIndex.value, todayStr.value, committers.value))

// 统计口径分组：剔除 remarks「排除统计」与全部技术类需求，作为成员维度数字聚合数据源（donut 渗透率
// 分母、chip 网格、需求 donut、质量卡作用域）。技术需求保留在展示侧但一律不进入任何统计口径。过滤
// 逻辑下沉到 filterExcludedFromStats，与 OverviewTab.vue 共用。与下方 displayGroup 的职责分工：
// 本分组驱动数字聚合（dacMembers/members/渗透率/总需求数），顶栏与列表头「共 N 人」由 displayGroup
// 派生的 displayMembers 提供（保留技术需求使仅参与技术需求的成员仍计入人数字）。
const statsGroup = computed(() => filterExcludedFromStats(curGroup.value, store.remarks))

// 统计侧成员集合（不含仅参与技术需求的成员，供渗透率/成员数等数字聚合）。
const dacMembers = computed(() => versionDacMembers(statsGroup.value, requirementsIndex.value, committers.value, bindings.value))
const nonDacMembers = computed(() => versionNonDacMembers(statsGroup.value, new Set(dacMembers.value.map(m => m.name)), committers.value))
const members = computed(() => [...dacMembers.value, ...nonDacMembers.value])

// 榜单/详情展示分组：保留全部需求（含技术类与「排除统计」需求）——仅参与技术需求的成员仍列出、
// 可选中；备注勾选「排除统计」的需求不再从成员需求列表/详情卡片中隐藏（排除只影响统计口径，
// 由 statsGroup 承担）。注意口径取舍：榜单成员 badge（reqCount/dacReqCount/lines/commits）仍计入
// 被排除需求（榜单反映全量参与，与概览 chip 网格的纯统计口径可能不同）。
// 技术需求对统计数字的隔离由 version 成员函数内部 + statsGroup 完成。
const displayGroup = computed(() => curGroup.value)
const displayDacMembers = computed(() => versionDacMembers(displayGroup.value, requirementsIndex.value, committers.value, bindings.value))
const displayNonDacMembers = computed(() => versionNonDacMembers(displayGroup.value, new Set(displayDacMembers.value.map(m => m.name)), committers.value))
const displayMembers = computed(() => [...displayDacMembers.value, ...displayNonDacMembers.value])

const generatedAt = computed(() => store.data?.generatedAt || '')
const crumbTail = computed(() => store.curPeopleViewMode === 'member' && selectedMember.value
  ? `/ ${selectedMember.value.name}`
  : '· 概览')
// 数据未返回时数字位以占位符呈现，避免顶栏出现误导性的 0
const topMeta = computed(() => {
  const head = store.data ? `共 ${displayMembers.value.length} 人` : '共 — 人'
  return generatedAt.value ? `${head} · 更新时间: ${generatedAt.value}` : head
})
const listHeadSub = computed(() => {
  if (!curGroup.value) return '暂无进行中的版本'
  const time = curGroup.value.time ? `${curGroup.value.time} 发布 · ` : ''
  return `${time}共 ${displayMembers.value.length} 人`
})

function statsText(m) {
  return [
    m.commits ? `${fmtNum(m.commits)} 次提交` : '',
    m.lines ? `+${fmtNum(m.lines)} 行` : '',
  ].filter(Boolean).join(' · ')
}

const donutGeo = { cx: 28, cy: 28, r: 23, circumference: 2 * Math.PI * 23 }
const memberPct = computed(() => members.value.length > 0 ? Math.round((dacMembers.value.length / members.value.length) * 100) : 0)
const memberDash = computed(() => donutGeo.circumference * (members.value.length > 0 ? dacMembers.value.length / members.value.length : 0))
const totalDacLines = computed(() => dacMembers.value.reduce((s, m) => s + (m.lines || 0), 0))
const totalDacReqs = computed(() => dacMembers.value.reduce((s, m) => s + (m.dacReqCount || 0), 0))
const avgDacReqs = computed(() => dacMembers.value.length > 0 ? (totalDacReqs.value / dacMembers.value.length).toFixed(1) : '0.0')

const ddpToTraceMap = computed(() => getDdpToTrace(bindings.value))
const curReqTotal = computed(() => (statsGroup.value?.items || []).length)
const curReqDac = computed(() => statsGroup.value ? versionDacCount(statsGroup.value, requirementsIndex.value, ddpToTraceMap.value) : 0)
const reqPct = computed(() => curReqTotal.value > 0 ? Math.round((curReqDac.value / curReqTotal.value) * 100) : null)
const reqDash = computed(() => donutGeo.circumference * (curReqTotal.value > 0 ? curReqDac.value / curReqTotal.value : 0))

// 质量卡作用域：当前版本关联的 DAC 工作流名（无当前版本时 null = 全局）。
// 有版本但映射为空时传 []，不能传 null，否则会误显示全局数字。与 OverviewTab.vue 保持
// 同一口径：基于排除统计后的 statsGroup 计算，避免已勾选排除的需求仍纳入质量卡统计范围。
const qualityScopeReqNames = computed(() => {
  if (!statsGroup.value) return null
  return groupTraceReqNames(statsGroup.value, ddpToTraceMap.value)
})

// 以成员姓名作为持久标识（与 store 既有 selectedCurPersonName 设计一致），抵御展示成员数组因数据刷新
// 重新排序。从 displayMembers（含仅参与技术需求的成员）中定位，保证技术-only 成员可被选中查看详情。
const selectedMember = computed(() => store.curPeopleViewMode === 'member'
  ? displayMembers.value.find(m => m.name === store.selectedCurPersonName) || null
  : null)

function isSelectedMember(name) {
  return store.curPeopleViewMode === 'member' && store.selectedCurPersonName === name
}

const { setItemRef } = useOverviewDetailToggle({
  list: displayMembers,
  isDetailMode: () => store.curPeopleViewMode === 'member',
  isSelected: m => m.name === store.selectedCurPersonName,
  toOverview: selectCurOverview,
  selectionKey: computed(() => store.selectedCurPersonName),
  isValidKey: name => !!name,
})

function onSidebarClick(name) {
  selectCurPerson(name)
}
function onOverviewCardClick(name) {
  selectCurPersonFromOverview(name)
}

const memberCards = computed(() => {
  const m = selectedMember.value
  if (!m) return []
  return [...m.reqs.entries()].map(([reqName, email]) => {
    // reqs 基于 displayGroup（未剔除排除统计）：成员详情需求卡展示全部需求（含被排除的），
    // 排除仅影响统计口径（statsGroup）
    const r = requirementsIndex.value.find(x => x.req_name === reqName)
    return r ? { reqName, email, r } : null
  }).filter(Boolean)
})
</script>
