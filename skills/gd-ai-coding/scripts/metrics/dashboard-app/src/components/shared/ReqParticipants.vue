<template>
  <span v-if="inline && names.length" class="rp-inline">
    <EpIcon name="user" :size="10" />{{ names.join('、') }}
  </span>
  <div v-else-if="names.length" style="margin-top:12px">
    <div class="ep-req-sub-title"><EpIcon name="user" :size="11" />参与人员（{{ names.length }}）</div>
    <div class="ep-req-meta" style="margin-top:0">
      <span v-for="name in names" :key="name" class="ep-bd"><EpIcon name="user" :size="9" />{{ name }}</span>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { store } from '../../store/dashboard'
import { PARTICIPANT_EXCLUDED_NAMES } from '../../utils/participants'
import { nameForEmail } from '../../utils/people'
import EpIcon from './EpIcon.vue'

// 版本视图卡片：展示该 DDP 需求的全部「参与 rd」——rdListEmails（DDP rdList ∩ 司机端团队，来自
// requirements_index.rd_list）与绑定到该需求的所有 dac trace 成员 committers 的并集，映射姓名
// （未命中回退邮箱前缀），并过滤掉排除名单中的人。并集保证不少于原口径：既补齐未用 dac 的司机端
// 参与 RD，也不丢用过 dac 的提交者；rdListEmails 缺省（旧快照无 rd_list）时退化为原 trace 口径。
const props = defineProps({
  traceReqs: { type: Array, default: () => [] },
  rdListEmails: { type: Array, default: () => [] },
  // true：卡片右上角进度文案左侧的一行紧凑展示；false：展开详情里的「参与人员」区块
  inline: { type: Boolean, default: false },
})

const names = computed(() => {
  const emails = [...new Set([
    ...(props.rdListEmails || []),
    ...(props.traceReqs || []).flatMap(t => t.committers || []),
  ].filter(Boolean))]
  return [...new Set(emails.map(e => nameForEmail(e, store.data?.committers)))]
    .filter(name => !PARTICIPANT_EXCLUDED_NAMES.has(name))
})
</script>

<style scoped>
/* 卡片右上角单行紧凑展示，超长省略 */
.rp-inline {
  display: inline-flex; align-items: center; gap: 4px;
  font-size: 11px; color: var(--t4); flex-shrink: 0;
  max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  align-self: flex-start;
}
</style>
