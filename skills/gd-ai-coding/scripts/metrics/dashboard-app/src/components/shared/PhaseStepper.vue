<template>
  <div class="ep-stepper">
    <!-- 连接线由 .ep-step::before / ::after 绘制，无需独立 connector 节点 -->
    <div v-for="p in PHASE_META" :key="p.key" class="ep-step" :class="stepClass(p.key)">
      <div class="ep-dot"></div>
      <div class="ep-lb">{{ p.label }}</div>
    </div>
  </div>
</template>

<script setup>
import { PHASE_META, PHASE_ORDER } from '../../utils/phase'

const props = defineProps({
  phases: { type: Array, default: () => [] },
  cur: { type: String, required: true },
})

function isDone(key) {
  return PHASE_ORDER[key] < (PHASE_ORDER[props.cur] ?? 0)
}
function stepClass(key) {
  if (key === props.cur) return 'cur'
  return isDone(key) ? 'done' : ''
}
</script>
