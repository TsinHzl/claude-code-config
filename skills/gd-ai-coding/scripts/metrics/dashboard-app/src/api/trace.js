export async function postDeleteTrace(committer, reqName) {
  const res = await fetch('/api/delete-trace', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ committer, req_name: reqName }),
  })
  if (!res.ok) throw new Error('HTTP ' + res.status)
  return await res.json()
}
