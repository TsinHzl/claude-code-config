<template>
  <div class="ep-req-meta">
    <template v-if="summary.total === 0">
      <span class="ep-bd">无功能记录</span>
    </template>
    <template v-else>
      <span v-if="summary.done" class="ep-bd ep-ok"><EpIcon name="check" :size="9" />{{ summary.done }} 已完成</span>
      <span v-if="summary.in_progress" class="ep-bd ep-info"><EpIcon name="refresh" :size="9" />{{ summary.in_progress }} 进行中</span>
      <span v-if="summary.pending" class="ep-bd"><EpIcon name="clock" :size="9" />{{ summary.pending }} 待开发</span>
      <span v-if="summary.failed" class="ep-bd ep-danger"><EpIcon name="x" :size="9" />{{ summary.failed }} 失败</span>
      <span v-if="summary.skipped" class="ep-bd"><EpIcon name="skip" :size="9" />{{ summary.skipped }} 跳过</span>
      <span class="feat-total">共 {{ summary.total }} 个</span>
    </template>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { featureSummary } from '../../utils/phase'
import EpIcon from './EpIcon.vue'

const props = defineProps({
  features: { type: Array, default: () => [] },
})

const summary = computed(() => featureSummary(props.features))
</script>

<style scoped>
.feat-total { font-size: 11px; color: var(--t4); }
</style>
