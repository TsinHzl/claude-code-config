<template>
  <div class="ep-req hl fold" :class="{ expanded, tech: req.is_technical }" @click="expanded = !expanded">
    <div class="ep-req-head">
      <div style="min-width:0;flex:1">
        <div class="ep-req-title">{{ req.ddp?.title || req.req_name }}</div>
        <div class="ep-req-id">
          <a v-if="ddpLinkUrl" :href="ddpLinkUrl" target="_blank" rel="noopener noreferrer"
             title="点击在 DDP 中打开（新标签页）" @click.stop>{{ req.req_name }} ↗</a>
          <template v-else>{{ req.req_name }}</template>
        </div>
        <div class="ep-req-flow">
          <EpIcon name="star" :size="11" />DAC AI 工作流 · {{ traceReqs.length }} 个绑定
        </div>
      </div>
      <ReqParticipants inline :trace-reqs="traceReqs" :rd-list-emails="req.rd_list" />
      <div class="ep-req-side">
        <span v-if="req.is_technical" class="ep-tech-badge" title="技术类需求，不计入需求维度统计">技术</span>
        <span class="ep-bd" :class="ddpDone ? 'ep-ok' : 'ep-brand'">{{ ddpLabel }}</span>
      </div>
    </div>
    <div class="ep-req-expand">
      <span class="ep-req-hint-on">▾ 点击展开详情</span><span class="ep-req-hint-off">▴ 点击收起</span>
    </div>
    <div class="ep-req-fold" @click.stop>
      <div v-for="tr in traceReqs" :key="tr.req_name" class="vmc-trace">
        <div class="ep-req-head">
          <div class="ep-req-flow" style="margin-top:0;min-width:0">
            <EpIcon name="star" :size="11" /><code>{{ tr.req_name }}</code>
          </div>
          <div class="ep-req-side" style="flex-direction:row;align-items:center;gap:6px">
            <span class="ep-bd" :class="traceDone(tr) ? 'ep-ok' : 'ep-info'">{{ traceLabel(tr) }}</span>
            <button class="ep-bd ep-danger" @click.stop="unbind(tr.req_name)">
              <EpIcon name="scissors" :size="9" />解绑
            </button>
          </div>
        </div>
        <TracePhaseStepper :phases="tr.phases" :cur="currentTracePhase(tr.phases)" :skipped-stages="tr.skipped_stages" />
        <ReqQualityBadges :req-name="tr.req_name" :alt-names="[req.req_name]" />
        <FeaturePills :features="tr.features" />
        <div v-if="traceStats(tr)" class="ep-req-foot">{{ traceStats(tr) }}</div>
      </div>
      <div class="ep-req-sub-title" style="margin-top:14px"><EpIcon name="bar" :size="11" />DDP 需求进度</div>
      <PhaseStepper :phases="req.phases" :cur="ddpCur" />
      <DdpChips :ddp="req.ddp" />
      <ReqParticipants :trace-reqs="traceReqs" :rd-list-emails="req.rd_list" />
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { setBindings } from '../../store/dashboard'
import { postUnbind } from '../../api/bindings'
import { ddpUrl } from '../../utils/ddp'
import { fmtNum } from '../../utils/format'
import { currentPhase, currentTracePhase, displayTracePhase, PHASE_LABEL, TRACE_PHASE_LABEL } from '../../utils/phase'
import PhaseStepper from './PhaseStepper.vue'
import TracePhaseStepper from './TracePhaseStepper.vue'
import FeaturePills from './FeaturePills.vue'
import ReqQualityBadges from './ReqQualityBadges.vue'
import DdpChips from './DdpChips.vue'
import ReqParticipants from './ReqParticipants.vue'
import EpIcon from './EpIcon.vue'

const props = defineProps({
  req: { type: Object, required: true },
  traceReqs: { type: Array, required: true },
})

const expanded = ref(false)

const ddpLinkUrl = computed(() => ddpUrl(props.req.req_name))
const ddpCur = computed(() => currentPhase(props.req.phases))
const ddpLabel = computed(() => PHASE_LABEL[ddpCur.value] || ddpCur.value)
const ddpDone = computed(() => ddpCur.value === 'released')

function traceDone(tr) {
  return currentTracePhase(tr.phases) === 'done'
}
function traceLabel(tr) {
  const c = displayTracePhase(currentTracePhase(tr.phases))
  return TRACE_PHASE_LABEL[c] || c
}
function traceStats(tr) {
  const items = []
  if (tr.commit_count) items.push(`${fmtNum(tr.commit_count)} 次提交`)
  if (tr.lines_added) items.push(`+${fmtNum(tr.lines_added)} 行`)
  return items.join(' · ')
}

async function unbind(traceReqName) {
  try {
    const bindings = await postUnbind(traceReqName)
    setBindings(bindings)
  } catch (e) {
    alert('解绑失败: ' + e.message)
  }
}
</script>

<style scoped>
/* 单个绑定 trace 分节，仅本组件消费 */
.vmc-trace { margin-top: 12px; padding-top: 12px; border-top: 1px dashed var(--line); }
.ep-req-id a { color: inherit; text-decoration: none; }
.ep-req-id a:hover { text-decoration: underline; }
</style>
