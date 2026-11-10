export const SEVERITIES = ['critical', 'high', 'medium', 'low', 'info']

export const SEVERITY_COLOR = {
  critical: 'var(--color-critical)',
  high: '#ff7a45',
  medium: 'var(--color-warning)',
  low: 'var(--color-blue)',
  info: 'var(--color-text-2)',
}

export const CHANNEL_LABEL = {
  domain: 'Domain',
  social: 'Social',
  app: 'Mobile app',
  email: 'Email',
}

export const STATUS_LABEL = {
  new: 'New',
  investigating: 'Investigating',
  takedown: 'Takedown',
  monitoring: 'Monitoring',
  resolved: 'Resolved',
  false_positive: 'False positive',
}

export const OPEN_STATUSES = ['new', 'investigating', 'takedown', 'monitoring']

export function scoreColor(score) {
  if (score == null) return 'var(--color-muted)'
  if (score >= 80) return 'var(--color-critical)'
  if (score >= 60) return '#ff7a45'
  if (score >= 40) return 'var(--color-warning)'
  return 'var(--color-success)'
}

export function timeAgo(value) {
  if (!value) return ''
  const seconds = Math.max(0, Math.round((Date.now() - new Date(value).getTime()) / 1000))
  if (seconds < 60) return `${seconds}s ago`
  const minutes = Math.round(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.round(minutes / 60)
  if (hours < 48) return `${hours}h ago`
  return `${Math.round(hours / 24)}d ago`
}

export function formatDateTime(value) {
  if (!value) return ''
  return new Date(value).toLocaleString(undefined, {
    year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit',
  })
}

export const isSample = (incident) => incident?.source === 'sample'
