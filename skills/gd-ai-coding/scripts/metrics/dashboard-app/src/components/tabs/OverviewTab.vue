<template>
  <div class="tab-content" :class="{ active: store.activeTab === 'tab-overview' }" id="tab-overview">
    <div class="ov-header">
      <div class="ov-header-title"><span class="ov-header-badge">DAC</span>司机端 AI 工作流数据看板</div>
      <div v-if="generatedAt" class="ov-header-time">更新时间: {{ generatedAt }}</div>
    </div>

    <div v-if="curGroup" class="hero-banner">
      <div class="hero-banner-left">
        <div class="hero-banner-row">
          <span class="hero-cur-badge">当前版本</span>
          <span v-if="curGroup.time" class="hero-banner-date">{{ curGroup.time }} 发布</span>
        </div>
        <div class="hero-banner-ver">{{ curGroup.name }}</div>
      </div>
      <div class="hero-banner-metrics">
        <HeroMetricCard label="需求使用率" :num="reqDac" :den="reqTotal" unit="个" color="var(--chart-req)" />
        <HeroMetricCard label="成员使用率" :num="dacMembers.length" :den="pplTotal" unit="人" color="var(--chart-mem)" />
      </div>
    </div>

    <!-- 工作流质量行（共享组件：方案/功能轮次 + 代码检查/CR 次数；自动生成比例暂时隐藏） -->
    <QualityStatsCard :req-names="qualityScopeReqNames" :subtitle="curGroup ? curGroup.name : '当前版本'" />

    <div class="overview-summary-card" v-if="!curGroup">
      <div style="font-size:15px;font-weight:700;color:var(--warm-text)">暂无当前版本</div>
      <div style="display:flex;gap:14px;margin-top:10px">
        <DonutCard title="工作流使用成员占比" :num="dacMembers.length" :den="pplTotal" color="var(--chart-mem)">
          <template #link><span class="overview-link" @click="setActiveTab('tab-current')">成员详情→</span></template>
        </DonutCard>
        <DonutCard title="需求工作流使用占比" :num="reqDac" :den="reqTotal" color="var(--chart-mem)" />
      </div>
    </div>

    <div class="overview-top-row">
      <TrendChart :recent-versions="recentVersions" :requirements-index="requirementsIndex" :committers="committers" :bindings="bindings" />
      <MemberTrendChart :recent-versions="recentVersions" :requirements-index="requirementsIndex" :committers="committers" :bindings="bindings" />
    </div>

    <div class="overview-list-row">
      <div class="overview-list-card">
        <div class="ov-list-head">
          <div class="ov-list-title">不活跃需求 ({{ inactiveReqs.length }})</div>
          <span class="overview-link" @click="goInactiveReqInVersion">查看全部 →</span>
        </div>
        <template v-if="inactiveReqs.length">
          <component v-for="r in inactiveReqs" :key="r.req_name" :is="r.ddpHref ? 'a' : 'div'" class="overview-list-item"
                     :class="{ 'overview-list-item-static': !r.ddpHref }"
                     :href="r.ddpHref || undefined" :target="r.ddpHref ? '_blank' : undefined" :rel="r.ddpHref ? 'noopener noreferrer' : undefined">
            <span class="ov-item-name" :title="r.ddp?.title || r.req_name">{{ r.ddp?.title || r.req_name }}</span>
            <span v-if="store.remarks?.[r.req_name]?.excluded_from_stats" class="ov-excluded-badge">已排除统计</span>
            <span v-if="r.is_technical" class="ep-tech-badge" title="技术类需求，不计入需求维度统计">技术</span>
            <button v-if="store.remarks?.[r.req_name]" type="button" class="ov-remark-chip"
                    :title="getRemarkTitle(r.req_name)" @click.stop.prevent="openRemark(r)">
              {{ store.remarks[r.req_name].reason_tag || '已备注' }}
            </button>
            <button v-else type="button" class="ov-remark-btn" title="添加未采用 AI 原因备注"
                    @click.stop.prevent="openRemark(r)">
              + 备注
            </button>
            <span class="ov-chip">{{ r.rdNames || '-' }}</span>
          </component>
        </template>
        <div v-else class="empty-state">暂无不活跃需求</div>
      </div>
      <div class="overview-list-card">
        <div class="ov-list-head">
          <div class="ov-list-title">不活跃成员 ({{ inactiveMembersList.length }})</div>
          <span class="overview-link" @click="setActiveTab('tab-current')">查看全部 →</span>
        </div>
        <template v-if="inactiveMembersList.length">
          <div v-for="m in inactiveMembersList" :key="m.name" class="overview-list-item" @click="goInactiveMemberDetail(m.name)">
            <span class="ov-avatar ov-avatar-warm">{{ m.name.slice(0, 1) }}</span>
            <span class="ov-item-name">{{ m.name }}</span>
            <span class="ov-chip">{{ m.reqCount }} 需求</span>
          </div>
        </template>
        <div v-else class="empty-state">暂无不活跃成员</div>
      </div>
      <div class="overview-list-card">
        <div class="ov-list-head">
          <div class="ov-list-title">活跃成员 ({{ activeMembersList.length }})</div>
          <span class="overview-link" @click="setActiveTab('tab-people')">查看全部 →</span>
        </div>
        <template v-if="activeMembersList.length">
          <div v-for="m in activeMembersList" :key="m.name" class="overview-list-item" @click="goMemberDetail(m.email)">
            <span class="ov-avatar ov-avatar-cool">{{ m.name.slice(0, 1) }}</span>
            <span class="ov-item-name">{{ m.name }}</span>
            <span class="ov-time">{{ m.ts ? fmtRelTime(m.ts) : '—' }}</span>
            <span class="ov-chip ov-chip-green">{{ m.dacReqCount }}/{{ m.reqCount }} 需求</span>
          </div>
        </template>
        <div v-else class="empty-state">暂无活跃成员</div>
      </div>
    </div>

    <!-- 各需求：下拉切换耗时/质量视图 -->
    <WorkflowViewsCard
      :cur-group="curGroup"
      :requirements-index="requirementsIndex"
      :bindings="bindings"
      :quality-stats="qualityStats"
      :current-version-name="curGroup?.name || ''"
      :active="store.activeTab === 'tab-overview'"
    />
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { store, setActiveTab, selectVersion, setVersionScrollTarget, selectPerson, selectCurPerson, showRemarkModal } from '../../store/dashboard'
import { formatRemarkTitle, remarkDefaultAuthor } from '../../utils/remark'
import { fmtRelTime } from '../../utils/format'
import {
  orderedVersionGroups, versionDacMembers, versionNonDacMembers, versionDacCount,
  recentCanonicalVersions, inactiveRequirements, reqCommitterNames, versionActiveMembers, versionInactiveMembers,
  groupTraceReqNames, filterExcludedFromStats,
} from '../../utils/version'
import { getDdpToTrace } from '../../utils/enrich'
import { ddpUrl } from '../../utils/ddp'
import DonutCard from '../overview/DonutCard.vue'
import HeroMetricCard from '../overview/HeroMetricCard.vue'
import TrendChart from '../overview/TrendChart.vue'
import MemberTrendChart from '../overview/MemberTrendChart.vue'
import QualityStatsCard from '../shared/QualityStatsCard.vue'
import WorkflowViewsCard from '../overview/WorkflowViewsCard.vue'

const requirementsIndex = computed(() => store.data?.requirements_index || [])
const committers = computed(() => store.data?.committers || [])
const bindings = computed(() => store.bindings || {})
const todayStr = computed(() => new Date().toISOString().slice(0, 10))
const generatedAt = computed(() => store.data?.generatedAt || '')

const qualityStats = computed(() => store.data?.quality_stats || [])

const curGroup = computed(() => {
  const { ordered, currentGroupIndex } = orderedVersionGroups(requirementsIndex.value, todayStr.value, committers.value)
  return currentGroupIndex >= 0 ? ordered[currentGroupIndex] : null
})

const ddpToTraceMap = computed(() => getDdpToTrace(bindings.value))

// 排除统计后的当前版本分组：所有面向"统计"的计算（人员/需求数/质量作用域）统一基于此分组，
// 保证勾选「排除统计」后该需求既不计入需求数，也不再让参与该需求的人出现在人员榜单里。
// 需求本身的展示（如 chartData、inactiveReqs）不受影响，仍用未过滤的 curGroup，符合
// 「在所有视图中依然展示（不隐藏），仅排除统计」的设计。
const statsGroup = computed(() => filterExcludedFromStats(curGroup.value, store.remarks))

const qualityScopeReqNames = computed(() => {
  if (!statsGroup.value) return null
  return groupTraceReqNames(statsGroup.value, ddpToTraceMap.value)
})

const dacMembers = computed(() => versionDacMembers(statsGroup.value, requirementsIndex.value, committers.value, bindings.value))
const nonDacMembers = computed(() => versionNonDacMembers(statsGroup.value, new Set(dacMembers.value.map(m => m.name)), committers.value))
const pplTotal = computed(() => dacMembers.value.length + nonDacMembers.value.length)
const reqTotal = computed(() => (statsGroup.value?.items || []).length)
const reqDac = computed(() => statsGroup.value ? versionDacCount(statsGroup.value, requirementsIndex.value, ddpToTraceMap.value) : 0)

// 趋势图（TrendChart/MemberTrendChart）消费的每个版本分组均需应用排除统计过滤，保持与
// Hero 卡/人员榜单同一口径；filterExcludedFromStats 保留分组其余字段（含 isCurrent），
// 仅替换 items。
const recentVersions = computed(() => recentCanonicalVersions(requirementsIndex.value, todayStr.value, 3, 1, committers.value)
  .map(g => filterExcludedFromStats(g, store.remarks)))
const inactiveReqs = computed(() => {
  const reqs = inactiveRequirements(curGroup.value, requirementsIndex.value, bindings.value, 10, committers.value)
    .map(r => ({ ...r, rdNames: reqCommitterNames(r, committers.value), ddpHref: ddpUrl(r.req_name) }))
  return reqs.slice().sort((a, b) => {
    const aHasRemark = Boolean(store.remarks?.[a.req_name]) ? 1 : 0
    const bHasRemark = Boolean(store.remarks?.[b.req_name]) ? 1 : 0
    return aHasRemark - bHasRemark
  })
})
const activeMembersList = computed(() => versionActiveMembers(statsGroup.value, requirementsIndex.value, committers.value, bindings.value, 10))
const inactiveMembersList = computed(() => versionInactiveMembers(statsGroup.value, requirementsIndex.value, committers.value, bindings.value, 10))

function goMemberDetail(email) {
  if (!email) return
  setActiveTab('tab-people')
  selectPerson(email)
}
function goInactiveMemberDetail(name) {
  if (!name) return
  setActiveTab('tab-current')
  selectCurPerson(name)
}

function goInactiveReqInVersion() {
  setActiveTab('tab-version')
  if (!curGroup.value) return
  selectVersion(curGroup.value.name)
  setVersionScrollTarget(inactiveReqs.value[0]?.req_name || null)
}

function getRemarkTitle(reqName) {
  return formatRemarkTitle(store.remarks?.[reqName])
}

function openRemark(r) {
  showRemarkModal({
    reqName: r.req_name,
    title: r.ddp?.title || r.req_name,
    defaultAuthor: remarkDefaultAuthor(r.rdNames),
    // 候选限定为该需求参与人（rd_list ∪ committers 映射姓名）
    authors: r.rdNames ? r.rdNames.split('、') : [],
  })
}
</script>

<style scoped>
.ov-remark-chip {
  font-size: 11px;
  font-weight: 500;
  padding: 2px 7px;
  border-radius: 5px;
  background: var(--brand-bg);
  color: var(--brand);
  border: 1px solid var(--brand-line);
  cursor: pointer;
  white-space: nowrap;
  flex-shrink: 0;
  max-width: 110px;
  overflow: hidden;
  text-overflow: ellipsis;
  transition: all 0.12s;
}
.ov-remark-chip:hover {
  background: var(--brand);
  color: #fff;
}
.ov-remark-btn {
  font-size: 11px;
  padding: 2px 6px;
  border-radius: 5px;
  background: none;
  color: var(--t4);
  border: 1px dashed var(--line);
  cursor: pointer;
  white-space: nowrap;
  flex-shrink: 0;
  transition: all 0.12s;
}
.ov-remark-btn:hover {
  color: var(--brand);
  border-color: var(--brand-line);
  background: var(--brand-bg);
}
.ov-excluded-badge {
  font-size: 11px;
  font-weight: 600;
  padding: 2px 6px;
  border-radius: 5px;
  background: var(--danger-bg);
  color: var(--danger);
  border: 1px solid var(--danger-line);
  white-space: nowrap;
  flex-shrink: 0;
}

</style>
