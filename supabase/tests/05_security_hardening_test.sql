-- =============================================================================
-- LOCAL TEST ONLY. Tests for migration 0005 (least-privilege hardening).
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

-- T1 Visitors who are not signed in have no table privileges at all
do $$ begin
  assert not exists (
    select 1 from information_schema.role_table_grants
     where grantee = 'anon' and table_schema = 'public'),
    'T1 anon still holds table privileges';
  raise notice 'PASS: T1 anon has no table privileges';
end $$;

-- T2 Signed-in users can never TRUNCATE (which skips Row Level Security)
do $$ begin
  assert not exists (
    select 1 from information_schema.role_table_grants
     where grantee = 'authenticated' and table_schema = 'public'
       and privilege_type in ('TRUNCATE', 'TRIGGER', 'REFERENCES')),
    'T2 authenticated holds TRUNCATE, TRIGGER or REFERENCES';
  raise notice 'PASS: T2 no TRUNCATE, TRIGGER or REFERENCES for signed-in users';
end $$;

-- T3 Machine-written tables are read-only for users
do $$
declare t text;
begin
  foreach t in array array['alerts', 'scan_runs', 'dmarc_reports', 'audit_log'] loop
    assert has_table_privilege('authenticated', 'public.' || t, 'select'), format('T3 cannot read %s', t);
    assert not has_table_privilege('authenticated', 'public.' || t, 'insert'), format('T3 can insert into %s', t);
    assert not has_table_privilege('authenticated', 'public.' || t, 'update'), format('T3 can update %s', t);
    assert not has_table_privilege('authenticated', 'public.' || t, 'delete'), format('T3 can delete from %s', t);
  end loop;
  assert not has_table_privilege('authenticated', 'public.evidence', 'update'), 'T3 evidence can be edited';
  raise notice 'PASS: T3 alerts, scan history, DMARC reports and audit log are read-only; evidence cannot be edited';
end $$;

-- T4 Internal functions cannot be called through the API
do $$
declare f text;
begin
  foreach f in array array[
    'public.registered_domain(text)', 'public.is_legitimate_host(text, text[])',
    'public.score_ct_candidate(text, text, text)', 'public.score_lookalike_domain(jsonb, text[], date)',
    'public.write_audit_log()', 'public.sync_brand_legitimate_domains()',
    'public.ingest_ct_certificates(uuid, jsonb)', 'public.ingest_lookalike_domains(uuid, jsonb)',
    'public.record_scan_failure(uuid, text, text)'] loop
    assert not has_function_privilege('anon', f, 'execute'), format('T4 anon can execute %s', f);
    assert not has_function_privilege('authenticated', f, 'execute'), format('T4 authenticated can execute %s', f);
  end loop;
  assert not has_function_privilege('anon', 'public.has_tenant_role(uuid, public.tenant_role)', 'execute'), 'T4 anon can run has_tenant_role';
  assert has_function_privilege('authenticated', 'public.has_tenant_role(uuid, public.tenant_role)', 'execute'), 'T4 RLS helper blocked';
  raise notice 'PASS: T4 internal functions are not callable by visitors or users';
end $$;

-- T5 The app still works for a signed-in analyst after hardening
insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000f5');
insert into public.tenants (id, name) values ('f5f5f5f5-f5f5-f5f5-f5f5-f5f5f5f5f5f5', 'SAMPLE Hardening Tenant');
insert into public.tenant_members (tenant_id, user_id, role) values
  ('f5f5f5f5-f5f5-f5f5-f5f5-f5f5f5f5f5f5', '00000000-0000-0000-0000-0000000000f5', 'analyst');
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f5', true);
do $$ begin
  insert into public.incidents (tenant_id, channel, title, source, source_ref)
  values ('f5f5f5f5-f5f5-f5f5-f5f5-f5f5f5f5f5f5', 'domain', 'SAMPLE manual report', 'manual', 'sample-hardening.example');
  update public.incidents set status = 'investigating' where source_ref = 'sample-hardening.example';
  assert found, 'T5 analyst could not update an incident';
  assert (select count(*) from public.scan_runs) = 0, 'T5 scan history not readable';
  raise notice 'PASS: T5 signed-in analyst can still read and work on incidents';
end $$;
rollback;

\echo 'ALL SECURITY HARDENING TESTS PASSED'
