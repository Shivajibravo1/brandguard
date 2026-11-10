-- =============================================================================
-- LOCAL TEST ONLY. Tests for migration 0003 (official brand assets).
-- All data below is labelled sample data.
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

-- Users: D admin (d1), D analyst (d2), E admin (e1)
insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000d1'),
  ('00000000-0000-0000-0000-0000000000d2'),
  ('00000000-0000-0000-0000-0000000000e1');

insert into public.tenants (id, name) values
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'SAMPLE Asset Tenant D'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'SAMPLE Asset Tenant E');

insert into public.tenant_members (tenant_id, user_id, role) values
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '00000000-0000-0000-0000-0000000000d1', 'admin'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '00000000-0000-0000-0000-0000000000d2', 'analyst'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '00000000-0000-0000-0000-0000000000e1', 'admin');

insert into public.brands (id, tenant_id, name, keywords) values
  ('dddddddd-0000-0000-0000-000000000001', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'SAMPLE Bank D', '{samplebankd}'),
  ('eeeeeeee-0000-0000-0000-000000000001', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'SAMPLE Bank E', '{samplebanke}');

-- T1 Admin adds every asset type; domains are normalised and synced
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', true);
do $$ begin
  insert into public.brand_assets (tenant_id, brand_id, asset_type, value) values
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'dddddddd-0000-0000-0000-000000000001', 'website', ' https://WWW.SampleBankD.com/en/home '),
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'dddddddd-0000-0000-0000-000000000001', 'email_domain', 'mail.samplebankd.ae');
  insert into public.brand_assets (tenant_id, brand_id, asset_type, platform, value, label, publisher) values
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'dddddddd-0000-0000-0000-000000000001', 'mobile_app', 'apple', '123456789', 'SAMPLE Bank D', 'SAMPLE Bank D PJSC'),
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'dddddddd-0000-0000-0000-000000000001', 'mobile_app', 'google', 'com.samplebankd.mobile', 'SAMPLE Bank D', 'SAMPLE Bank D PJSC'),
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'dddddddd-0000-0000-0000-000000000001', 'social', 'X', '@SampleBankD', null, null);

  assert (select value from public.brand_assets where asset_type = 'website') = 'samplebankd.com', 'T1 website not normalised';
  assert (select value from public.brand_assets where asset_type = 'social') = 'SampleBankD', 'T1 handle @ not stripped';
  assert (select platform from public.brand_assets where asset_type = 'social') = 'x', 'T1 platform not lower-cased';
  assert (select legitimate_domains from public.brands where id = 'dddddddd-0000-0000-0000-000000000001')
         = '{mail.samplebankd.ae,samplebankd.com}', 'T1 legitimate_domains not synced';

  delete from public.brand_assets where asset_type = 'email_domain';
  assert (select legitimate_domains from public.brands where id = 'dddddddd-0000-0000-0000-000000000001')
         = '{samplebankd.com}', 'T1 legitimate_domains not updated after delete';
  raise notice 'PASS: T1 admin manages assets; domains normalised and synced to legitimate_domains';
end $$;
rollback;

-- T2 Invalid values are rejected
begin;
do $$
declare
  bad record;
begin
  for bad in select * from (values
      ('website'::public.brand_asset_type, '', 'not a domain'),
      ('website', '', 'localhost'),
      ('mobile_app', 'apple', 'com.samplebankd.mobile'),
      ('mobile_app', 'google', '12345'),
      ('mobile_app', 'windows', 'com.samplebankd.mobile'),
      ('social', 'myspace', 'samplebankd'),
      ('social', 'x', 'bad handle!')) as t(asset_type, platform, value)
  loop
    begin
      insert into public.brand_assets (tenant_id, brand_id, asset_type, platform, value)
      values ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'dddddddd-0000-0000-0000-000000000001', bad.asset_type, bad.platform, bad.value);
      raise exception 'T2 FAILED: accepted % / % / %', bad.asset_type, bad.platform, bad.value;
    exception when check_violation then null;
    end;
  end loop;
  raise notice 'PASS: T2 invalid domains, app ids, platforms and handles rejected';
end $$;
rollback;

-- T3 Duplicates are rejected (after normalisation)
begin;
do $$ begin
  insert into public.brand_assets (tenant_id, brand_id, asset_type, value)
  values ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'dddddddd-0000-0000-0000-000000000001', 'website', 'samplebankd.com');
  begin
    insert into public.brand_assets (tenant_id, brand_id, asset_type, value)
    values ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'dddddddd-0000-0000-0000-000000000001', 'website', 'https://www.SAMPLEBANKD.com');
    raise exception 'T3 FAILED: duplicate accepted';
  exception when unique_violation then null;
  end;
  raise notice 'PASS: T3 duplicate assets rejected';
end $$;
rollback;

-- T4 Analyst can read but not change assets
begin;
insert into public.brand_assets (tenant_id, brand_id, asset_type, value)
values ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'dddddddd-0000-0000-0000-000000000001', 'website', 'samplebankd.com');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', true);
do $$ begin
  assert (select count(*) from public.brand_assets) = 1, 'T4 analyst should see 1 asset';
  begin
    insert into public.brand_assets (tenant_id, brand_id, asset_type, value)
    values ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'dddddddd-0000-0000-0000-000000000001', 'website', 'other.com');
    raise exception 'T4 FAILED: analyst insert allowed';
  exception when insufficient_privilege then null;
  end;
  delete from public.brand_assets;
  assert not found, 'T4 analyst delete removed rows';
  raise notice 'PASS: T4 analyst can read but not change assets';
end $$;
rollback;

-- T5 Tenant isolation: admin E cannot see or attach assets to tenant D
begin;
insert into public.brand_assets (tenant_id, brand_id, asset_type, value)
values ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'dddddddd-0000-0000-0000-000000000001', 'website', 'samplebankd.com');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', true);
do $$ begin
  assert (select count(*) from public.brand_assets) = 0, 'T5 admin E sees tenant D assets';
  -- Own tenant id with tenant D brand: blocked by the composite foreign key
  begin
    insert into public.brand_assets (tenant_id, brand_id, asset_type, value)
    values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'dddddddd-0000-0000-0000-000000000001', 'website', 'evil.com');
    raise exception 'T5 FAILED: attached asset to another tenant''s brand';
  exception when foreign_key_violation then null;
  end;
  -- Tenant D id: blocked by Row Level Security
  begin
    insert into public.brand_assets (tenant_id, brand_id, asset_type, value)
    values ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'dddddddd-0000-0000-0000-000000000001', 'website', 'evil.com');
    raise exception 'T5 FAILED: cross-tenant insert allowed';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: T5 assets are isolated per tenant';
end $$;
rollback;

-- T6 Deleting a brand removes its assets; CT ingestion skips official domains
begin;
do $$
declare
  v_count integer;
begin
  insert into public.brand_assets (tenant_id, brand_id, asset_type, value) values
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'dddddddd-0000-0000-0000-000000000001', 'website', 'samplebankd.com'),
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'dddddddd-0000-0000-0000-000000000001', 'website', 'samplebankd-online.com');

  select count(*) into v_count from public.ingest_ct_certificates('dddddddd-0000-0000-0000-000000000001', $json$[
    {"id": 91, "issuer_name": "C=US, O=Let's Encrypt, CN=R10", "not_before": "2026-11-05T00:00:00", "name_value": "samplebankd-online.com"},
    {"id": 92, "issuer_name": "C=US, O=Let's Encrypt, CN=R10", "not_before": "2026-11-05T00:00:00", "name_value": "samplebankd-login.com"}
  ]$json$::jsonb);
  assert v_count = 1, format('T6 expected 1 incident (official domain skipped), got %s', v_count);

  delete from public.brands where id = 'dddddddd-0000-0000-0000-000000000001';
  assert (select count(*) from public.brand_assets where brand_id = 'dddddddd-0000-0000-0000-000000000001') = 0, 'T6 assets left behind';
  raise notice 'PASS: T6 official domains excluded from detection; assets removed with brand';
end $$;
rollback;

\echo 'ALL BRAND ASSET TESTS PASSED'
