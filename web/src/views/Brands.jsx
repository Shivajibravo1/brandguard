import { useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { Button, Icon, InfoButton, Modal, Panel, useToast } from '../components/ui'

/* ------------------------------------------------------------------ config */

const APP_STORES = { apple: 'Apple App Store', google: 'Google Play' }

const SOCIAL = {
  x: { label: 'X (Twitter)', url: (h) => `https://x.com/${h}` },
  instagram: { label: 'Instagram', url: (h) => `https://www.instagram.com/${h}` },
  facebook: { label: 'Facebook', url: (h) => `https://www.facebook.com/${h}` },
  linkedin: { label: 'LinkedIn', url: (h) => `https://www.linkedin.com/company/${h}` },
  tiktok: { label: 'TikTok', url: (h) => `https://www.tiktok.com/@${h}` },
  youtube: { label: 'YouTube', url: (h) => `https://www.youtube.com/@${h}` },
  telegram: { label: 'Telegram', url: (h) => `https://t.me/${h}` },
  snapchat: { label: 'Snapchat', url: (h) => `https://www.snapchat.com/add/${h}` },
}

// What BrandGuard does today for each asset type. Kept honest on purpose.
const SECTIONS = [
  {
    type: 'website', title: 'Websites', icon: 'globe',
    help: 'Domains of your official websites. Every day BrandGuard generates thousands of lookalike names, checks which are registered, and inspects their websites and mail servers. These official domains are never alerted on.',
    monitoring: { state: 'live', text: 'Live: daily lookalike scan + certificates' },
  },
  {
    type: 'email_domain', title: 'Email domains', icon: 'mail',
    help: 'Domains you send email from. Used to check your email protection (SPF, DKIM, DMARC) and find lookalikes that can send email.',
    monitoring: { state: 'next', text: 'Next build: email protection check' },
  },
  {
    type: 'mobile_app', title: 'Mobile apps', icon: 'phone',
    help: 'Your official apps. BrandGuard will flag store apps that use your brand but come from another developer.',
    monitoring: { state: 'planned', text: 'Planned: app store search' },
  },
  {
    type: 'social', title: 'Social media', icon: 'people',
    help: 'Your official accounts. BrandGuard will look for lookalike usernames on each platform.',
    monitoring: { state: 'planned', text: 'Planned: limited with free tools' },
  },
]

const STATE_COLOR = { live: 'var(--color-success)', next: 'var(--color-warning)', planned: 'var(--color-text-2)' }

/* ----------------------------------------------------------------- helpers */

// Accept what people paste (links, @handles, www.) and reduce it to the value
function cleanDomain(input) {
  return input.trim().toLowerCase().replace(/^[a-z]+:\/\//, '').replace(/[/?#:].*$/, '').replace(/^www\./, '').replace(/\.$/, '')
}

function cleanAppId(store, input) {
  const v = input.trim()
  if (store === 'apple') {
    const m = v.match(/id(\d{5,12})/) || v.match(/^(\d{5,12})$/)
    return m ? m[1] : v
  }
  const m = v.match(/[?&]id=([A-Za-z0-9._]+)/)
  return m ? m[1] : v
}

function cleanHandle(input) {
  let v = input.trim()
  if (/^https?:\/\//i.test(v) || /\.(com|me)\//i.test(v)) {
    const path = v.replace(/^https?:\/\//i, '').split(/[?#]/)[0].split('/').filter(Boolean)
    const parts = path.slice(1).filter((p) => !['company', 'add', 'channel', 'c', 'user'].includes(p.toLowerCase()))
    v = parts[0] || ''
  }
  return v.replace(/^@/, '')
}

function assetLink(a) {
  if (a.asset_type === 'website') return `https://${a.value}`
  if (a.asset_type === 'mobile_app') {
    return a.platform === 'apple' ? `https://apps.apple.com/app/id${a.value}` : `https://play.google.com/store/apps/details?id=${a.value}`
  }
  if (a.asset_type === 'social') return SOCIAL[a.platform]?.url(a.value)
  return null
}

function friendlyError(error, type) {
  if (error.code === '23505') return 'This asset is already on the list.'
  if (error.code === '23514') {
    if (type === 'website' || type === 'email_domain') return 'That does not look like a domain. Example: example.com'
    if (type === 'mobile_app') return 'App id not recognised. Apple: the number after "id" in the App Store link. Google: the text after "id=" in the Play link.'
    if (type === 'social') return 'Handle not recognised. Use letters, numbers, dots, dashes or underscores.'
  }
  if (error.code === '42501') return 'Only admins can change the brand setup.'
  return error.message
}

/* -------------------------------------------------------------------- view */

export default function Brands({ data }) {
  const { brands, assets, tenant, membership, reload } = data
  const canEdit = ['owner', 'admin'].includes(membership?.role)
  const [brandId, setBrandId] = useState(brands[0]?.id ?? null)
  const [creating, setCreating] = useState(false)
  const [editing, setEditing] = useState(false)

  // Fall back to the first brand when the selected one no longer exists
  const brand = brands.find((b) => b.id === brandId) || brands[0]
  const selectedId = brand?.id ?? null
  const brandAssets = useMemo(() => assets.filter((a) => a.brand_id === selectedId), [assets, selectedId])

  return (
    <div className="space-y-4">
      <div className="panel flex flex-wrap items-center gap-2 p-3">
        <span className="mr-1 flex items-center gap-2 text-xs uppercase tracking-wider text-text-2">Brands
          <InfoButton title="Brands">
            Each brand is one company or product name you want to protect. Pick a brand to see and edit its official assets.
            The green dot means monitoring is on; grey means paused.
          </InfoButton>
        </span>
        {brands.map((b) => (
          <button
            key={b.id}
            type="button"
            onClick={() => setBrandId(b.id)}
            aria-pressed={b.id === selectedId}
            className={`flex items-center gap-2 rounded-lg border px-3 py-1.5 text-sm transition-colors ${
              b.id === selectedId ? 'border-accent bg-accent/10 text-accent' : 'border-line text-text-2 hover:text-text'
            }`}
          >
            <span className="inline-block h-1.5 w-1.5 rounded-full" style={{ background: b.is_active ? 'var(--color-success)' : 'var(--color-muted)' }} />
            {b.name}
          </button>
        ))}
        {canEdit && (
          <Button onClick={() => setCreating(true)} className="ml-auto !py-1.5">
            <Icon name="plus" size={16} /> Add brand
          </Button>
        )}
      </div>

      {!canEdit && (
        <div className="panel border-warning/40 p-3 text-sm text-warning">
          You can view the brand setup. Only a tenant admin can add or change brands and assets.
        </div>
      )}

      {!brand ? (
        <Panel>
          <p className="py-8 text-center text-sm text-text-2">No brands yet. {canEdit ? 'Click Add brand to start.' : ''}</p>
        </Panel>
      ) : (
        <>
          <BrandHeader brand={brand} assets={brandAssets} canEdit={canEdit} onEdit={() => setEditing(true)} reload={reload} />
          <div className="grid gap-4 xl:grid-cols-2">
            {SECTIONS.map((s) => (
              <AssetSection
                key={s.type}
                section={s}
                brand={brand}
                assets={brandAssets.filter((a) => a.asset_type === s.type)}
                canEdit={canEdit}
                reload={reload}
              />
            ))}
          </div>
        </>
      )}

      {creating && (
        <BrandForm
          tenantId={tenant?.id}
          onClose={() => setCreating(false)}
          onSaved={async (id) => { setCreating(false); await reload(); setBrandId(id) }}
        />
      )}
      {editing && brand && (
        <BrandForm
          tenantId={tenant?.id}
          brand={brand}
          onClose={() => setEditing(false)}
          onSaved={() => { setEditing(false); reload() }}
        />
      )}
    </div>
  )
}

function BrandHeader({ brand, assets, canEdit, onEdit, reload }) {
  const toast = useToast()
  const [busy, setBusy] = useState(false)
  const count = (t) => assets.filter((a) => a.asset_type === t).length

  async function toggleActive() {
    setBusy(true)
    const { error } = await supabase.from('brands').update({ is_active: !brand.is_active }).eq('id', brand.id)
    setBusy(false)
    if (error) return toast(friendlyError(error), 'error')
    toast(brand.is_active ? 'Monitoring paused for this brand' : 'Monitoring resumed for this brand')
    reload()
  }

  return (
    <section className="panel p-4">
      <div className="flex flex-wrap items-start gap-4">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-3">
            <h2 className="truncate text-lg font-semibold">{brand.name}</h2>
            <span
              className="rounded-md px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide"
              style={{
                color: brand.is_active ? 'var(--color-success)' : 'var(--color-text-2)',
                background: brand.is_active ? 'color-mix(in srgb, var(--color-success) 12%, transparent)' : 'var(--color-panel-4)',
              }}
            >
              {brand.is_active ? 'Monitoring on' : 'Paused'}
            </span>
          </div>
          <div className="mt-2 flex flex-wrap items-center gap-1.5 text-xs text-text-2">
            <InfoButton title="Search terms">
              Words BrandGuard looks for inside new domain names and certificates, usually the brand name without spaces
              (for example examplebank). Use at least 4 letters; short words create a lot of noise.
            </InfoButton>
            Search terms:
            {brand.keywords.map((k) => (
              <span key={k} className="rounded border border-line bg-panel-3 px-1.5 py-0.5 font-mono text-text">{k}</span>
            ))}
            {brand.keywords.length === 0 && <span className="text-warning">none (add one so detection can run)</span>}
          </div>
        </div>
        {canEdit && (
          <div className="flex gap-2">
            <Button onClick={onEdit}><Icon name="edit" size={16} /> Edit</Button>
            <Button onClick={toggleActive} disabled={busy}>{brand.is_active ? 'Pause monitoring' : 'Resume monitoring'}</Button>
          </div>
        )}
      </div>
      <div className="mt-4 grid grid-cols-2 gap-2 md:grid-cols-4">
        {SECTIONS.map((s) => (
          <div key={s.type} className="rounded-lg border border-line bg-panel-1 p-3">
            <div className="flex items-center gap-2 text-xs text-text-2"><Icon name={s.icon} size={15} /> {s.title}</div>
            <div className="mt-1 font-mono text-2xl font-semibold">{count(s.type)}</div>
            <div className="mt-1 flex items-center gap-1.5 text-[11px]" style={{ color: STATE_COLOR[s.monitoring.state] }}>
              <span className="inline-block h-1.5 w-1.5 shrink-0 rounded-full" style={{ background: STATE_COLOR[s.monitoring.state] }} />
              {s.monitoring.text}
            </div>
          </div>
        ))}
      </div>
    </section>
  )
}

function AssetSection({ section, brand, assets, canEdit, reload }) {
  const toast = useToast()
  const [busyId, setBusyId] = useState(null)

  async function remove(asset) {
    setBusyId(asset.id)
    const { error } = await supabase.from('brand_assets').delete().eq('id', asset.id)
    setBusyId(null)
    if (error) return toast(friendlyError(error, asset.asset_type), 'error')
    toast(`Removed ${asset.value}`)
    reload()
  }

  return (
    <Panel
      title={<span className="flex items-center gap-2"><span className="text-accent"><Icon name={section.icon} /></span>{section.title} <span className="font-mono text-xs text-text-2">({assets.length})</span></span>}
      info={<>{section.help} <span className="mt-1 block text-text-2">Status: {section.monitoring.text}.</span></>}
    >
      <p className="-mt-1 mb-3 text-xs text-text-2">{section.help}</p>
      <ul className="divide-y divide-line rounded-lg border border-line">
        {assets.map((a) => {
          const link = assetLink(a)
          return (
            <li key={a.id} className="flex items-center gap-3 px-3 py-2">
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  {a.platform && (
                    <span className="shrink-0 rounded bg-panel-4 px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-text-2">
                      {section.type === 'mobile_app' ? (a.platform === 'apple' ? 'Apple' : 'Google Play') : SOCIAL[a.platform]?.label}
                    </span>
                  )}
                  <span className="truncate font-mono text-sm">{section.type === 'social' ? `@${a.value}` : a.value}</span>
                </div>
                {(a.label || a.publisher) && (
                  <div className="mt-0.5 truncate text-xs text-text-2">
                    {a.label}{a.label && a.publisher ? ' · ' : ''}{a.publisher ? `by ${a.publisher}` : ''}
                  </div>
                )}
              </div>
              {link && (
                <a href={link} target="_blank" rel="noreferrer" className="text-text-2 hover:text-accent" title="Open the official page" aria-label={`Open ${a.value}`}>
                  <Icon name="external" size={16} />
                </a>
              )}
              {canEdit && (
                <button
                  type="button"
                  onClick={() => remove(a)}
                  disabled={busyId === a.id}
                  className="text-text-2 hover:text-critical disabled:opacity-40"
                  title="Remove"
                  aria-label={`Remove ${a.value}`}
                >
                  <Icon name="trash" size={16} />
                </button>
              )}
            </li>
          )
        })}
        {assets.length === 0 && <li className="px-3 py-4 text-center text-xs text-muted">Nothing added yet.</li>}
      </ul>
      {canEdit && <AddAssetForm type={section.type} brand={brand} reload={reload} />}
    </Panel>
  )
}

const inputClass = 'w-full rounded-lg border border-line bg-panel-1 px-3 py-2 text-sm placeholder:text-muted focus:border-accent focus:outline-none'

function AddAssetForm({ type, brand, reload }) {
  const toast = useToast()
  const [value, setValue] = useState('')
  const [platform, setPlatform] = useState(type === 'mobile_app' ? 'apple' : type === 'social' ? 'x' : '')
  const [label, setLabel] = useState('')
  const [publisher, setPublisher] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)

  async function submit(e) {
    e.preventDefault()
    let clean = value
    if (type === 'website' || type === 'email_domain') clean = cleanDomain(value)
    if (type === 'mobile_app') clean = cleanAppId(platform, value)
    if (type === 'social') clean = cleanHandle(value)
    if (!clean) return setError('Enter a value first.')

    setBusy(true)
    const { error: err } = await supabase.from('brand_assets').insert({
      tenant_id: brand.tenant_id,
      brand_id: brand.id,
      asset_type: type,
      platform,
      value: clean,
      label: label || null,
      publisher: publisher || null,
    })
    setBusy(false)
    if (err) return setError(friendlyError(err, type))
    setError(null)
    setValue(''); setLabel(''); setPublisher('')
    toast(`Added ${clean}`)
    reload()
  }

  // Example text so it is clear what to type in each box
  const placeholder = {
    website: 'e.g. examplebank.in  or  https://www.examplebank.in/home',
    email_domain: 'e.g. examplebank.in  (the part after @ in your email address)',
    mobile_app: platform === 'apple'
      ? 'e.g. https://apps.apple.com/in/app/example-bank/id1234567890  or  1234567890'
      : 'e.g. com.examplebank.mobile  or  its Google Play link',
    social: 'e.g. https://x.com/ExampleBank  or  @ExampleBank',
  }[type]

  return (
    <form onSubmit={submit} className="mt-3 space-y-2">
      <div className="flex flex-wrap gap-2">
        {type === 'mobile_app' && (
          <select value={platform} onChange={(e) => setPlatform(e.target.value)} className={`${inputClass} !w-auto`} aria-label="App store">
            {Object.entries(APP_STORES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        )}
        {type === 'social' && (
          <select value={platform} onChange={(e) => setPlatform(e.target.value)} className={`${inputClass} !w-auto`} aria-label="Platform">
            {Object.entries(SOCIAL).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
          </select>
        )}
        <input
          value={value}
          onChange={(e) => { setValue(e.target.value); setError(null) }}
          placeholder={placeholder}
          className={`${inputClass} min-w-0 flex-1`}
          aria-label={`New ${type.replace('_', ' ')}`}
        />
        <Button type="submit" variant="primary" disabled={busy || !value.trim()}>
          <Icon name="plus" size={16} /> Add
        </Button>
      </div>
      {type === 'mobile_app' && (
        <div className="flex flex-wrap gap-2">
          <input value={label} onChange={(e) => setLabel(e.target.value)} placeholder="App name (optional), e.g. Example Bank Mobile" className={`${inputClass} min-w-0 flex-1`} aria-label="App name" />
          <input value={publisher} onChange={(e) => setPublisher(e.target.value)} placeholder="Official developer (optional), e.g. Example Bank Ltd" className={`${inputClass} min-w-0 flex-1`} aria-label="Official developer name" />
        </div>
      )}
      {error && <p className="text-xs text-critical" role="alert">{error}</p>}
    </form>
  )
}

function BrandForm({ tenantId, brand, onClose, onSaved }) {
  const toast = useToast()
  const [name, setName] = useState(brand?.name || '')
  const [keywords, setKeywords] = useState(brand ? brand.keywords.join(', ') : '')
  const [website, setWebsite] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [keywordsTouched, setKeywordsTouched] = useState(Boolean(brand))

  // Suggest a search term from the name until the user edits it
  const suggested = name.toLowerCase().replace(/[^a-z0-9]/g, '')
  const effectiveKeywords = keywordsTouched ? keywords : suggested

  async function submit(e) {
    e.preventDefault()
    const list = [...new Set(effectiveKeywords.split(',').map((k) => k.trim().toLowerCase()).filter(Boolean))]
    if (!name.trim()) return setError('Enter the brand name.')
    if (list.length === 0) return setError('Enter at least one search term.')
    if (list.some((k) => k.length < 4)) return setError('Search terms must be at least 4 characters, or results will be mostly noise.')

    setBusy(true)
    let id = brand?.id
    if (brand) {
      const { error: err } = await supabase.from('brands').update({ name: name.trim(), keywords: list }).eq('id', brand.id)
      if (err) { setBusy(false); return setError(err.code === '23505' ? 'A brand with this name already exists.' : friendlyError(err)) }
    } else {
      const { data: row, error: err } = await supabase.from('brands')
        .insert({ tenant_id: tenantId, name: name.trim(), keywords: list })
        .select('id').single()
      if (err) { setBusy(false); return setError(err.code === '23505' ? 'A brand with this name already exists.' : friendlyError(err)) }
      id = row.id
      if (website.trim()) {
        const { error: wErr } = await supabase.from('brand_assets').insert({
          tenant_id: tenantId, brand_id: id, asset_type: 'website', value: cleanDomain(website),
        })
        if (wErr) toast(`Brand created, but the website was not added: ${friendlyError(wErr, 'website')}`, 'error')
      }
    }
    setBusy(false)
    toast(brand ? 'Brand updated' : 'Brand added. Monitoring starts with the next scan.')
    onSaved(id)
  }

  return (
    <Modal title={brand ? 'Edit brand' : 'Add a brand to protect'} onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <label className="block">
          <span className="text-xs text-text-2">Brand or company name</span>
          <input value={name} onChange={(e) => setName(e.target.value)} className={`${inputClass} mt-1`} placeholder="e.g. Example Small Finance Bank" autoFocus />
        </label>
        <label className="block">
          <span className="text-xs text-text-2">Search terms (comma separated)</span>
          <input
            value={effectiveKeywords}
            onChange={(e) => { setKeywords(e.target.value); setKeywordsTouched(true) }}
            className={`${inputClass} mt-1 font-mono`}
            placeholder="e.g. examplebank  (several: examplebank, exbank)"
          />
          <span className="mt-1 block text-[11px] text-muted">
            The words BrandGuard looks for inside new domain names, usually the brand name without spaces.
          </span>
        </label>
        {!brand && (
          <label className="block">
            <span className="text-xs text-text-2">Main website (optional, you can add more later)</span>
            <input value={website} onChange={(e) => setWebsite(e.target.value)} className={`${inputClass} mt-1`} placeholder="e.g. examplebank.in" />
          </label>
        )}
        {error && <p className="text-xs text-critical" role="alert">{error}</p>}
        <div className="flex justify-end gap-2">
          <Button onClick={onClose}>Cancel</Button>
          <Button type="submit" variant="primary" disabled={busy}>{brand ? 'Save' : 'Add brand'}</Button>
        </div>
      </form>
    </Modal>
  )
}
