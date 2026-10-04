import { spawn } from 'node:child_process'
import { writeFileSync } from 'node:fs'
import { setTimeout as sleep } from 'node:timers/promises'

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const PORT = 9334
const chrome = spawn(CHROME, [
  '--headless=new',
  `--remote-debugging-port=${PORT}`,
  '--user-data-dir=/tmp/dac-cdp-profile',
  '--disable-gpu',
  '--window-size=1440,1800',
  'about:blank',
], { stdio: 'ignore' })

let ws
try {
  let ver
  for (let i = 0; i < 25; i++) {
    await sleep(200)
    try {
      ver = await fetch(`http://127.0.0.1:${PORT}/json/version`).then((r) => r.json())
      break
    } catch {}
  }
  if (!ver) throw new Error('cdp not up')
  ws = new WebSocket(ver.webSocketDebuggerUrl)
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej })
  const pending = new Map()
  let n = 1
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data)
    if (msg.id != null && pending.has(msg.id)) pending.get(msg.id)(msg)
  }
  function fcall(method, params = {}, sessionId) {
    const id = n++
    return new Promise((resolve) => {
      pending.set(id, resolve)
      const payload = { id, method, params }
      if (sessionId) payload.sessionId = sessionId
      ws.send(JSON.stringify(payload))
    })
  }
  const created = await fcall('Target.createTarget', { url: 'http://localhost:47890/?t=cdp' })
  const targetId = created.result.targetId
  const attached = await fcall('Target.attachToTarget', { targetId, flatten: true })
  const sessionId = attached.result.sessionId
  await fcall('Page.enable', {}, sessionId)
  await fcall('Runtime.enable', {}, sessionId)
  await sleep(3000)
  const evalRes = await fcall('Runtime.evaluate', {
    expression: `(() => {
      const q = document.querySelector('.quality-grid')
      const sub = document.querySelector('.card-title-sub')
      const el = document.querySelector('#dur-chart')
      const scroll = document.querySelector('.dur-scroll')
      return JSON.stringify({
        quality: q && q.innerText,
        sub: sub && sub.innerText,
        svgW: el && el.getAttribute('width'),
        svgBox: el && Math.round(el.getBoundingClientRect().width),
        scrollW: scroll && Math.round(scroll.getBoundingClientRect().width),
        texts: el ? [...el.querySelectorAll('text')].slice(0, 18).map(t => t.textContent) : [],
        poly: el ? el.querySelectorAll('polyline').length : 0,
      })
    })()`,
    returnByValue: true,
  }, sessionId)
  console.log('EVAL', evalRes.result && evalRes.result.result && evalRes.result.result.value)
  const shot = await fcall('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true }, sessionId)
  const b64 = shot.result && shot.result.data
  if (b64) {
    writeFileSync('/tmp/dac-overview.png', Buffer.from(b64, 'base64'))
    console.log('wrote /tmp/dac-overview.png', Buffer.from(b64, 'base64').length)
  } else {
    console.log('no screenshot', JSON.stringify(shot).slice(0, 800))
  }
} finally {
  try { ws && ws.close() } catch {}
  chrome.kill()
}
