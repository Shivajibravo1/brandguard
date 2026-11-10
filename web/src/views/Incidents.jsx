import { useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { Button, Chip, Icon, InfoButton, Modal, RiskBar, SampleBadge, SeverityBadge, useToast } from '../components/ui'
import {
  CHANNEL_LABEL, OPEN_STATUSES, SEVERITIES, SEVERITY_COLOR, STATUS_LABEL, formatDateTime, isSample, timeAgo,
} from '../lib/format'

const STATUS_FILTERS = { open: 'Open', closed: 'Closed', all: 'All' }

export default function Incidents({ data, filters, setFilters, selected, setSelected, userId }) {
  const { incidents, brands, takedowns, tenant, membership, reload } = data
  const toast = useToast()
  const [reporting, setReporting] = useState(false)
  const [busy, setBusy] = useState(false)
  const canEdit = ['owner', 'admin', 'analyst'].includes(membership?.role)

  const severity = filters.severity || 'all'
  const statusFilter = filters.status || 'open'
  const query = (filters.query || '').trim().toLowerCase()

  const rows = useMemo(() => incidents.filter((i) => {
    if (severity !== 'all' && i.severity !== severity) return false
    if (statusFilter === 'open' && !OPEN_STATUSES.includes(i.status)) return false
    if (statusFilter === 'closed' && OPEN_STATUSES.includes(i.status)) return false
    if (query && !`${i.title} ${i.source_ref} ${i.channel} ${i.score_explanation || ''}`.toLowerCase().includes(query)) return false
    return true
  }), [incidents, severity, statusFilter, query])

  const counts = useMemo(() => {
    const c = { all: 0 }
    for (const i of incidents) {
      if (!OPEN_STATUSES.includes(i.status) && statusFilter === 'open') continue
      c.all += 1
      c[i.severity] = (c[i.severity] || 0) + 1
    }
    return c
  }, [incidents, statusFilter])

  async function setStatus(incident, status) {
    setBusy(true)
    const { error } = await supabase.from('incidents').update({ status }).eq('id', incident.id)
    setBusy(false)
    if (error) return toast(`Could not update: ${error.message}`, 'error')
    toast(`Incident marked ${STATUS_LABEL[status].toLowerCase()}`)
    setSelected((s) => (s && s.id === incident.id ? { ...s, status } : s))
    reload()
  }

  async function startTakedown(incident) {
    setBusy(true)
    const target = incident.details?.host || incident.source_ref
    const { error } = await supabase.from('takedowns').insert({
      tenant_id: incident.tenant_id,
      incident_id: incident.id,
      target: incident.channel === 'domain' ? incident.source_ref : target,
      provider: incident.channel === 'domain' ? 'Registrar or hosting provider (to identify)' : null,
      status: 'draft',
      created_by: userId,
      notes: 'Takedown record created from the Incidents view. Prepare the evidence bundle and abuse report.',
    })
    if (!error) await supabase.from('incidents').update({ status: 'takedown' }).eq('id', incident.id)
    setBusy(false)
    if (error) return toast(`Could not start takedown: ${error.message}`, 'error')
    toast('Takedown record created (draft)')
    setSelected((s) => (s && s.id === incident.id ? { ...s, status: 'takedown' } : s))
    reload()
  }

  return (
    <div className="space-y-4">
      <div className="panel space-y-3 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <InfoButton title="Filters">
            Severity chips show findings by how dangerous they are: Critical (80 to 100), High (60 to 79), Medium (40 to 59),
            Low (20 to 39) and Info (below 20). Use the search box for a domain or a word in the reason, and Open, Closed or All
            to choose which statuses to show. Report incident adds something a customer or colleague told you about.
          </InfoButton>
          <Chip active={severity === 'all'} onClick={() => setFilters({ ...filters, severity: 'all' })}>All ({counts.all})</Chip>
          {SEVERITIES.map((s) => (
            <Chip key={s} active={severity === s} color={SEVERITY_COLOR[s]} onClick={() => setFilters({ ...filters, severity: s })}>
              {s} ({counts[s] || 0})
            </Chip>
          ))}
        </div>
        <div className="flex flex-wrap items-center gap-3">
          <label className="relative min-w-56 flex-1">
            <span className="sr-only">Search incidents</span>
            <Icon name="search" size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted" />
            <input
              value={filters.query || ''}
              onChange={(e) => setFilters({ ...filters, query: e.target.value })}
              placeholder="Search, e.g. login, kyc, homoglyph or a domain name"
              className="w-full rounded-lg border border-line bg-black py-2 pl-9 pr-3 text-sm outline-none focus:border-accent"
            />
          </label>
          <div className="flex gap-1 rounded-lg border border-line p-1">
            {Object.entries(STATUS_FILTERS).map(([key, label]) => (
              <button
                key={key}
                type="button"
                onClick={() => setFilters({ ...filters, status: key })}
                className={`rounded-md px-3 py-1 text-xs ${statusFilter === key ? 'bg-accent/15 text-accent' : 'text-text-2 hover:text-text'}`}
              >
                {label}
              </button>
            ))}
          </div>
          <Button variant="primary" onClick={() => setReporting(true)} disabled={!canEdit} title={canEdit ? '' : 'Viewers cannot report incidents'}>
            <Icon name="plus" size={16} /> Report incident
          </Button>
        </div>
      </div>

      <div className="panel scanline overflow-x-auto">
        <table className="w-full min-w-[760px] text-sm">
          <thead>
            <tr className="border-b border-line text-left text-xs uppercase tracking-wider text-text-2">
              <th className="px-4 py-3 font-medium">
                <span className="inline-flex items-center gap-2">Severity
                  <InfoButton title="Incident list">
                    One row per finding. Risk is the 0 to 100 score with a plain-English reason inside each incident. Status shows
                    where it is in the workflow: New, Investigating, Takedown, Monitoring, Resolved or False positive. Click a row
                    to open the evidence and the action buttons.
                  </InfoButton>
                </span>
              </th>
              <th className="px-4 py-3 font-medium">Incident</th>
              <th className="px-4 py-3 font-medium">Channel</th>
              <th className="px-4 py-3 font-medium">Risk</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 font-medium">Detected</th>
              <th className="px-4 py-3 font-medium"><span className="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody>
            {rows.map((i) => (
              <tr key={i.id} className="cursor-pointer border-b border-line/60 hover:bg-panel-3/60" onClick={() => setSelected(i)}>
                <td className="px-4 py-2.5"><SeverityBadge severity={i.severity} /></td>
                <td className="max-w-[340px] px-4 py-2.5">
                  <div className="flex items-center gap-2">
                    <span className="truncate font-mono text-[13px]">{i.channel === 'domain' ? i.source_ref : i.title}</span>
                    {isSample(i) && <SampleBadge />}
                  </div>
                  {i.channel === 'domain' && <div className="truncate text-xs text-muted">{i.score_category?.replaceAll('_', ' ')}</div>}
                </td>
                <td className="px-4 py-2.5 text-text-2">{CHANNEL_LABEL[i.channel]}</td>
                <td className="px-4 py-2.5"><RiskBar score={i.risk_score} /></td>
                <td className="px-4 py-2.5 text-text-2">{STATUS_LABEL[i.status]}</td>
                <td className="px-4 py-2.5 text-xs text-text-2" title={formatDateTime(i.detected_at)}>{timeAgo(i.detected_at)}</td>
                <td className="px-4 py-2.5 text-right" onClick={(e) => e.stopPropagation()}>
                  {OPEN_STATUSES.includes(i.status) && i.status !== 'takedown' && (
                    <Button className="!py-1 text-xs" disabled={!canEdit || busy} onClick={() => startTakedown(i)}>Takedown</Button>
                  )}
                </td>
              </tr>
            ))}
            {rows.length === 0 && (
              <tr><td colSpan={7} className="px-4 py-10 text-center text-text-2">No incidents match these filters.</td></tr>
            )}
          </tbody>
        </table>
      </div>

      {selected && (
        <IncidentDetail
          incident={selected}
          brand={brands.find((b) => b.id === selected.brand_id)}
          takedown={takedowns.find((t) => t.incident_id === selected.id)}
          canEdit={canEdit}
          busy={busy}
          onClose={() => setSelected(null)}
          onStatus={setStatus}
          onTakedown={startTakedown}
        />
      )}

      {reporting && (
        <ReportIncident
          tenantId={tenant?.id}
          brands={brands}
          userId={userId}
          onClose={() => setReporting(false)}
          onCreated={() => { setReporting(false); toast('Incident reported'); reload() }}
        />
      )}
    </div>
  )
}

function Field({ label, children }) {
  return (
    <div>
      <dt className="text-xs uppercase tracking-wider text-muted">{label}</dt>
      <dd className="mt-0.5 break-words text-sm">{children}</dd>
    </div>
  )
}

const SOURCE_LABEL = {
  dnstwist: 'Website monitor (lookalike domains)',
  'crt.sh': 'Certificate Transparency (crt.sh)',
  manual: 'Reported manually',
  sample: 'SAMPLE data',
}

const FUZZER_LABEL = {
  homoglyph: 'Look-alike characters', cyrillic: 'Look-alike characters', dictionary: 'Brand plus a word',
  'tld-swap': 'Other domain ending', addition: 'Extra character', omission: 'Missing character',
  replacement: 'Swapped character', transposition: 'Swapped order', insertion: 'Inserted character',
  repetition: 'Repeated character', 'vowel-swap': 'Changed vowel', hyphenation: 'Added hyphen',
  bitsquatting: 'One-bit error', plural: 'Plural', subdomain: 'Split into subdomain', various: 'Other variation',
  '*original': 'Exact search term',
}

function websiteSummary(d) {
  if (!d.web_live) return 'No website reachable'
  const parts = []
  if (d.web_final_host && d.web_final_host !== d.domain) parts.push(`redirects to ${d.web_final_host}`)
  else parts.push(`live${d.web_status ? ` (HTTP ${d.web_status})` : ''}`)
  if (d.web_parked) parts.push('parked or for sale')
  if (d.web_password_field) parts.push('shows a password field')
  if (d.web_mentions_brand) parts.push('mentions the brand')
  return parts.join(', ')
}

function LookalikeEvidence({ d, domain }) {
  const list = (v) => (Array.isArray(v) && v.length ? v.join(', ') : 'None')
  return (
    <>
      <Field label="Lookalike of"><span className="font-mono">{d.lookalike_of || 'Unknown'}</span></Field>
      <Field label="How the name was made">{FUZZER_LABEL[d.fuzzer] || d.fuzzer || 'Unknown'}</Field>
      <Field label="Registered">{d.whois_created || 'Date not published'}{d.whois_registrar ? ` · ${d.whois_registrar}` : ''}</Field>
      <Field label="Website">{websiteSummary(d)}</Field>
      {d.web_title && <Field label="Page title">{d.web_title}</Field>}
      <Field label="Web addresses (A records)"><span className="font-mono text-xs">{list(d.dns_a)}</span></Field>
      <Field label="Mail servers (MX records)"><span className="font-mono text-xs">{list(d.dns_mx)}</span></Field>
      {d.checked_at && <Field label="Last checked">{formatDateTime(d.checked_at)}</Field>}
      <Field label="Evidence">
        <a href={`https://lookup.icann.org/en/lookup?name=${encodeURIComponent(domain)}`} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 text-accent hover:underline">
          Registration record (ICANN lookup) <Icon name="external" size={14} />
        </a>
        <span className="mt-1 block text-[11px] text-muted">The suspect site is not linked on purpose. Open it only in an isolated browser.</span>
      </Field>
    </>
  )
}

function IncidentDetail({ incident: i, brand, takedown, canEdit, busy, onClose, onStatus, onTakedown }) {
  const open = OPEN_STATUSES.includes(i.status)
  return (
    <Modal title={i.title} onClose={onClose} wide>
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <SeverityBadge severity={i.severity} />
        {isSample(i) && <SampleBadge />}
        <span className="text-xs text-text-2">{CHANNEL_LABEL[i.channel]} · {STATUS_LABEL[i.status]}</span>
      </div>

      <div className="mb-4 rounded-lg border border-line bg-black/60 p-3">
        <div className="mb-1 flex items-center justify-between">
          <span className="flex items-center gap-2 text-xs uppercase tracking-wider text-muted">Risk assessment
            <InfoButton title="Risk assessment">
              The score adds up simple, explainable rules: how the name was made (for example look-alike characters), whether
              there is a live website, a password field, mail servers, and how recently it was registered. Each rule that applied
              is listed in the text. A score is a guide for priority, not proof: always check the evidence.
            </InfoButton>
          </span>
          <RiskBar score={i.risk_score} />
        </div>
        <p className="text-sm leading-relaxed text-text">{i.score_explanation || 'Not scored yet.'}</p>
        {i.details?.scoring && <p className="mt-1 text-xs text-muted">Scoring: {i.details.scoring}</p>}
      </div>

      <dl className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <Field label="Asset"><span className="font-mono">{i.source_ref}</span></Field>
        <Field label="Brand">{brand?.name || 'Not linked'}</Field>
        <Field label="Source">{SOURCE_LABEL[i.source] || i.source}</Field>
        <Field label="Detected">{formatDateTime(i.detected_at)}</Field>
        {i.details?.host && i.details.host !== i.source_ref && <Field label="Host seen in certificate"><span className="font-mono">{i.details.host}</span></Field>}
        {i.details?.issuer && <Field label="Certificate issuer">{i.details.issuer}</Field>}
        {i.details?.not_before && <Field label="Certificate valid from">{formatDateTime(i.details.not_before)}</Field>}
        {i.details?.crtsh_url && (
          <Field label="Evidence">
            <a href={i.details.crtsh_url} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 text-accent hover:underline">
              View certificate on crt.sh <Icon name="external" size={14} />
            </a>
          </Field>
        )}
        {i.source === 'dnstwist' && <LookalikeEvidence d={i.details || {}} domain={i.source_ref} />}
        {takedown && <Field label="Takedown">{takedown.status} · started {timeAgo(takedown.created_at)}</Field>}
        {i.details?.notes && <Field label="Notes">{i.details.notes}</Field>}
      </dl>

      <div className="mt-5 flex flex-wrap items-center gap-2 border-t border-line pt-4">
        <InfoButton title="Actions">
          Start takedown: create a removal request record. Investigate: you are checking it. Monitor: keep watching, no action now.
          Resolve: the threat is gone. False positive: it is not a threat (for example a domain your company owns). Reopen: bring a
          closed finding back. Every action is recorded in the audit log with your name.
        </InfoButton>
        {!canEdit && <p className="text-sm text-text-2">Your role is read-only.</p>}
        {canEdit && open && i.status !== 'takedown' && (
          <Button variant="primary" disabled={busy} onClick={() => onTakedown(i)}>Start takedown</Button>
        )}
        {canEdit && i.status === 'new' && <Button disabled={busy} onClick={() => onStatus(i, 'investigating')}>Investigate</Button>}
        {canEdit && open && i.status !== 'monitoring' && <Button disabled={busy} onClick={() => onStatus(i, 'monitoring')}>Monitor</Button>}
        {canEdit && open && <Button disabled={busy} onClick={() => onStatus(i, 'resolved')}>Resolve</Button>}
        {canEdit && open && <Button variant="danger" disabled={busy} onClick={() => onStatus(i, 'false_positive')}>False positive</Button>}
        {canEdit && !open && <Button disabled={busy} onClick={() => onStatus(i, 'investigating')}>Reopen</Button>}
      </div>
    </Modal>
  )
}

function ReportIncident({ tenantId, brands, userId, onClose, onCreated }) {
  const [form, setForm] = useState({ title: '', channel: 'domain', severity: 'medium', asset: '', brand_id: brands[0]?.id || '', notes: '' })
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value })

  async function submit(e) {
    e.preventDefault()
    if (!form.title.trim() || !form.asset.trim()) return setError('Title and asset are required.')
    setSaving(true)
    const { error: err } = await supabase.from('incidents').insert({
      tenant_id: tenantId,
      brand_id: form.brand_id || null,
      channel: form.channel,
      title: form.title.trim(),
      source: 'manual',
      source_ref: form.asset.trim().toLowerCase(),
      severity: form.severity,
      details: { reported_by: userId, notes: form.notes.trim() || undefined },
    })
    setSaving(false)
    if (err) return setError(err.code === '23505' ? 'An incident for this asset already exists.' : err.message)
    onCreated()
  }

  const input = 'w-full rounded-lg border border-line bg-black px-3 py-2 text-sm outline-none focus:border-accent'
  return (
    <Modal title="Report incident" onClose={onClose}>
      <form onSubmit={submit} className="space-y-3">
        <label className="block text-sm">Title<input className={`${input} mt-1`} value={form.title} onChange={set('title')} placeholder="e.g. Fake KYC update page reported by a customer" /></label>
        <label className="block text-sm">Asset (domain, profile URL or app id)<input className={`${input} mt-1 font-mono`} value={form.asset} onChange={set('asset')} placeholder="e.g. examplebank-kyc.in  or  https://x.com/Fake_ExampleBank" /></label>
        <div className="grid grid-cols-2 gap-3">
          <label className="block text-sm">Channel
            <select className={`${input} mt-1`} value={form.channel} onChange={set('channel')}>
              {Object.entries(CHANNEL_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </label>
          <label className="block text-sm">Severity
            <select className={`${input} mt-1 capitalize`} value={form.severity} onChange={set('severity')}>
              {SEVERITIES.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </label>
        </div>
        <label className="block text-sm">Brand
          <select className={`${input} mt-1`} value={form.brand_id} onChange={set('brand_id')}>
            {brands.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
        </label>
        <label className="block text-sm">Notes<textarea className={`${input} mt-1`} rows={3} value={form.notes} onChange={set('notes')} placeholder="e.g. Customer received this link by SMS on 10 Nov. Screenshot saved in ticket INC-1042." /></label>
        {error && <p className="text-sm text-critical">{error}</p>}
        <div className="flex justify-end gap-2 pt-2">
          <Button onClick={onClose}>Cancel</Button>
          <Button variant="primary" type="submit" disabled={saving}>{saving ? 'Saving...' : 'Report incident'}</Button>
        </div>
      </form>
    </Modal>
  )
}
