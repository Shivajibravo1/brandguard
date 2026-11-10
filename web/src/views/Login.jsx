import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { Button, Icon } from '../components/ui'

export default function Login() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)

  async function submit(e) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    const { error: err } = await supabase.auth.signInWithPassword({ email: email.trim(), password })
    setBusy(false)
    if (err) setError(err.message)
  }

  const input = 'mt-1 w-full rounded-lg border border-line bg-black px-3 py-2.5 text-sm outline-none focus:border-accent'
  return (
    <div className="hex-bg flex min-h-full items-center justify-center p-4">
      <form onSubmit={submit} className="panel fade-in w-full max-w-sm space-y-4 p-6">
        <div className="flex items-center gap-3">
          <span className="text-accent"><Icon name="shield" size={30} /></span>
          <div>
            <h1 className="text-lg font-semibold">BrandGuard</h1>
            <p className="text-xs text-text-2">by Shivaji, PM · Digital impersonation protection</p>
          </div>
        </div>
        <label className="block text-sm">Email
          <input className={input} type="email" autoComplete="username" placeholder="e.g. analyst@yourcompany.com" value={email} onChange={(e) => setEmail(e.target.value)} required />
        </label>
        <label className="block text-sm">Password
          <input className={input} type="password" autoComplete="current-password" placeholder="Your BrandGuard password" value={password} onChange={(e) => setPassword(e.target.value)} required />
        </label>
        {error && <p className="text-sm text-critical">{error}</p>}
        <Button variant="primary" type="submit" disabled={busy} className="w-full">{busy ? 'Signing in...' : 'Sign in'}</Button>
        <p className="text-xs text-muted">Local demo. Demo logins are listed in supabase/seed.sql.</p>
      </form>
    </div>
  )
}
