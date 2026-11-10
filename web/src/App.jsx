import { useEffect, useState } from 'react'
import { supabase } from './lib/supabase'
import { useTenantData } from './lib/useTenantData'
import { Icon, Ping, ToastProvider } from './components/ui'
import { timeAgo } from './lib/format'
import Login from './views/Login'
import Dashboard from './views/Dashboard'
import Incidents from './views/Incidents'
import Brands from './views/Brands'

const NAV = [
  { key: 'dashboard', label: 'Dashboard', icon: 'dashboard' },
  { key: 'incidents', label: 'Incidents', icon: 'incidents' },
  { key: 'brands', label: 'Brand setup', icon: 'brand' },
]

export default function App() {
  const [session, setSession] = useState(undefined)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session))
    const { data: sub } = supabase.auth.onAuthStateChange((_event, s) => setSession(s))
    return () => sub.subscription.unsubscribe()
  }, [])

  if (session === undefined) return <div className="hex-bg h-full" />
  return <ToastProvider>{session ? <Shell session={session} /> : <Login />}</ToastProvider>
}

function Shell({ session }) {
  const data = useTenantData()
  const [view, setView] = useState('dashboard')
  const [filters, setFilters] = useState({ severity: 'all', status: 'open', query: '' })
  const [selected, setSelected] = useState(null)
  const [, forceTick] = useState(0)

  // Re-render every 10 s so "updated Xs ago" stays accurate
  useEffect(() => {
    const t = setInterval(() => forceTick((n) => n + 1), 10000)
    return () => clearInterval(t)
  }, [])

  const openIncident = (incident) => { setSelected(incident); setView('incidents') }
  const goToIncidents = (f) => { setFilters({ severity: 'all', status: 'open', query: '', ...f }); setView('incidents') }
  const critical = data.incidents.filter((i) => i.severity === 'critical' && ['new', 'investigating', 'takedown', 'monitoring'].includes(i.status))

  return (
    <div className="hex-bg flex min-h-full">
      <aside className="hidden w-56 shrink-0 flex-col border-r border-line bg-panel-1/80 p-4 md:flex">
        <div className="mb-8 flex items-center gap-2.5">
          <span className="text-accent"><Icon name="shield" size={26} /></span>
          <div>
            <div className="font-semibold leading-tight">BrandGuard</div>
            <div className="text-[11px] text-text-2">by Shivaji, PM</div>
          </div>
        </div>
        <nav className="space-y-1">
          {NAV.map((n) => (
            <button
              key={n.key}
              type="button"
              onClick={() => setView(n.key)}
              className={`flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm transition-colors ${
                view === n.key ? 'bg-accent/10 text-accent' : 'text-text-2 hover:bg-panel-3 hover:text-text'
              }`}
            >
              <Icon name={n.icon} /> {n.label}
            </button>
          ))}
        </nav>
        <div className="mt-auto rounded-lg border border-line p-3 text-[11px] leading-relaxed text-muted">
          Local demo build. Website monitor and certificate search are live. Items marked SAMPLE are invented examples.
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-30 border-b border-line bg-black/85 backdrop-blur">
          <div className="flex items-center gap-4 px-4 py-3 md:px-6">
            <div className="min-w-0 flex-1">
              <h1 className="truncate text-base font-semibold">{NAV.find((n) => n.key === view)?.label}</h1>
              <p className="truncate text-xs text-text-2">{data.tenant?.name || 'Loading tenant...'}{data.membership ? ` · ${data.membership.role}` : ''}</p>
            </div>
            <div className="flex items-center gap-2 text-xs" title="Data refreshes automatically every 20 seconds">
              <Ping color={data.error ? 'var(--color-critical)' : 'var(--color-success)'} size={8} />
              <span className={`font-mono font-semibold tracking-[0.2em] ${data.error ? 'text-critical' : 'text-success'}`}>{data.error ? 'OFFLINE' : 'LIVE'}</span>
              {data.lastUpdated && <span className="hidden text-text-2 sm:inline">updated {timeAgo(data.lastUpdated)}</span>}
            </div>
            <div className="hidden text-right text-xs text-text-2 lg:block">{session.user.email}</div>
            <button type="button" onClick={() => supabase.auth.signOut()} className="text-text-2 hover:text-text" aria-label="Sign out" title="Sign out">
              <Icon name="logout" />
            </button>
          </div>
          <div className="flex gap-1 border-t border-line px-2 md:hidden">
            {NAV.map((n) => (
              <button key={n.key} type="button" onClick={() => setView(n.key)} className={`flex-1 py-2 text-sm ${view === n.key ? 'text-accent' : 'text-text-2'}`}>{n.label}</button>
            ))}
          </div>
          {!data.error && <div className="scan-bar" aria-hidden="true" />}
          {critical.length > 0 && (
            <button
              type="button"
              onClick={() => goToIncidents({ severity: 'critical' })}
              className="alert-flash flex w-full items-center gap-3 overflow-hidden border-t border-critical/30 bg-critical/10 px-4 py-1.5 text-left text-xs text-critical md:px-6"
              title="Open critical incidents"
            >
              <span className="pulse-dot shrink-0" />
              <span className="glitch shrink-0 font-mono font-semibold tracking-wider">ALERT // {critical.length} CRITICAL OPEN</span>
              <span className="min-w-0 flex-1 overflow-hidden">
                <span className="ticker-track font-mono text-critical/85">
                  {[0, 1].map((copy) => (
                    <span key={copy} aria-hidden={copy === 1} className="pr-10">
                      {critical.map((i) => `>> ${i.source_ref} [${i.risk_score ?? '--'}]`).join('      ')}
                    </span>
                  ))}
                </span>
              </span>
            </button>
          )}
        </header>

        <main className="flex-1 p-4 md:p-6">
          {data.error && (
            <div className="panel mb-4 border-critical/50 p-3 text-sm text-critical">Could not load data: {data.error}</div>
          )}
          {data.loading ? (
            <div className="py-20 text-center text-text-2">Loading...</div>
          ) : view === 'dashboard' ? (
            <Dashboard data={data} onOpenIncident={openIncident} onGoToIncidents={goToIncidents} />
          ) : view === 'brands' ? (
            <Brands data={data} />
          ) : (
            <Incidents
              data={data}
              filters={filters}
              setFilters={setFilters}
              selected={selected}
              setSelected={setSelected}
              userId={session.user.id}
            />
          )}
        </main>
      </div>
    </div>
  )
}
