import { createContext, useCallback, useContext, useEffect, useId, useRef, useState } from 'react'
import { SEVERITY_COLOR, scoreColor } from '../lib/format'

/* ---------------------------------------------------------------- Icons */
const paths = {
  dashboard: 'M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z',
  incidents: 'M12 2 1 21h22L12 2zm0 4.5L19.5 19h-15L12 6.5zM11 10v4h2v-4h-2zm0 6v2h2v-2h-2z',
  shield: 'M12 2 4 5v6c0 5.5 3.4 10.3 8 11.9 4.6-1.6 8-6.4 8-11.9V5l-8-3z',
  search: 'M15.5 14h-.8l-.3-.3A6.5 6.5 0 1 0 14 15.5l.3.3v.8l5 5 1.5-1.5-5-5zm-6 0a4.5 4.5 0 1 1 0-9 4.5 4.5 0 0 1 0 9z',
  close: 'M19 6.4 17.6 5 12 10.6 6.4 5 5 6.4 10.6 12 5 17.6 6.4 19 12 13.4 17.6 19 19 17.6 13.4 12z',
  logout: 'M10 17v-3H3v-4h7V7l5 5-5 5zm9-14H12v2h7v14h-7v2h7a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2z',
  plus: 'M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z',
  external: 'M14 3v2h3.6l-9.8 9.8 1.4 1.4L19 6.4V10h2V3h-7zm5 16H5V5h7V3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7h-2v7z',
  brand: 'M21.4 11.6 12.4 2.6A2 2 0 0 0 11 2H4a2 2 0 0 0-2 2v7c0 .6.2 1.1.6 1.4l9 9a2 2 0 0 0 2.8 0l7-7a2 2 0 0 0 0-2.8zM5.5 7A1.5 1.5 0 1 1 7 5.5 1.5 1.5 0 0 1 5.5 7z',
  globe: 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm6.9 6h-2.9a15.7 15.7 0 0 0-1.4-3.6A8 8 0 0 1 18.9 8zM12 4c.8 1.2 1.5 2.5 1.9 4h-3.8c.4-1.5 1.1-2.8 1.9-4zM4.3 14a8.2 8.2 0 0 1 0-4h3.4a16.5 16.5 0 0 0 0 4H4.3zm.8 2h2.9c.3 1.3.8 2.5 1.4 3.6A8 8 0 0 1 5.1 16zM8 8H5.1a8 8 0 0 1 4.3-3.6C8.8 5.5 8.3 6.7 8 8zm4 12c-.8-1.2-1.5-2.5-1.9-4h3.8c-.4 1.5-1.1 2.8-1.9 4zm2.3-6H9.7a14.7 14.7 0 0 1 0-4h4.6a14.7 14.7 0 0 1 0 4zm.3 5.6c.6-1.1 1.1-2.3 1.4-3.6h2.9a8 8 0 0 1-4.3 3.6zm1.8-5.6a16.5 16.5 0 0 0 0-4h3.4a8.2 8.2 0 0 1 0 4h-3.4z',
  mail: 'M20 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 4-8 5-8-5V6l8 5 8-5v2z',
  phone: 'M17 1H7a2 2 0 0 0-2 2v18a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V3a2 2 0 0 0-2-2zm0 18H7V5h10v14z',
  people: 'M16 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm-8 0a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm0 2c-2.3 0-7 1.2-7 3.5V19h14v-2.5C15 14.2 10.3 13 8 13zm8 0c-.3 0-.6 0-1 .1 1.2.8 2 2 2 3.4V19h6v-2.5c0-2.3-4.7-3.5-7-3.5z',
  trash: 'M6 19a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z',
  edit: 'M3 17.25V21h3.75L17.8 9.94l-3.75-3.75L3 17.25zM20.7 7.04a1 1 0 0 0 0-1.41l-2.33-2.33a1 1 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.82-1.84z',
}

export function Icon({ name, size = 18, className = '' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" className={className}>
      <path d={paths[name]} />
    </svg>
  )
}

/* ---------------------------------------------------------------- Badges */
export function SeverityBadge({ severity }) {
  const color = SEVERITY_COLOR[severity] || 'var(--color-text-2)'
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-md px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide"
      style={{ color, background: `color-mix(in srgb, ${color} 14%, transparent)`, border: `1px solid color-mix(in srgb, ${color} 35%, transparent)` }}
    >
      {severity === 'critical' && <span className="pulse-dot" style={{ width: 6, height: 6 }} />}
      {severity}
    </span>
  )
}

export function SampleBadge() {
  return (
    <span
      title="Invented example for a channel that is not built yet. Not a real detection."
      className="rounded px-1.5 py-0.5 text-[10px] font-bold tracking-wider text-purple border border-purple/40 bg-purple/10"
    >
      SAMPLE
    </span>
  )
}

export function Chip({ active, onClick, children, color }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={`rounded-full border px-3 py-1 text-xs font-medium capitalize transition-colors ${
        active ? 'border-accent bg-accent/10 text-accent' : 'border-line text-text-2 hover:text-text hover:border-muted'
      }`}
      style={active && color ? { color, borderColor: color, background: `color-mix(in srgb, ${color} 12%, transparent)` } : undefined}
    >
      {children}
    </button>
  )
}

/* ---------------------------------------------------------------- Risk */
export function RiskBar({ score }) {
  if (score == null) return <span className="text-xs text-muted">Not scored</span>
  const color = scoreColor(score)
  return (
    <div className="flex items-center gap-2" title={`Risk score ${score} of 100`}>
      <div className="h-1.5 w-20 overflow-hidden rounded-full bg-panel-4">
        <div className="h-full rounded-full" style={{ width: `${score}%`, background: color }} />
      </div>
      <span className="font-mono text-xs" style={{ color }}>{score}</span>
    </div>
  )
}

export function RiskRing({ score, size = 132 }) {
  const stroke = 10
  const r = (size - stroke) / 2
  const c = 2 * Math.PI * r
  const value = score ?? 0
  const color = scoreColor(score)
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} role="img" aria-label={`Brand risk ${value} of 100`}>
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--color-panel-4)" strokeWidth={stroke} />
      <circle
        cx={size / 2} cy={size / 2} r={r} fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round"
        strokeDasharray={`${(value / 100) * c} ${c}`} transform={`rotate(-90 ${size / 2} ${size / 2})`}
        style={{ transition: 'stroke-dasharray 0.6s ease' }}
      />
      <text x="50%" y="48%" textAnchor="middle" dominantBaseline="middle" fill="var(--color-text)" fontSize="30" fontWeight="700" fontFamily="var(--font-mono)">
        {score ?? '--'}
      </text>
      <text x="50%" y="68%" textAnchor="middle" fill="var(--color-text-2)" fontSize="11">of 100</text>
    </svg>
  )
}

/* ---------------------------------------------------------------- Layout */
export function Panel({ title, action, info, children, className = '' }) {
  return (
    <section className={`panel neon-hover p-4 ${className}`}>
      {(title || action || info) && (
        <div className="mb-3 flex items-center justify-between gap-2">
          <h2 className="flex items-center gap-2 text-sm font-semibold tracking-wide text-text">
            {title}
            {info && <InfoButton title={typeof title === 'string' ? title : undefined}>{info}</InfoButton>}
          </h2>
          {action}
        </div>
      )}
      {children}
    </section>
  )
}

export function MetricCard({ label, value, hint, info, color = 'var(--color-accent)', onClick }) {
  const Tag = onClick ? 'button' : 'div'
  return (
    <div className="relative">
      <Tag
        onClick={onClick}
        className={`panel neon-hover fade-in block w-full p-4 text-left ${onClick ? 'cursor-pointer transition-colors hover:border-accent/50' : ''}`}
      >
        <div className="pr-6 text-xs uppercase tracking-wider text-text-2">{label}</div>
        <div className="mt-2 font-mono text-3xl font-semibold" style={{ color, textShadow: `0 0 12px color-mix(in srgb, ${color} 45%, transparent)` }}>{value}</div>
        {hint && <div className="mt-1 text-xs text-muted">{hint}</div>}
      </Tag>
      {info && <div className="absolute right-3 top-3"><InfoButton title={label}>{info}</InfoButton></div>}
    </div>
  )
}

/* ---------------------------------------------------------------- Info (i) */
// Small "i" button that explains a section in plain language.
export function InfoButton({ title, children }) {
  const [open, setOpen] = useState(false)
  const ref = useRef(null)
  const id = useId()
  useEffect(() => {
    if (!open) return
    const onDown = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false) }
    const onKey = (e) => { if (e.key === 'Escape') setOpen(false) }
    document.addEventListener('mousedown', onDown)
    document.addEventListener('keydown', onKey)
    return () => { document.removeEventListener('mousedown', onDown); document.removeEventListener('keydown', onKey) }
  }, [open])
  return (
    <span ref={ref} className="relative inline-flex normal-case tracking-normal">
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); setOpen((o) => !o) }}
        aria-expanded={open}
        aria-controls={id}
        aria-label={title ? `About ${title}` : 'About this section'}
        title="What is this?"
        className={`flex h-[18px] w-[18px] items-center justify-center rounded-full border font-mono text-[10px] font-bold leading-none transition-colors ${
          open ? 'border-accent bg-accent text-black' : 'border-accent/50 text-accent hover:bg-accent/15'
        }`}
      >
        i
      </button>
      {open && (
        <span
          id={id}
          role="tooltip"
          className="fade-in absolute left-1/2 top-6 z-40 w-72 -translate-x-1/2 rounded-lg border border-accent/40 bg-panel-2 p-3 text-left text-xs font-normal leading-relaxed text-text shadow-[0_0_24px_rgba(0,229,200,0.18)]"
        >
          {title && <span className="mb-1 block font-semibold text-accent">{title}</span>}
          {children}
        </span>
      )}
    </span>
  )
}

/* ---------------------------------------------------------------- Effects */
// Radar with a rotating sweep; blips mark recent findings (purely visual).
export function Radar({ size = 132, blips = [], active = true }) {
  return (
    <div className="radar" style={{ width: size, height: size }} role="img" aria-label={active ? 'Monitoring is running' : 'Monitoring paused'}>
      <div className="radar-grid" />
      {active && <div className="radar-sweep" />}
      {blips.slice(0, 8).map((b, i) => (
        <span
          key={i}
          className="radar-blip"
          style={{ left: `${b.x}%`, top: `${b.y}%`, background: b.color, color: b.color, animationDelay: `${(i * 0.37) % 3}s` }}
        />
      ))}
    </div>
  )
}

// Expanding "ping" rings around a status dot
export function Ping({ color = 'var(--color-success)', size = 10 }) {
  return (
    <span className="ping" style={{ color, width: size, height: size }} aria-hidden="true">
      <span /><span />
    </span>
  )
}

export function Button({ variant = 'secondary', className = '', ...props }) {
  const styles = {
    primary: 'bg-accent text-black hover:brightness-110',
    secondary: 'border border-line text-text hover:border-accent/60 hover:text-accent',
    danger: 'border border-critical/50 text-critical hover:bg-critical/10',
  }
  return (
    <button
      type="button"
      {...props}
      className={`inline-flex items-center justify-center gap-1.5 rounded-lg px-3 py-2 text-sm font-medium transition disabled:cursor-not-allowed disabled:opacity-40 ${styles[variant]} ${className}`}
    />
  )
}

export function Modal({ title, onClose, children, wide = false }) {
  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm" onMouseDown={onClose}>
      <div
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className={`panel fade-in max-h-[90vh] w-full overflow-y-auto p-5 ${wide ? 'max-w-3xl' : 'max-w-lg'}`}
        onMouseDown={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-start justify-between gap-4">
          <h2 className="text-base font-semibold">{title}</h2>
          <button type="button" onClick={onClose} className="text-text-2 hover:text-text" aria-label="Close">
            <Icon name="close" />
          </button>
        </div>
        {children}
      </div>
    </div>
  )
}

/* ---------------------------------------------------------------- Toasts */
const ToastContext = createContext(() => {})

export function ToastProvider({ children }) {
  const [toasts, setToasts] = useState([])
  const push = useCallback((message, kind = 'success') => {
    const id = Math.random().toString(36).slice(2)
    setToasts((t) => [...t, { id, message, kind }])
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 4500)
  }, [])
  return (
    <ToastContext.Provider value={push}>
      {children}
      <div className="fixed bottom-4 right-4 z-[60] flex flex-col gap-2" aria-live="polite">
        {toasts.map((t) => (
          <div
            key={t.id}
            className="panel fade-in max-w-sm px-4 py-3 text-sm"
            style={{ borderColor: t.kind === 'error' ? 'var(--color-critical)' : 'var(--color-accent)' }}
          >
            {t.message}
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  )
}

export const useToast = () => useContext(ToastContext)
