<template>
  <div class="app-shell">
    <aside class="nav-rail">
      <div class="nav-brand">
        <div class="nav-brand-icon">DAC</div>
        <div class="nav-brand-text">
          <div class="nav-brand-title">司机端 AI 看板</div>
          <div class="nav-brand-sub">gd-ai-coding</div>
        </div>
        <button class="nav-theme-btn" @click="toggleTheme($event)" :aria-label="themeBtnLabel" :title="themeBtnLabel">
          <svg v-if="store.theme === 'dark'" class="nav-theme-ico" aria-hidden="true" focusable="false"
               viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7">
            <circle cx="10" cy="10" r="3.8" />
            <path d="M10 2v1.8M10 16.2V18M2 10h1.8M16.2 10H18M4.3 4.3l1.3 1.3M14.4 14.4l1.3 1.3M15.7 4.3l-1.3 1.3M5.6 14.4l-1.3 1.3" />
          </svg>
          <svg v-else class="nav-theme-ico" aria-hidden="true" focusable="false"
               viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7">
            <path d="M16.5 12.4A7 7 0 0 1 7.6 3.5a7 7 0 1 0 8.9 8.9z" />
          </svg>
        </button>
      </div>
      <div class="nav-refresh">
        <button id="refresh-btn" class="nav-refresh-btn" @click="startStream" :disabled="store.refreshDisabled"
          :style="{ color: store.refreshButtonColor || undefined }">
          {{ store.refreshButtonText }}
        </button>
        <div id="stream-progress" v-show="store.streamProgressVisible" class="nav-refresh-note">{{ store.streamProgressText }}</div>
        <div id="refresh-tip" v-show="store.refreshTipVisible" class="nav-refresh-note"
          :style="{ color: store.refreshTipColor || undefined }">{{ store.refreshTipText }}</div>
      </div>
      <button class="tab-btn" :class="{ active: store.activeTab === 'tab-overview' }" @click="setActiveTab('tab-overview')">
        <svg class="nav-ico" aria-hidden="true" focusable="false" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7">
          <rect x="2.5" y="2.5" width="6" height="6" rx="1.6" /><rect x="11.5" y="2.5" width="6" height="6" rx="1.6" />
          <rect x="2.5" y="11.5" width="6" height="6" rx="1.6" /><rect x="11.5" y="11.5" width="6" height="6" rx="1.6" />
        </svg>概览看板
      </button>
      <button class="tab-btn" :class="{ active: store.activeTab === 'tab-current' }" @click="setActiveTab('tab-current')">
        <svg class="nav-ico" aria-hidden="true" focusable="false" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7">
          <path d="M12.6 3.1l4.3 4.3-9 9H3.6v-4.3z" /><path d="M10.4 5.3l4.3 4.3" />
        </svg>当前版本
      </button>
      <button class="tab-btn" :class="{ active: store.activeTab === 'tab-version' }" @click="setActiveTab('tab-version')">
        <svg class="nav-ico" aria-hidden="true" focusable="false" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7">
          <path d="M3.6 16.6V10M10 16.6V4M16.4 16.6v-4.4" />
        </svg>版本视图
      </button>
      <button class="tab-btn" :class="{ active: store.activeTab === 'tab-people' }" @click="setActiveTab('tab-people')">
        <svg class="nav-ico" aria-hidden="true" focusable="false" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7">
          <circle cx="10" cy="6.6" r="3.1" /><path d="M4 16.9c0-3.2 2.7-5.1 6-5.1s6 1.9 6 5.1" />
        </svg>人员视图
      </button>
      <button class="tab-btn" :class="{ active: store.activeTab === 'tab-reqs' }" @click="setActiveTab('tab-reqs')">
        <svg class="nav-ico" aria-hidden="true" focusable="false" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7">
          <path d="M5 2.7h6.6l3.9 3.9v10.7H5z" /><path d="M7.6 9.6h5M7.6 12.7h5" />
        </svg>需求视图
      </button>
      <div style="flex:1"></div>
      <button class="tab-btn" :class="{ active: store.activeTab === 'tab-release-notes' }" @click="setActiveTab('tab-release-notes')">
        <svg class="nav-ico" aria-hidden="true" focusable="false" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7">
          <circle cx="10" cy="10" r="7.2" /><path d="M10 6.2V10l2.8 1.8" />
        </svg>更新日志
      </button>
    </aside>
    <div class="container">
      <OverviewTab />
      <CurVersionTab />
      <PeopleTab />
      <VersionTab />
      <ReqsTab />
      <ReleaseNotesTab />
    </div>
    <BindModal />
    <DeleteModal />
    <RemarkModal />
  </div>
</template>

<script setup>
import { computed, onMounted } from 'vue'
import { store, setActiveTab } from './store/dashboard'
import { toggleTheme } from './utils/theme'
import { startStream, initialLoad } from './services/refresh'
import OverviewTab from './components/tabs/OverviewTab.vue'
import CurVersionTab from './components/tabs/CurVersionTab.vue'
import PeopleTab from './components/tabs/PeopleTab.vue'
import VersionTab from './components/tabs/VersionTab.vue'
import ReqsTab from './components/tabs/ReqsTab.vue'
import ReleaseNotesTab from './components/tabs/ReleaseNotesTab.vue'
import BindModal from './components/modals/BindModal.vue'
import DeleteModal from './components/modals/DeleteModal.vue'
import RemarkModal from './components/modals/RemarkModal.vue'

const themeBtnLabel = computed(() => (store.theme === 'dark' ? '切换到亮色模式' : '切换到暗色模式'))

onMounted(() => {
  initialLoad()
})
</script>

<style>
/* Nav rail（侧边栏） */
.nav-rail {
  width: 236px;
  flex-shrink: 0;
  background: var(--nav);
  border-right: none;
  padding: 22px 16px;
  box-sizing: border-box;
  position: sticky;
  top: 0;
  height: 100vh;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
}
.nav-brand {
  display: flex; align-items: center; gap: 11px;
  padding: 0 6px 18px; margin-bottom: 18px;
  border-bottom: 1px solid var(--nav-line);
}
.nav-brand-icon {
  width: 38px; height: 38px; border-radius: 10px; flex-shrink: 0;
  background: linear-gradient(135deg, var(--brand-strong-2), var(--brand-strong));
  display: flex; align-items: center; justify-content: center;
  /* 保留写死白字：底色为橙色渐变实心块，两种主题下均应白字 */
  font-size: 13px; font-weight: 800; color: #fff;
}
.nav-brand-text { min-width: 0; }
.nav-brand-title { font-size: 15px; font-weight: 700; color: var(--nav-title); }
.nav-brand-sub { font-size: 11px; color: var(--nav-text); margin-top: 2px; }
.nav-theme-btn {
  margin-left: auto; flex-shrink: 0;
  width: 30px; height: 30px;
  display: flex; align-items: center; justify-content: center;
  border: 1px solid var(--nav-btn-line); border-radius: 9px;
  background: none; color: var(--nav-btn-text);
  cursor: pointer; transition: all 0.15s;
}
.nav-theme-btn:hover { background: var(--nav-btn-hover); border-color: var(--nav-btn-hover-line); }
.nav-theme-ico { width: 16px; height: 16px; stroke-linecap: round; stroke-linejoin: round; }
.nav-refresh { padding: 0 0 18px; }
.nav-refresh-btn {
  width: 100%;
  padding: 10px 16px;
  font-size: 13px; font-weight: 600;
  border: 1px solid var(--nav-btn-line); border-radius: 10px;
  background: var(--nav-line); color: var(--nav-btn-text);
  cursor: pointer; white-space: nowrap;
  transition: all 0.15s;
}
.nav-refresh-btn:hover:not(:disabled) { background: var(--nav-btn-hover); border-color: var(--nav-btn-hover-line); }
.nav-refresh-btn:disabled { opacity: 0.6; cursor: default; }
.nav-refresh-note {
  font-size: 11px; color: var(--nav-text); margin-top: 8px;
  font-family: "SF Mono", monospace;
}
.nav-rail .tab-btn {
  display: flex; align-items: center; gap: 11px;
  width: 100%; text-align: left;
  padding: 11px 13px; margin-bottom: 4px;
  font-size: 14px; font-weight: 600; color: var(--nav-text);
  background: none; border: none; border-bottom: none;
  border-radius: 10px;
  cursor: pointer; transition: all 0.15s;
}
.nav-rail .tab-btn:hover { color: var(--nav-text-hover); background: var(--nav-line); }
.nav-rail .tab-btn.active {
  /* 保留写死白字：底色为橙色渐变实心块，两种主题下均应白字
     （暗色下 [data-theme=dark] 会整条改为浅橙描边态，届时由该规则接管前景色）*/
  color: #fff;
  background: linear-gradient(135deg, var(--brand-strong-2), var(--brand-strong));
  border-bottom: none;
  box-shadow: 0 4px 12px rgba(242, 101, 34, 0.3);
}
.nav-ico { width: 18px; height: 18px; flex-shrink: 0; stroke-linecap: round; stroke-linejoin: round; }

/* Tab buttons（现用于侧边栏导航项，样式由 .nav-rail .tab-btn 覆盖） */
.tab-btn {
  padding: 10px 22px;
  font-size: 15px;
  font-weight: 600;
  color: var(--warm-text);
  background: none;
  border: none;
  border-bottom: 3px solid transparent;
  cursor: pointer;
  transition: all 0.2s;
  margin-bottom: -2px;
}
.tab-btn:hover { color: var(--brand-deep); }
.tab-btn.active { color: var(--brand-deep); border-bottom-color: var(--brand-deep); }
.tab-content { display: none; }
/* flex:1 + min-height:0 让当前激活的 tab 撑满 .container 剩余高度，
   并逐层向下传导（见 .master-detail），使成员列表/详情面板高度跟随容器而非固定像素 */
.tab-content.active { display: flex; flex-direction: column; flex: 1; min-height: 0; }
</style>
