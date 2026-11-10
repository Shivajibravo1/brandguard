-- =============================================================================
-- BrandGuard by MySolution
-- Migration 0003: official brand assets (customer onboarding)
--
-- The customer enters the assets they officially own, per brand:
--   website       official website domains, e.g. examplebank.in
--   email_domain  domains they send email from, e.g. examplebank.in
--   mobile_app    official apps in the Apple App Store or Google Play
--   social        official social media accounts
--
-- BrandGuard uses these two ways:
--   1. As the "known good" list: findings on these assets are never alerted.
--   2. As the starting point for searching lookalikes on each channel.
--
-- brands.legitimate_domains is kept in step automatically with the website
-- and email domain assets, so the existing crt.sh ingestion keeps working.
-- =============================================================================

create type public.brand_asset_type as enum ('website', 'email_domain', 'mobile_app', 'social');

-- Lets brand_assets reference (brand id, tenant id) together, so an asset can
-- never be attached to another tenant's brand.
alter table public.brands add constraint brands_id_tenant_uk unique (id, tenant_id);

create table public.brand_assets (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null,
  brand_id    uuid not null,
  asset_type  public.brand_asset_type not null,
  -- website and email_domain: the domain (lower case, no https:// or www.)
  -- mobile_app: the store app id (Apple numeric id, or Google package name)
  -- social: the account handle without @
  value       text not null check (length(trim(value)) > 0 and length(value) <= 255),
  -- mobile_app: apple | google. social: x | instagram | facebook | linkedin |
  -- tiktok | youtube | telegram | snapchat. Empty for domains.
  platform    text not null default '',
  label       text check (label is null or length(label) <= 200),        -- e.g. app name or page name
  publisher   text check (publisher is null or length(publisher) <= 200), -- official app developer name
  created_at  timestamptz not null default now(),
  foreign key (brand_id, tenant_id) references public.brands (id, tenant_id) on delete cascade,
  unique (brand_id, asset_type, platform, value),

  constraint brand_assets_domain_format check (
    asset_type not in ('website', 'email_domain')
    or (platform = '' and value ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{1,62}$')
  ),
  constraint brand_assets_app_format check (
    asset_type <> 'mobile_app'
    or (platform = 'apple' and value ~ '^[0-9]{5,12}$')
    or (platform = 'google' and value ~ '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$')
  ),
  constraint brand_assets_social_format check (
    asset_type <> 'social'
    or (platform in ('x', 'instagram', 'facebook', 'linkedin', 'tiktok', 'youtube', 'telegram', 'snapchat')
        and value ~ '^[A-Za-z0-9._-]{1,100}$')
  )
);
create index brand_assets_tenant_idx on public.brand_assets (tenant_id, brand_id);

-- Normalise input before the format checks run: trim, lower-case domains,
-- strip https://, www. and paths from domains, strip @ from handles.
create or replace function public.normalise_brand_asset()
returns trigger
language plpgsql
as $$
begin
  new.value := trim(new.value);
  new.platform := lower(trim(coalesce(new.platform, '')));
  if new.asset_type in ('website', 'email_domain') then
    new.value := lower(new.value);
    new.value := regexp_replace(new.value, '^[a-z]+://', '');
    new.value := regexp_replace(new.value, '[/?#:].*$', '');
    new.value := regexp_replace(new.value, '^www\.', '');
    new.value := trim(both '.' from new.value);
  elsif new.asset_type = 'social' then
    new.value := regexp_replace(new.value, '^@', '');
  end if;
  new.label := nullif(trim(new.label), '');
  new.publisher := nullif(trim(new.publisher), '');
  return new;
end;
$$;

create trigger brand_assets_normalise
  before insert or update on public.brand_assets
  for each row execute function public.normalise_brand_asset();

-- Keep brands.legitimate_domains equal to the brand's website and email
-- domain assets, so detection never alerts on the customer's own domains.
create or replace function public.sync_brand_legitimate_domains()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_brand_id uuid;
begin
  for v_brand_id in
    select distinct b from unnest(array[
      case when tg_op in ('UPDATE', 'DELETE') then old.brand_id end,
      case when tg_op in ('INSERT', 'UPDATE') then new.brand_id end]) as b
    where b is not null
  loop
    update public.brands
       set legitimate_domains = coalesce((
             select array_agg(distinct a.value order by a.value)
               from public.brand_assets a
              where a.brand_id = v_brand_id
                and a.asset_type in ('website', 'email_domain')), '{}')
     where id = v_brand_id;
  end loop;
  return null;
end;
$$;

create trigger brand_assets_sync_domains
  after insert or update or delete on public.brand_assets
  for each row execute function public.sync_brand_legitimate_domains();

create trigger audit_brand_assets
  after insert or update or delete on public.brand_assets
  for each row execute function public.write_audit_log();

-- Row Level Security: members read, admins and owners manage
alter table public.brand_assets enable row level security;

create policy brand_assets_select on public.brand_assets for select to authenticated
  using (public.has_tenant_role(tenant_id, 'viewer'));
create policy brand_assets_write on public.brand_assets for all to authenticated
  using (public.has_tenant_role(tenant_id, 'admin'))
  with check (public.has_tenant_role(tenant_id, 'admin'));

grant select, insert, update, delete on public.brand_assets to authenticated;
