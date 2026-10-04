import {
  store, setData, setBindings, setConfig, setRemarks,
  setRefreshButton, setRefreshDisabled, setStreamProgress, setRefreshTip,
} from '../store/dashboard'
import { fetchData, fetchBindings, fetchConfig } from '../api/data'
import { fetchRemarks } from '../api/remarks'

let activeStream = null

export function startStream() {
  if (window.__STATIC_DATA__ !== null && window.__STATIC_DATA__ !== undefined) {
    setRefreshTip('静态模式下无法刷新，请重新运行 /dashboard 命令', '', true)
    setTimeout(() => setRefreshTip('', '', false), 4000)
    return
  }

  if (activeStream) { activeStream.close(); activeStream = null }

  setRefreshDisabled(true)
  setRefreshButton('⏳ 加载中…')
  setRefreshTip('', '', false)
  setStreamProgress('正在连接数据流...', true)

  const es = new EventSource('/api/stream')
  activeStream = es

  es.onmessage = async function (e) {
    let msg
    try { msg = JSON.parse(e.data) } catch { return }

    if (msg.type === 'backend_snapshot') {
      setData({ committers: msg.committers, requirements_index: msg.requirements_index, generatedAt: msg.generatedAt, dac_req_count: msg.dac_req_count || 0, personal_totals: msg.personal_totals, quality_stats: msg.quality_stats ?? store.data?.quality_stats ?? [] })
    } else if (msg.type === 'progress') {
      setStreamProgress(msg.message, true)
    } else if (msg.type === 'trace_preview') {
      setData({ committers: msg.committers, requirements_index: msg.requirements_index, generatedAt: msg.generatedAt, dac_req_count: 0, personal_totals: msg.personal_totals, quality_stats: msg.quality_stats ?? store.data?.quality_stats ?? [] })
    } else if (msg.type === 'page') {
      setData({ committers: msg.committers, requirements_index: msg.requirements_index, generatedAt: msg.generatedAt, dac_req_count: msg.dac_req_count, quality_stats: msg.quality_stats ?? store.data?.quality_stats ?? [] })
      setRefreshButton(`⏳ 第 ${msg.page} 页…`)
    } else if (msg.type === 'done') {
      es.close(); activeStream = null
      const bindings = await fetchBindings()
      if (bindings !== undefined) setBindings(bindings)
      const remarks = await fetchRemarks()
      if (remarks !== undefined) setRemarks(remarks)
      try {
        const fresh = await fetchData()
        setData({ ...store.data, personal_totals: fresh.personal_totals, quality_stats: fresh.quality_stats ?? store.data?.quality_stats })
      } catch (err) {
        console.warn('reload personal_totals failed:', err)
      }
      setStreamProgress('', false)
      setRefreshButton('✓ 已更新', '#059669')
      setTimeout(() => {
        setRefreshButton('↻ 刷新数据')
        setRefreshDisabled(false)
      }, 2500)
    } else if (msg.type === 'error') {
      es.close(); activeStream = null
      setRefreshButton('↻ 刷新数据')
      setRefreshDisabled(false)
      setStreamProgress('', false)
      setRefreshTip('加载失败：' + (msg.message || '').slice(0, 150), '#dc2626', true)
    }
  }

  es.onerror = function () {
    if (es.readyState === EventSource.CLOSED) return
    es.close(); activeStream = null
    setRefreshButton('↻ 刷新数据')
    setRefreshDisabled(false)
    setStreamProgress('', false)
    setRefreshTip('数据流连接失败，请检查 server 是否通过 /dashboard 启动', '#dc2626', true)
  }
}

export async function initialLoad() {
  setConfig(await fetchConfig())
  const bindings = await fetchBindings()
  if (bindings !== undefined) setBindings(bindings)
  const remarks = await fetchRemarks()
  if (remarks !== undefined) setRemarks(remarks)
  try {
    const data = await fetchData()
    setData(data)
  } catch (e) {
    console.error('load cached data failed:', e)
  }
  if (window.__STATIC_DATA__ === null || window.__STATIC_DATA__ === undefined) {
    startStream()
  }
}
