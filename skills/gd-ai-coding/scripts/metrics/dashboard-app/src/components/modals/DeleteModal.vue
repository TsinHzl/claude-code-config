<template>
  <div v-if="store.deleteModalVisible" id="delete-overlay" @click.self="hideDeleteModal()"
    style="display:flex;position:fixed;inset:0;background:rgba(0,0,0,0.45);align-items:center;justify-content:center;z-index:999">
    <div style="background:var(--card);border-radius:14px;padding:28px 30px;width:460px;max-width:94vw;box-shadow:0 24px 80px rgba(0,0,0,0.22)">
      <div style="font-size:17px;font-weight:700;margin-bottom:10px;color:var(--danger)">删除 AI 使用数据</div>
      <div style="font-size:13px;color:var(--t2);line-height:1.7;margin-bottom:8px">
        即将删除以下 trace 记录（该成员该需求跨所有仓库的全部记录）：
      </div>
      <div style="font-size:13px;background:var(--sub-bg);border:1px solid var(--line);border-radius:8px;padding:10px 12px;margin-bottom:12px">
        <div>成员：<code style="color:var(--t1)">{{ store.deleteTarget?.committer || '(未知)' }}</code></div>
        <div style="margin-top:4px">需求：<code style="color:var(--brand)">{{ store.deleteTarget?.reqName }}</code></div>
      </div>
      <div style="font-size:12px;color:var(--danger);background:var(--danger-bg);border:1px solid var(--danger-line);border-radius:8px;padding:8px 10px;margin-bottom:16px;line-height:1.6">
        <EpIcon name="alert" :size="11" style="vertical-align:-1px" /> 此操作不可撤销，且作用于共享后端库（所有查看看板的人都会受影响）。删除会被记住；仅当本人重新真实提交（新的 AI 工作流上报或 commit）时才会复活。
      </div>
      <div style="display:flex;gap:8px">
        <button id="delete-confirm" @click="confirmDelete"
          style="flex:1;padding:9px;background:var(--danger);color:#fff;border:none;border-radius:8px;font-size:14px;font-weight:600;cursor:pointer"
          :disabled="submitting" :style="{ opacity: submitting ? 0.5 : 1 }">
          {{ submitting ? '删除中…' : '确认删除' }}
        </button>
        <button @click="hideDeleteModal()"
          style="padding:9px 18px;background:var(--sub-bg);color:var(--t2);border:1px solid var(--line);border-radius:8px;font-size:14px;cursor:pointer">
          取消
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { store, hideDeleteModal, setData, setBindings } from '../../store/dashboard'
import { postDeleteTrace } from '../../api/trace'
import { fetchData, fetchBindings } from '../../api/data'
import EpIcon from '../shared/EpIcon.vue'

const submitting = ref(false)

async function confirmDelete() {
  const target = store.deleteTarget
  if (!target || submitting.value) return
  submitting.value = true
  try {
    await postDeleteTrace(target.committer, target.reqName)
  } catch (e) {
    alert('删除失败: ' + e.message)
    submitting.value = false
    return
  }
  hideDeleteModal()
  try {
    const bindings = await fetchBindings()
    if (bindings !== undefined) setBindings(bindings)
    const data = await fetchData()
    setData(data)
  } catch (e) {
    alert('删除成功，但刷新页面数据失败: ' + e.message)
  } finally {
    submitting.value = false
  }
}
</script>
