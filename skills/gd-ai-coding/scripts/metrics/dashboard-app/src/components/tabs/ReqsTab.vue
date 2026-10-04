<template>
  <div class="tab-content ep-page" :class="{ active: store.activeTab === 'tab-reqs' }" id="tab-reqs">
    <div class="ep-top-bar">
      <div class="ep-page-title-box">
        <span class="ep-dac-pill">DAC</span>
        <h2 class="ep-page-title">需求视图</h2>
        <span class="ep-crumb" v-if="store.reqsViewMode === 'detail' && selectedReq">/ <b>{{ selectedReq.req_name }}</b> · {{ detailKindLabel }}</span>
        <span class="ep-crumb" v-else>/ <b>全部 {{ totalReqs }} 个需求</b> · 概览</span>
      </div>
      <div class="ep-top-meta">{{ topMeta }}</div>
    </div>

    <div class="ep-ws">
      <div class="ep-list-pane">
        <div class="ep-list-head" style="display:block">
          <div class="ep-search">
            <EpIcon name="search" />
            <input v-model="filterModel" placeholder="搜索需求名称或 ID…">
          </div>
        </div>
        <div class="ep-list-body" id="reqs-list" ref="listRef">
          <div class="ep-li" :class="{ 'sel-ok': store.reqsViewMode === 'overview' }" @click="selectReqsOverview()">
            <div class="ep-li-top">
              <div class="ep-ic-box" :class="{ 'ep-ok': store.reqsViewMode === 'overview' }"><EpIcon name="donut" /></div>
              <div class="ep-li-txt">
                <div class="ep-li-name">概览</div>
                <div class="ep-li-sub">全部需求 dac 使用情况</div>
              </div>
            </div>
          </div>
          <div v-if="!visible.length" class="ep-empty">暂无数据</div>
          <template v-for="(x, idx) in ordered" :key="x.r.req_name">
            <div v-if="idx === 0 && dacReqsCount > 0" class="ep-group-label">
              <EpIcon name="star" :size="10" class="ep-spark" />使用 dac 需求（{{ dacReqsCount }}）
            </div>
            <div v-if="idx === dacReqsCount && nonDacReqsCount > 0" class="ep-group-label">
              <EpIcon name="file" :size="10" />未使用 dac 需求（{{ nonDacReqsCount }}）
            </div>
            <div class="ep-li ep-req-li" :class="{ dac: x.isAi, sel: isSelectedReq(x.r.req_name) }"
                 @click="selectReq(x.r.req_name)">
              <div class="ep-li-top">
                <div class="ep-ic-box" :class="iconTone(x)"><EpIcon name="file" /></div>
                <div class="ep-li-txt">
                  <div class="ep-li-name wrap">{{ reqTitle(x) }}</div>
                  <div class="ep-li-sub">{{ x.r.req_name }}</div>
                </div>
                <button v-if="x.isDac" class="ep-bd ep-brand" style="flex-shrink:0"
                        @click.stop="showBindModal(x.r.req_name, x.r.committers || [])">
                  <EpIcon name="link" :size="9" />绑定
                </button>
              </div>
              <div v-for="tr in x.traceReqs" :key="tr.req_name" class="reqs-trace-row">
                <EpIcon name="star" :size="9" class="ep-spark" />
                <span class="reqs-trace-name">{{ tr.req_name }}</span>
                <button class="ep-bd ep-danger" @click.stop="unbind(tr.req_name)">
                  <EpIcon name="scissors" :size="9" />解绑
                </button>
              </div>
              <div class="ep-li-badges">
                <span v-if="x.r.is_technical" class="ep-tech-badge" title="技术类需求，不计入需求维度统计">技术</span>
                <span class="ep-bd" :class="x.isDone ? 'ep-ok' : (x.isAi ? 'ep-info' : 'ep-brand')">{{ x.curLabel }}</span>
                <span v-if="x.s.total" class="ep-bd ep-info">{{ x.s.done }}/{{ x.s.total }} 功能</span>
              </div>
              <div v-if="reqLines(x)" class="ep-li-stat">+{{ fmtNum(reqLines(x)) }} 行</div>
            </div>
          </template>
        </div>
      </div>

      <div class="ep-detail-pane" id="reqs-detail">
        <template v-if="store.reqsViewMode === 'overview'">
          <div class="ep-stat-card solo">
            <svg class="ep-donut" viewBox="0 0 56 56">
              <circle :cx="donutGeo.cx" :cy="donutGeo.cy" :r="donutGeo.r" fill="none" stroke="var(--line)" stroke-width="6" />
              <circle v-if="totalReqs > 0" :cx="donutGeo.cx" :cy="donutGeo.cy" :r="donutGeo.r" fill="none" stroke="var(--ok)" stroke-width="6"
                      :stroke-dasharray="`${overviewDash.toFixed(1)} ${donutGeo.circumference.toFixed(1)}`" stroke-linecap="round"
                      :transform="`rotate(-90 ${donutGeo.cx} ${donutGeo.cy})`" />
              <text :x="donutGeo.cx" :y="donutGeo.cy" text-anchor="middle" dominant-baseline="central"
                    font-size="13" font-weight="800" :fill="totalReqs > 0 ? 'var(--ok)' : 'var(--t4)'">{{ totalReqs > 0 ? overviewPct + '%' : '—' }}</text>
            </svg>
            <div class="ep-stat-lines">
              <div class="ep-stat-primary"><em>{{ dacReqCountGlobal }} 个需求使用 dac</em> · {{ totalReqs - dacReqCountGlobal }} 个未使用</div>
              <div class="ep-stat-sub">占全部 {{ totalReqs }} 个需求的 {{ overviewPct }}%</div>
              <div class="ep-stat-sub">累计 dac 行数 {{ fmtLines(totalDacLines) }}</div>
            </div>
            <div class="ep-legend">
              <div class="ep-legend-item"><span class="ep-dot-s"></span>使用 dac {{ dacReqCountGlobal }}</div>
              <div class="ep-legend-item"><span class="ep-dot-s ep-mute"></span>未使用 {{ totalReqs - dacReqCountGlobal }}</div>
            </div>
          </div>

          <div class="ep-stat-row">
            <div class="ep-kpi-box">
              <div class="ep-kpi-head"><span>dac 需求渗透率</span><span class="ep-kpi-ratio">{{ dacReqCountGlobal }} / {{ totalReqs }}</span></div>
              <div class="ep-kpi-num">{{ overviewPct }}% <span class="ep-kpi-ratio">需求覆盖</span></div>
              <div class="ep-kpi-bar"><div class="ep-kpi-fill" :style="{ width: overviewPct + '%', background: 'var(--ok)' }"></div></div>
            </div>
            <div class="ep-kpi-box">
              <div class="ep-kpi-head"><span>dac 需求已完成</span><span class="ep-kpi-ratio">{{ dacDoneCount }} / {{ dacReqsCount }}</span></div>
              <div class="ep-kpi-num">{{ dacDonePct }}% <span class="ep-kpi-ratio">已完成</span></div>
              <div class="ep-kpi-bar"><div class="ep-kpi-fill" :style="{ width: dacDonePct + '%' }"></div></div>
            </div>
          </div>

          <div class="ep-sec-title">
            <EpIcon name="star" :size="12" class="ep-spark" />
            使用 dac <span class="ep-n">{{ dacReqsCount }} 个需求</span>
          </div>
          <div v-if="dacReqsCount" class="ep-chip-grid c3">
            <div v-for="x in dacReqsList" :key="x.r.req_name" class="ep-chip dac" @click="selectReq(x.r.req_name)">
              <div class="ep-chip-txt">
                <div class="ep-chip-name reqs-chip-title">
                  <span class="reqs-chip-txt">{{ reqTitle(x) }}</span>
                  <span v-if="x.r.is_technical" class="ep-tech-badge" title="技术类需求，不计入需求维度统计">技术</span>
                </div>
                <div class="ep-chip-stat">
                  {{ x.r.req_name }}<template v-if="reqLines(x)"> · <span class="ep-ok">+{{ fmtNum(reqLines(x)) }} 行</span></template>
                </div>
              </div>
            </div>
          </div>
          <div v-else class="ep-empty">暂无需求使用 dac</div>

          <div class="ep-sec-title">
            <EpIcon name="file" :size="12" />
            未使用 dac <span class="ep-n">{{ nonDacReqsCount }} 个需求</span>
          </div>
          <div v-if="nonDacReqsCount" class="ep-chip-grid c3">
            <div v-for="x in nonDacReqsList" :key="x.r.req_name" class="ep-chip" @click="selectReq(x.r.req_name)">
              <div class="ep-chip-txt">
                <div class="ep-chip-name reqs-chip-title">
                  <span class="reqs-chip-txt">{{ reqTitle(x) }}</span>
                  <span v-if="x.r.is_technical" class="ep-tech-badge" title="技术类需求，不计入需求维度统计">技术</span>
                </div>
                <div class="ep-chip-stat">{{ x.r.req_name }} · {{ x.curLabel }}</div>
              </div>
            </div>
          </div>
          <div v-else class="ep-empty">全部需求均已使用 dac</div>
        </template>

        <template v-else-if="store.reqsViewMode === 'detail'">
          <div v-if="!selectedReq" class="ep-empty">← 选择一个需求查看详情</div>

          <template v-else-if="isMergedDetail">
            <div class="ep-card tight">
              <div class="ep-req-head">
                <div style="min-width:0">
                  <div class="ep-req-title" style="font-size:16px">{{ selectedReq.ddp?.title || selectedReq.req_name }}</div>
                  <div class="ep-req-id">
                    <a v-if="detailDdpUrl" :href="detailDdpUrl" target="_blank" rel="noopener noreferrer" @click.stop>{{ selectedReq.req_name }} ↗</a>
                    <template v-else>{{ selectedReq.req_name }}</template>
                  </div>
                  <div class="ep-dh-badges">
                    <span v-if="selectedReq.is_technical" class="ep-tech-badge" title="技术类需求，不计入需求维度统计">技术</span>
                    <span v-if="selectedReq.ddp?.state" class="ep-bd">{{ selectedReq.ddp.state }}</span>
                    <span v-if="versionBadgeText" class="ep-bd"><EpIcon name="rocket" :size="9" />{{ versionBadgeText }}</span>
                    <span v-else-if="selectedReq.ddp?.expected_release" class="ep-bd"><EpIcon name="calendar" :size="9" />{{ selectedReq.ddp.expected_release }}</span>
                    <span class="ep-bd ep-info">{{ detailTraceReqs.length }} 个 DAC AI 工作流</span>
                    <span v-if="mergedCommitCount" class="ep-bd ep-ok">共 {{ fmtNum(mergedCommitCount) }} 次 AI 辅助提交</span>
                  </div>
                </div>
                <div class="ep-req-side"><span class="ep-bd" :class="ddpDone ? 'ep-ok' : 'ep-solid'">{{ ddpLabel }}</span></div>
              </div>
            </div>

            <div class="ep-card tight">
              <div class="ep-req-sub-title"><EpIcon name="user" :size="11" />参与成员（{{ ddpOwnerRows.length }}）</div>
              <template v-if="ddpOwnerRows.length">
                <OwnerRow v-for="o in ddpOwnerRows" :key="o.key" :owner="o" />
              </template>
              <div v-else class="ep-empty">暂无参与者</div>
            </div>

            <div v-for="tr in detailTraceReqs" :key="tr.req_name" class="ep-req hl">
              <div class="ep-req-head">
                <div style="min-width:0">
                  <div class="ep-req-flow" style="margin-top:0">
                    <EpIcon name="star" :size="11" />DAC AI 工作流 <code>{{ tr.req_name }}</code>
                  </div>
                  <div v-if="tr.commit_count" class="ep-req-foot">共 {{ fmtNum(tr.commit_count) }} 次 AI 辅助提交</div>
                </div>
                <div class="ep-req-side">
                  <span class="ep-bd ep-info">{{ traceLabel(tr) }}</span>
                  <button class="ep-bd ep-danger" @click.stop="unbind(tr.req_name)">
                    <EpIcon name="scissors" :size="9" />解绑
                  </button>
                </div>
              </div>
              <TracePhaseStepper :phases="tr.phases" :cur="currentTracePhase(tr.phases)" :skipped-stages="tr.skipped_stages" />
              <ReqQualityBadges :req-name="tr.req_name" :alt-names="[selectedReq.req_name]" />
              <FeaturePills :features="tr.features" />
            </div>

            <div class="ep-req">
              <div class="ep-req-head">
                <div class="ep-req-sub-title" style="margin:0"><EpIcon name="bar" :size="11" />DDP 需求进度</div>
                <div class="ep-req-side"><span class="ep-bd" :class="ddpDone ? 'ep-ok' : 'ep-brand'">{{ ddpLabel }}</span></div>
              </div>
              <PhaseStepper :phases="selectedReq.phases" :cur="ddpCur" />
            </div>
          </template>

          <template v-else-if="isDacOnlyDetail">
            <div class="ep-card tight">
              <div class="ep-req-head">
                <div style="min-width:0">
                  <div class="ep-req-flow" style="margin-top:0">
                    <EpIcon name="star" :size="11" />DAC AI 工作流 <code>{{ selectedReq.req_name }}</code>
                  </div>
                  <div class="ep-dh-badges">
                    <span class="ep-bd" :class="dacIsDone ? 'ep-ok' : 'ep-info'">{{ dacCurLabel }}</span>
                    <span v-if="dacCommitCount" class="ep-bd ep-ok">共 {{ fmtNum(dacCommitCount) }} 次 AI 辅助提交</span>
                    <span v-if="dacTs" class="ep-bd"><EpIcon name="clock" :size="9" />最后提交：{{ dacTs }}</span>
                  </div>
                </div>
                <div class="ep-req-side">
                  <button v-if="!dacAlreadyBound" class="ep-bd ep-brand"
                          @click.stop="showBindModal(selectedReq.req_name, selectedReq.committers || [])">
                    <EpIcon name="link" :size="9" />绑定到 DDP 需求
                  </button>
                </div>
              </div>
            </div>

            <div class="ep-card tight">
              <div class="ep-req-sub-title"><EpIcon name="user" :size="11" />参与成员（{{ dacOwnerRows.length }}）</div>
              <template v-if="dacOwnerRows.length">
                <OwnerRow v-for="o in dacOwnerRows" :key="o.key" :owner="o" />
              </template>
              <div v-else class="ep-empty">暂无参与者</div>
            </div>

            <div class="ep-req hl">
              <div class="ep-req-sub-title"><EpIcon name="bar" :size="11" />DAC 工作流进度</div>
              <TracePhaseStepper :phases="selectedReq.phases" :cur="dacCur" :skipped-stages="selectedReq.skipped_stages" />
              <ReqQualityBadges :req-name="selectedReq.req_name" />
              <FeaturePills :features="selectedReq.features" />
            </div>
          </template>

          <template v-else>
            <div class="ep-card tight">
              <div class="ep-req-head">
                <div style="min-width:0">
                  <div class="ep-req-title" style="font-size:16px">{{ selectedReq.ddp?.title || selectedReq.req_name }}</div>
                  <div class="ep-req-id">
                    <a v-if="detailDdpUrl" :href="detailDdpUrl" target="_blank" rel="noopener noreferrer" @click.stop>{{ selectedReq.req_name }} ↗</a>
                    <template v-else>{{ selectedReq.req_name }}</template>
                  </div>
                  <div class="ep-dh-badges">
                    <span v-if="selectedReq.is_technical" class="ep-tech-badge" title="技术类需求，不计入需求维度统计">技术</span>
                    <span v-if="selectedReq.ddp?.state" class="ep-bd">{{ selectedReq.ddp.state }}</span>
                    <span v-if="versionBadgeText" class="ep-bd"><EpIcon name="rocket" :size="9" />{{ versionBadgeText }}</span>
                    <span v-else-if="selectedReq.ddp?.expected_release" class="ep-bd"><EpIcon name="calendar" :size="9" />{{ selectedReq.ddp.expected_release }}</span>
                  </div>
                </div>
                <div class="ep-req-side"><span class="ep-bd" :class="ddpDone ? 'ep-ok' : 'ep-solid'">{{ ddpLabel }}</span></div>
              </div>
            </div>

            <div class="ep-card tight">
              <div class="ep-req-sub-title"><EpIcon name="user" :size="11" />参与成员（{{ ddpOwnerRows.length }}）</div>
              <template v-if="ddpOwnerRows.length">
                <OwnerRow v-for="o in ddpOwnerRows" :key="o.key" :owner="o" />
              </template>
              <div v-else class="ep-empty">暂无参与者</div>
            </div>

            <div class="ep-req">
              <div class="ep-req-head">
                <div class="ep-req-sub-title" style="margin:0"><EpIcon name="bar" :size="11" />需求进度</div>
                <div class="ep-req-side"><span class="ep-bd" :class="ddpDone ? 'ep-ok' : 'ep-brand'">{{ ddpLabel }}</span></div>
              </div>
              <PhaseStepper :phases="selectedReq.phases" :cur="ddpCur" />
              <FeaturePills :features="selectedReq.features" />
            </div>
          </template>
        </template>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import { store, selectReq, selectReqsOverview, setReqsFilterText, showBindModal, setBindings } from '../../store/dashboard'
import { getDdpToTrace } from '../../utils/enrich'
import { ddpUrl } from '../../utils/ddp'
import { globalDacStats, reqCommitterNames } from '../../utils/version'
import { fmtNum, fmtLines, fmtRelTime } from '../../utils/format'
import { currentPhase, currentTracePhase, displayTracePhase, PHASE_LABEL, TRACE_PHASE_LABEL, featureSummary } from '../../utils/phase'
import { postUnbind } from '../../api/bindings'
import { useOverviewDetailToggle } from '../../composables/useOverviewDetailToggle'
import PhaseStepper from '../shared/PhaseStepper.vue'
import TracePhaseStepper from '../shared/TracePhaseStepper.vue'
import FeaturePills from '../shared/FeaturePills.vue'
import ReqQualityBadges from '../shared/ReqQualityBadges.vue'
import OwnerRow from '../shared/OwnerRow.vue'
import EpIcon from '../shared/EpIcon.vue'

const committers = computed(() => store.data?.committers || [])
const requirementsIndex = computed(() => store.data?.requirements_index || [])
const bindings = computed(() => store.bindings || {})
const ddpToTraceMap = computed(() => getDdpToTrace(bindings.value))

function buildSidebarItem(r, i, isDac, isBoundAi, boundTraceReqNames) {
  const idx = requirementsIndex.value
  const traceReqs = isBoundAi ? boundTraceReqNames.flatMap(name => idx.filter(x => x.req_name === name)) : []
  const traceReq = traceReqs[0] || null
  const isAi = isDac || isBoundAi
  let cur, curLabel, isDone, s
  if (isDac) {
    cur = currentTracePhase(r.phases)
    curLabel = TRACE_PHASE_LABEL[displayTracePhase(cur)] || cur
    isDone = cur === 'done'
    s = featureSummary(r.features)
  } else if (isBoundAi && traceReq) {
    cur = currentTracePhase(traceReq.phases)
    curLabel = TRACE_PHASE_LABEL[displayTracePhase(cur)] || cur
    isDone = cur === 'done'
    s = featureSummary(traceReq.features)
  } else {
    cur = currentPhase(r.phases)
    curLabel = PHASE_LABEL[cur] || cur
    isDone = cur === 'released'
    s = featureSummary(r.features)
  }
  return { r, i, isDac, isBoundAi, isAi, traceReqs, curLabel, isDone, s }
}

function activeTs(r) {
  return r.last_commit_ts || r.reported_at || 0
}

const visible = computed(() => {
  const idx = requirementsIndex.value
  const ddpToTrace = ddpToTraceMap.value
  const boundTraceSet = new Set(Object.keys(bindings.value))
  const items = []
  idx.forEach((r, i) => {
    const isDac = !r.ddp && (r.workflow_session_ids || []).length > 0
    if (isDac && boundTraceSet.has(r.req_name)) return
    if (r.ddp && reqCommitterNames(r, committers.value) === '' && !(ddpToTrace[r.req_name] || []).length) return
    const boundTraceReqNames = r.ddp ? (ddpToTrace[r.req_name] || []) : []
    items.push(buildSidebarItem(r, i, isDac, boundTraceReqNames.length > 0, boundTraceReqNames))
  })
  items.sort((a, b) => (a.isBoundAi === b.isBoundAi ? 0 : (a.isBoundAi ? -1 : 1)) || (activeTs(b.r) - activeTs(a.r)) || (a.i - b.i))
  return items
})

const globalStats = computed(() => globalDacStats(committers.value, requirementsIndex.value, bindings.value))
const totalReqs = computed(() => globalStats.value.reqs)
const dacReqCountGlobal = computed(() => globalStats.value.dacReqCount)
const overviewPct = computed(() => totalReqs.value > 0 ? Math.round((dacReqCountGlobal.value / totalReqs.value) * 100) : 0)

const dacReqsList = computed(() => visible.value.filter(x => x.isAi))
const nonDacReqsList = computed(() => visible.value.filter(x => !x.isAi))
const dacReqsCount = computed(() => dacReqsList.value.length)
const nonDacReqsCount = computed(() => nonDacReqsList.value.length)
// 列表按「使用 dac / 未使用 dac」两段渲染，与右侧芯片墙同序
const ordered = computed(() => [...dacReqsList.value, ...nonDacReqsList.value])
const dacDoneCount = computed(() => dacReqsList.value.filter(x => x.isDone).length)
const dacDonePct = computed(() => dacReqsCount.value > 0 ? Math.round((dacDoneCount.value / dacReqsCount.value) * 100) : 0)

const generatedAt = computed(() => store.data?.generatedAt || '')
// 数据未返回时数字位以占位符呈现，避免顶栏出现误导性的 0
const topMeta = computed(() => {
  const head = store.data ? `共 ${totalReqs.value} 个需求` : '共 — 个需求'
  return generatedAt.value ? `${head} · 更新时间: ${generatedAt.value}` : head
})

function reqLines(x) {
  if (x.isDac) return x.r.lines_added || 0
  if (x.isBoundAi) return x.traceReqs.reduce((s, t) => s + (t.lines_added || 0), 0)
  return 0
}
const totalDacLines = computed(() => dacReqsList.value.reduce((s, x) => s + reqLines(x), 0))

const donutGeo = { cx: 28, cy: 28, r: 23, circumference: 2 * Math.PI * 23 }
const overviewDash = computed(() => donutGeo.circumference * (totalReqs.value > 0 ? dacReqCountGlobal.value / totalReqs.value : 0))

function reqTitle(x) {
  return x.isDac ? x.r.req_name : (x.r.ddp?.title || x.r.req_name)
}
function isSelectedReq(reqName) {
  return store.reqsViewMode === 'detail' && store.selectedReqName === reqName
}
function iconTone(x) {
  if (isSelectedReq(x.r.req_name)) return 'ep-brand'
  return x.isAi ? 'ep-ok' : ''
}

useOverviewDetailToggle({
  list: visible,
  isDetailMode: () => store.reqsViewMode === 'detail',
  isSelected: x => x.r.req_name === store.selectedReqName,
  toOverview: selectReqsOverview,
})

const selectedReq = computed(() => requirementsIndex.value.find(r => r.req_name === store.selectedReqName) || null)
const detailTraceReqs = computed(() => {
  const r = selectedReq.value
  if (!r || !r.ddp) return []
  const names = ddpToTraceMap.value[r.req_name] || []
  return names.flatMap(n => requirementsIndex.value.filter(x => x.req_name === n))
})
const isMergedDetail = computed(() => detailTraceReqs.value.length > 0)
const isDacOnlyDetail = computed(() => !!selectedReq.value && !selectedReq.value.ddp && (selectedReq.value.workflow_session_ids || []).length > 0)
const mergedCommitCount = computed(() => detailTraceReqs.value.reduce((s, t) => s + (t.commit_count || 0), 0))
const detailKindLabel = computed(() => {
  if (isMergedDetail.value) return `${detailTraceReqs.value.length} 个 DAC AI 工作流`
  if (isDacOnlyDetail.value) return 'DAC AI 工作流'
  return '需求详情'
})

const detailDdpUrl = computed(() => ddpUrl(selectedReq.value?.req_name))
const versionBadgeText = computed(() => {
  const ddp = selectedReq.value?.ddp
  if (!ddp?.release_version_name) return ''
  return ddp.release_version_name + (ddp.release_version_time ? ` · ${ddp.release_version_time}` : '')
})

const ddpCur = computed(() => currentPhase(selectedReq.value?.phases))
const ddpLabel = computed(() => PHASE_LABEL[ddpCur.value] || ddpCur.value)
const ddpDone = computed(() => ddpCur.value === 'released')

const dacCur = computed(() => currentTracePhase(selectedReq.value?.phases))
const dacCurLabel = computed(() => TRACE_PHASE_LABEL[displayTracePhase(dacCur.value)] || dacCur.value)
const dacIsDone = computed(() => dacCur.value === 'done')
const dacTs = computed(() => fmtRelTime(selectedReq.value?.last_commit_ts))
const dacCommitCount = computed(() => selectedReq.value?.commit_count || 0)
const dacAlreadyBound = computed(() => Object.keys(bindings.value).includes(selectedReq.value?.req_name))

function ownerRow(email, tag, tagStyle) {
  const c = committers.value.find(x => x.committer === email)
  const name = c?.committer_name || email
  return { key: email, name, email, tag, tagStyle, avatarStyle: tag === 'DAC' ? 'background:var(--brand)' : '' }
}
function pmOwnerRow(pmName) {
  return { key: 'pm', name: pmName, email: '产品经理', tag: 'PM', tagStyle: 'background:var(--info-bg);color:var(--info)', avatarStyle: 'background:var(--info)' }
}

const dacOwnerRows = computed(() => (selectedReq.value?.committers || []).map(e => ownerRow(e, 'DAC', 'background:var(--brand-bg);color:var(--brand)')))
const ddpOwnerRows = computed(() => {
  const r = selectedReq.value
  if (!r) return []
  const rdEmails = [...new Set([...(r.rd_list || []), ...(r.committers || [])])]
  const rows = rdEmails.map(e => ownerRow(e, 'RD', 'background:var(--ok-bg);color:var(--ok-text)'))
  const pmName = r.ddp?.pm_owner || ''
  return pmName ? [pmOwnerRow(pmName), ...rows] : rows
})

function traceLabel(tr) {
  const c = displayTracePhase(currentTracePhase(tr.phases))
  return TRACE_PHASE_LABEL[c] || c
}

async function unbind(traceReqName) {
  try {
    const b = await postUnbind(traceReqName)
    setBindings(b)
  } catch (e) {
    alert('解绑失败: ' + e.message)
  }
}

const filterModel = computed({
  get: () => store.reqsFilterText,
  set: (v) => setReqsFilterText(v),
})

const listRef = ref(null)
function applyListFilter() {
  const root = listRef.value
  if (!root) return
  const q = (store.reqsFilterText || '').toLowerCase()
  let label = null
  let shown = 0
  // 分组标题随本组命中数显隐，避免过滤后残留空分组
  const flushLabel = () => { if (label) label.style.display = shown > 0 ? '' : 'none' }
  for (const el of root.children) {
    if (el.classList.contains('ep-group-label')) {
      flushLabel()
      label = el
      shown = 0
      continue
    }
    if (!el.classList.contains('ep-req-li')) continue
    const hit = el.textContent.toLowerCase().includes(q)
    el.style.display = hit ? '' : 'none'
    if (hit) shown++
  }
  flushLabel()
}
watch([visible, () => store.reqsFilterText], applyListFilter, { flush: 'post' })
</script>

<style scoped>
/* 已绑定的 DAC 工作流行（列表项内），仅本组件单一消费点 */
.reqs-trace-row {
  display: flex; align-items: center; gap: 5px;
  margin-top: 5px; font-size: 10px; color: var(--ok-text);
}
.reqs-trace-name {
  min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  font-family: "SF Mono", ui-monospace, monospace;
}
/* 概览芯片墙标题行：标题可截断、技术角标固定同行不换行不被 ellipsis 吞掉
   （base.css 的 .ep-chip-name 为 block 单行截断，直接内嵌角标会被截断，故此处包 flex） */
.reqs-chip-title { display: flex; align-items: center; gap: 5px; }
.reqs-chip-title .reqs-chip-txt {
  min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.ep-req-id a { color: inherit; text-decoration: none; }
.ep-req-id a:hover { text-decoration: underline; }
</style>
