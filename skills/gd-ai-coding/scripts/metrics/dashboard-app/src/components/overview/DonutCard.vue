<template>
  <div class="overview-donut-card">
    <div>
      <div style="font-size:15px;color:var(--warm-title);font-weight:600">{{ title }}</div>
      <slot name="link" />
    </div>
    <div class="overview-donut-num" :style="{ color: den > 0 ? color : 'var(--warm-text)' }">
      <template v-if="den > 0">{{ num }}<span class="overview-donut-den">/{{ den }}</span></template>
      <template v-else>— / —</template>
    </div>
  </div>
</template>

<script setup>
defineProps({
  title: { type: String, required: true },
  num: { type: Number, default: 0 },
  den: { type: Number, default: 0 },
  color: { type: String, default: 'var(--chart-mem)' },
})
</script>
