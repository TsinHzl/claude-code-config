<template>
  <div class="overview-trend-chart tc-mem">
    <div v-if="!points.length" class="empty-state">暂无可用于趋势分析的正式版本数据</div>
    <template v-else>
      <div class="chart-title">版本成员使用率趋势</div>
      <svg :viewBox="`0 0 ${dims.W} ${dims.H}`" xmlns="http://www.w3.org/2000/svg" style="width:100%;font-family:sans-serif">
        <template v-for="t in ticks" :key="'tick-' + t.v">
          <line class="tc-grid" :x1="dims.padL" :y1="t.y" :x2="dims.W - dims.padR" :y2="t.y" stroke-width="1" />
          <text class="tc-axis" :x="dims.padL - 8" :y="t.y" text-anchor="end" dominant-baseline="central" font-size="10">{{ t.v }}%</text>
        </template>
        <line v-if="curIndex >= 0" class="tc-cur-line" :x1="points[curIndex].x" :y1="dims.padT" :x2="points[curIndex].x" :y2="dims.H - dims.padB"
              stroke-width="1.5" stroke-dasharray="4,4" opacity="0.75" />
        <text v-for="p in points" :key="'xl-' + p.name" class="tc-xlabel" :class="{ cur: p.isCurrent }"
              :x="p.x" :y="dims.H - dims.padB + 16" text-anchor="middle"
              font-size="10" :font-weight="p.isCurrent ? 700 : 400">{{ p.shortLabel }}{{ p.isCurrent ? '(本版本)' : '' }}</text>
        <path class="tc-line" :d="pathD" fill="none" stroke-width="2.2" stroke-linejoin="round" />
        <template v-for="p in points" :key="'dot-' + p.name">
          <circle v-if="!p.isCurrent" class="tc-dot" :cx="p.x" :cy="p.y" r="4" stroke-width="2" />
          <circle v-else class="tc-dot cur" :cx="p.x" :cy="p.y" r="4.5" />
        </template>
        <template v-for="p in points" :key="'val-' + p.name">
          <text v-if="!p.isCurrent" class="tc-val" :x="p.x" :y="p.y - 12" text-anchor="middle" font-size="11" font-weight="600">{{ Math.round(p.pct) }}%</text>
          <template v-else>
            <rect class="tc-badge" :x="p.x - 21" :y="p.y - 32" width="42" height="21" rx="6" />
            <text class="tc-badge-txt" :x="p.x" :y="p.y - 21.5" text-anchor="middle" dominant-baseline="central" font-size="11" font-weight="700">{{ Math.round(p.pct) }}%</text>
          </template>
        </template>
      </svg>
      <div class="chart-footer">
        <span>{{ footerLeft }}</span>
      </div>
    </template>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { fmtNum } from '../../utils/format'
import {
  versionMemberPct, versionDacMembers, versionDacLines,
  compareVersionDesc, shortVersionLabel,
} from '../../utils/version'

const props = defineProps({
  recentVersions: { type: Array, default: () => [] },
  requirementsIndex: { type: Array, default: () => [] },
  committers: { type: Array, default: () => [] },
  bindings: { type: Object, default: () => ({}) },
})

const dims = { W: 560, H: 220, padL: 40, padR: 18, padT: 36, padB: 32 }
dims.plotW = dims.W - dims.padL - dims.padR
dims.plotH = dims.H - dims.padT - dims.padB

const curG = computed(() => props.recentVersions.find(g => g.isCurrent) || null)

const curDacMembers = computed(() => versionDacMembers(curG.value, props.requirementsIndex, props.committers, props.bindings))
const rawPoints = computed(() => props.recentVersions.map(g => ({
  name: g.name,
  pct: versionMemberPct(g, props.requirementsIndex, props.committers, props.bindings),
  isCurrent: !!g.isCurrent,
})).sort((a, b) => -compareVersionDesc(a.name, b.name)))

const yMax = computed(() => {
  const maxVal = Math.max(45, ...rawPoints.value.map(p => p.pct))
  return Math.max(45, Math.ceil(maxVal / 15) * 15)
})

const ticks = computed(() => {
  const list = []
  for (let v = 0; v <= yMax.value; v += 15) list.push(v)
  return list.map(v => ({ v, y: yAt(v) }))
})

function xAt(i) {
  const n = rawPoints.value.length
  const xStep = n > 1 ? dims.plotW / (n - 1) : 0
  return dims.padL + (n > 1 ? i * xStep : dims.plotW / 2)
}
function yAt(v) {
  return dims.padT + dims.plotH - (v / yMax.value) * dims.plotH
}

const points = computed(() => rawPoints.value.map((p, i) => ({
  ...p,
  x: xAt(i),
  y: yAt(p.pct),
  shortLabel: shortVersionLabel(p.name),
})))

const curIndex = computed(() => points.value.findIndex(p => p.isCurrent))

const pathD = computed(() => points.value.map((p, i) => `${i === 0 ? 'M' : 'L'}${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' '))

const footerLeft = computed(() => (curG.value
  ? `DAC 成员 ${curDacMembers.value.length}人 · 代码 ${fmtNum(versionDacLines(curG.value, props.requirementsIndex, props.committers, props.bindings))}行`
  : 'DAC 成员数据缺失'))
</script>
