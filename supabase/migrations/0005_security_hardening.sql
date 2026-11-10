-- =============================================================================
-- BrandGuard by Shivaji, PM
-- Migration 0005: least-privilege hardening (defence in depth)
--
-- Row Level Security (RLS) already limits every row to the user's tenant.
-- This migration also removes privileges nobody needs, so a mistake in one
-- layer is caught by another:
--   * anon (not signed in): no table or function access at all.
--   * authenticated (signed in): only the statements the app uses; never
--     TRUNCATE (which skips RLS), TRIGGER or REFERENCES.
--   * Read-only tables for users: alerts, scan_runs, dmarc_reports, audit_log.
--   * Internal helper and trigger functions cannot be called through the API.
-- Maps to OWASP Top 10 A01 (Broken Access Control) and A05 (Security
-- Misconfiguration), and NIST CSF 2.0 PR.AA (access control).
-- =============================================================================

-- Tables -----------------------------------------------------------------------
revoke all on all tables in schema public from anon;
revoke truncate, trigger, references on all tables in schema public from authenticated;

-- Operational and configuration tables: RLS policies decide which rows
revoke all on public.tenants, public.tenant_members, public.brands, public.brand_assets,
              public.executives, public.incidents, public.domains, public.takedowns, public.evidence
  from authenticated;
grant select, update on public.tenants to authenticated;
grant select, insert, update, delete on public.tenant_members, public.brands, public.brand_assets,
  public.executives, public.incidents, public.domains, public.takedowns to authenticated;
grant select, insert, delete on public.evidence to authenticated;   -- evidence is never edited

-- Written only by N8N (service role) or triggers: read-only for users
revoke all on public.alerts, public.scan_runs, public.dmarc_reports, public.audit_log from authenticated;
grant select on public.alerts, public.scan_runs, public.dmarc_reports, public.audit_log to authenticated;

-- New tables do not get automatic grants for anon
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on functions from anon;

-- Functions --------------------------------------------------------------------
-- Pure helpers and trigger functions: internal only
revoke execute on function
  public.registered_domain(text),
  public.is_legitimate_host(text, text[]),
  public.score_ct_candidate(text, text, text),
  public.score_lookalike_domain(jsonb, text[], date),
  public.normalise_brand_asset(),
  public.sync_brand_legitimate_domains(),
  public.write_audit_log(),
  public.block_audit_log_change(),
  public.set_updated_at()
from public, anon, authenticated;

-- has_tenant_role is used inside RLS policies, so signed-in users need it.
-- It only answers "does the current user hold this role", nothing else.
revoke execute on function public.has_tenant_role(uuid, public.tenant_role) from public, anon;
grant  execute on function public.has_tenant_role(uuid, public.tenant_role) to authenticated, service_role;
