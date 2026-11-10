-- =============================================================================
-- BrandGuard by MySolution
-- Migration 0001: initial multi-tenant schema with Row Level Security (RLS)
--
-- STATUS: DRAFT FOR OWNER REVIEW. Do not run until approved.
--
-- Tenant isolation model:
--   * Every business table carries tenant_id.
--   * A signed-in user sees a row only if they are a member of that tenant
--     (table tenant_members). Cross-tenant reads return no rows; cross-tenant
--     writes are rejected by RLS.
--   * N8N workflows use the Supabase service role key, which bypasses RLS.
--     Workflows must always take tenant_id from the brands table.
--
-- Roles (per tenant): owner > admin > analyst > viewer
--   viewer  : read
--   analyst : read, create and update incidents, takedowns, evidence
--   admin   : analyst rights plus manage brands, executives, members, deletes
--   owner   : admin rights plus manage the tenant record
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Enumerated types
-- -----------------------------------------------------------------------------
create type public.tenant_role      as enum ('owner', 'admin', 'analyst', 'viewer');
create type public.threat_channel   as enum ('domain', 'social', 'app', 'email');
create type public.severity_level   as enum ('critical', 'high', 'medium', 'low', 'info');
create type public.incident_status  as enum ('new', 'investigating', 'takedown', 'monitoring', 'resolved', 'false_positive');
create type public.alert_channel    as enum ('email', 'teams', 'sms', 'slack');
create type public.alert_status     as enum ('pending', 'sent', 'failed');
create type public.takedown_status  as enum ('draft', 'submitted', 'acknowledged', 'in_progress', 'completed', 'rejected');

-- -----------------------------------------------------------------------------
-- Tenants and membership
-- -----------------------------------------------------------------------------
create table public.tenants (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(trim(name)) > 0),
  plan        text not null default 'starter' check (plan in ('starter', 'professional', 'enterprise', 'managed')),
  created_at  timestamptz not null default now()
);

create table public.tenant_members (
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  role        public.tenant_role not null default 'viewer',
  created_at  timestamptz not null default now(),
  primary key (tenant_id, user_id)
);
create index tenant_members_user_idx on public.tenant_members (user_id);

-- Helper: does the current user hold at least min_role in the tenant?
-- SECURITY DEFINER so it can read tenant_members without recursive RLS checks.
create or replace function public.has_tenant_role(p_tenant_id uuid, p_min_role public.tenant_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.tenant_members m
    where m.tenant_id = p_tenant_id
      and m.user_id = auth.uid()
      -- enum order is owner, admin, analyst, viewer: lower ordinal = more rights
      and m.role <= p_min_role
  );
$$;

-- -----------------------------------------------------------------------------
-- Brands and executives (watchlist configuration)
-- -----------------------------------------------------------------------------
create table public.brands (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.tenants(id) on delete cascade,
  name                text not null check (length(trim(name)) > 0),
  keywords            text[] not null default '{}',   -- terms searched in crt.sh and feeds
  legitimate_domains  text[] not null default '{}',   -- owned domains, excluded from alerts
  social_handles      jsonb  not null default '{}'::jsonb,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  unique (tenant_id, name)
);
create index brands_tenant_idx on public.brands (tenant_id);

create table public.executives (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  brand_id        uuid references public.brands(id) on delete set null,
  full_name       text not null,
  job_title       text,
  social_handles  jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now()
);
create index executives_tenant_idx on public.executives (tenant_id);

-- -----------------------------------------------------------------------------
-- Incidents (one row per detected impersonation finding)
-- -----------------------------------------------------------------------------
create table public.incidents (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.tenants(id) on delete cascade,
  brand_id           uuid references public.brands(id) on delete set null,
  channel            public.threat_channel not null,
  title              text not null,
  source             text not null,                 -- e.g. 'crt.sh', 'urlhaus', 'manual'
  source_ref         text not null,                 -- dedupe key from the source, e.g. certificate id or domain
  severity           public.severity_level not null default 'medium',
  status             public.incident_status not null default 'new',
  risk_score         smallint check (risk_score between 0 and 100),  -- null until AI scoring runs
  score_category     text,
  score_explanation  text,
  score_confidence   numeric(4,3) check (score_confidence between 0 and 1),
  scored_at          timestamptz,
  details            jsonb not null default '{}'::jsonb,
  detected_at        timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  -- Prevents duplicate incidents when N8N re-polls the same source
  unique (tenant_id, channel, source, source_ref)
);
create index incidents_tenant_detected_idx on public.incidents (tenant_id, detected_at desc);
create index incidents_tenant_status_idx   on public.incidents (tenant_id, status);

-- -----------------------------------------------------------------------------
-- Lookalike domains (Domains view)
-- -----------------------------------------------------------------------------
create table public.domains (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  brand_id         uuid references public.brands(id) on delete set null,
  incident_id      uuid references public.incidents(id) on delete set null,
  domain           text not null,
  tld              text,
  similarity       smallint check (similarity between 0 and 100),
  registered_at    timestamptz,
  registrar        text,
  cert_issuer      text,
  cert_not_before  timestamptz,
  hosting_ip       inet,
  status           text not null default 'watching' check (status in ('watching', 'flagged', 'takedown', 'removed', 'cleared')),
  first_seen_at    timestamptz not null default now(),
  last_seen_at     timestamptz not null default now(),
  unique (tenant_id, domain)
);
create index domains_tenant_idx on public.domains (tenant_id);

-- -----------------------------------------------------------------------------
-- Alerts (delivery log for notifications)
-- -----------------------------------------------------------------------------
create table public.alerts (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants(id) on delete cascade,
  incident_id  uuid not null references public.incidents(id) on delete cascade,
  channel      public.alert_channel not null,
  recipient    text not null,
  status       public.alert_status not null default 'pending',
  error        text,
  sent_at      timestamptz,
  created_at   timestamptz not null default now()
);
create index alerts_tenant_idx on public.alerts (tenant_id, created_at desc);

-- -----------------------------------------------------------------------------
-- Takedowns and evidence
-- -----------------------------------------------------------------------------
create table public.takedowns (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  incident_id    uuid not null references public.incidents(id) on delete cascade,
  target         text not null,                 -- domain, profile URL or app id
  provider       text,                          -- registrar, platform or store
  status         public.takedown_status not null default 'draft',
  notes          text,
  created_by     uuid references auth.users(id) on delete set null,
  submitted_at   timestamptz,
  resolved_at    timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index takedowns_tenant_idx on public.takedowns (tenant_id, status);

create table public.evidence (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants(id) on delete cascade,
  incident_id   uuid not null references public.incidents(id) on delete cascade,
  takedown_id   uuid references public.takedowns(id) on delete set null,
  storage_path  text not null,                  -- path in Supabase Storage, prefixed by tenant_id
  sha256        text check (sha256 ~ '^[0-9a-f]{64}$'),
  description   text,
  uploaded_by   uuid references auth.users(id) on delete set null,
  captured_at   timestamptz not null default now()
);
create index evidence_tenant_idx on public.evidence (tenant_id, incident_id);

-- -----------------------------------------------------------------------------
-- DMARC aggregate report rows (Phase 3, created now so the schema is stable)
-- -----------------------------------------------------------------------------
create table public.dmarc_reports (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  domain         text not null,
  reporter_org   text not null,
  report_id      text not null,
  date_begin     timestamptz not null,
  date_end       timestamptz not null,
  source_ip      inet not null,
  message_count  integer not null check (message_count >= 0),
  disposition    text,
  dkim_result    text,
  spf_result     text,
  received_at    timestamptz not null default now(),
  unique (tenant_id, reporter_org, report_id, source_ip)
);
create index dmarc_reports_tenant_idx on public.dmarc_reports (tenant_id, domain, date_begin desc);

-- -----------------------------------------------------------------------------
-- Audit log (append-only)
-- -----------------------------------------------------------------------------
create table public.audit_log (
  id          bigint generated always as identity primary key,
  -- No foreign key on purpose: audit history is kept after a tenant is deleted
  -- (regulatory evidence), and the append-only rule would block a cascade.
  tenant_id   uuid not null,
  actor_id    uuid,                              -- null when the change came from N8N (service role)
  table_name  text not null,
  row_id      uuid,
  action      text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  old_data    jsonb,
  new_data    jsonb,
  created_at  timestamptz not null default now()
);
create index audit_log_tenant_idx on public.audit_log (tenant_id, created_at desc);

create or replace function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row jsonb := to_jsonb(coalesce(new, old));
begin
  insert into public.audit_log (tenant_id, actor_id, table_name, row_id, action, old_data, new_data)
  values (
    (v_row ->> 'tenant_id')::uuid,
    auth.uid(),
    tg_table_name,
    case when v_row ? 'id' then (v_row ->> 'id')::uuid end,
    tg_op,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end
  );
  return coalesce(new, old);
end;
$$;

create trigger audit_incidents      after insert or update or delete on public.incidents      for each row execute function public.write_audit_log();
create trigger audit_takedowns      after insert or update or delete on public.takedowns      for each row execute function public.write_audit_log();
create trigger audit_evidence       after insert or update or delete on public.evidence       for each row execute function public.write_audit_log();
create trigger audit_tenant_members after insert or update or delete on public.tenant_members for each row execute function public.write_audit_log();
create trigger audit_brands         after insert or update or delete on public.brands         for each row execute function public.write_audit_log();

-- Block edits to the audit log for everyone, including the service role
create or replace function public.block_audit_log_change()
returns trigger
language plpgsql
as $$
begin
  raise exception 'audit_log is append-only';
end;
$$;

create trigger audit_log_immutable
  before update or delete on public.audit_log
  for each row execute function public.block_audit_log_change();

-- -----------------------------------------------------------------------------
-- updated_at maintenance
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger incidents_updated_at before update on public.incidents for each row execute function public.set_updated_at();
create trigger takedowns_updated_at before update on public.takedowns for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------
alter table public.tenants        enable row level security;
alter table public.tenant_members enable row level security;
alter table public.brands         enable row level security;
alter table public.executives     enable row level security;
alter table public.incidents      enable row level security;
alter table public.domains        enable row level security;
alter table public.alerts         enable row level security;
alter table public.takedowns      enable row level security;
alter table public.evidence       enable row level security;
alter table public.dmarc_reports  enable row level security;
alter table public.audit_log      enable row level security;

-- tenants
create policy tenants_select on public.tenants for select to authenticated
  using (public.has_tenant_role(id, 'viewer'));
create policy tenants_update on public.tenants for update to authenticated
  using (public.has_tenant_role(id, 'owner'))
  with check (public.has_tenant_role(id, 'owner'));
-- Tenant creation happens through onboarding (service role) in Phase 3.

-- tenant_members
-- Admins manage members, but only an owner can grant, change or remove the owner role.
create policy members_select on public.tenant_members for select to authenticated
  using (public.has_tenant_role(tenant_id, 'viewer'));
create policy members_insert on public.tenant_members for insert to authenticated
  with check (public.has_tenant_role(tenant_id, 'admin')
              and (role <> 'owner' or public.has_tenant_role(tenant_id, 'owner')));
create policy members_update on public.tenant_members for update to authenticated
  using (public.has_tenant_role(tenant_id, 'admin')
         and (role <> 'owner' or public.has_tenant_role(tenant_id, 'owner')))
  with check (public.has_tenant_role(tenant_id, 'admin')
              and (role <> 'owner' or public.has_tenant_role(tenant_id, 'owner')));
create policy members_delete on public.tenant_members for delete to authenticated
  using (public.has_tenant_role(tenant_id, 'admin')
         and (role <> 'owner' or public.has_tenant_role(tenant_id, 'owner')));

-- Configuration tables: read for members, write for admins
create policy brands_select on public.brands for select to authenticated using (public.has_tenant_role(tenant_id, 'viewer'));
create policy brands_write  on public.brands for all    to authenticated
  using (public.has_tenant_role(tenant_id, 'admin')) with check (public.has_tenant_role(tenant_id, 'admin'));

create policy executives_select on public.executives for select to authenticated using (public.has_tenant_role(tenant_id, 'viewer'));
create policy executives_write  on public.executives for all    to authenticated
  using (public.has_tenant_role(tenant_id, 'admin')) with check (public.has_tenant_role(tenant_id, 'admin'));

-- Operational tables: read for members, insert and update for analysts, delete for admins
create policy incidents_select on public.incidents for select to authenticated using (public.has_tenant_role(tenant_id, 'viewer'));
create policy incidents_insert on public.incidents for insert to authenticated with check (public.has_tenant_role(tenant_id, 'analyst'));
create policy incidents_update on public.incidents for update to authenticated
  using (public.has_tenant_role(tenant_id, 'analyst')) with check (public.has_tenant_role(tenant_id, 'analyst'));
create policy incidents_delete on public.incidents for delete to authenticated using (public.has_tenant_role(tenant_id, 'admin'));

create policy domains_select on public.domains for select to authenticated using (public.has_tenant_role(tenant_id, 'viewer'));
create policy domains_insert on public.domains for insert to authenticated with check (public.has_tenant_role(tenant_id, 'analyst'));
create policy domains_update on public.domains for update to authenticated
  using (public.has_tenant_role(tenant_id, 'analyst')) with check (public.has_tenant_role(tenant_id, 'analyst'));
create policy domains_delete on public.domains for delete to authenticated using (public.has_tenant_role(tenant_id, 'admin'));

create policy takedowns_select on public.takedowns for select to authenticated using (public.has_tenant_role(tenant_id, 'viewer'));
create policy takedowns_insert on public.takedowns for insert to authenticated with check (public.has_tenant_role(tenant_id, 'analyst'));
create policy takedowns_update on public.takedowns for update to authenticated
  using (public.has_tenant_role(tenant_id, 'analyst')) with check (public.has_tenant_role(tenant_id, 'analyst'));
create policy takedowns_delete on public.takedowns for delete to authenticated using (public.has_tenant_role(tenant_id, 'admin'));

create policy evidence_select on public.evidence for select to authenticated using (public.has_tenant_role(tenant_id, 'viewer'));
create policy evidence_insert on public.evidence for insert to authenticated with check (public.has_tenant_role(tenant_id, 'analyst'));
create policy evidence_delete on public.evidence for delete to authenticated using (public.has_tenant_role(tenant_id, 'admin'));
-- No update policy on evidence: evidence is immutable once uploaded.

-- Written only by N8N (service role); read-only for users
create policy alerts_select        on public.alerts        for select to authenticated using (public.has_tenant_role(tenant_id, 'viewer'));
create policy dmarc_reports_select on public.dmarc_reports for select to authenticated using (public.has_tenant_role(tenant_id, 'viewer'));

-- Audit log: admins can read; nobody writes directly (trigger only)
create policy audit_log_select on public.audit_log for select to authenticated using (public.has_tenant_role(tenant_id, 'admin'));
