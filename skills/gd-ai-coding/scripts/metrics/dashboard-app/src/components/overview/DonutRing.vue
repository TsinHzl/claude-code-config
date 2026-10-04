<template>
  <svg viewBox="0 0 60 60" :style="{ width: size + 'px', height: size + 'px', flexShrink: 0, fontFamily: 'sans-serif' }">
    <circle :cx="cx" :cy="cy" :r="r" fill="none" stroke="var(--warm-line)" stroke-width="7" />
    <circle v-if="den > 0" :cx="cx" :cy="cy" :r="r" fill="none" :stroke="color" stroke-width="7"
            :stroke-dasharray="`${dash} ${circumference.toFixed(1)}`" stroke-linecap="round"
            :transform="`rotate(-90 ${cx} ${cy})`" />
    <text :x="cx" :y="cy" text-anchor="middle" dominant-baseline="central" font-size="16" font-weight="700"
          :fill="den > 0 ? color : 'var(--warm-text)'">{{ pct !== null ? pct + '%' : '—' }}</text>
  </svg>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  num: { type: Number, default: 0 },
  den: { type: Number, default: 0 },
  color: { type: String, default: 'var(--chart-mem)' },
  size: { type: Number, default: 60 },
})

const r = 25, cx = 30, cy = 30
const circumference = 2 * Math.PI * r
const ratio = computed(() => (props.den > 0 ? props.num / props.den : 0))
const pct = computed(() => (props.den > 0 ? Math.round(ratio.value * 100) : null))
const dash = computed(() => (circumference * ratio.value).toFixed(1))
</script>
