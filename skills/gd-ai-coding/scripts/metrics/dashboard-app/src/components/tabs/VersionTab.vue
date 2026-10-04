<template>
  <div class="tab-content ep-page" :class="{ active: store.activeTab === 'tab-version' }" id="tab-version">
    <div class="ep-top-bar">
      <div class="ep-page-title-box">
        <span class="ep-dac-pill">DAC</span>
        <h2 class="ep-page-title">版本视图</h2>
        <span class="ep-crumb" v-if="selectedGroup">/ <b>{{ selectedGroup.name }}</b> / 需求列表</span>
        <span class="ep-crumb" v-else>/ <b>全部 {{ totalVersions }} 个版本</b> · 概览</span>
      </div>
      <div class="ep-top-meta">{{ topMeta }}</div>
    </div>

    <div class="ep-ws">
      <div class="ep-list-pane" id="version-list">
        <div class="ep-list-head">
          <div class="ep-ic-box ep-brand"><EpIcon name="bar" /></div>
          <div class="ep-list-head-col">
            <div class="ep-list-head-title">版本列表</div>
            <div class="ep-list-head-sub">共 {{ totalVersions }} 个版本 · {{ dacVersionCount }} 个使用 dac</div>
          </div>
        </div>
        <div class="ep-list-body">
          <div v-if="!ordered.length" class="ep-empty">暂无数据</div>
          <template v-else>
            <div class="ep-li" :class="{ 'sel-ok': store.versionViewMode === 'overview' }" @click="selectVersionOverview()">
              <div class="ep-li-top">
                <div class="ep-ic-box" :class="{ 'ep-ok': store.versionViewMode === 'overview' }"><EpIcon name="donut" /></div>
                <div class="ep-li-txt">
                  <div class="ep-li-name">概览</div>
                  <div class="ep-li-sub">全部版本 dac 使用情况</div>
                </div>
              </div>
            </div>

            <template v-if="dacVersions.length">
              <div class="ep-group-label">
                <EpIcon name="star" :size="10" class="ep-spark" />使用 dac 版本（{{ dacVersionCount }}）
              </div>
              <div v-for="x in dacVersions" :key="x.g.name" class="ep-li dac" :class="{ sel: isSelectedVersion(x.g.name) }"
                   @click="selectVersion(x.g.name)">
                <div class="ep-li-top">
                  <div class="ep-ic-box" :class="isSelectedVersion(x.g.name) ? 'ep-brand' : 'ep-ok'"><EpIcon name="cube" /></div>
                  <div class="ep-li-txt">
                    <div class="ep-li-name wrap">{{ x.g.name }}</div>
                    <div class="ep-li-sub">{{ versionSub(x) }}</div>
                  </div>
                </div>
                <div class="ep-li-badges">
                  <span v-if="x.i === currentGroupIndex" class="ep-bd ep-solid">当前版本</span>
                  <span class="ep-bd ep-brand">{{ x.reqTotal }} 个需求</span>
                  <span class="ep-bd ep-ok">{{ x.dacReqCount }} 个 dac</span>
                  <span v-if="x.g.isEstimated" class="ep-bd ep-info">预估</span>
                  <span v-if="x.g.isUnassigned" class="ep-bd">未分配</span>
                </div>
              </div>
            </template>

            <template v-if="nonDacVersions.length">
              <div class="ep-group-label">
                <EpIcon name="cube" :size="10" />未使用 dac 版本（{{ nonDacVersionCount }}）
              </div>
              <div v-for="x in nonDacVersions" :key="x.g.name" class="ep-li" :class="{ sel: isSelectedVersion(x.g.name) }"
                   @click="selectVersion(x.g.name)">
                <div class="ep-li-top">
                  <div class="ep-ic-box" :class="{ 'ep-brand': isSelectedVersion(x.g.name) }"><EpIcon name="cube" /></div>
                  <div class="ep-li-txt">
                    <div class="ep-li-name wrap">{{ x.g.name }}</div>
                    <div class="ep-li-sub">{{ versionSub(x) }}</div>
                  </div>
                </div>
                <div class="ep-li-badges">
                  <span v-if="x.i === currentGroupIndex" class="ep-bd ep-solid">当前版本</span>
                  <span class="ep-bd ep-brand">{{ x.reqTotal }} 个需求</span>
                  <span v-if="x.g.isEstimated" class="ep-bd ep-info">预估</span>
                  <span v-if="x.g.isUnassigned" class="ep-bd">未分配</span>
                </div>
              </div>
            </template>
          </template>
        </div>
      </div>

      <div class="ep-detail-col">
        <div class="ep-search" v-show="store.versionViewMode === 'detail'">
          <EpIcon name="search" />
          <input v-model="filterModel" placeholder="搜索需求名称或 ID…">
        </div>
        <div class="ep-detail-pane" id="version-detail" ref="detailRef">
          <div v-if="!ordered.length" class="ep-empty">← 选择一个版本查看该版本需求</div>

          <template v-else-if="store.versionViewMode === 'overview'">
            <QualityStatsCard :req-names="null" subtitle="全部需求累计" />
            <div class="ep-stat-card solo">
              <svg class="ep-donut" viewBox="0 0 56 56">
                <circle :cx="donutGeo.cx" :cy="donutGeo.cy" :r="donutGeo.r" fill="none" stroke="var(--line)" stroke-width="6" />
                <circle v-if="totalVersions > 0" :cx="donutGeo.cx" :cy="donutGeo.cy" :r="donutGeo.r" fill="none" stroke="var(--ok)" stroke-width="6"
                        :stroke-dasharray="`${overviewDash.toFixed(1)} ${donutGeo.circumference.toFixed(1)}`" stroke-linecap="round"
                        :transform="`rotate(-90 ${donutGeo.cx} ${donutGeo.cy})`" />
                <text :x="donutGeo.cx" :y="donutGeo.cy" text-anchor="middle" dominant-baseline="central"
                      font-size="13" font-weight="800" :fill="totalVersions > 0 ? 'var(--ok)' : 'var(--t4)'">{{ totalVersions > 0 ? overviewPct + '%' : '—' }}</text>
              </svg>
              <div class="ep-stat-lines">
                <div class="ep-stat-primary"><em>{{ dacVersionCount }} 个版本使用 dac</em> · {{ nonDacVersionCount }} 个未使用</div>
                <div class="ep-stat-sub">占全部 {{ totalVersions }} 个版本的 {{ overviewPct }}%</div>
                <div class="ep-stat-sub">累计 dac 需求 {{ totalDacReqsAll }} 个 · 版本人均 dac 需求 {{ avgDacReqsAll }} · 累计 dac 行数 {{ fmtLines(totalDacLinesAll) }}</div>
              </div>
              <div class="ep-legend">
                <div class="ep-legend-item"><span class="ep-dot-s"></span>使用 dac {{ dacVersionCount }}</div>
                <div class="ep-legend-item"><span class="ep-dot-s ep-mute"></span>未使用 {{ nonDacVersionCount }}</div>
              </div>
            </div>

            <div class="ep-stat-row">
              <div class="ep-kpi-box">
                <div class="ep-kpi-head"><span>累计 dac 需求</span><span class="ep-kpi-ratio">{{ totalDacReqsAll }} / {{ allReqTotal }}</span></div>
                <div class="ep-kpi-num">{{ totalDacReqsAll }} <span class="ep-kpi-ratio">个</span></div>
                <div class="ep-kpi-bar"><div class="ep-kpi-fill" :style="{ width: dacReqPct + '%', background: 'var(--ok)' }"></div></div>
              </div>
              <div class="ep-kpi-box">
                <div class="ep-kpi-head"><span>使用 dac 版本</span><span class="ep-kpi-ratio">{{ overviewPct }}%</span></div>
                <div class="ep-kpi-num">{{ dacVersionCount }} <span class="ep-kpi-ratio">/ {{ totalVersions }} 个版本</span></div>
                <div class="ep-kpi-bar"><div class="ep-kpi-fill" :style="{ width: overviewPct + '%' }"></div></div>
              </div>
            </div>

            <div class="ep-sec-title">
              <EpIcon name="star" :size="12" class="ep-spark" />
              使用 dac <span class="ep-n">{{ dacVersionCount }} 个版本</span>
            </div>
            <div v-if="dacVersions.length" class="ep-chip-grid">
              <div v-for="x in dacVersions" :key="x.g.name" class="ep-chip dac" @click="selectVersion(x.g.name)">
                <div class="ep-ic-box ep-ok" style="width:22px;height:22px"><EpIcon name="cube" :size="11" /></div>
                <div class="ep-chip-txt">
                  <div class="ep-chip-name">{{ shortVersionLabel(x.g.name) }}</div>
                  <div class="ep-chip-stat">
                    <span class="ep-ok">{{ x.dacReqCount }} dac</span> · {{ x.reqTotal }} 需求{{ x.dacLines ? ' · +' + fmtNum(x.dacLines) + ' 行' : '' }}
                  </div>
                </div>
              </div>
            </div>
            <div v-else class="ep-empty">暂无版本使用 dac</div>

            <div class="ep-sec-title">
              <EpIcon name="cube" :size="12" />
              未使用 dac <span class="ep-n">{{ nonDacVersionCount }} 个版本</span>
            </div>
            <div v-if="nonDacVersions.length" class="ep-chip-grid c6">
              <div v-for="x in nonDacVersions" :key="x.g.name" class="ep-chip" @click="selectVersion(x.g.name)">
                <div class="ep-chip-txt">
                  <div class="ep-chip-name">{{ shortVersionLabel(x.g.name) }}</div>
                  <div class="ep-chip-stat">{{ x.reqTotal }} 需求</div>
                </div>
              </div>
            </div>
            <div v-else class="ep-empty">全部版本均已使用 dac</div>
          </template>

          <template v-else-if="selectedGroup">
            <div class="ep-card tight">
              <div class="ep-detail-head">
                <div class="ep-ic-box ep-brand" style="width:36px;height:36px;border-radius:9px"><EpIcon name="cube" :size="18" /></div>
                <div style="flex:1;min-width:0">
                  <div class="ep-dh-name">{{ selectedGroup.name }}</div>
                  <div class="ep-dh-mail">{{ selectedGroup.time ? selectedGroup.time + ' 发布' : '暂无发布时间' }}</div>
                  <div class="ep-dh-badges">
                    <span class="ep-bd ep-brand">{{ statsReqTotal }} 个需求</span>
                    <span v-if="dacCount" class="ep-bd ep-ok"><EpIcon name="star" :size="9" />{{ dacCount }} 个 dac 需求</span>
                    <span v-if="selectedGroup.isEstimated" class="ep-bd ep-info">预估版本</span>
                    <span v-if="selectedGroup.isUnassigned" class="ep-bd">未分配</span>
                  </div>
                </div>
                <div class="ep-kpi-box" style="width:210px">
                  <div class="ep-kpi-head"><span>dac（AI）开发覆盖</span><span class="ep-kpi-ratio">{{ detailDacPct }}%</span></div>
                  <div class="ep-kpi-num">{{ dacCount }} <span class="ep-kpi-ratio">/ {{ statsReqTotal }} 个需求</span></div>
                  <div class="ep-kpi-bar"><div class="ep-kpi-fill" :style="{ width: detailDacPct + '%', background: 'var(--ok)' }"></div></div>
                </div>
              </div>
            </div>
            <div v-if="!cards.length" class="ep-empty">该版本暂无需求</div>
            <template v-else>
              <!-- 过滤以外层 slot 为单位，隐藏时不会在 .ep-detail-pane 的 gap 中留下空档 -->
              <div v-for="item in cards" :key="item.r.req_name" class="ep-req-slot" :ref="el => setItemRef(item.r.req_name, el)">
                <VersionMergedCard v-if="item.traceReqs.length > 1" :req="item.r" :trace-reqs="item.traceReqs" />
                <ReqCard v-else :req="item.r" :committer-email="singleEmail(item.traceReqs)" :show-participants="true" :trace-reqs="item.traceReqs" />
              </div>
            </template>
          </template>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import { store, selectVersion, selectVersionOverview, setVersionFilterText } from '../../store/dashboard'
import { orderedVersionGroups, versionDacCount, versionDacLines, shortVersionLabel, compareVersionDesc, filterExcludedFromStats } from '../../utils/version'
import { getDdpToTrace } from '../../utils/enrich'
import { fmtNum, fmtLines } from '../../utils/format'
import { useOverviewDetailToggle } from '../../composables/useOverviewDetailToggle'
import ReqCard from '../shared/ReqCard.vue'
import VersionMergedCard from '../shared/VersionMergedCard.vue'
import QualityStatsCard from '../shared/QualityStatsCard.vue'
import EpIcon from '../shared/EpIcon.vue'

const committers = computed(() => store.data?.committers || [])
const requirementsIndex = computed(() => store.data?.requirements_index || [])
const bindings = computed(() => store.bindings || {})
const todayStr = computed(() => new Date().toISOString().slice(0, 10))

const groupsResult = computed(() => orderedVersionGroups(requirementsIndex.value, todayStr.value, committers.value))
const ordered = computed(() => groupsResult.value.ordered)
const currentGroupIndex = computed(() => groupsResult.value.currentGroupIndex)
const ddpToTraceMap = computed(() => getDdpToTrace(bindings.value))

// 排除统计后的版本分组：左侧列表徽章（个需求/个 dac）与详情头部统计（dacCount/detailDacPct）
// 统一基于此计算，勾选「排除统计」后该需求不再计入版本的需求数/dac 需求数。需求卡片本身的
// 展示（cards）不受影响，仍用未过滤的 selectedGroup/ordered，口径与 OverviewTab.vue 一致。
const statsOrdered = computed(() => ordered.value.map(g => filterExcludedFromStats(g, store.remarks)))
const statsSelectedGroup = computed(() => filterExcludedFromStats(selectedGroup.value, store.remarks))

const ranked = computed(() => statsOrdered.value.map((g, i) => {
  const dacReqCount = versionDacCount(g, requirementsIndex.value, ddpToTraceMap.value)
  return {
    g, i,
    hasDac: dacReqCount > 0,
    dacReqCount,
    reqTotal: g.items.length,
    dacLines: versionDacLines(g, requirementsIndex.value, committers.value, bindings.value),
  }
}))
const dacVersions = computed(() => ranked.value.filter(x => x.hasDac))
const nonDacVersions = computed(() => ranked.value.filter(x => !x.hasDac).slice().sort((a, b) => compareVersionDesc(a.g.name, b.g.name)))
const totalVersions = computed(() => ranked.value.length)
const dacVersionCount = computed(() => dacVersions.value.length)
const nonDacVersionCount = computed(() => nonDacVersions.value.length)
const overviewPct = computed(() => totalVersions.value > 0 ? Math.round((dacVersionCount.value / totalVersions.value) * 100) : 0)
const totalDacReqsAll = computed(() => dacVersions.value.reduce((s, x) => s + x.dacReqCount, 0))
const totalDacLinesAll = computed(() => dacVersions.value.reduce((s, x) => s + x.dacLines, 0))
const avgDacReqsAll = computed(() => dacVersionCount.value > 0 ? (totalDacReqsAll.value / dacVersionCount.value).toFixed(1) : '0.0')
const allReqTotal = computed(() => ranked.value.reduce((s, x) => s + x.reqTotal, 0))
const dacReqPct = computed(() => allReqTotal.value > 0 ? Math.round((totalDacReqsAll.value / allReqTotal.value) * 100) : 0)

const generatedAt = computed(() => store.data?.generatedAt || '')
// 数据未返回时数字位以占位符呈现，避免顶栏出现误导性的 0
const topMeta = computed(() => {
  const head = store.data ? `共 ${totalVersions.value} 个版本` : '共 — 个版本'
  return generatedAt.value ? `${head} · 更新时间: ${generatedAt.value}` : head
})

function versionSub(x) {
  return [x.g.time, x.i === currentGroupIndex.value ? '当前版本' : ''].filter(Boolean).join(' · ') || '暂无发布时间'
}

const donutGeo = { cx: 28, cy: 28, r: 23, circumference: 2 * Math.PI * 23 }
const overviewDash = computed(() => donutGeo.circumference * (totalVersions.value > 0 ? dacVersionCount.value / totalVersions.value : 0))

const selectedGroup = computed(() => store.versionViewMode === 'detail'
  ? ordered.value.find(g => g.name === store.selectedVersionKey) || null
  : null)

function isSelectedVersion(name) {
  return store.versionViewMode === 'detail' && store.selectedVersionKey === name
}

const { setItemRef } = useOverviewDetailToggle({
  list: ordered,
  isDetailMode: () => store.versionViewMode === 'detail',
  isSelected: g => g.name === store.selectedVersionKey,
  toOverview: selectVersionOverview,
  selectionKey: () => store.versionScrollTarget,
  isValidKey: key => !!key,
})

const cards = computed(() => {
  const g = selectedGroup.value
  if (!g) return []
  const isNamedGroup = !g.isEstimated && !g.isUnassigned
  const decorated = g.items.map(({ r }) => {
    const rr = (isNamedGroup && r.ddp && !r.ddp.release_version_name)
      ? { ...r, ddp: { ...r.ddp, release_version_name: g.name, release_version_time: g.time } }
      : r
    return { r: rr, traceReqs: (ddpToTraceMap.value[rr.req_name] || []).flatMap(n => requirementsIndex.value.filter(x => x.req_name === n)) }
  })
  decorated.sort((a, b) => cardSortRank(a) - cardSortRank(b))
  return decorated
})

// 排序优先级：已使用 dac trace 的需求最前；未使用 dac 但已添加备注的需求紧跟其后
// （方便复核备注是否准确，避免混在大量未处理的需求中）；剩余未备注需求排最后。
function cardSortRank(item) {
  if (item.traceReqs.length > 0) return 0
  if (store.remarks?.[item.r.req_name]) return 1
  return 2
}
// 详情头部统计（个需求/个 dac 需求/dac 开发覆盖）基于排除统计后的分组，与卡片列表展示（cards，
// 仍用未过滤的 selectedGroup）区分开 —— 勾选「排除统计」的需求卡片照常展示，仅不计入这里的统计数字。
const statsReqTotal = computed(() => statsSelectedGroup.value?.items.length || 0)
const dacCount = computed(() => statsSelectedGroup.value ? versionDacCount(statsSelectedGroup.value, requirementsIndex.value, ddpToTraceMap.value) : 0)
const detailDacPct = computed(() => statsReqTotal.value > 0 ? Math.round((dacCount.value / statsReqTotal.value) * 100) : 0)

function singleEmail(traceReqs) {
  return (traceReqs[0]?.committers || []).find(Boolean) || ''
}

const filterModel = computed({
  get: () => store.versionFilterText,
  set: (v) => setVersionFilterText(v),
})

const detailRef = ref(null)
function applyCardFilter() {
  const root = detailRef.value
  if (!root) return
  const q = (store.versionFilterText || '').toLowerCase()
  root.querySelectorAll('.ep-req-slot').forEach(el => {
    el.style.display = el.textContent.toLowerCase().includes(q) ? '' : 'none'
  })
}
watch([cards, () => store.versionFilterText], applyCardFilter, { flush: 'post' })
</script>
