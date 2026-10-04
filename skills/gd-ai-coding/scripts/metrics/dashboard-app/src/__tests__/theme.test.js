import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { initTheme, toggleTheme, readStoredTheme } from '../utils/theme'
import { store, setTheme } from '../store/dashboard'

const STORAGE_KEY = 'dac-dashboard-theme'

// 本环境的全局 localStorage 是个无方法的空对象（Node 22 内置实验性 localStorage 覆盖了
// jsdom 的实现，运行时可见 `--localstorage-file` 警告），直接用会抛 TypeError。
// 故自备内存 Storage 桩，测的是 theme.js 的逻辑而非宿主实现。
function makeStorage() {
  const map = new Map()
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => void map.set(k, String(v)),
    removeItem: (k) => void map.delete(k),
    clear: () => map.clear(),
  }
}

describe('theme.js 主题初始化与切换', () => {
  let storage

  beforeEach(() => {
    storage = makeStorage()
    vi.stubGlobal('localStorage', storage)
    setTheme('light')
    delete document.documentElement.dataset.theme
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it('无存储值时回落亮色，并把 data-theme 写成 light', () => {
    expect(initTheme()).toBe('light')
    expect(document.documentElement.dataset.theme).toBe('light')
    expect(store.theme).toBe('light')
  })

  it('存储值为 dark 时恢复暗色', () => {
    storage.setItem(STORAGE_KEY, 'dark')
    expect(initTheme()).toBe('dark')
    expect(document.documentElement.dataset.theme).toBe('dark')
    expect(store.theme).toBe('dark')
  })

  it('存储值非法时降级为亮色，不抛异常', () => {
    storage.setItem(STORAGE_KEY, 'midnight')
    expect(readStoredTheme()).toBe('light')
    expect(initTheme()).toBe('light')
    expect(store.theme).toBe('light')
  })

  it('localStorage 读抛异常（file:// 下的 SecurityError）时降级为亮色', () => {
    vi.spyOn(storage, 'getItem').mockImplementation(() => {
      throw new DOMException('denied', 'SecurityError')
    })
    expect(() => initTheme()).not.toThrow()
    expect(store.theme).toBe('light')
    expect(document.documentElement.dataset.theme).toBe('light')
  })

  it('toggleTheme 双向切换，并把结果写入 localStorage', () => {
    initTheme()
    expect(toggleTheme()).toBe('dark')
    expect(store.theme).toBe('dark')
    expect(document.documentElement.dataset.theme).toBe('dark')
    expect(storage.getItem(STORAGE_KEY)).toBe('dark')

    expect(toggleTheme()).toBe('light')
    expect(store.theme).toBe('light')
    expect(document.documentElement.dataset.theme).toBe('light')
    expect(storage.getItem(STORAGE_KEY)).toBe('light')
  })

  it('localStorage 写抛异常时当次切换仍生效（仅丢失持久化）', () => {
    initTheme()
    vi.spyOn(storage, 'setItem').mockImplementation(() => {
      throw new DOMException('quota', 'QuotaExceededError')
    })
    expect(() => toggleTheme()).not.toThrow()
    expect(store.theme).toBe('dark')
    expect(document.documentElement.dataset.theme).toBe('dark')
  })

  it('不支持 View Transitions 时退化为直接切换', () => {
    initTheme()
    expect(toggleTheme()).toBe('dark')
    expect(document.documentElement.dataset.theme).toBe('dark')
    expect(storage.getItem(STORAGE_KEY)).toBe('dark')
  })

  it('支持 View Transitions 时走圆形扩散：切换经 startViewTransition 回调生效', async () => {
    vi.stubGlobal('matchMedia', () => ({ matches: false }))
    const animateSpy = vi.fn()
    document.documentElement.animate = animateSpy
    let runChange
    const ready = Promise.resolve()
    const startViewTransition = vi.fn((cb) => {
      runChange = cb
      return { ready, updateCallbackDone: Promise.resolve() }
    })
    document.startViewTransition = startViewTransition
    initTheme()

    toggleTheme({ clientX: 20, clientY: 30 })
    expect(startViewTransition).toHaveBeenCalledTimes(1)
    // 回调执行前主题未变（快照捕获时机由 startViewTransition 决定）
    expect(store.theme).toBe('light')
    runChange()
    expect(store.theme).toBe('dark')
    expect(document.documentElement.dataset.theme).toBe('dark')
    expect(storage.getItem(STORAGE_KEY)).toBe('dark')
    // 返回值在回调执行前即已确定（next 提前计算），不依赖异步回调
    expect(toggleTheme({ clientX: 20, clientY: 30 })).toBe('dark')

    await ready
    // clipPath 圆形扩散自点击位置展开，半径覆盖视口最远角
    expect(animateSpy).toHaveBeenCalledWith(
      { clipPath: ['circle(0px at 20px 30px)', expect.stringMatching(/^circle\(\d+(\.\d+)?px at 20px 30px\)$/) ] },
      expect.objectContaining({ duration: 550, pseudoElement: '::view-transition-new(root)' }),
    )
    vi.unstubAllGlobals()
  })

  it('reduced-motion（减弱动态效果）时退化为直接切换', () => {
    vi.stubGlobal('matchMedia', (q) => ({ matches: q === '(prefers-reduced-motion: reduce)' }))
    initTheme()
    expect(toggleTheme()).toBe('dark')
    expect(document.documentElement.dataset.theme).toBe('dark')
    vi.unstubAllGlobals()
  })
})
