export async function fetchRemarks() {
  if (window.__STATIC_DATA__ !== null && window.__STATIC_DATA__ !== undefined) return {}
  try {
    const res = await fetch('/api/remarks')
    if (res.ok) return await res.json()
  } catch (e) {
    console.warn('load remarks failed:', e)
  }
  return {}
}

export async function postRemark({ req_name, reason_tag, note, author, excluded_from_stats = false, clear = false }) {
  const res = await fetch('/api/remarks', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ req_name, reason_tag, note, author, excluded_from_stats, clear }),
  })
  if (!res.ok) throw new Error('HTTP ' + res.status)
  return await res.json()
}
