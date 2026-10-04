<template>
  <div class="tab-content ep-page" :class="{ active: store.activeTab === 'tab-release-notes' }" id="tab-release-notes">
    <div class="ep-top-bar">
      <div class="ep-page-title-box">
        <span class="ep-dac-pill">DAC</span>
        <h2 class="ep-page-title">更新日志</h2>
        <span class="ep-crumb">/ DAC 看板版本历史与功能变更记录</span>
      </div>
      <!-- 加载中 / 错误态不渲染汇总，避免出现占位错值 -->
      <div v-if="topMeta" class="ep-top-meta">{{ topMeta }}</div>
    </div>

    <div class="rn-scroll">
      <div v-if="loading" class="rn-state rn-state-loading">加载中...</div>
      <div v-else-if="error" class="rn-state rn-state-error">更新日志加载失败：{{ error }}</div>
      <div v-else-if="releases.length === 0" class="rn-state rn-state-empty">暂无更新记录</div>
      <div v-else class="ep-doc-col">
        <div v-for="(entry, idx) in releases" :key="entry.date" class="ep-rn-entry" :class="{ new: idx === 0 }">
          <div class="ep-rn-date-row">
            <div class="ep-rn-dot"></div>
            <span class="ep-rn-date">{{ entry.date }}</span>
            <span v-if="idx === 0" class="ep-rn-new">NEW</span>
            <span class="ep-rn-count">{{ groupsOf(entry).length }} 个模块 · {{ itemCount(entry) }} 项变更</span>
          </div>

          <div v-for="group in groupsOf(entry)" :key="group.title" class="ep-rn-group">
            <div class="ep-rn-group-title">{{ group.title }}</div>
            <ul class="ep-rn-items">
              <li v-for="item in (group.items || [])" :key="item" class="ep-rn-item">{{ item }}</li>
            </ul>
          </div>
        </div>

        <div class="ep-rn-foot">已到达最早记录 · 共 {{ releases.length }} 次发布</div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { store } from '../../store/dashboard'
import { fetchReleaseNotes } from '../../api/data'

const releases = ref([])
const loading = ref(true)
const error = ref(null)

const groupsOf = (entry) => entry.groups || []
const itemCount = (entry) => groupsOf(entry).reduce((n, g) => n + (g.items || []).length, 0)

const topMeta = computed(() => {
  if (loading.value || error.value) return ''
  const groups = releases.value.reduce((n, e) => n + groupsOf(e).length, 0)
  const items = releases.value.reduce((n, e) => n + itemCount(e), 0)
  return `${releases.value.length} 次发布 · ${groups} 个模块 · ${items} 项变更`
})

onMounted(async () => {
  try {
    // 存量数据中存在 groups 为空 / items 全空的占位条目（旧版 gen-changelog.sh 未拦截，
    // 且 install.sh 不保留 release-notes.json、无法靠重装清掉），渲染出来是一张
    // 「0 个模块 · 0 项变更」的空卡片，这里统一过滤掉
    const data = await fetchReleaseNotes()
    releases.value = data.filter((entry) => itemCount(entry) > 0)
  } catch (e) {
    error.value = e.message || String(e)
  } finally {
    loading.value = false
  }
})
</script>

<style scoped>
/* 单列文档流独立滚动，顶栏固定 */
.rn-scroll {
  flex: 1; min-height: 0; overflow-y: auto;
  display: flex; justify-content: flex-start; align-items: flex-start;
}
/* 内容宽度与全宽顶栏（.ep-top-bar）左右对齐，不再按 .ep-doc-col 的 980px 居中收窄 */
.rn-scroll .ep-doc-col { max-width: none; }
.rn-state {
  padding: 40px 0; text-align: center; font-size: 13px; color: var(--t4);
}
.rn-state-error { color: var(--danger); }
</style>
