<template>
  <div v-if="items.length" class="rq-badges">
    <span v-for="it in items" :key="it.key" class="ep-bd" :class="it.cls">{{ it.text }}</span>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { store } from '../../store/dashboard'
import { reqQualityItems } from '../../utils/qualityStats'

const props = defineProps({
  reqName: { type: String, default: '' },
  altNames: { type: Array, default: () => [] },
})

const items = computed(() =>
  reqQualityItems(store.data?.quality_stats || [], props.reqName, props.altNames))
</script>

<style scoped>
.rq-badges { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; }
</style>
