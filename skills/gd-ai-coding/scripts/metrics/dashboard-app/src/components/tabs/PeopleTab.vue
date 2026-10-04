<template>
  <div class="tab-content ep-page" :class="{ active: store.activeTab === 'tab-people' }" id="tab-people">
    <div class="ep-top-bar">
      <div class="ep-page-title-box">
        <span class="ep-dac-pill">DAC</span>
        <h2 class="ep-page-title">人员视图</h2>
        <span class="ep-crumb" v-if="selectedMember">/ <b>{{ memberName(selectedMember) }}</b> / 需求明细</span>
        <span class="ep-crumb" v-else>/ <b>团队概览</b> · {{ totalMembers }} 位成员</span>
      </div>
      <div class="ep-top-meta">{{ topMeta }}</div>
    </div>

    <div class="ep-ws">
      <div class="ep-list-pane" id="people-list">
        <div class="ep-list-head">
          <div class="ep-ic-box ep-brand"><EpIcon name="users" /></div>
          <div class="ep-list-head-col">
            <div class="ep-list-head-title">团队成员</div>
            <div class="ep-list-head-sub">{{ totalMembers }} 位成员 · {{ dacMembers.length }} 人使用 dac</div>
          </div>
        </div>
        <div class="ep-list-body">
          <div class="people-sort-toggle" @click="togglePeopleSortMode()">
            <span>{{ store.peopleSortMode === 'activity' ? '按最近活跃排序' : '按 dac 使用量排序' }}</span>
            <EpIcon name="refresh" :size="12" />
          </div>

          <div v-if="!ranked.length" class="ep-empty">暂无数据</div>
          <template v-else>
            <div class="ep-li" :class="{ 'sel-ok': store.peopleViewMode === 'overview' }" @click="selectPeopleOverview()">
              <div class="ep-li-top">
                <div class="ep-ic-box" :class="{ 'ep-ok': store.peopleViewMode === 'overview' }"><EpIcon name="donut" /></div>
                <div class="ep-li-txt">
                  <div class="ep-li-name">团队概览</div>
                  <div class="ep-li-sub">全员 dac 使用情况</div>
                </div>
              </div>
            </div>

            <template v-for="(x, idx) in ranked" :key="x.c.committer">
              <div v-if="idx === 0 && dacMembers.length > 0" class="ep-group-label">
                <EpIcon name="star" :size="10" class="ep-spark" />使用 dac 成员（{{ dacMembers.length }}）
              </div>
              <div v-if="idx === dacMembers.length && nonDacMembers.length > 0" class="ep-group-label">
                <EpIcon name="user" :size="10" />未使用 dac 成员（{{ nonDacMembers.length }}）
              </div>
              <div class="ep-li" :class="{ dac: x.hasAi, sel: isSelectedMember(x.c.committer) }"
                   :ref="el => setItemRef(x.c.committer, el)"
                   @click="onSidebarClick(x.c.committer)">
                <div class="ep-li-top">
                  <div class="ep-av" :class="avatarTone(x, isSelectedMember(x.c.committer))">{{ initials(memberName(x)) }}</div>
                  <div class="ep-li-txt">
                    <div class="ep-li-name">{{ memberName(x) }}</div>
                    <div class="ep-li-sub" :title="x.c.committer">{{ x.c.committer }}</div>
                  </div>
                </div>
                <div class="ep-li-badges">
                  <span class="ep-bd ep-brand">{{ x.reqCount }} 个需求</span>
                  <span v-if="x.doneCount" class="ep-bd ep-ok">{{ x.doneCount }} 已完成</span>
                  <span v-if="x.hasAi" class="ep-bd ep-ok">
                    <EpIcon name="star" :size="9" />{{ x.dacReqs }} 个 dac 需求
                  </span>
                  <span v-if="personalBadge(x.c.committer)" class="ep-bd ep-info"
                        :style="personalBadge(x.c.committer).total === null ? 'opacity:0.5' : ''">
                    <EpIcon name="user" :size="9" />vibe coding {{ personalBadge(x.c.committer).text }}
                  </span>
                </div>
                <div v-if="dacStatLine(x)" class="ep-li-stat">{{ dacStatLine(x) }}</div>
                <div v-if="x.c.ai_stats" class="ai-usage-row">
                  <span class="ai-chip"><EpIcon name="bot" :size="9" />AI</span>
                  <span>{{ fmtNum(x.c.ai_stats.ai_commits) }} 次提交</span>
                  <span>·</span>
                  <span>{{ fmtLines(x.c.ai_stats.ai_lines_accepted) }} 行采纳</span>
                  <template v-if="aiModelsLabel(x.c.ai_stats)">
                    <span>·</span><span>{{ aiModelsLabel(x.c.ai_stats) }}</span>
                  </template>
                </div>
              </div>
            </template>
          </template>
        </div>
      </div>

      <div class="ep-detail-pane" id="people-detail">
        <template v-if="store.peopleViewMode === 'overview'">
          <div v-if="!ranked.length" class="ep-empty">暂无数据</div>
          <template v-else>
            <div class="ep-stat-card solo">
              <svg class="ep-donut" viewBox="0 0 56 56">
                <circle :cx="donut.cx" :cy="donut.cy" :r="donut.r" fill="none" stroke="var(--line)" stroke-width="6" />
                <circle v-if="totalMembers > 0" :cx="donut.cx" :cy="donut.cy" :r="donut.r" fill="none" stroke="var(--ok)" stroke-width="6"
                        :stroke-dasharray="`${donutDash.toFixed(1)} ${donut.circumference.toFixed(1)}`" stroke-linecap="round"
                        :transform="`rotate(-90 ${donut.cx} ${donut.cy})`" />
                <text :x="donut.cx" :y="donut.cy" text-anchor="middle" dominant-baseline="central"
                      font-size="13" font-weight="800" :fill="totalMembers > 0 ? 'var(--ok)' : 'var(--t4)'">{{ totalMembers > 0 ? overviewPct + '%' : '—' }}</text>
              </svg>
              <div class="ep-stat-lines">
                <div class="ep-stat-primary"><em>{{ dacMembers.length }} 人使用 dac</em> · {{ nonDacMembers.length }} 人未使用</div>
                <div class="ep-stat-sub">占团队 {{ totalMembers }} 位成员的 {{ overviewPct }}%</div>
                <div class="ep-stat-sub">
                  累计 dac 行数 {{ fmtLines(totalDacLines) }} · 人均 dac 需求 {{ avgDacReqs }}<template v-if="vibeKpiVisible"> · vibe coding 总量 {{ fmtLines(vibeTotal) }}</template>
                </div>
              </div>
              <div class="ep-legend">
                <div class="ep-legend-item"><span class="ep-dot-s"></span>使用 dac {{ dacMembers.length }}</div>
                <div class="ep-legend-item"><span class="ep-dot-s ep-mute"></span>未使用 {{ nonDacMembers.length }}</div>
              </div>
            </div>

            <div :class="vibeKpiVisible ? 'ep-kpi-row' : 'ep-stat-row'">
              <div class="ep-kpi-box">
                <div class="ep-kpi-head"><span>累计 dac 需求</span><span class="ep-kpi-ratio">{{ totalDacReqs }} / {{ allReqTotal }}</span></div>
                <div class="ep-kpi-num">{{ totalDacReqs }} <span class="ep-kpi-ratio">个</span></div>
                <div class="ep-kpi-bar"><div class="ep-kpi-fill" :style="{ width: dacReqPct + '%', background: 'var(--ok)' }"></div></div>
              </div>
              <div class="ep-kpi-box">
                <div class="ep-kpi-head"><span>使用 dac 成员</span><span class="ep-kpi-ratio">{{ overviewPct }}%</span></div>
                <div class="ep-kpi-num">{{ dacMembers.length }} <span class="ep-kpi-ratio">/ {{ totalMembers }} 人</span></div>
                <div class="ep-kpi-bar"><div class="ep-kpi-fill" :style="{ width: overviewPct + '%' }"></div></div>
              </div>
              <div v-if="vibeKpiVisible" class="ep-kpi-box">
                <div class="ep-kpi-head"><span>vibe coding 总量</span><span class="ep-kpi-ratio">{{ vibePctText }}</span></div>
                <div class="ep-kpi-num">{{ fmtLines(vibeTotal) }} <span class="ep-kpi-ratio">行</span></div>
                <div class="ep-kpi-bar"><div class="ep-kpi-fill" :style="{ width: vibeBarWidth + '%', background: 'var(--info)' }"></div></div>
              </div>
            </div>

            <div class="ep-sec-title">
              <EpIcon name="star" :size="12" class="ep-spark" />
              使用 dac <span class="ep-n">{{ dacMembers.length }} 人</span>
            </div>
            <div v-if="dacMembers.length" class="ep-chip-grid c6">
              <div v-for="x in dacMembers" :key="x.c.committer" class="ep-chip dac" @click="onOverviewCardClick(x.c.committer)">
                <div class="ep-av ep-ok sm">{{ initials(memberName(x)) }}</div>
                <div class="ep-chip-txt">
                  <div class="ep-chip-name">{{ memberName(x) }}</div>
                  <div class="ep-chip-stat">
                    <span class="ep-ok">{{ x.dacReqs }} dac</span>{{ x.dacLines ? ' · +' + fmtNum(x.dacLines) : '' }}
                  </div>
                </div>
              </div>
            </div>
            <div v-else class="ep-empty">团队暂无成员使用 dac</div>

            <div class="ep-sec-title">
              <EpIcon name="user" :size="12" />
              未使用 dac <span class="ep-n">{{ nonDacMembers.length }} 人</span>
            </div>
            <div v-if="nonDacMembers.length" class="ep-chip-grid c6">
              <div v-for="x in nonDacMembers" :key="x.c.committer" class="ep-chip" @click="onOverviewCardClick(x.c.committer)">
                <div class="ep-av sm">{{ initials(memberName(x)) }}</div>
                <div class="ep-chip-txt">
                  <div class="ep-chip-name">{{ memberName(x) }}</div>
                  <div class="ep-chip-stat">未使用 dac</div>
                </div>
              </div>
            </div>
            <div v-else class="ep-empty">团队成员均已使用 dac</div>
          </template>
        </template>
        <template v-else>
          <template v-if="selectedMember && selectedMember.reqs.length">
            <div class="ep-card tight">
              <div class="ep-detail-head">
                <div class="ep-av lg" :class="selectedMember.hasAi ? 'ep-ok' : ''">{{ initials(memberName(selectedMember)) }}</div>
                <div style="flex:1;min-width:0">
                  <div class="ep-dh-name">{{ memberName(selectedMember) }}</div>
                  <div class="ep-dh-mail">{{ selectedMember.c.committer }}</div>
                  <div class="ep-dh-badges">
                    <span class="ep-bd ep-brand">{{ selectedMember.reqCount }} 个需求</span>
                    <span v-if="selectedMember.doneCount" class="ep-bd ep-ok">{{ selectedMember.doneCount }} 已完成</span>
                    <span v-if="selectedMember.hasAi" class="ep-bd ep-ok">
                      <EpIcon name="star" :size="9" />{{ selectedMember.dacReqs }} 个 dac 需求{{ selectedMember.dacStatsText ? ' · ' + selectedMember.dacStatsText : '' }}
                    </span>
                    <span v-if="personalBadge(selectedMember.c.committer)" class="ep-bd ep-info"
                          :style="personalBadge(selectedMember.c.committer).total === null ? 'opacity:0.5' : ''">
                      <EpIcon name="user" :size="9" />vibe coding {{ personalBadge(selectedMember.c.committer).text }}
                    </span>
                    <span v-if="selectedMember.dacTs" class="ep-bd">
                      <EpIcon name="clock" :size="9" />{{ fmtRelTime(selectedMember.dacTs) }}
                    </span>
                  </div>
                </div>
              </div>
            </div>
            <AiStatBlock :ai="selectedMember.c.ai_stats" />
            <template v-if="cardReqsSorted.length">
              <ReqCard v-for="item in cardReqsSorted" :key="item.req.req_name"
                        :req="item.req" :committer-email="selectedMember.c.committer"
                        :allow-delete="true" :is-current-version="item.isCurrentVersion" />
            </template>
            <div v-else class="ep-empty">该成员暂无可展示的需求卡片</div>
          </template>
          <div v-else class="ep-empty">该成员暂无需求记录</div>
        </template>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { store, selectPeopleOverview, selectPerson, selectPersonFromOverview, togglePeopleSortMode } from '../../store/dashboard'
import { initials, fmtNum, fmtLines, fmtRelTime } from '../../utils/format'
import { rankedMembersWithAiStats, personalTotalFor, personalLastReportedAtFor, vibeTotalSum } from '../../utils/peopleStats'
import { sortReqsByDisplayOrder } from '../../utils/reqOrder'
import { useOverviewDetailToggle } from '../../composables/useOverviewDetailToggle'
import AiStatBlock from '../shared/AiStatBlock.vue'
import ReqCard from '../shared/ReqCard.vue'
import EpIcon from '../shared/EpIcon.vue'

const committers = computed(() => store.data?.committers || [])
const requirementsIndex = computed(() => store.data?.requirements_index || [])
const bindings = computed(() => store.bindings || {})
const todayStr = computed(() => new Date().toISOString().slice(0, 10))

const ranked = computed(() => rankedMembersWithAiStats(committers.value, bindings.value, requirementsIndex.value, store.data?.personal_totals, store.peopleSortMode, store.remarks))
const dacMembers = computed(() => ranked.value.filter(x => x.hasAi))
const nonDacMembers = computed(() => ranked.value.filter(x => !x.hasAi)
  .slice().sort((a, b) => (a.c.committer_name || a.c.committer).localeCompare(b.c.committer_name || b.c.committer)))
const totalMembers = computed(() => ranked.value.length)
const overviewPct = computed(() => totalMembers.value > 0 ? Math.round((dacMembers.value.length / totalMembers.value) * 100) : 0)
const totalDacLines = computed(() => dacMembers.value.reduce((s, x) => s + (x.dacLines || 0), 0))
const totalDacReqs = computed(() => dacMembers.value.reduce((s, x) => s + (x.dacReqs || 0), 0))
const avgDacReqs = computed(() => dacMembers.value.length > 0 ? (totalDacReqs.value / dacMembers.value.length).toFixed(1) : '0.0')
const allReqTotal = computed(() => ranked.value.reduce((s, x) => s + (x.reqCount || 0), 0))
const dacReqPct = computed(() => allReqTotal.value > 0 ? Math.round((totalDacReqs.value / allReqTotal.value) * 100) : 0)
const vibeTotal = computed(() => vibeTotalSum(store.data?.personal_totals))

const generatedAt = computed(() => store.data?.generatedAt || '')
// 数据未返回时数字位以占位符呈现，避免顶栏出现误导性的 0
const topMeta = computed(() => {
  const head = store.data ? `共 ${totalMembers.value} 人` : '共 — 人'
  return generatedAt.value ? `${head} · 更新时间: ${generatedAt.value}` : head
})

const vibeKpiVisible = computed(() => vibeTotal.value !== null && !!store.config?.vibeVisible)
// vibe 总量口径覆盖全部仓库，可能超过 dac 行数；文案按实数展示，进度条封顶 100% 避免溢出
const vibePct = computed(() => totalDacLines.value > 0 ? Math.round((vibeTotal.value / totalDacLines.value) * 100) : null)
const vibePctText = computed(() => vibePct.value === null ? '全团队' : `占 dac ${vibePct.value}%`)
const vibeBarWidth = computed(() => vibePct.value === null ? 0 : Math.min(100, vibePct.value))

const donut = { cx: 28, cy: 28, r: 23, circumference: 2 * Math.PI * 23 }
const donutDash = computed(() => donut.circumference * (totalMembers.value > 0 ? dacMembers.value.length / totalMembers.value : 0))

// 以 email 作为选中态的持久标识，抵御 ranked 数组因数据刷新重新排序
const effectiveIdx = computed(() => ranked.value.findIndex(x => x.c.committer === store.selectedPersonEmail))
const selectedMember = computed(() => (store.peopleViewMode === 'member' && effectiveIdx.value >= 0) ? ranked.value[effectiveIdx.value] : null)

function memberName(x) {
  return x.c.committer_name || x.c.committer
}
function isSelectedMember(email) {
  return store.peopleViewMode === 'member' && store.selectedPersonEmail === email
}
function avatarTone(x, selected) {
  if (selected) return 'ep-brand'
  return x.hasAi ? 'ep-ok' : ''
}
function dacStatLine(x) {
  if (!x.hasAi) return ''
  return [x.dacStatsText, x.dacTs ? `最近 ${fmtRelTime(x.dacTs)}` : ''].filter(Boolean).join(' · ')
}

const { setItemRef } = useOverviewDetailToggle({
  list: ranked,
  isDetailMode: () => store.peopleViewMode === 'member',
  isSelected: x => x.c.committer === store.selectedPersonEmail,
  toOverview: selectPeopleOverview,
  selectionKey: computed(() => store.selectedPersonEmail),
  isValidKey: email => !!email,
})

function onSidebarClick(committer) {
  selectPerson(committer)
}
function onOverviewCardClick(committer) {
  selectPersonFromOverview(committer)
}

function personalBadge(committer) {
  if (!store.config?.vibeVisible) return null
  const total = personalTotalFor(committer, store.data?.personal_totals)
  const lastTs = fmtRelTime(personalLastReportedAtFor(committer, store.data?.personal_totals))
  const text = (total === null ? '—' : `${fmtNum(total)} 行`) + (lastTs ? `：${lastTs}` : '')
  return { total, text }
}

function aiModelsLabel(ai) {
  return (ai?.models_used || []).map(m => m.replace('claude-', '').replace(/-\d+$/, '')).join(' / ')
}

const cardReqsSorted = computed(() => {
  const m = selectedMember.value
  if (!m) return []
  const cardReqs = m.reqs.filter(r => r.req_name !== '__dac_file_proof__')
  const { sorted, curVerSet } = sortReqsByDisplayOrder(cardReqs, {
    requirementsIndex: requirementsIndex.value,
    todayStr: todayStr.value,
    // dacReqList 已由 computeMemberAiStats 按 enrichReq 口径算过，无需在排序里重复 enrich
    dacReqNames: new Set(m.dacReqList.map(r => r.req_name)),
  })
  return sorted.map(r => ({ req: r, isCurrentVersion: curVerSet.has(r.req_name) }))
})
</script>

<style scoped>
/* 排序切换：沿用重构前的隐藏状态（display:none），仅换配色，行为不变 */
.people-sort-toggle {
  display: none; align-items: center; justify-content: space-between;
  margin: 0 0 2px; padding: 6px 10px;
  background: var(--sub-bg); border: 1px solid var(--line); border-radius: 8px;
  font-size: 11px; font-weight: 600; color: var(--t2);
  cursor: pointer; transition: background .12s, border-color .12s;
}
.people-sort-toggle:hover { border-color: var(--brand-line); background: var(--brand-bg); }

/* AI 编码统计行，仅本组件单一消费点，不入 base.css */
.ai-usage-row {
  display: flex; align-items: center; gap: 5px; flex-wrap: wrap;
  margin-top: 6px; font-size: 10px; color: var(--info);
}
.ai-chip {
  display: inline-flex; align-items: center; gap: 3px;
  background: var(--info-bg); color: var(--info); border: 1px solid var(--info-line);
  font-size: 9px; font-weight: 700;
  padding: 1px 5px; border-radius: 4px;
}
</style>
