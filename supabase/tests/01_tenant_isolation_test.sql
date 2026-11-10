-- =============================================================================
-- LOCAL TEST ONLY. Tenant isolation and role tests for migration 0001.
-- Test data below is labelled sample data and never goes to production.
-- Each test prints "PASS: ..." or stops the script with an error.
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

-- Fixed ids for readability
--   Tenant A: 'aaaaaaaa-...'   Tenant B: 'bbbbbbbb-...'
--   Users: A admin (a1), A analyst (a2), A viewer (a3), B analyst (b2)
insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-0000000000a2'),
  ('00000000-0000-0000-0000-0000000000a3'),
  ('00000000-0000-0000-0000-0000000000b2');

insert into public.tenants (id, name) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'SAMPLE Tenant A'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'SAMPLE Tenant B');

insert into public.tenant_members (tenant_id, user_id, role) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '00000000-0000-0000-0000-0000000000a1', 'admin'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '00000000-0000-0000-0000-0000000000a2', 'analyst'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '00000000-0000-0000-0000-0000000000a3', 'viewer'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '00000000-0000-0000-0000-0000000000b2', 'analyst');

insert into public.brands (id, tenant_id, name, keywords) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'SAMPLE Brand A', '{samplea}'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'SAMPLE Brand B', '{sampleb}');

insert into public.incidents (id, tenant_id, brand_id, channel, title, source, source_ref) values
  ('aaaaaaaa-1111-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaaaaaa-0000-0000-0000-000000000001', 'domain', 'SAMPLE lookalike A', 'crt.sh', 'cert-a-1'),
  ('bbbbbbbb-1111-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bbbbbbbb-0000-0000-0000-000000000001', 'domain', 'SAMPLE lookalike B', 'crt.sh', 'cert-b-1');

insert into public.evidence (id, tenant_id, incident_id, storage_path) values
  ('aaaaaaaa-2222-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaaaaaa-1111-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/sample.png');

-- ---------------------------------------------------------------------------
-- T1 Viewer A sees only tenant A data
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a3', true);
do $$ begin
  assert (select count(*) from public.incidents) = 1, 'T1 viewer A should see exactly 1 incident';
  assert (select count(*) from public.incidents where tenant_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') = 0, 'T1 viewer A must not see tenant B';
  assert (select count(*) from public.tenants) = 1, 'T1 viewer A should see 1 tenant';
  assert (select count(*) from public.brands) = 1, 'T1 viewer A should see 1 brand';
  raise notice 'PASS: T1 viewer A sees only tenant A rows';
end $$;
rollback;

-- T2 Viewer A cannot create incidents
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a3', true);
do $$ begin
  begin
    insert into public.incidents (tenant_id, channel, title, source, source_ref)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'domain', 'x', 'manual', 'v-1');
    raise exception 'T2 FAILED: viewer insert was allowed';
  exception when insufficient_privilege then
    raise notice 'PASS: T2 viewer cannot insert incidents';
  end;
end $$;
rollback;

-- T3 Analyst B cannot insert into tenant A
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', true);
do $$ begin
  begin
    insert into public.incidents (tenant_id, channel, title, source, source_ref)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'domain', 'x', 'manual', 'b-into-a');
    raise exception 'T3 FAILED: cross-tenant insert was allowed';
  exception when insufficient_privilege then
    raise notice 'PASS: T3 cross-tenant insert rejected';
  end;
end $$;
rollback;

-- T4 Analyst B cannot update or delete tenant A incidents
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', true);
do $$ declare n int; begin
  update public.incidents set status = 'resolved' where id = 'aaaaaaaa-1111-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 0, 'T4 cross-tenant update affected rows';
  delete from public.incidents where id = 'aaaaaaaa-1111-0000-0000-000000000001';
  get diagnostics n = row_count;
  assert n = 0, 'T4 cross-tenant delete affected rows';
  raise notice 'PASS: T4 cross-tenant update and delete affect 0 rows';
end $$;
rollback;

-- T5 Analyst B cannot move own incident into tenant A
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', true);
do $$ begin
  begin
    update public.incidents set tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    where id = 'bbbbbbbb-1111-0000-0000-000000000001';
    raise exception 'T5 FAILED: tenant_id change was allowed';
  exception when insufficient_privilege then
    raise notice 'PASS: T5 cannot move a row to another tenant';
  end;
end $$;
rollback;

-- T6 Analyst A can create incidents; duplicates are rejected; audit records actor
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', true);
do $$ begin
  insert into public.incidents (tenant_id, channel, title, source, source_ref)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'domain', 'SAMPLE new', 'crt.sh', 'cert-a-2');
  begin
    insert into public.incidents (tenant_id, channel, title, source, source_ref)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'domain', 'SAMPLE dup', 'crt.sh', 'cert-a-2');
    raise exception 'T6 FAILED: duplicate incident was allowed';
  exception when unique_violation then null;
  end;
  raise notice 'PASS: T6 analyst insert works and duplicates are rejected';
end $$;
reset role;
do $$ begin
  assert (select count(*) from public.audit_log
          where table_name = 'incidents' and action = 'INSERT'
            and actor_id = '00000000-0000-0000-0000-0000000000a2') = 1,
         'T6 audit row with actor id missing';
  raise notice 'PASS: T6 audit log records the acting user';
end $$;
rollback;

-- T7 Audit log: viewer cannot read, admin reads only own tenant
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a3', true);
do $$ begin
  assert (select count(*) from public.audit_log) = 0, 'T7 viewer can read audit log';
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
do $$ begin
  assert (select count(*) from public.audit_log) > 0, 'T7 admin sees no audit rows';
  assert (select count(*) from public.audit_log where tenant_id <> 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') = 0, 'T7 admin sees other tenant audit rows';
  raise notice 'PASS: T7 audit log readable by admin of own tenant only';
end $$;
rollback;

-- T8 Audit log is append-only, even for the database owner
begin;
do $$ begin
  begin
    update public.audit_log set action = 'DELETE';
    raise exception 'T8 FAILED: audit log update allowed';
  exception when raise_exception then
    if sqlerrm <> 'audit_log is append-only' then raise; end if;
    raise notice 'PASS: T8 audit log rejects updates';
  end;
end $$;
rollback;

-- T9 Admin A cannot add members to tenant B; viewer cannot raise own role
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
do $$ begin
  begin
    insert into public.tenant_members (tenant_id, user_id, role)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '00000000-0000-0000-0000-0000000000a1', 'owner');
    raise exception 'T9 FAILED: admin A joined tenant B';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a3', true);
do $$ declare n int; begin
  update public.tenant_members set role = 'owner' where user_id = '00000000-0000-0000-0000-0000000000a3';
  get diagnostics n = row_count;
  assert n = 0, 'T9 viewer escalated own role';
  raise notice 'PASS: T9 no cross-tenant membership and no self-escalation';
end $$;
rollback;

-- T10 Evidence cannot be edited after upload
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
do $$ declare n int; begin
  -- Either refused outright (no UPDATE privilege, migration 0005) or 0 rows (no RLS update policy)
  begin
    update public.evidence set storage_path = 'tampered' where id = 'aaaaaaaa-2222-0000-0000-000000000001';
    get diagnostics n = row_count;
    assert n = 0, 'T10 evidence was edited';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: T10 evidence is immutable';
end $$;
rollback;

-- T11 Anonymous (signed-out) users see nothing
begin;
set local role anon;
do $$ declare n int; begin
  -- Either refused outright (no privileges, migration 0005) or 0 rows (RLS)
  begin
    select count(*) into n from public.incidents;
    assert n = 0, 'T11 anon sees incidents';
  exception when insufficient_privilege then null;
  end;
  begin
    select count(*) into n from public.tenants;
    assert n = 0, 'T11 anon sees tenants';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: T11 signed-out users see no data';
end $$;
rollback;

-- T12 Service role (N8N) can write for any tenant
begin;
set local role service_role;
do $$ begin
  insert into public.incidents (tenant_id, channel, title, source, source_ref)
  values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'domain', 'SAMPLE n8n', 'crt.sh', 'cert-b-2');
  insert into public.alerts (tenant_id, incident_id, channel, recipient)
  values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bbbbbbbb-1111-0000-0000-000000000001', 'email', 'sample@example.invalid');
  raise notice 'PASS: T12 service role (N8N) can write incidents and alerts';
end $$;
rollback;

-- T13 A tenant can be fully deleted (offboarding) without errors
begin;
do $$ begin
  delete from public.tenants where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  assert (select count(*) from public.incidents where tenant_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') = 0, 'T13 incidents left behind';
  assert (select count(*) from public.audit_log where tenant_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') > 0, 'T13 audit history was lost';
  raise notice 'PASS: T13 tenant deletion cascades cleanly and keeps audit history';
end $$;
rollback;

-- T14 Admin cannot grant the owner role (to self or others)
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
do $$ begin
  begin
    update public.tenant_members set role = 'owner'
    where tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and user_id = '00000000-0000-0000-0000-0000000000a1';
    raise exception 'T14 FAILED: admin promoted self to owner';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.tenant_members set role = 'owner'
    where tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and user_id = '00000000-0000-0000-0000-0000000000a2';
    raise exception 'T14 FAILED: admin granted owner to another user';
  exception when insufficient_privilege then null;
  end;
  -- Admin can still manage normal roles
  update public.tenant_members set role = 'viewer'
  where tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and user_id = '00000000-0000-0000-0000-0000000000a2';
  assert found, 'T14 admin could not change a normal role';
  raise notice 'PASS: T14 only owners can grant the owner role';
end $$;
rollback;

\echo 'ALL TESTS PASSED'
