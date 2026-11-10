-- =============================================================================
-- LOCAL TEST ONLY. Tests for migration 0002 (crt.sh ingestion and scoring).
-- Certificates below are labelled sample rows shaped like crt.sh JSON output.
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

insert into public.tenants (id, name) values ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'SAMPLE CT Tenant');
insert into public.brands (id, tenant_id, name, keywords, legitimate_domains) values
  ('cccccccc-0000-0000-0000-000000000001', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'SAMPLE Paybrand',
   '{paybrand}', '{paybrand.com,paybrandobjects.com}');

-- Helper data: one call's worth of sample certificates
create temp table sample_certs as select $json$[
  {"id": 1, "issuer_name": "C=US, O=DigiCert Inc, CN=DigiCert G2", "not_before": "2026-11-01T00:00:00",
   "name_value": "www.paybrand.com\npaybrand-help.com"},
  {"id": 2, "issuer_name": "C=US, O=SSL Corporation, CN=SSL.com DV", "not_before": "2026-11-02T00:00:00",
   "name_value": "paybrand--checkout.pages.dev"},
  {"id": 3, "issuer_name": "C=US, O=Let's Encrypt, CN=R11", "not_before": "2026-11-03T00:00:00",
   "name_value": "http-paybrand--limited.unrelated-shop.com"},
  {"id": 4, "issuer_name": "C=US, O=DigiCert Inc, CN=DigiCert G2", "not_before": "2026-11-04T00:00:00",
   "name_value": "paybrand.vc\nwww.paybrand.vc"},
  {"id": 5, "issuer_name": "C=US, O=Let's Encrypt, CN=R10", "not_before": "2026-11-05T00:00:00",
   "name_value": "secure-login.paybrand-account.com\n*.paybrand-account.com"},
  {"id": 6, "issuer_name": "C=US, O=Let's Encrypt, CN=R10", "not_before": "2026-11-05T00:00:00",
   "name_value": "unrelated.example.org"}
]$json$::jsonb as certs;

-- T1 Unit checks on helpers
do $$ begin
  assert public.registered_domain('a.b.paybrand-help.com') = 'paybrand-help.com', 'T1 registered_domain .com';
  assert public.registered_domain('shop.example.co.uk') = 'example.co.uk', 'T1 registered_domain co.uk';
  assert public.is_legitimate_host('www.paybrand.com', '{paybrand.com}'), 'T1 legit subdomain';
  assert not public.is_legitimate_host('paybrand.com.evil.net', '{paybrand.com}'), 'T1 suffix trick must not be legit';
  raise notice 'PASS: T1 domain helper functions';
end $$;

-- T2 First ingestion creates the expected incidents
create temp table run1 as
  select * from public.ingest_ct_certificates('cccccccc-0000-0000-0000-000000000001', (select certs from sample_certs));
do $$ begin
  assert (select count(*) from run1) = 4, format('T2 expected 4 new incidents, got %s', (select count(*) from run1));
  assert not exists (select 1 from run1 where asset = 'paybrand-help.com'), 'T2 brand-owned cert (covers paybrand.com) must be skipped';
  assert not exists (select 1 from run1 where asset like '%example.org'), 'T2 cert without the keyword must be ignored';
  assert (select count(*) from run1 where asset = 'paybrand-account.com') = 1, 'T2 hosts must collapse to one registered domain';
  raise notice 'PASS: T2 ingestion filters brand-owned and unrelated certificates';
end $$;

-- T3 Scores follow the rules
do $$ begin
  assert (select severity from run1 where asset = 'paybrand--checkout.pages.dev') in ('critical', 'high'), 'T3 free hosting should be high or critical';
  assert (select severity from run1 where asset = 'http-paybrand--limited.unrelated-shop.com') in ('critical', 'high'), 'T3 brand in subdomain should be high or critical';
  assert (select severity from run1 where asset = 'paybrand.vc') in ('low', 'info'), 'T3 exact name with paid CA should be low';
  assert (select risk_score from run1 where asset = 'paybrand-account.com')
       > (select risk_score from run1 where asset = 'paybrand.vc'), 'T3 combosquat should outscore exact name';
  assert not exists (select 1 from run1 where coalesce(explanation, '') = ''), 'T3 every incident needs an explanation';
  raise notice 'PASS: T3 risk scores and explanations follow the rules';
end $$;

-- T4 Re-running the same batch creates no duplicates and logs both scans
do $$ begin
  assert (select count(*) from public.ingest_ct_certificates('cccccccc-0000-0000-0000-000000000001', (select certs from sample_certs))) = 0,
         'T4 second run must not create incidents';
  assert (select count(*) from public.incidents where tenant_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc') = 4, 'T4 duplicate incidents found';
  assert (select count(*) from public.scan_runs where tenant_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc' and status = 'success') = 2, 'T4 scan runs not logged';
  assert (select count(*) from public.domains where tenant_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc') = 4, 'T4 domains rows missing';
  raise notice 'PASS: T4 no duplicates on re-scan; scan history recorded';
end $$;

-- T5 Signed-in users and visitors cannot run ingestion
begin;
set local role authenticated;
do $$ begin
  begin
    perform public.ingest_ct_certificates('cccccccc-0000-0000-0000-000000000001', '[]'::jsonb);
    raise exception 'T5 FAILED: authenticated user ran ingestion';
  exception when insufficient_privilege then null;
  end;
end $$;
set local role anon;
do $$ begin
  begin
    perform public.ingest_ct_certificates('cccccccc-0000-0000-0000-000000000001', '[]'::jsonb);
    raise exception 'T5 FAILED: anonymous visitor ran ingestion';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: T5 only the service role (N8N) can run ingestion';
end $$;
rollback;

-- T6 Failed scans are recorded
do $$ begin
  perform public.record_scan_failure('cccccccc-0000-0000-0000-000000000001', 'crt.sh', 'SAMPLE timeout');
  assert (select count(*) from public.scan_runs where tenant_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc' and status = 'failed') = 1, 'T6 failure not recorded';
  raise notice 'PASS: T6 failed scans are recorded';
end $$;

\echo 'ALL CT INGESTION TESTS PASSED'
