<template>
  <div class="ep-stepper">
    <!-- 连接线由 .ep-step::before / ::after 绘制，无需独立 connector 节点 -->
    <div v-for="p in TRACE_PHASE_META" :key="p.key" class="ep-step" :class="stepClass(p.key)">
      <div class="ep-dot"></div>
      <div class="ep-lb">{{ p.label }}</div>
      <div class="ep-lb-ts" :class="labels[p.key]?.tier !== 'normal' ? `tier-${labels[p.key].tier}` : ''"
           :title="labels[p.key]?.title || undefined">{{ labels[p.key]?.text }}</div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import {
  TRACE_PHASE_META, TRACE_PHASE_ORDER, phaseDurations, skippedPhaseSet, displayTracePhase,
} from '../../utils/phase'
import { fmtDurationTiered } from '../../utils/format'

const props = defineProps({
  phases: { type: Array, default: () => [] },
  cur: { type: String, required: true },
  skippedStages: { type: Array, default: () => [] },
})

const durations = computed(() => phaseDurations(props.phases))
const skipped = computed(() => skippedPhaseSet(props.skippedStages))
const recorded = computed(() => {
  const s = new Set()
  for (const p of props.phases || []) {
    if (p && p.phase) s.add(p.phase)
  }
  return s
})
const displayCur = computed(() => displayTracePhase(props.cur))

function isDone(key) {
  return TRACE_PHASE_ORDER[key] < (TRACE_PHASE_ORDER[displayCur.value] ?? TRACE_PHASE_ORDER[props.cur] ?? 0)
}
function stepClass(key) {
  if (key === displayCur.value) return 'cur'
  return isDone(key) ? 'done' : ''
}

const HEAVY_KEYS = new Set(['feature-done'])

const labels = computed(() => {
  const out = {}
  const d = durations.value
  const skip = skipped.value
  const rec = recorded.value
  for (const p of TRACE_PHASE_META) {
    if (p.key === 'init') { out[p.key] = { text: '', tier: 'normal', title: '' }; continue }
    if (p.key === displayCur.value) { out[p.key] = { text: '运行中', tier: 'normal', title: '' }; continue }
    if (skip.has(p.key) && !rec.has(p.key)) {
      out[p.key] = { text: '已跳过', tier: 'skip', title: '当前阶段被跳过' }
      continue
    }
    if (!isDone(p.key)) { out[p.key] = { text: '—', tier: 'normal', title: '' }; continue }
    const ms = d[p.key]
    out[p.key] = ms
      ? fmtDurationTiered(ms, { heavy: HEAVY_KEYS.has(p.key) })
      : { text: '—', tier: 'normal', title: '' }
  }
  return out
})
</script>

<style scoped>
.ep-lb-ts {
  font-size: 9px;
  color: var(--t4);
  font-weight: 500;
  margin-top: 2px;
  white-space: nowrap;
}
.ep-step.cur .ep-lb-ts { color: var(--brand); font-weight: 700; }
.ep-step.done .ep-lb-ts { color: var(--t3); }
.ep-step.done .ep-lb-ts.tier-warn { color: #D97706; font-weight: 600; }
.ep-step.done .ep-lb-ts.tier-idle { color: var(--t4); }
.ep-step.done .ep-lb-ts.tier-skip { color: var(--t4); font-style: italic; }
.ep-lb-ts.tier-warn { color: #D97706; font-weight: 600; }
.ep-lb-ts.tier-idle { color: var(--t4); }
.ep-lb-ts.tier-skip { color: var(--t4); font-style: italic; }
</style>
