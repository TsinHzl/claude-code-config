<template>
  <div class="card-block">
    <div class="card-title">工作流质量 <span class="card-title-sub">{{ subtitle }}</span></div>
    <div class="quality-grid">
      <div class="ep-kpi-box">
        <div class="ep-kpi-head"><span>方案平均轮次</span><span class="hint">?<span class="tip">方案(proposal)门：用户打回/调整次数 + 1。一次通过 = 1 轮。</span></span></div>
        <div class="ep-kpi-num">{{ fmtRounds(proposalRounds) }} <span class="ep-kpi-ratio">轮</span></div>
        <div class="ep-kpi-bar"><div class="ep-kpi-fill" :style="{ width: barPct(proposalRounds, 4) }"></div></div>
      </div>
      <div class="ep-kpi-box">
        <div class="ep-kpi-head"><span>功能拆分平均轮次</span><span class="hint">?<span class="tip">feature_plan 门：功能列表被调整次数 + 1。无调整 = 1 轮。</span></span></div>
        <div class="ep-kpi-num">{{ fmtRounds(featurePlanRounds) }} <span class="ep-kpi-ratio">轮</span></div>
        <div class="ep-kpi-bar"><div class="ep-kpi-fill" :style="{ width: barPct(featurePlanRounds, 4) }"></div></div>
      </div>
      <div class="ep-kpi-box">
        <div class="ep-kpi-head"><span>平均代码检查次数</span><span class="hint">?<span class="tip">L2 dart analyze：每个 feature 失败次数 + 1（一次过 = 1 次），与方案轮次同一口径。无检查结果的 feature 不参与平均。</span></span></div>
        <div class="ep-kpi-num">{{ fmtRounds(codegenTimes) }} <span class="ep-kpi-ratio">次</span></div>
        <div class="ep-kpi-bar"><div class="ep-kpi-fill" :style="{ width: barPct(codegenTimes, 4), background: 'var(--ok)' }"></div></div>
      </div>
      <div class="ep-kpi-box">
        <div class="ep-kpi-head"><span>平均 CR 次数</span><span class="hint">?<span class="tip">代码评审：每个 feature 发现问题次数 + 1（一次干净 = 1 次）。skipped 不计入。无 CR 结果的 feature 不参与平均。</span></span></div>
        <div class="ep-kpi-num">{{ fmtRounds(crTimes) }} <span class="ep-kpi-ratio">次</span></div>
        <div class="ep-kpi-bar"><div class="ep-kpi-fill" :style="{ width: barPct(crTimes, 4), background: 'var(--info)' }"></div></div>
      </div>
      <!-- 代码自动生成比例暂时隐藏：结算未铺开前数字不准 -->
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { store } from '../../store/dashboard'
import { avgRounds, avgAttempts } from '../../utils/qualityStats'

// reqNames: 作用域需求名数组(null = 全局；[] = 空范围)；subtitle: 卡片副标题说明统计范围
const props = defineProps({
  reqNames: { type: Array, default: null },
  subtitle: { type: String, default: '' },
})

const qualityStats = computed(() => store.data?.quality_stats || [])
const proposalRounds = computed(() => avgRounds(qualityStats.value, props.reqNames, 'proposal_rounds'))
const featurePlanRounds = computed(() => avgRounds(qualityStats.value, props.reqNames, 'feature_plan_rounds'))
const codegenTimes = computed(() => avgAttempts(qualityStats.value, props.reqNames, 'codegen_check_times', 'codegen_feats_total'))
const crTimes = computed(() => avgAttempts(qualityStats.value, props.reqNames, 'cr_check_times', 'cr_feats_total'))

function fmtRounds(v) { return v == null ? '—' : String(v) }
function barPct(v, max) { return `${Math.min(100, max && v != null ? (v / max) * 100 : 0)}%` }
</script>

<style scoped>
.card-block {
  background: var(--card);
  border: 1px solid var(--card-line);
  border-radius: 14px;
  padding: 18px 22px;
  margin-bottom: 16px;
  box-shadow: var(--card-shadow);
}
.card-title {
  font-size: 14px;
  font-weight: 700;
  color: var(--t1);
  margin-bottom: 14px;
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}
.card-title-sub { font-size: 12px; color: var(--t4); font-weight: 500; }
.quality-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; }
.ep-kpi-box {
  display: flex;
  flex-direction: column;
  gap: 4px;
  background: var(--sub-bg);
  border: 1px solid var(--line);
  border-radius: 8px;
  padding: 10px 14px;
}
.ep-kpi-head {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 11px;
  color: var(--t3);
  font-weight: 600;
}
.ep-kpi-head .ep-kpi-ratio { margin-left: auto; font-weight: 500; }
.ep-kpi-num { font-size: 22px; font-weight: 800; color: var(--t1); display: flex; align-items: baseline; gap: 6px; }
.ep-kpi-ratio { font-size: 11px; color: var(--t4); font-weight: 500; }
.ep-kpi-bar { width: 100%; height: 6px; background: var(--track); border-radius: 3px; overflow: hidden; margin-top: 2px; }
.ep-kpi-fill { height: 100%; border-radius: 3px; background: var(--brand-strong); transition: width .3s; }
.hint {
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 14px;
  height: 14px;
  border-radius: 50%;
  background: var(--chip-bg);
  color: var(--t3);
  font-size: 10px;
  font-weight: 700;
  cursor: help;
  flex-shrink: 0;
}
.hint:hover { background: var(--brand-bg); color: var(--brand-strong); }
.hint .tip {
  position: absolute;
  bottom: calc(100% + 6px);
  left: 50%;
  transform: translateX(-50%);
  background: #0F172A;
  color: #fff;
  font-size: 11px;
  font-weight: 400;
  line-height: 1.5;
  padding: 8px 10px;
  border-radius: 7px;
  width: 210px;
  text-align: left;
  white-space: normal;
  box-shadow: 0 4px 14px rgba(0,0,0,.2);
  opacity: 0;
  pointer-events: none;
  transition: opacity .12s;
  z-index: 20;
}
.hint .tip::after {
  content: "";
  position: absolute;
  top: 100%;
  left: 50%;
  transform: translateX(-50%);
  border: 6px solid transparent;
  border-top-color: #0F172A;
}
.hint:hover .tip { opacity: 1; }
</style>
