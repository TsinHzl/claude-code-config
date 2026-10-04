<template>
  <!-- 分支 1：DDP 需求已绑定 dac trace（isMerged） -->
  <div
    v-if="isMerged"
    class="ep-req hl fold"
    :class="{ expanded, tech: enrichedReq.is_technical, excluded: isExcludedFromStats }"
    @click="expanded = !expanded"
  >
    <div class="ep-req-head">
      <div style="min-width:0;flex:1">
        <div class="ep-req-title">{{ enrichedReq.ddp?.title || enrichedReq.req_name }}</div>
        <div class="ep-req-id">
          <a v-if="ddpLinkUrl" :href="ddpLinkUrl" target="_blank" rel="noopener noreferrer"
             title="点击在 DDP 中打开（新标签页）" @click.stop>{{ enrichedReq.req_name }} ↗</a>
          <template v-else>{{ enrichedReq.req_name }}</template>
        </div>
        <div class="ep-req-flow">
          <EpIcon name="star" :size="11" />DAC AI 工作流 <code>{{ enrichedReq._boundTrace }}</code>
        </div>
      </div>
      <ReqParticipants v-if="showParticipants" inline :trace-reqs="traceReqs" :rd-list-emails="enrichedReq.rd_list" />
      <div class="ep-req-side">
        <span v-if="enrichedReq.is_technical" class="ep-tech-badge" title="技术类需求，不计入需求维度统计">技术</span>
        <span v-if="isExcludedFromStats" class="ep-bd ep-excluded" title="概览看板数据统计已排除此需求">已排除统计</span>
        <span v-if="isCurrentVersion" class="ep-bd ep-ok"><EpIcon name="rocket" :size="9" />当前版本</span>
        <span class="ep-bd" :class="traceIsDone ? 'ep-ok' : 'ep-info'">{{ traceLabel }}</span>
        <button class="ep-bd ep-danger" @click.stop="unbind(enrichedReq._boundTrace)">
          <EpIcon name="scissors" :size="9" />解绑
        </button>
        <button v-if="allowDelete" class="ep-bd ep-danger"
                @click.stop="showDeleteModal({ committer: committerEmail, reqName: enrichedReq._boundTrace })">
          <EpIcon name="trash" :size="9" />删除
        </button>
      </div>
    </div>
    <div class="ep-req-expand">
      <span class="ep-req-hint-on">▾ 点击展开详情</span><span class="ep-req-hint-off">▴ 点击收起</span>
    </div>
    <div class="ep-req-fold" @click.stop>
      <TracePhaseStepper :phases="enrichedReq._tracePhases" :cur="traceCur" :skipped-stages="enrichedReq._traceSkippedStages" />
      <ReqQualityBadges :req-name="enrichedReq._boundTrace" :alt-names="[enrichedReq.req_name]" />
      <FeaturePills :features="enrichedReq._traceFeatures" />
      <div v-if="traceStatsLine" class="ep-req-foot">{{ traceStatsLine }}</div>
      <div v-if="editedTs" class="ep-req-foot">最近编辑：{{ editedTs }}</div>
      <div class="ep-req-sub-title" style="margin-top:14px"><EpIcon name="bar" :size="11" />DDP 需求进度</div>
      <PhaseStepper :phases="enrichedReq.phases" :cur="ddpCur" />
      <DdpChips :ddp="enrichedReq.ddp" />
      <ReqParticipants v-if="showParticipants" :trace-reqs="traceReqs" :rd-list-emails="enrichedReq.rd_list" />
    </div>
  </div>

  <!-- 分支 2：纯 dac trace（无 DDP，isTrace） -->
  <div v-else-if="isTrace" class="ep-req hl">
    <div class="ep-req-head">
      <div style="min-width:0;flex:1">
        <div class="ep-req-flow" style="margin-top:0">
          <EpIcon name="star" :size="11" />DAC AI 工作流 <code>{{ enrichedReq.req_name }}</code>
        </div>
        <div v-if="boundDdp" class="ep-req-id">→ {{ boundDdp }}</div>
      </div>
      <div class="ep-req-side">
        <span class="ep-bd" :class="traceIsDone ? 'ep-ok' : 'ep-info'">{{ traceLabel }}</span>
        <button v-if="boundDdp" class="ep-bd ep-danger" @click.stop="unbind(enrichedReq.req_name)">
          <EpIcon name="scissors" :size="9" />解绑
        </button>
        <button v-else class="ep-bd ep-brand"
                @click.stop="showBindModal(enrichedReq.req_name, committerEmail ? [committerEmail] : [])">
          <EpIcon name="link" :size="9" />绑定到 DDP 需求
        </button>
        <button v-if="allowDelete" class="ep-bd ep-danger"
                @click.stop="showDeleteModal({ committer: committerEmail, reqName: enrichedReq.req_name })">
          <EpIcon name="trash" :size="9" />删除
        </button>
      </div>
    </div>
    <TracePhaseStepper :phases="enrichedReq.phases" :cur="traceCur" :skipped-stages="enrichedReq.skipped_stages" />
    <ReqQualityBadges :req-name="enrichedReq.req_name" />
    <FeaturePills :features="enrichedReq.features" />
    <div v-if="traceStatsLine" class="ep-req-foot">{{ traceStatsLine }}</div>
    <div v-if="lastCommitTs" class="ep-req-foot">最后提交：{{ lastCommitTs }}</div>
    <div v-if="editedTs" class="ep-req-foot">最近编辑：{{ editedTs }}</div>
  </div>

  <!-- 分支 3：普通 DDP 需求（未绑定 dac trace） -->
  <div v-else class="ep-req" :class="{ tech: enrichedReq.is_technical, excluded: isExcludedFromStats }">
    <div class="ep-req-head">
      <div style="min-width:0;flex:1">
        <div class="ep-req-title">{{ enrichedReq.ddp?.title || enrichedReq.req_name }}</div>
        <div v-if="enrichedReq.ddp?.title" class="ep-req-id">
          <a v-if="ddpLinkUrl" :href="ddpLinkUrl" target="_blank" rel="noopener noreferrer"
             title="点击在 DDP 中打开（新标签页）" @click.stop>{{ enrichedReq.req_name }} ↗</a>
          <template v-else>{{ enrichedReq.req_name }}</template>
        </div>
      </div>
      <ReqParticipants v-if="showParticipants" inline :trace-reqs="traceReqs" :rd-list-emails="enrichedReq.rd_list" />
      <div class="ep-req-side">
        <span v-if="enrichedReq.is_technical" class="ep-tech-badge" title="技术类需求，不计入需求维度统计">技术</span>
        <span v-if="isExcludedFromStats" class="ep-bd ep-excluded" title="概览看板数据统计已排除此需求">已排除统计</span>
        <span v-if="isCurrentVersion" class="ep-bd ep-ok"><EpIcon name="rocket" :size="9" />当前版本</span>
        <button v-if="remark" type="button" class="ep-bd ep-remark-chip" :title="remarkTitle" @click.stop="openRemark">
          {{ remark.reason_tag || '已备注' }}
        </button>
        <button v-else-if="reqName" type="button" class="ep-bd ep-remark-btn" title="添加未采用 AI 原因备注" @click.stop="openRemark">
          + 备注
        </button>
        <span class="ep-bd" :class="ddpIsDone ? 'ep-ok' : 'ep-brand'">{{ ddpLabel }}</span>
      </div>
    </div>
    <PhaseStepper :phases="enrichedReq.phases" :cur="ddpCur" />
    <FeaturePills :features="enrichedReq.features" />
    <DdpChips :ddp="enrichedReq.ddp" />
    <ReqParticipants v-if="showParticipants" :trace-reqs="traceReqs" :rd-list-emails="enrichedReq.rd_list" />
    <div v-if="lastCommitTsAbs" class="ep-req-foot">最后提交：{{ lastCommitTsAbs }}</div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { store, setBindings, showBindModal, showDeleteModal, showRemarkModal } from '../../store/dashboard'
import { postUnbind } from '../../api/bindings'
import { enrichReq } from '../../utils/enrich'
import { ddpUrl } from '../../utils/ddp'
import { fmtNum, fmtTs, fmtRelTime } from '../../utils/format'
import { currentPhase, currentTracePhase, displayTracePhase, PHASE_LABEL, TRACE_PHASE_LABEL } from '../../utils/phase'
import { reqCommitterNames } from '../../utils/version'
import { formatRemarkTitle, remarkDefaultAuthor } from '../../utils/remark'
import PhaseStepper from './PhaseStepper.vue'
import TracePhaseStepper from './TracePhaseStepper.vue'
import FeaturePills from './FeaturePills.vue'
import ReqQualityBadges from './ReqQualityBadges.vue'
import DdpChips from './DdpChips.vue'
import ReqParticipants from './ReqParticipants.vue'
import EpIcon from './EpIcon.vue'

const props = defineProps({
  req: { type: Object, required: true },
  committerEmail: { type: String, default: '' },
  showParticipants: { type: Boolean, default: false },
  traceReqs: { type: Array, default: () => [] },
  allowDelete: { type: Boolean, default: false },
  isCurrentVersion: { type: Boolean, default: false },
})

const expanded = ref(false)

const enrichedReq = computed(() =>
  enrichReq(props.req, props.committerEmail, store.bindings, store.data?.requirements_index))

const ddpLinkUrl = computed(() => ddpUrl(enrichedReq.value.req_name))
const isMerged = computed(() => !!(enrichedReq.value.ddp && enrichedReq.value._boundTrace))
const isTrace = computed(() => !enrichedReq.value.ddp && (enrichedReq.value.workflow_session_ids || []).length > 0)

const traceCur = computed(() => currentTracePhase(isMerged.value ? enrichedReq.value._tracePhases : enrichedReq.value.phases))
const traceLabel = computed(() => {
  const key = displayTracePhase(traceCur.value)
  return TRACE_PHASE_LABEL[key] || key
})
const traceIsDone = computed(() => traceCur.value === 'done')

const ddpCur = computed(() => currentPhase(enrichedReq.value.phases))
const ddpLabel = computed(() => PHASE_LABEL[ddpCur.value] || ddpCur.value)
const ddpIsDone = computed(() => ddpCur.value === 'released')

const boundDdp = computed(() => (store.bindings || {})[enrichedReq.value.req_name])

// 备注（不活跃需求原因备注/排除统计）仅针对未使用 dac 的 DDP 需求（分支3），语义是记录"未采用
// AI 的原因"，已绑定 dac trace（分支1/isMerged）的需求不展示备注按钮——该收窄由模板层的分支
// 结构控制，本 computed 只负责取 DDP req_name（纯 dac trace 无 ddp 时取不到，同样不展示）。
// isExcludedFromStats 复用同一个 reqName：分支1 仍保留该徽章展示（不受本次收窄影响），因为
// 「排除统计」是历史已有功能，与本次新增的备注入口是两件事。
const reqName = computed(() => (enrichedReq.value.ddp ? enrichedReq.value.req_name : null))

const isExcludedFromStats = computed(() => !!(reqName.value && store.remarks?.[reqName.value]?.excluded_from_stats))

const remark = computed(() => (reqName.value ? store.remarks?.[reqName.value] || null : null))

const remarkTitle = computed(() => formatRemarkTitle(remark.value))

function openRemark() {
  if (!reqName.value) return
  const rdNames = reqCommitterNames(enrichedReq.value, store.data?.committers)
  showRemarkModal({
    reqName: reqName.value,
    title: enrichedReq.value.ddp?.title || reqName.value,
    defaultAuthor: remarkDefaultAuthor(rdNames),
    // 填写人候选限定为该需求参与人（与 ReqParticipants 同口径：rd_list ∪ committers）
    authors: rdNames ? rdNames.split('、') : [],
  })
}

const traceStatsLine = computed(() => {
  const req = enrichedReq.value
  const commitCount = isMerged.value ? req._traceCommitCount : req.commit_count
  const linesAdded = isMerged.value ? req._traceLinesAdded : req.lines_added
  const items = []
  if (commitCount) items.push(`${fmtNum(commitCount)} 次提交`)
  if (linesAdded) items.push(`+${fmtNum(linesAdded)} 行`)
  return items.join(' · ')
})

const editedTs = computed(() => fmtRelTime(isMerged.value ? enrichedReq.value._traceReportedAt : enrichedReq.value.reported_at))
const lastCommitTs = computed(() => fmtRelTime(enrichedReq.value.last_commit_ts))
const lastCommitTsAbs = computed(() => fmtTs(enrichedReq.value.last_commit_ts))

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
.ep-req-id a { color: inherit; text-decoration: none; }
.ep-req-id a:hover { text-decoration: underline; }
.ep-excluded {
  background: var(--danger-bg) !important;
  color: var(--danger) !important;
  border: 1px solid var(--danger-line) !important;
  font-weight: 600;
}
.ep-remark-chip {
  background: var(--brand-bg);
  color: var(--brand);
  border-color: var(--brand-line);
  cursor: pointer;
  max-width: 110px;
  overflow: hidden;
  text-overflow: ellipsis;
  transition: all 0.12s;
}
.ep-remark-chip:hover {
  background: var(--brand);
  color: #fff;
}
.ep-remark-btn {
  background: none;
  color: var(--t4);
  border: 1px dashed var(--line);
  cursor: pointer;
  transition: all 0.12s;
}
.ep-remark-btn:hover {
  color: var(--brand);
  border-color: var(--brand-line);
  background: var(--brand-bg);
}
</style>
