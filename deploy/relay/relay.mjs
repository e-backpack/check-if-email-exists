// Reacher relay: same API and secret as a Reacher instance, forwards to the backends of RELAY_BACKENDS.
// - round-robin, next backend on network error / timeout / 429 / 5xx;
// - an answer refused for an IP blocklist (smtp.error.description "IpBlacklisted") is retried on the next
//   backend, and that backend is restarted through the Heroku API (new dyno = new outbound IP), at most
//   once per RELAY_RESTART_COOLDOWN_MIN per backend; it goes last in the order meanwhile;
// - after RELAY_MAX_RESTARTS restarts still listed, it is only logged ("relay-backend-hopeless") so the
//   app can be destroyed and recreated by hand (deploy/heroku/create-apps.sh).
// Env: PORT, RCH__HEADER_SECRET (checked, then forwarded), RELAY_BACKENDS (comma separated URLs),
// HEROKU_API_TOKEN (optional, for restarts), RELAY_TIMEOUT_MS (default 28000, Heroku router cuts at 30 s).
import http from 'node:http'

const secret = process.env.RCH__HEADER_SECRET || ''
const backends = (process.env.RELAY_BACKENDS || '').split(',').map(s => s.trim().replace(/\/+$/, '')).filter(Boolean)
const timeoutMs = Number(process.env.RELAY_TIMEOUT_MS || 28000)
const cooldownMs = Number(process.env.RELAY_RESTART_COOLDOWN_MIN || 20) * 60_000
const maxRestarts = Number(process.env.RELAY_MAX_RESTARTS || 10)
const token = process.env.HEROKU_API_TOKEN || ''
if (!secret || !backends.length) { console.error('relay: RCH__HEADER_SECRET and RELAY_BACKENDS are required'); process.exit(1) }

const state = new Map(backends.map(b => [b, { listedUntil: 0, lastRestart: 0, restarts: 0, downUntil: 0 }]))
let next = 0
const log = (msg, o = {}) => console.log(JSON.stringify({ t: new Date().toISOString(), msg, ...o }))

/** Healthy backends first (round-robin), listed / failing ones last. */
function order() {
  const now = Date.now()
  const rr = backends.map((_, i) => backends[(next + i) % backends.length])
  next = (next + 1) % backends.length
  const bad = b => state.get(b).listedUntil > now || state.get(b).downUntil > now
  return [...rr.filter(b => !bad(b)), ...rr.filter(bad)]
}

function appOf(url) {
  const m = /^https:\/\/([a-z0-9-]+?)(?:-[0-9a-f]{12})?\.herokuapp\.com/.exec(url)
  return m ? m[1] : null
}

async function restart(b) {
  const s = state.get(b), app = appOf(b)
  if (!token || !app || Date.now() - s.lastRestart < cooldownMs) return
  s.lastRestart = Date.now()
  if (++s.restarts > maxRestarts) { log('relay-backend-hopeless', { backend: app, restarts: s.restarts - 1 }); return }
  try {
    const r = await fetch(`https://api.heroku.com/apps/${app}/dynos`, { method: 'DELETE', headers: { Accept: 'application/vnd.heroku+json; version=3', Authorization: `Bearer ${token}` } })
    log('relay-backend-restarted', { backend: app, status: r.status, restarts: s.restarts })
  } catch (e) { log('relay-backend-restart-failed', { backend: app, error: String(e?.message ?? e) }) }
}

function ipBlacklisted(body) {
  try { return JSON.parse(body)?.smtp?.error?.description === 'IpBlacklisted' } catch { return false }
}

async function forward(method, path, headers, body) {
  let last = { status: 502, body: JSON.stringify({ error: 'no Reacher backend answered' }), type: 'application/json' }
  for (const b of order()) {
    const s = state.get(b)
    try {
      const r = await fetch(b + path, { method, headers, body: method === 'GET' ? undefined : body, signal: AbortSignal.timeout(timeoutMs) })
      const text = await r.text()
      const res = { status: r.status, body: text, type: r.headers.get('content-type') || 'application/json' }
      if (r.status === 429 || r.status >= 500) { s.downUntil = Date.now() + 60_000; last = res; continue }
      if (r.ok && ipBlacklisted(text)) { s.listedUntil = Date.now() + cooldownMs; restart(b); last = res; continue }
      if (r.ok && path.startsWith('/v0/check_email')) s.restarts = 0
      return res
    } catch (e) {
      s.downUntil = Date.now() + 60_000
      log('relay-backend-error', { backend: appOf(b) || b, error: String(e?.message ?? e) })
    }
  }
  return last
}

http.createServer(async (req, res) => {
  if (req.url === '/healthz') { res.writeHead(200).end('ok'); return }
  if (req.url !== '/version' && req.headers['x-reacher-secret'] !== secret) {
    res.writeHead(400, { 'content-type': 'text/plain' }).end('Missing/Invalid request header "x-reacher-secret"'); return
  }
  const chunks = []; for await (const c of req) chunks.push(c)
  const out = await forward(req.method, req.url, { 'content-type': 'application/json', 'x-reacher-secret': secret }, Buffer.concat(chunks))
  res.writeHead(out.status, { 'content-type': out.type }).end(out.body)
}).listen(Number(process.env.PORT || 8080), () => log('relay-up', { backends: backends.map(b => appOf(b) || b) }))
