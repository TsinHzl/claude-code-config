export async function fetchData() {
  if (window.__STATIC_DATA__ !== null && window.__STATIC_DATA__ !== undefined) {
    return window.__STATIC_DATA__
  }
  const res = await fetch('/api/data')
  if (!res.ok) throw new Error('fetch /api/data failed: ' + res.status)
  return await res.json()
}

export async function fetchBindings() {
  if (window.__STATIC_DATA__ !== null && window.__STATIC_DATA__ !== undefined) return undefined
  try {
    const res = await fetch('/api/bindings')
    if (res.ok) return await res.json()
  } catch (e) {
    console.warn('load bindings failed:', e)
  }
  return undefined
}

export async function fetchReleaseNotes() {
  const res = await fetch('/release-notes.json')
  if (!res.ok) throw new Error('fetch /release-notes.json failed: ' + res.status)
  return await res.json()
}

export async function fetchConfig() {
  if (window.__STATIC_DATA__ !== null && window.__STATIC_DATA__ !== undefined) {
    return { vibeVisible: false }
  }
  try {
    const res = await fetch('/api/config')
    if (res.ok) return await res.json()
  } catch (e) {
    console.warn('load config failed:', e)
  }
  return { vibeVisible: false }
}
