<template>
  <div class="hero-metric-box">
    <div class="hero-metric-label">{{ label }}</div>
    <div class="hero-metric-val">
      <span class="hero-metric-pct" :style="{ color: den > 0 ? undefined : 'var(--t4)' }">
        <template v-if="den > 0">{{ pctText }}%</template>
        <template v-else>—</template>
      </span>
      <span class="hero-metric-frac">
        <template v-if="den > 0">({{ num }} / {{ den }}{{ unit ? ' ' + unit : '' }})</template>
        <template v-else>(— / —)</template>
      </span>
    </div>
    <div class="hero-metric-bar">
      <div class="hero-metric-bar-fill" :style="{ width: pct + '%', background: color }"></div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  label: { type: String, required: true },
  num: { type: Number, default: 0 },
  den: { type: Number, default: 0 },
  unit: { type: String, default: '' },
  color: { type: String, default: 'var(--chart-mem)' },
})

const pct = computed(() => (props.den > 0 ? Math.min(100, (props.num / props.den) * 100) : 0))
const pctText = computed(() => pct.value.toFixed(1))
</script>
