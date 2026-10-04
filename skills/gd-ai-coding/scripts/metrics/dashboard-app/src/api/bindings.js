export async function postBind(traceReq, ddpReq) {
  const res = await fetch('/api/bind-req', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ trace_req: traceReq, ddp_req: ddpReq }),
  })
  if (!res.ok) throw new Error('HTTP ' + res.status)
  const data = await res.json()
  return data.bindings
}

export async function postUnbind(traceReq) {
  const res = await fetch('/api/bind-req', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ trace_req: traceReq, unbind: true }),
  })
  if (!res.ok) throw new Error('HTTP ' + res.status)
  const data = await res.json()
  return data.bindings
}
