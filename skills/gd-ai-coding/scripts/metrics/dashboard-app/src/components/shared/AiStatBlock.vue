<template>
  <div v-if="ai" class="ai-stat-block">
    <div class="ep-req-sub-title ai-stat-title"><EpIcon name="bot" :size="11" />AI 使用量</div>
    <div class="ep-kpi-row">
      <div class="ep-kpi-box">
        <div class="ep-kpi-head"><span>辅助提交</span></div>
        <div class="ep-kpi-num ai-stat-num">{{ fmtNum(ai.ai_commits) }}</div>
      </div>
      <div class="ep-kpi-box">
        <div class="ep-kpi-head"><span>生成行数</span></div>
        <div class="ep-kpi-num ai-stat-num">{{ fmtLines(ai.ai_lines_added) }}</div>
      </div>
      <div class="ep-kpi-box">
        <div class="ep-kpi-head"><span>采纳行数</span></div>
        <div class="ep-kpi-num ai-stat-num">{{ fmtLines(ai.ai_lines_accepted) }}</div>
      </div>
    </div>
    <div v-if="models" class="ai-models">模型：{{ models }}</div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { fmtNum, fmtLines } from '../../utils/format'
import EpIcon from './EpIcon.vue'

const props = defineProps({
  ai: { type: Object, default: null },
})

const models = computed(() => (props.ai?.models_used || []).join('、'))
</script>

<style scoped>
/* AI 使用量块：info 蓝底容器 + 三列 KPI 盒 */
.ai-stat-block {
  background: var(--info-bg); border: 1px solid var(--info-line);
  border-radius: 10px; padding: 12px 16px 14px;
}
.ai-stat-title { color: var(--info); }
.ai-stat-num { color: var(--info); }
.ai-models { font-size: 11px; color: var(--info); margin-top: 9px; }
</style>
