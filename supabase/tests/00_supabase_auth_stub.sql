-- =============================================================================
-- LOCAL TEST ONLY. Do not run on Supabase.
-- Minimal stand-in for the Supabase auth layer so migrations can be tested in
-- a plain PostgreSQL container: roles, auth.users, auth.uid(), default grants.
-- =============================================================================
-- Roles are cluster-wide, so create them only if missing (safe to rerun)
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon')          then create role anon          nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role')  then create role service_role  nologin noinherit bypassrls; end if;
end $$;

create schema auth;
create table auth.users (id uuid primary key);

-- Supabase reads the user id from the JWT (JSON Web Token) "sub" claim
create function auth.uid() returns uuid
language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

grant usage on schema auth   to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;

-- Supabase grants table privileges to these roles; RLS is what restricts them
alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
