<template>
  <div v-if="store.remarkModalVisible" id="remark-overlay" @click.self="!submitting && hideRemarkModal()"
    style="display:flex;position:fixed;inset:0;background:rgba(0,0,0,0.45);align-items:center;justify-content:center;z-index:999">
    <div style="background:var(--card);border-radius:14px;padding:28px 30px;width:520px;max-width:94vw;max-height:85vh;display:flex;flex-direction:column;box-shadow:0 24px 80px rgba(0,0,0,0.22)">
      <div style="font-size:17px;font-weight:700;margin-bottom:6px;color:var(--t1)">不活跃需求原因备注</div>
      <div style="font-size:13px;color:var(--t3);margin-bottom:14px;line-height:1.5">
        记录未采用 AI 的原因与背景，便于团队复盘与瓶颈分析。
      </div>

      <!-- 需求信息卡片 -->
      <div style="background:var(--sub-bg);border:1px solid var(--line);border-radius:8px;padding:10px 12px;margin-bottom:16px">
        <div style="font-size:13px;font-weight:600;color:var(--t1)">{{ store.remarkModalReqTitle || store.remarkModalReqName }}</div>
        <div style="display:flex;align-items:center;gap:8px;margin-top:4px">
          <code style="font-size:12px;color:var(--brand);background:var(--brand-bg);padding:1px 6px;border-radius:4px">{{ store.remarkModalReqName }}</code>
          <span v-if="existingRemark?.updated_at" style="font-size:11px;color:var(--t4)">上次更新: {{ formatTime(existingRemark.updated_at) }}</span>
        </div>
      </div>

      <div style="overflow-y:auto;flex:1;padding-right:2px">
        <!-- 原因标签 -->
        <div style="margin-bottom:14px">
          <label style="display:block;font-size:12px;font-weight:600;color:var(--t2);margin-bottom:6px">原因标签</label>
          <div style="display:flex;flex-wrap:wrap;gap:6px">
            <button v-for="tag in PRESET_TAGS" :key="tag" type="button" class="tag-chip"
              :class="{ active: selectedTag === tag }" @click="toggleTag(tag)">
              {{ tag }}
            </button>
          </div>
        </div>

        <!-- 详细说明 -->
        <div style="margin-bottom:14px">
          <label style="display:block;font-size:12px;font-weight:600;color:var(--t2);margin-bottom:6px">详细说明</label>
          <textarea v-model="note" class="remark-textarea" rows="3" placeholder="请输入未采用 AI 的原因说明或其他补充信息…"></textarea>
        </div>

        <!-- 排除统计 -->
        <div style="margin-bottom:14px">
          <label style="display:flex;align-items:center;gap:8px;cursor:pointer;user-select:none">
            <input type="checkbox" v-model="excludedFromStats" style="width:15px;height:15px;accent-color:var(--brand);cursor:pointer" />
            <span style="font-size:13px;font-weight:600;color:var(--t1)">排除统计</span>
            <span style="font-size:12px;color:var(--t3)">勾选后，概览看板数据统计中将排除此需求</span>
          </label>
        </div>

        <!-- 填写人（下拉多选，禁自由输入） -->
        <div style="margin-bottom:16px">
          <label style="display:block;font-size:12px;font-weight:600;color:var(--t2);margin-bottom:6px">填写人</label>
          <div class="author-select" ref="authorSelectRef">
            <div class="author-box" @click="authorDropdownOpen = !authorDropdownOpen">
              <span v-if="selectedAuthors.length === 0" class="author-placeholder">点击选择填写人（可多选）</span>
              <span v-else class="author-chips">
                <span v-for="name in selectedAuthors" :key="name" class="tag-chip active author-chip" @click.stop="toggleAuthor(name)">{{ name }} ✕</span>
              </span>
              <span class="author-arrow">▾</span>
            </div>
            <div v-if="authorDropdownOpen" class="author-dropdown">
              <button v-for="opt in authorOptions" :key="opt" type="button" class="tag-chip"
                :class="{ active: selectedAuthors.includes(opt) }" @click="toggleAuthor(opt)">
                {{ opt }}
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- 底部按钮 -->
      <div style="display:flex;gap:8px;margin-top:14px">
        <button id="remark-save" @click="saveRemark" class="btn-primary" :disabled="submitting || (!selectedTag && !note.trim())">
          {{ submitting ? '保存中…' : '保存' }}
        </button>
        <button v-if="hasExistingRemark" id="remark-clear" @click="clearRemark" class="btn-danger" :disabled="submitting">
          清空备注
        </button>
        <button @click="hideRemarkModal()" class="btn-secondary" :disabled="submitting">
          取消
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>

import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { store, hideRemarkModal, setRemarks } from '../../store/dashboard'
import { postRemark } from '../../api/remarks'

const PRESET_TAGS = ['非业务代码', '仅改配置', '排期较紧', '第三方SDK对接', '调研/探索型需求', '工具/环境问题', '其他']

const selectedTag = ref('')
const note = ref('')
const selectedAuthors = ref([])
const excludedFromStats = ref(false)
const submitting = ref(false)
const authorDropdownOpen = ref(false)
const authorSelectRef = ref(null)

// 候选人 = 该需求的参与人（打开入口传入）；缺省时回退为全团队 committers
const authorOptions = computed(() => {
  const fromReq = store.remarkModalAuthors
  if (Array.isArray(fromReq) && fromReq.length) return fromReq
  const list = (store.data?.committers || [])
    .map((c) => c.committer_name || c.committer)
    .filter(Boolean)
  return [...new Set(list)]
})

function toggleAuthor(name) {
  selectedAuthors.value = selectedAuthors.value.includes(name)
    ? selectedAuthors.value.filter((n) => n !== name)
    : [...selectedAuthors.value, name]
}

function onClickOutsideAuthor(e) {
  if (authorDropdownOpen.value && authorSelectRef.value && !authorSelectRef.value.contains(e.target)) {
    authorDropdownOpen.value = false
  }
}
onMounted(() => document.addEventListener('click', onClickOutsideAuthor))
onBeforeUnmount(() => document.removeEventListener('click', onClickOutsideAuthor))

const existingRemark = computed(() => {
  const reqName = store.remarkModalReqName
  if (!reqName || !store.remarks) return null
  return store.remarks[reqName] || null
})

const hasExistingRemark = computed(() => !!existingRemark.value)

watch(() => store.remarkModalVisible, (visible) => {
  if (visible) {
    authorDropdownOpen.value = false
    const cur = existingRemark.value
    if (cur) {
      selectedTag.value = cur.reason_tag || ''
      note.value = cur.note || ''
      // 旧数据为单值字符串；多选后按「、」拆回数组（天然兼容旧值）
      selectedAuthors.value = (cur.author || store.remarkModalDefaultAuthor || '')
        .split('、').map((s) => s.trim()).filter(Boolean)
      excludedFromStats.value = !!cur.excluded_from_stats
    } else {
      selectedTag.value = ''
      note.value = ''
      selectedAuthors.value = (store.remarkModalDefaultAuthor || '')
        .split('、').map((s) => s.trim()).filter(Boolean)
      excludedFromStats.value = false
    }
  }
}, { immediate: true })

function toggleTag(tag) {
  selectedTag.value = selectedTag.value === tag ? '' : tag
}

function formatTime(ts) {
  if (!ts) return ''
  const d = new Date(ts)
  if (isNaN(d.getTime())) return ''
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const date = String(d.getDate()).padStart(2, '0')
  const hh = String(d.getHours()).padStart(2, '0')
  const mm = String(d.getMinutes()).padStart(2, '0')
  return `${y}-${m}-${date} ${hh}:${mm}`
}

async function saveRemark() {
  const reqName = store.remarkModalReqName
  if (!reqName || submitting.value) return
  if (selectedAuthors.value.length === 0) {
    alert('请至少选择一名填写人')
    return
  }
  // 后端 author 字段上限 128 字符，全选（或候选含邮箱前缀）时可能超限
  const authorText = selectedAuthors.value.join('、')
  if (authorText.length > 128) {
    alert('填写人合计超过 128 字符，请减少选择人数')
    return
  }
  submitting.value = true
  try {
    const updated = await postRemark({
      req_name: reqName,
      reason_tag: selectedTag.value,
      note: note.value.trim(),
      author: authorText,
      excluded_from_stats: excludedFromStats.value,
      clear: false,
    })
    setRemarks(updated)
    hideRemarkModal()
  } catch (e) {
    alert('保存备注失败: ' + e.message)
  } finally {
    submitting.value = false
  }
}

async function clearRemark() {
  const reqName = store.remarkModalReqName
  if (!reqName || submitting.value) return
  submitting.value = true
  try {
    const updated = await postRemark({
      req_name: reqName,
      clear: true,
    })
    setRemarks(updated)
    hideRemarkModal()
  } catch (e) {
    alert('清空备注失败: ' + e.message)
  } finally {
    submitting.value = false
  }
}
</script>

<style scoped>
.tag-chip {
  padding: 4px 10px;
  font-size: 12px;
  border-radius: 6px;
  border: 1px solid var(--line);
  background: var(--card);
  color: var(--t2);
  cursor: pointer;
  transition: all 0.12s;
}
.tag-chip:hover {
  background: var(--sub-bg);
  border-color: var(--brand-line);
}
.tag-chip.active {
  background: var(--brand-bg);
  color: var(--brand);
  border-color: var(--brand);
  font-weight: 600;
}

.author-select {
  position: relative;
}
.author-box {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  min-height: 36px;
  padding: 4px 10px;
  border: 1.5px solid var(--line);
  border-radius: 8px;
  background: var(--card);
  cursor: pointer;
  font-size: 13px;
  color: var(--t1);
}
.author-box:hover {
  border-color: var(--brand-line);
}
.author-placeholder {
  color: var(--t4);
  font-size: 13px;
}
.author-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
.author-chip {
  cursor: pointer;
}
.author-arrow {
  color: var(--t3);
  font-size: 12px;
  flex-shrink: 0;
}
.author-dropdown {
  /* 流内展开：父级弹窗滚动容器有 overflow 裁剪，absolute 浮层会被裁掉 */
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-top: 6px;
  padding: 10px;
  background: var(--card);
  border: 1px solid var(--line);
  border-radius: 8px;
  box-shadow: 0 8px 24px rgba(0,0,0,0.12);
  max-height: 220px;
  overflow-y: auto;
}

.remark-textarea {
  width: 100%;
  padding: 8px 12px;
  border: 1.5px solid var(--line);
  border-radius: 8px;
  font-size: 13px;
  outline: none;
  box-sizing: border-box;
  background: var(--card);
  color: var(--t1);
  resize: vertical;
  font-family: inherit;
}
.remark-textarea::placeholder {
  color: var(--t4);
}
.remark-textarea:focus {
  border-color: var(--brand-line);
}

.btn-primary {
  flex: 1;
  padding: 9px;
  background: var(--brand);
  color: #fff;
  border: none;
  border-radius: 8px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  transition: opacity 0.15s;
}
.btn-primary:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.btn-danger {
  padding: 9px 14px;
  background: var(--danger-bg);
  color: var(--danger);
  border: 1px solid var(--danger-line);
  border-radius: 8px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  transition: opacity 0.15s;
}
.btn-danger:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.btn-secondary {
  padding: 9px 18px;
  background: var(--sub-bg);
  color: var(--t2);
  border: 1px solid var(--line);
  border-radius: 8px;
  font-size: 14px;
  cursor: pointer;
}
</style>
