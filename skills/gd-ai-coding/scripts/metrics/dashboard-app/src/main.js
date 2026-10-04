import { createApp } from 'vue'
import App from './App.vue'
import './assets/base.css'
import { initTheme } from './utils/theme'

// 必须先于 mount：否则首帧用亮色令牌绘制，暗色用户每次刷新都会闪一次白
initTheme()

createApp(App).mount('#app')
