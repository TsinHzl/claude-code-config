<template>
  <div v-if="store.bindModalVisible" id="bind-overlay" @click.self="hideBindModal()"
    style="display:flex;position:fixed;inset:0;background:rgba(0,0,0,0.45);align-items:center;justify-content:center;z-index:999">
    <div style="background:var(--card);border-radius:14px;padding:28px 30px;width:500px;max-width:94vw;max-height:82vh;display:flex;flex-direction:column;box-shadow:0 24px 80px rgba(0,0,0,0.22)">
      <div style="font-size:17px;font-weight:700;margin-bottom:5px;color:var(--t1)">绑定到 DDP 需求</div>
      <div style="font-size:13px;color:var(--t3);margin-bottom:14px">
        将 <code style="font-size:13px;color:var(--brand);background:var(--brand-bg);padding:1px 6px;border-radius:4px">{{ store.bindModalTraceReq }}</code> 与 DDP 需求关联后，该 DDP 需求将高亮显示为 AI 使用
      </div>
      <input class="bind-search" v-model="filterModel" placeholder="搜索需求标题或需求 ID…">
      <div id="bind-list" ref="listRef" style="overflow-y:auto;max-height:300px;flex:1;margin-bottom:4px">
        <div v-if="!candidates.length" style="color:var(--t4);padding:12px;font-size:13px">暂无可绑定的 DDP 需求</div>
        <div v-for="r in candidates" :key="r.req_name" class="bind-item" :class="{ selected: store.bindSelectedDdpReq === r.req_name }"
             :data-search="searchText(r)" @click="selectBindItem(r.req_name)">
          <div class="bind-item-title">{{ r.ddp?.title || r.req_name }}</div>
          <div class="bind-item-meta">
            <span class="bind-item-id">{{ r.req_name }}</span>
            <span v-if="r.ddp?.release_version_name" class="ep-bd ep-brand">
              <EpIcon name="rocket" :size="9" />{{ r.ddp.release_version_name }}
            </span>
            <span v-if="r.ddp?.release_version_time" class="ep-bd ep-info">
              <EpIcon name="calendar" :size="9" />{{ r.ddp.release_version_time }}
            </span>
            <span v-else-if="r.ddp?.expected_release" class="ep-bd">
              <EpIcon name="calendar" :size="9" />预计 {{ r.ddp.expected_release }}
            </span>
            <span v-if="!r.ddp?.release_version_name && !r.ddp?.release_version_time && !r.ddp?.expected_release"
                  class="ep-bd">未排期</span>
          </div>
        </div>
      </div>
      <div style="display:flex;gap:8px;margin-top:14px">
        <button id="bind-confirm" @click="confirmBind"
          style="flex:1;padding:9px;background:var(--brand);color:#fff;border:none;border-radius:8px;font-size:14px;font-weight:600;cursor:pointer;transition:opacity 0.15s"
          :disabled="!store.bindSelectedDdpReq || submitting" :style="{ opacity: (!store.bindSelectedDdpReq || submitting) ? 0.5 : 1 }">
          {{ submitting ? '绑定中…' : '确认绑定' }}
        </button>
        <button @click="hideBindModal()"
          style="padding:9px 18px;background:var(--sub-bg);color:var(--t2);border:1px solid var(--line);border-radius:8px;font-size:14px;cursor:pointer">
          取消
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import { store, hideBindModal, selectBindItem, setBindFilterText, setBindings } from '../../store/dashboard'
import { postBind } from '../../api/bindings'
import { computeMemberAiStats } from '../../utils/peopleStats'
import { sortReqsByDisplayOrder } from '../../utils/reqOrder'
import EpIcon from '../shared/EpIcon.vue'

// 候选项现在还渲染版本号/上线时间徽章，若沿用 textContent 匹配会把版本号也纳入搜索，
// 偏离「搜索需求标题或需求 ID」语义，故显式声明可搜索文本
const searchText = (r) => `${r.ddp?.title || ''} ${r.req_name}`

const committers = computed(() => store.data?.committers || [])
const requirementsIndex = computed(() => store.data?.requirements_index || [])

const norm = (s) => (s || '').trim().toLowerCase()

const candidates = computed(() => {
  const allowedReqNames = new Set()
  const dacReqNames = new Set()
  ;(store.bindModalOwnerEmails || []).map(norm).filter(Boolean).forEach(email => {
    const c = committers.value.find(x => norm(x.committer) === email)
    if (!c) return
    ;(c.requirements || []).filter(r => r.ddp).forEach(r => allowedReqNames.add(r.req_name))
    // dac 判定沿用人员视图同一口径，保证候选列表与人员视图需求卡片先后顺序一致
    computeMemberAiStats(c, store.bindings, requirementsIndex.value).dacReqList
      .forEach(r => dacReqNames.add(r.req_name))
  })
  const list = requirementsIndex.value.filter(r => r.ddp && allowedReqNames.has(r.req_name))
  return sortReqsByDisplayOrder(list, {
    requirementsIndex: requirementsIndex.value,
    todayStr: new Date().toISOString().slice(0, 10),
    dacReqNames,
  }).sorted
})

const filterModel = computed({
  get: () => store.bindFilterText,
  set: (v) => setBindFilterText(v),
})

const submitting = ref(false)

const listRef = ref(null)
function applyListFilter() {
  const root = listRef.value
  if (!root) return
  const q = (store.bindFilterText || '').toLowerCase()
  root.querySelectorAll('.bind-item').forEach(el => {
    el.style.display = (el.dataset.search || '').toLowerCase().includes(q) ? '' : 'none'
  })
}
watch([candidates, () => store.bindFilterText], applyListFilter, { flush: 'post' })

async function confirmBind() {
  if (!store.bindSelectedDdpReq || !store.bindModalTraceReq || submitting.value) return
  submitting.value = true
  try {
    const bindings = await postBind(store.bindModalTraceReq, store.bindSelectedDdpReq)
    setBindings(bindings)
    hideBindModal()
  } catch (e) {
    alert('绑定失败: ' + e.message)
  } finally {
    submitting.value = false
  }
}
</script>

<style scoped>
/* 弹窗内搜索框 / 候选项：原 base.css 全局 .bind-* 迁入组件作用域，配色换令牌 */
.bind-search {
  width: 100%; padding: 8px 12px;
  border: 1.5px solid var(--line); border-radius: 8px;
  font-size: 13px; margin-bottom: 10px; outline: none; box-sizing: border-box;
  /* 与全站 .ep-search 同族：亮色 --card 即 #FFFFFF，与默认白底等值，暗色下才跟随变深 */
  background: var(--card); color: var(--t1);
}
.bind-search::placeholder { color: var(--t4); }
.bind-search:focus { border-color: var(--brand-line); }
.bind-item {
  padding: 10px 12px; border-radius: 8px; cursor: pointer;
  border: 1.5px solid transparent; margin-bottom: 4px;
  transition: all 0.12s;
}
.bind-item:hover { background: var(--sub-bg); border-color: var(--line); }
.bind-item.selected { background: var(--brand-bg); border-color: var(--brand-line); }
.bind-item-title { font-size: 13px; font-weight: 600; color: var(--t1); }
.bind-item-meta { display: flex; align-items: center; flex-wrap: wrap; gap: 6px; margin-top: 6px; }
.bind-item-id { font-size: 11px; color: var(--t4); font-family: ui-monospace, monospace; }
</style>
