import { store, setTheme } from '../store/dashboard'

const STORAGE_KEY = 'dac-dashboard-theme'
const THEMES = ['light', 'dark']

export function readStoredTheme() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    return THEMES.includes(raw) ? raw : 'light'
  } catch {
    // dist-single/index.html 以 file:// 打开时，部分浏览器访问 localStorage 直接抛 SecurityError
    return 'light'
  }
}

function persistTheme(theme) {
  try {
    localStorage.setItem(STORAGE_KEY, theme)
  } catch {
    // 写失败仅影响持久化，当次会话内切换仍生效
  }
}

export function applyTheme(theme) {
  const next = THEMES.includes(theme) ? theme : 'light'
  document.documentElement.dataset.theme = next
  setTheme(next)
  return next
}

export function initTheme() {
  return applyTheme(readStoredTheme())
}

/** View Transitions 圆形扩散动画是否可用（浏览器支持 + 未开启减弱动态效果） */
function supportsCircularReveal() {
  try {
    return (
      typeof document !== 'undefined' &&
      typeof document.startViewTransition === 'function' &&
      !window.matchMedia('(prefers-reduced-motion: reduce)').matches
    )
  } catch {
    return false
  }
}

function switchTheme(next) {
  applyTheme(next)
  persistTheme(next)
  return next
}

export function toggleTheme(clickEvent) {
  const next = store.theme === 'dark' ? 'light' : 'dark'
  // 无动画能力/减弱动态时退化为直接切换
  if (!supportsCircularReveal()) return switchTheme(next)
  // 圆形扩散：新主题自点击位置（缺省视口中心）向外揭示
  const cx = clickEvent?.clientX ?? window.innerWidth / 2
  const cy = clickEvent?.clientY ?? window.innerHeight / 2
  const radius = Math.hypot(Math.max(cx, window.innerWidth - cx), Math.max(cy, window.innerHeight - cy))
  const transition = document.startViewTransition(() => {
    switchTheme(next)
  })
  // 动画被新 transition 抢占（连续快速点击）时 ready 会 reject，静默即可；
  // updateCallbackDone 兜底防 unhandled rejection（回调内抛错等罕见路径）
  transition.updateCallbackDone.catch(() => {})
  transition.ready.then(() => {
    document.documentElement.animate(
      { clipPath: [`circle(0px at ${cx}px ${cy}px)`, `circle(${radius}px at ${cx}px ${cy}px)`] },
      {
        duration: 550,
        easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
        pseudoElement: '::view-transition-new(root)',
      },
    )
  }).catch(() => {
    // 动画被新 transition 抢占（连续快速点击）时 ready 会 reject，静默即可
  })
  return store.theme
}
