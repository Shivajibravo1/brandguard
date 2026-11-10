import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from './supabase'

const REFRESH_MS = 20000

/**
 * Loads everything the Dashboard and Incidents views need for the signed-in
 * user's tenant. Row Level Security limits every query to that tenant, so no
 * tenant filter is needed here. Refreshes automatically every 20 seconds.
 */
export function useTenantData() {
  const [data, setData] = useState({
    tenant: null, membership: null, brands: [], assets: [], incidents: [], scanRuns: [], takedowns: [], domainsCount: 0,
  })
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [lastUpdated, setLastUpdated] = useState(null)
  const mounted = useRef(true)

  const load = useCallback(async () => {
    const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString()
    const { data: userData } = await supabase.auth.getUser()
    const userId = userData?.user?.id

    const [tenants, members, brands, assets, incidents, scanRuns, takedowns, domains] = await Promise.all([
      supabase.from('tenants').select('id, name, plan').limit(1),
      supabase.from('tenant_members').select('tenant_id, role').eq('user_id', userId).limit(1),
      supabase.from('brands').select('id, tenant_id, name, keywords, legitimate_domains, is_active, created_at').order('name'),
      supabase.from('brand_assets').select('*').order('created_at'),
      supabase.from('incidents').select('*')
        .order('detected_at', { ascending: false })
        .order('risk_score', { ascending: false, nullsFirst: false })
        .limit(1000),
      supabase.from('scan_runs').select('*').gte('started_at', since).order('started_at', { ascending: false }).limit(500),
      supabase.from('takedowns').select('id, incident_id, target, status, created_at').order('created_at', { ascending: false }),
      supabase.from('domains').select('id', { count: 'exact', head: true }),
    ])

    const failed = [tenants, members, brands, assets, incidents, scanRuns, takedowns, domains].find((r) => r.error)
    if (!mounted.current) return
    if (failed) {
      setError(failed.error.message)
    } else {
      setError(null)
      setData({
        tenant: tenants.data[0] || null,
        membership: members.data[0] || null,
        brands: brands.data,
        assets: assets.data,
        incidents: incidents.data,
        scanRuns: scanRuns.data,
        takedowns: takedowns.data,
        domainsCount: domains.count ?? 0,
      })
      setLastUpdated(new Date())
    }
    setLoading(false)
  }, [])

  useEffect(() => {
    mounted.current = true
    load()
    const timer = setInterval(load, REFRESH_MS)
    return () => {
      mounted.current = false
      clearInterval(timer)
    }
  }, [load])

  return { ...data, loading, error, lastUpdated, reload: load }
}
