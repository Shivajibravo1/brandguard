import { useMemo } from 'react'
import { MetricCard, Panel, Ping, Radar, RiskRing, SampleBadge, SeverityBadge, Button } from '../components/ui'
import { CHANNEL_LABEL, OPEN_STATUSES, isSample, scoreColor, timeAgo, STATUS_LABEL } from '../lib/format'

const DAY_MS = 24 * 3600 * 1000

// Stable pseudo-random position for a radar blip, from the incident id
function blipPosition(id) {
  let h = 0
  for (const c of id) h = (h * 31 + c.charCodeAt(0)) >>> 0
  const angle = (h % 360) * (Math.PI / 180)
  const radius = 14 + ((h >> 9) % 30)
  return { x: 50 + radius * Math.cos(angle), y: 50 + radius * Math.sin(angle) }
}

// Next daily run of the website monitor (06:00 UTC)
function nextWebsiteRun() {
  const now = new Date()
  const next = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 6, 0, 0))
  if (next <= now) next.setUTCDate(next.getUTCDate() + 1)
  return next
}

export default function Dashboard({ data, onOpenIncident, onGoToIncidents }) {
  const { incidents, scanRuns, takedowns, domainsCount, brands } = data
  const activeBrands = brands.filter((b) => b.is_active).length

  const stats = useMemo(() => {
    const open = incidents.filter((i) => OPEN_STATUSES.includes(i.status))
    const critical = open.filter((i) => i.severity === 'critical')
    const takedowns30 = takedowns.filter((t) => Date.now() - new Date(t.created_at).getTime() < 30 * DAY_MS)

    // Brand risk: average of the five highest open risk scores from live
    // detections (SAMPLE incidents are excluded so they never inflate it)
    const top = open.filter((i) => !isSample(i)).map((i) => i.risk_score).filter((s) => s != null).sort((a, b) => b - a).slice(0, 5)
    const brandRisk = top.length ? Math.round(top.reduce((a, b) => a + b, 0) / top.length) : null

    const channels = Object.keys(CHANNEL_LABEL).map((ch) => {
      const list = open.filter((i) => i.channel === ch)
      const scores = list.map((i) => i.risk_score).filter((s) => s != null)
      return { channel: ch, count: list.length, max: scores.length ? Math.max(...scores) : null, sampleOnly: list.length > 0 && list.every(isSample) }
    })
    return { open, critical, takedowns30, brandRisk, channels }
  }, [incidents, takedowns])

  // New incidents per hour over the last 24 hours, from the scan history
  const hourly = useMemo(() => {
    const now = Date.now()
    const buckets = Array.from({ length: 24 }, (_, i) => ({ hour: i, scans: 0, found: 0, failed: 0 }))
    for (const run of scanRuns) {
      const age = now - new Date(run.started_at).getTime()
      if (age < 0 || age >= DAY_MS) continue
      const b = buckets[23 - Math.floor(age / 3600000)]
      b.scans += 1
      b.found += run.new_incidents
      if (run.status === 'failed') b.failed += 1
    }
    return buckets
  }, [scanRuns])
  const maxFound = Math.max(1, ...hourly.map((b) => b.found))
  const lastScan = scanRuns[0]

  const activeTakedowns = takedowns.filter((t) => !['completed', 'rejected'].includes(t.status)).slice(0, 5)
  const byId = useMemo(() => Object.fromEntries(incidents.map((i) => [i.id, i])), [incidents])
  const blips = useMemo(
    () => stats.open.filter((i) => !isSample(i) && (i.risk_score ?? 0) >= 60).slice(0, 8)
      .map((i) => ({ ...blipPosition(i.id), color: scoreColor(i.risk_score) })),
    [stats.open],
  )
  const highRiskOpen = stats.open.filter((i) => !isSample(i) && (i.risk_score ?? 0) >= 60).length
  const lastBySource = (src) => scanRuns.find((r) => r.source === src)
  const monitors = [
    { name: 'Website monitor', detail: 'Lookalike domains, daily 06:00 UTC', run: lastBySource('dnstwist'), next: nextWebsiteRun(), live: true },
    { name: 'Certificate search', detail: 'New certificates (crt.sh), every 15 min', run: lastBySource('crt.sh'), live: true },
    { name: 'Email protection', detail: 'SPF, DKIM, DMARC checks', live: false, note: 'Next build' },
    { name: 'App stores', detail: 'Apple App Store, Google Play', live: false, note: 'Planned' },
    { name: 'Social media', detail: 'Lookalike accounts', live: false, note: 'Planned' },
  ]

  return (
    <div className="space-y-4">
      <Panel
        title="Live monitoring"
        info="What BrandGuard is watching right now. The radar sweeps while monitoring is on; each dot is an open high-risk finding (risk score 60 or more). Each row is one monitor: when it last ran and whether it worked."
      >
        <div className="flex flex-col items-center gap-5 sm:flex-row">
          <Radar size={140} blips={blips} active={activeBrands > 0} />
          <div className="w-full min-w-0 flex-1">
            <div className="mb-2 font-mono text-xs text-text-2">
              <span className="text-accent">{activeBrands}</span> brand(s) protected · <span className="text-accent">{highRiskOpen}</span> open high-risk finding(s)
            </div>
            <ul className="grid gap-1.5 sm:grid-cols-2">
              {monitors.map((m) => {
                const failed = m.run?.status === 'failed'
                const color = !m.live ? 'var(--color-muted)' : failed ? 'var(--color-critical)' : 'var(--color-success)'
                return (
                  <li key={m.name} className="flex items-center gap-2.5 rounded-lg border border-line bg-black/40 px-2.5 py-1.5">
                    {m.live ? <Ping color={color} size={7} /> : <span className="inline-block h-[7px] w-[7px] rounded-full" style={{ background: color }} />}
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center justify-between gap-2 text-xs">
                        <span className="font-semibold">{m.name}</span>
                        <span className="shrink-0 font-mono text-[10px]" style={{ color }}>
                          {!m.live ? m.note.toUpperCase() : failed ? 'LAST RUN FAILED' : m.run ? 'ONLINE' : 'WAITING'}
                        </span>
                      </div>
                      <div className="truncate text-[11px] text-text-2">
                        {m.detail}
                        {m.live && (m.run ? ' · last ' + timeAgo(m.run.started_at) : ' · no run yet')}
                        {m.next && ' · next ' + m.next.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                      </div>
                    </div>
                  </li>
                )
              })}
            </ul>
          </div>
        </div>
      </Panel>

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <MetricCard label="Critical incidents" value={stats.critical.length} hint="Open, critical severity" info="Open findings scored 80 to 100. These are the most likely to be live attacks, such as a fake login page. Review these first. Click the card to see them." color="var(--color-critical)" onClick={() => onGoToIncidents({ severity: 'critical' })} />
        <MetricCard label="Active incidents" value={stats.open.length} hint="New, investigating, takedown, monitoring" info="All findings that still need attention: New (not looked at yet), Investigating, Takedown (removal requested) and Monitoring (watched for changes). Resolved and false positive findings are not counted." color="var(--color-warning)" onClick={() => onGoToIncidents({})} />
        <MetricCard label="Takedowns (30 days)" value={stats.takedowns30.length} hint="Started in the last 30 days" info="Takedown requests started in the last 30 days. A takedown asks the registrar, hosting company, app store or social platform to remove the fake asset." color="var(--color-success)" />
        <MetricCard label="Lookalike domains tracked" value={domainsCount} hint="Found by the website monitor and certificate search" info="Every registered domain that looks like one of your official domains, including low-risk ones. The website monitor rechecks them daily, so a parked domain that turns into a phishing site is caught." />
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Panel title="Brand risk" info="One number for how exposed the brand is right now: the average of the five highest open risk scores (0 safe, 100 severe). SAMPLE items are excluded. The bars show the highest open score per channel.">
          <div className="flex flex-col items-center gap-4">
            <RiskRing score={stats.brandRisk} />
            <div className="w-full space-y-2.5">
              {stats.channels.map((c) => (
                <div key={c.channel}>
                  <div className="flex items-center justify-between gap-2 whitespace-nowrap text-xs">
                    <span className="flex items-center gap-1.5 text-text-2">{CHANNEL_LABEL[c.channel]} {c.sampleOnly && <SampleBadge />}</span>
                    <span className="font-mono text-text-2">{c.count} open</span>
                  </div>
                  <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-panel-4">
                    <div className="h-full rounded-full" style={{ width: `${c.max ?? 0}%`, background: scoreColor(c.max) }} />
                  </div>
                </div>
              ))}
            </div>
          </div>
          <p className="mt-3 text-xs text-muted">Ring: average of the five highest open risk scores from live detections. Bars: highest open score per channel.</p>
        </Panel>

        <Panel
          title="Live alert feed"
          info="The newest findings across all channels, newest first. Click any row to open the evidence and act on it."
          className="lg:col-span-2"
          action={<Button onClick={() => onGoToIncidents({})} className="!py-1 text-xs">View all</Button>}
        >
          <ul className="divide-y divide-line">
            {incidents.slice(0, 7).map((i) => (
              <li key={i.id} className="row-in">
                <button type="button" onClick={() => onOpenIncident(i)} className="flex w-full items-center gap-3 py-2 text-left hover:bg-panel-3/60">
                  <SeverityBadge severity={i.severity} />
                  <span className="min-w-0 flex-1 truncate text-sm">{i.title}</span>
                  {isSample(i) && <SampleBadge />}
                  <span className="hidden text-xs text-text-2 sm:inline">{CHANNEL_LABEL[i.channel]}</span>
                  <span className="w-16 text-right text-xs text-muted">{timeAgo(i.detected_at)}</span>
                </button>
              </li>
            ))}
            {incidents.length === 0 && <li className="py-6 text-center text-sm text-text-2">No incidents yet. The certificate search runs every 15 minutes and the website monitor daily.</li>}
          </ul>
        </Panel>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Panel title="Scans, last 24 hours" className="lg:col-span-2" info="One bar per hour. Bar height is the number of new findings in that hour. Red bars mean a scan failed in that hour (for example the source was down); the next scan retries automatically.">
          <div className="flex h-36 items-end gap-1" role="img" aria-label="New incidents found per hour over the last 24 hours">
            {hourly.map((b) => (
              <div key={b.hour} className="group relative flex h-full flex-1 flex-col justify-end">
                <div
                  className="w-full rounded-t"
                  style={{
                    height: b.scans ? `${Math.max(4, (b.found / maxFound) * 100)}%` : '2px',
                    background: b.failed ? 'var(--color-critical)' : b.scans ? 'var(--color-accent)' : 'var(--color-panel-4)',
                    opacity: b.found ? 1 : 0.45,
                  }}
                />
                <div className="pointer-events-none absolute bottom-full left-1/2 z-10 mb-1 hidden -translate-x-1/2 whitespace-nowrap rounded bg-panel-4 px-2 py-1 text-[11px] group-hover:block">
                  {23 - b.hour === 0 ? 'This hour' : `${23 - b.hour}h ago`}: {b.scans} scan(s), {b.found} new{b.failed ? `, ${b.failed} failed` : ''}
                </div>
              </div>
            ))}
          </div>
          <div className="mt-2 flex justify-between text-[11px] text-muted"><span>24h ago</span><span>Now</span></div>
          <p className="mt-2 text-xs text-text-2">
            Bar height: new incidents found. {lastScan ? `Last scan ${timeAgo(lastScan.started_at)} (${lastScan.status}).` : 'No scans recorded yet.'}
          </p>
        </Panel>

        <Panel title="Active takedowns" info="Takedown requests that are not finished yet. Click one to open its incident.">
          <ul className="space-y-2">
            {activeTakedowns.map((t) => (
              <li key={t.id}>
                <button
                  type="button"
                  onClick={() => byId[t.incident_id] && onOpenIncident(byId[t.incident_id])}
                  className="w-full rounded-lg border border-line p-2 text-left hover:border-accent/50"
                >
                  <div className="truncate font-mono text-xs">{t.target}</div>
                  <div className="mt-1 flex justify-between text-[11px] text-text-2">
                    <span className="capitalize">{t.status.replace('_', ' ')}</span>
                    <span>{timeAgo(t.created_at)}</span>
                  </div>
                </button>
              </li>
            ))}
            {activeTakedowns.length === 0 && (
              <li className="text-sm text-text-2">No active takedowns. Start one from an incident.</li>
            )}
          </ul>
        </Panel>
      </div>

      <Panel title="Detection log" info="A live log of every scan and the findings it produced, like a security operations console. Red lines are failed scans.">
        <div className="scanline h-48 overflow-y-auto rounded-lg border border-line bg-black p-3 font-mono text-xs leading-relaxed">
          {scanRuns.slice(0, 12).map((r) => (
            <div key={r.id} className={r.status === 'failed' ? 'text-critical' : 'text-text-2'}>
              <span className="text-muted">[{new Date(r.started_at).toLocaleTimeString()}]</span>{' '}
              {r.status === 'failed'
                ? `${r.source} scan FAILED: ${r.error}`
                : r.source === 'dnstwist'
                  ? `website monitor ${r.status}: ${r.certificates_checked} names generated, ${r.candidates_found} registered, `
                  : `${r.source} scan ${r.status}: ${r.certificates_checked} certificates, ${r.candidates_found} candidates, `}
              {r.status !== 'failed' && <span className={r.new_incidents ? 'text-accent' : ''}>{r.new_incidents} new</span>}
            </div>
          ))}
          {incidents.filter((i) => ['crt.sh', 'dnstwist'].includes(i.source)).slice(0, 8).map((i) => (
            <div key={i.id} style={{ color: scoreColor(i.risk_score) }}>
              <span className="text-muted">[{new Date(i.detected_at).toLocaleTimeString()}]</span> match {i.source_ref} score {i.risk_score} ({STATUS_LABEL[i.status]})
            </div>
          ))}
          {scanRuns.length === 0 && <div className="text-muted">Waiting for the first scan...</div>}
          <div className="caret text-muted">&gt; monitoring</div>
        </div>
      </Panel>
    </div>
  )
}
