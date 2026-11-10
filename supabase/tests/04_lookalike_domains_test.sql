-- =============================================================================
-- LOCAL TEST ONLY. Tests for migration 0004 (lookalike domain monitoring).
-- Scanner rows below are labelled sample data shaped like the scanner output.
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

insert into public.tenants (id, name) values ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'SAMPLE Lookalike Tenant');
insert into public.brands (id, tenant_id, name, keywords) values
  ('ffffffff-0000-0000-0000-000000000001', 'ffffffff-ffff-ffff-ffff-ffffffffffff', 'SAMPLE Small Bank', '{samplesfb}');
insert into public.brand_assets (tenant_id, brand_id, asset_type, value) values
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'ffffffff-0000-0000-0000-000000000001', 'website', 'samplesfb.bank.in'),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'ffffffff-0000-0000-0000-000000000001', 'website', 'samplesfb.in'),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'ffffffff-0000-0000-0000-000000000001', 'website', 'samplesfb.com');

create temp table sample_scan as select $json$
{"domain": "samplesfb.in", "generated": 4800, "engine": "dnstwist 20250130", "registered": [
  {"domain": "samplesfb.in", "fuzzer": "*original", "dns_a": ["198.51.100.1"]},
  {"domain": "samplesfb.com", "fuzzer": "tld-swap", "dns_a": ["198.51.100.1"]},
  {"domain": "sannplesfb.in", "fuzzer": "homoglyph", "dns_a": ["203.0.113.10"], "dns_mx": ["mx.sannplesfb.in"],
   "whois_created": "2026-10-20", "web_live": true, "web_final_host": "sannplesfb.in",
   "web_mentions_brand": true, "web_password_field": true, "web_parked": false},
  {"domain": "samplesfb-kyc.in", "fuzzer": "dictionary", "dns_a": ["203.0.113.11"],
   "whois_created": "2026-03-01", "web_live": true, "web_final_host": "samplesfb-kyc.in", "web_parked": true},
  {"domain": "samplesfb.co.in", "fuzzer": "tld-swap", "dns_a": ["203.0.113.12"],
   "whois_created": "2012-01-01", "web_live": true, "web_final_host": "samplesfb.bank.in"},
  {"domain": "sample.sfb.in", "fuzzer": "subdomain", "dns_a": ["203.0.113.13"], "whois_created": "2001-01-01"},
  {"domain": "samplesfv.in", "fuzzer": "replacement", "whois_created": "not a date"}
]}
$json$::jsonb as scan;

-- T1 Indian domain endings
do $$ begin
  assert public.registered_domain('examplesfb.bank.in') = 'examplesfb.bank.in', 'T1 bank.in';
  assert public.registered_domain('www.examplesfb.bank.in') = 'examplesfb.bank.in', 'T1 www bank.in';
  assert public.registered_domain('login.example.co.in') = 'example.co.in', 'T1 co.in';
  assert public.registered_domain('login.example.in') = 'example.in', 'T1 .in';
  assert public.registered_domain('a.paybrand-help.com') = 'paybrand-help.com', 'T1 .com still works';
  raise notice 'PASS: T1 registered domain understands .bank.in and other Indian endings';
end $$;

-- T2 Scoring rules
do $$
declare
  r record;
  official text[] := '{samplesfb.bank.in,samplesfb.in}';
begin
  select * into r from public.score_lookalike_domain((select scan -> 'registered' -> 2 from sample_scan), official, '2026-11-10');
  assert r.risk_score = 100 and r.severity = 'critical' and r.category = 'possible_phishing_page',
    format('T2 phishing case got %s %s %s', r.risk_score, r.severity, r.category);
  assert r.explanation like '%password field%' and r.explanation like '%mail servers%' and r.explanation like '%Registered recently%',
    'T2 phishing reasons missing';

  select * into r from public.score_lookalike_domain((select scan -> 'registered' -> 3 from sample_scan), official, '2026-11-10');
  assert r.category = 'parked_lookalike' and r.risk_score = 35, format('T2 parked case got %s %s', r.risk_score, r.category);

  select * into r from public.score_lookalike_domain((select scan -> 'registered' -> 4 from sample_scan), official, '2026-11-10');
  assert r.category = 'brand_owned_redirect' and r.risk_score = 0 and r.severity = 'info',
    format('T2 redirect case got %s %s', r.risk_score, r.category);

  select * into r from public.score_lookalike_domain((select scan -> 'registered' -> 5 from sample_scan), official, '2026-11-10');
  assert r.category = 'unrelated_parent_domain' and r.risk_score < 20, format('T2 subdomain case got %s %s', r.risk_score, r.category);

  select * into r from public.score_lookalike_domain((select scan -> 'registered' -> 6 from sample_scan), official, '2026-11-10');
  assert r.category = 'typosquatting' and r.risk_score = 25, format('T2 bad date case got %s %s', r.risk_score, r.category);
  raise notice 'PASS: T2 risk scores and reasons follow the rules';
end $$;

-- T3 First ingestion
create temp table run1 as
  select * from public.ingest_lookalike_domains('ffffffff-0000-0000-0000-000000000001', (select scan from sample_scan));
do $$ begin
  assert (select count(*) from run1) = 5, format('T3 expected 5 alertable incidents, got %s', (select count(*) from run1));
  assert not exists (select 1 from run1 where asset in ('samplesfb.in', 'samplesfb.com')), 'T3 official domain reported';
  assert (select count(*) from run1 where change = 'new') = 5, 'T3 change should be new';
  assert (select certificates_checked from public.scan_runs where source = 'dnstwist' and tenant_id = 'ffffffff-ffff-ffff-ffff-ffffffffffff') = 4800, 'T3 generated count not stored';
  assert (select candidates_found from public.scan_runs where source = 'dnstwist' and tenant_id = 'ffffffff-ffff-ffff-ffff-ffffffffffff') = 5, 'T3 candidates wrong';
  assert (select registered_at::date from public.domains where domain = 'sannplesfb.in') = '2026-10-20', 'T3 registration date not stored';
  assert (select host(hosting_ip) from public.domains where domain = 'sannplesfb.in') = '203.0.113.10', 'T3 IP not stored';
  assert (select details ->> 'lookalike_of' from public.incidents where source_ref = 'sannplesfb.in') = 'samplesfb.in', 'T3 evidence missing';
  raise notice 'PASS: T3 ingestion creates scored incidents and skips official domains';
end $$;

-- T4 Re-scan: no duplicates; rising risk on an open incident is reported once
do $$
declare
  v_scan jsonb := (select scan from sample_scan);
  v_count integer;
begin
  select count(*) into v_count from public.ingest_lookalike_domains('ffffffff-0000-0000-0000-000000000001', v_scan);
  assert v_count = 0, format('T4 unchanged re-scan returned %s rows', v_count);
  assert (select count(*) from public.incidents where tenant_id = 'ffffffff-ffff-ffff-ffff-ffffffffffff') = 5, 'T4 duplicates created';

  -- The parked domain now shows a login page
  v_scan := jsonb_set(v_scan, '{registered,3}', (v_scan -> 'registered' -> 3)
                      || '{"web_parked": false, "web_password_field": true, "web_mentions_brand": true}'::jsonb);
  -- The analyst already closed the subdomain case as a false positive
  update public.incidents set status = 'false_positive' where source_ref = 'sample.sfb.in';
  v_scan := jsonb_set(v_scan, '{registered,5}', (v_scan -> 'registered' -> 5) || '{"web_password_field": true, "web_live": true}'::jsonb);

  create temp table run2 as select * from public.ingest_lookalike_domains('ffffffff-0000-0000-0000-000000000001', v_scan);
  assert (select count(*) from run2) = 1, format('T4 expected 1 alert, got %s', (select count(*) from run2));
  assert (select asset from run2) = 'samplesfb-kyc.in', 'T4 wrong domain alerted';
  assert (select change from run2) like 'risk increased from 35 to %', format('T4 change text was %s', (select change from run2));
  assert (select score_category from public.incidents where source_ref = 'samplesfb-kyc.in') = 'possible_phishing_page', 'T4 score not updated';
  assert (select status from public.incidents where source_ref = 'sample.sfb.in') = 'false_positive', 'T4 status overwritten';
  raise notice 'PASS: T4 re-scans update evidence, avoid duplicates and re-alert only on rising risk';
end $$;

-- T5 Only the service role (N8N) can run ingestion
begin;
set local role authenticated;
do $$ begin
  begin
    perform public.ingest_lookalike_domains('ffffffff-0000-0000-0000-000000000001', '{"domain": "x.in", "registered": []}'::jsonb);
    raise exception 'T5 FAILED: authenticated user ran ingestion';
  exception when insufficient_privilege then null;
  end;
end $$;
set local role anon;
do $$ begin
  begin
    perform public.ingest_lookalike_domains('ffffffff-0000-0000-0000-000000000001', '{"domain": "x.in", "registered": []}'::jsonb);
    raise exception 'T5 FAILED: anonymous visitor ran ingestion';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: T5 only the service role (N8N) can run lookalike ingestion';
end $$;
rollback;

-- T6 Bad input is rejected
do $$ begin
  begin
    perform public.ingest_lookalike_domains('ffffffff-0000-0000-0000-000000000001', '{"domain": "x.in"}'::jsonb);
    raise exception 'T6 FAILED: missing registered list accepted';
  exception when raise_exception then
    if sqlerrm like 'T6 FAILED%' then raise; end if;
  end;
  raise notice 'PASS: T6 malformed scanner output is rejected';
end $$;

\echo 'ALL LOOKALIKE DOMAIN TESTS PASSED'
