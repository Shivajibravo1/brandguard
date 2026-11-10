-- =============================================================================
-- BrandGuard by MySolution
-- Migration 0002: Certificate Transparency (CT) ingestion and rule-based scoring
--
-- N8N fetches certificates from crt.sh and passes them to
-- public.ingest_ct_certificates(). This function filters out brand-owned
-- certificates, scores the rest from 0 to 100 with plain-English reasons, and
-- creates incidents without duplicates. Only the service role (N8N) may call it.
--
-- Scoring is deliberately simple and explainable (rule-based). AI scoring is a
-- later phase and will write to the same columns.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Scan history (Dashboard scan chart and CT terminal)
-- -----------------------------------------------------------------------------
create table public.scan_runs (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.tenants(id) on delete cascade,
  brand_id              uuid references public.brands(id) on delete set null,
  source                text not null,
  started_at            timestamptz not null default now(),
  finished_at           timestamptz,
  certificates_checked  integer not null default 0 check (certificates_checked >= 0),
  candidates_found      integer not null default 0 check (candidates_found >= 0),
  new_incidents         integer not null default 0 check (new_incidents >= 0),
  status                text not null default 'running' check (status in ('running', 'success', 'failed')),
  error                 text
);
create index scan_runs_tenant_idx on public.scan_runs (tenant_id, started_at desc);

alter table public.scan_runs enable row level security;
create policy scan_runs_select on public.scan_runs for select to authenticated
  using (public.has_tenant_role(tenant_id, 'viewer'));

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------

-- Registered domain (the part someone actually buys), e.g.
--   login.brand-help.com   -> brand-help.com
--   shop.example.co.uk    -> example.co.uk
-- Simplified public suffix handling: a short list of common two-label suffixes.
-- Good enough for the demo; replace with a full Public Suffix List later.
create or replace function public.registered_domain(p_host text)
returns text
language sql
immutable
as $$
  with parts as (
    select string_to_array(lower(trim(both '.' from p_host)), '.') as p
  )
  select case
    when array_length(p, 1) is null or array_length(p, 1) < 2 then null
    when array_length(p, 1) >= 3
         and (p[array_length(p, 1) - 1] || '.' || p[array_length(p, 1)]) in (
           'co.uk','org.uk','ac.uk','com.au','net.au','org.au','co.nz','co.jp','co.kr','co.in','co.id',
           'co.za','co.il','co.th','com.br','com.mx','com.ar','com.tr','com.sg','com.hk','com.tw',
           'com.my','com.ph','com.sa','com.cn','com.pe','com.ve','com.co','com.eg','com.pk','com.ng',
           'ae.org','com.de')
      then array_to_string(p[array_length(p, 1) - 2 : array_length(p, 1)], '.')
    else array_to_string(p[array_length(p, 1) - 1 : array_length(p, 1)], '.')
  end
  from parts;
$$;

-- Is the host one of the brand's legitimate domains (or a subdomain of one)?
create or replace function public.is_legitimate_host(p_host text, p_legit text[])
returns boolean
language sql
immutable
as $$
  select exists (
    select 1 from unnest(p_legit) as l(d)
    where lower(p_host) = lower(l.d) or lower(p_host) like '%.' || lower(l.d)
  );
$$;

-- -----------------------------------------------------------------------------
-- Rule-based score for one candidate host
-- -----------------------------------------------------------------------------
create or replace function public.score_ct_candidate(
  p_host     text,
  p_keyword  text,
  p_issuer   text
)
returns table (risk_score smallint, severity public.severity_level, category text, explanation text)
language plpgsql
immutable
as $$
declare
  v_host     text := lower(p_host);
  v_reg      text := public.registered_domain(p_host);
  v_label    text := split_part(public.registered_domain(p_host), '.', 1);
  v_score    integer := 20;
  v_reasons  text[] := '{}';
  v_category text := 'lookalike_domain';
  v_free_hosting boolean;
  v_issuer   text := coalesce(p_issuer, '');
begin
  -- Free hosting and app platforms: anyone can publish under these in minutes
  v_free_hosting := v_reg in (
    'pages.dev','workers.dev','netlify.app','vercel.app','github.io','web.app','firebaseapp.com',
    'hosted.app','glitch.me','onrender.com','herokuapp.com','weebly.com','wixsite.com','blogspot.com',
    'azurewebsites.net','appspot.com','ngrok-free.app','repl.co','surge.sh','framer.app');

  if v_free_hosting then
    v_score := v_score + 45;
    v_category := 'free_hosting_impersonation';
    v_reasons := array_append(v_reasons, format('Brand name used on the free hosting platform %s, where anyone can publish a page in minutes.', v_reg));
  elsif position(p_keyword in v_reg) = 0 then
    v_score := v_score + 40;
    v_category := 'brand_in_subdomain';
    v_reasons := array_append(v_reasons, format('Brand name appears only in a subdomain of the unrelated domain %s.', v_reg));
  elsif v_label = p_keyword then
    v_score := v_score + 5;
    v_category := 'exact_name_other_tld';
    v_reasons := array_append(v_reasons, format('Exact brand name on another domain ending (%s). Brands often register these themselves; confirm the owner.', v_reg));
  else
    v_score := v_score + 25;
    v_category := 'combosquatting';
    v_reasons := array_append(v_reasons, format('Registered domain %s combines the brand name with other words (combosquatting).', v_reg));
  end if;

  -- Words typical of phishing pages
  if v_host ~ '(login|log-in|signin|sign-in|verify|verification|secure|account|support|update|limited|checkout|billing|refund|retoure|wallet|unlock|confirm|helpdesk|resolution|recover|suspend)' then
    v_score := v_score + 15;
    v_reasons := array_append(v_reasons, 'Host name contains words typical of phishing pages (for example login, verify, support, refund).');
  end if;

  -- Unusual host shapes often seen in phishing kits
  if v_host ~ '--' or v_host ~ '[0-9]{6,}' then
    v_score := v_score + 10;
    v_reasons := array_append(v_reasons, 'Host name has an unusual pattern (double hyphen or long number) common in throwaway phishing hosts.');
  end if;

  -- Certificate authority signal
  if v_issuer ~* '(let''s encrypt|zerossl|google trust services|cpanel|ssl corporation|buypass)' then
    v_score := v_score + 10;
    v_reasons := array_append(v_reasons, 'Certificate is from a free or low-cost certificate authority that issues automatically.');
  elsif v_issuer ~* '(digicert|entrust|globalsign)' and not v_free_hosting then
    v_score := v_score - 20;
    v_reasons := array_append(v_reasons, 'Certificate is from a paid certificate authority commonly used by large organisations, which lowers the likelihood of phishing.');
  end if;

  v_score := greatest(0, least(100, v_score));

  risk_score  := v_score;
  severity    := case
                   when v_score >= 80 then 'critical'
                   when v_score >= 60 then 'high'
                   when v_score >= 40 then 'medium'
                   when v_score >= 20 then 'low'
                   else 'info'
                 end;
  category    := v_category;
  explanation := array_to_string(v_reasons, ' ');
  return next;
end;
$$;

-- -----------------------------------------------------------------------------
-- Ingest a batch of crt.sh certificates for one brand
--
-- p_certs: JSON array of crt.sh rows, each with at least
--   id, issuer_name, name_value (newline-separated host names), not_before
-- Returns the incidents created by this call (for alerting).
-- -----------------------------------------------------------------------------
create or replace function public.ingest_ct_certificates(p_brand_id uuid, p_certs jsonb)
returns table (tenant_id uuid, incident_id uuid, asset text, risk_score smallint, severity public.severity_level, explanation text)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_brand        public.brands%rowtype;
  v_run_id       uuid;
  v_cert         jsonb;
  v_names        text[];
  v_host         text;
  v_keyword      text;
  v_asset        text;
  v_reg          text;
  v_checked      integer := 0;
  v_candidates   integer := 0;
  v_new          integer := 0;
  v_score        record;
  v_incident_id  uuid;
begin
  select * into v_brand from public.brands where id = p_brand_id and is_active;
  if not found then
    raise exception 'Brand % not found or inactive', p_brand_id;
  end if;
  if jsonb_typeof(p_certs) <> 'array' then
    raise exception 'p_certs must be a JSON array';
  end if;

  insert into public.scan_runs (tenant_id, brand_id, source)
  values (v_brand.tenant_id, v_brand.id, 'crt.sh')
  returning id into v_run_id;

  for v_cert in select value from jsonb_array_elements(p_certs) loop
    v_checked := v_checked + 1;

    select array_agg(distinct regexp_replace(lower(trim(n)), '^\*\.', ''))
      into v_names
      from unnest(string_to_array(coalesce(v_cert ->> 'name_value', ''), E'\n')) as n
     where trim(n) like '%.%';

    if v_names is null then continue; end if;

    -- A certificate that also covers a legitimate brand domain is brand-owned
    if exists (select 1 from unnest(v_names) h where public.is_legitimate_host(h, v_brand.legitimate_domains)) then
      continue;
    end if;

    foreach v_host in array v_names loop
      select k into v_keyword from unnest(v_brand.keywords) k where position(lower(k) in v_host) > 0 limit 1;
      if v_keyword is null then continue; end if;

      v_reg := public.registered_domain(v_host);
      if v_reg is null or public.is_legitimate_host(v_reg, v_brand.legitimate_domains) then continue; end if;

      -- The asset to act on: the registered domain when the brand is in it,
      -- otherwise the exact host (free hosting, or brand only in a subdomain)
      v_asset := case when position(lower(v_keyword) in v_reg) > 0
                       and v_reg not in ('pages.dev','workers.dev','netlify.app','vercel.app','github.io','web.app',
                                         'firebaseapp.com','hosted.app','glitch.me','onrender.com','herokuapp.com',
                                         'weebly.com','wixsite.com','blogspot.com','azurewebsites.net','appspot.com',
                                         'ngrok-free.app','repl.co','surge.sh','framer.app')
                      then v_reg else v_host end;

      v_candidates := v_candidates + 1;
      select * into v_score from public.score_ct_candidate(v_asset, lower(v_keyword), v_cert ->> 'issuer_name');

      insert into public.incidents (
        tenant_id, brand_id, channel, title, source, source_ref, severity, status,
        risk_score, score_category, score_explanation, scored_at, details
      ) values (
        v_brand.tenant_id, v_brand.id, 'domain',
        'Lookalike certificate: ' || v_asset, 'crt.sh', v_asset, v_score.severity, 'new',
        v_score.risk_score, v_score.category, v_score.explanation, now(),
        jsonb_build_object(
          'host', v_host,
          'crtsh_id', v_cert -> 'id',
          'crtsh_url', 'https://crt.sh/?id=' || (v_cert ->> 'id'),
          'issuer', v_cert ->> 'issuer_name',
          'not_before', v_cert ->> 'not_before',
          'scoring', 'rule-based v1')
      )
      on conflict (tenant_id, channel, source, source_ref) do nothing
      returning id into v_incident_id;

      if v_incident_id is not null then
        v_new := v_new + 1;
        insert into public.domains (tenant_id, brand_id, incident_id, domain, tld, similarity, cert_issuer, cert_not_before, status)
        values (
          v_brand.tenant_id, v_brand.id, v_incident_id, v_asset,
          substring(v_asset from '\.([a-z0-9-]+)$'),
          v_score.risk_score,
          v_cert ->> 'issuer_name',
          (v_cert ->> 'not_before')::timestamptz,
          case when v_score.risk_score >= 60 then 'flagged' else 'watching' end
        )
        on conflict (tenant_id, domain) do update set last_seen_at = now();

        tenant_id   := v_brand.tenant_id;
        incident_id := v_incident_id;
        asset       := v_asset;
        risk_score  := v_score.risk_score;
        severity    := v_score.severity;
        explanation := v_score.explanation;
        return next;
      else
        update public.domains d set last_seen_at = now()
         where d.tenant_id = v_brand.tenant_id and d.domain = v_asset;
      end if;
      v_incident_id := null;
    end loop;
  end loop;

  update public.scan_runs
     set finished_at = now(), certificates_checked = v_checked, candidates_found = v_candidates,
         new_incidents = v_new, status = 'success'
   where id = v_run_id;
end;
$$;

-- Record a failed scan (called by N8N when crt.sh is unreachable)
create or replace function public.record_scan_failure(p_brand_id uuid, p_source text, p_error text)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.scan_runs (tenant_id, brand_id, source, finished_at, status, error)
  select tenant_id, id, p_source, now(), 'failed', left(p_error, 2000)
  from public.brands where id = p_brand_id;
$$;

-- Only N8N (service role) may run ingestion; signed-in users and visitors may not
revoke execute on function public.ingest_ct_certificates(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.record_scan_failure(uuid, text, text) from public, anon, authenticated;
grant  execute on function public.ingest_ct_certificates(uuid, jsonb) to service_role;
grant  execute on function public.record_scan_failure(uuid, text, text) to service_role;
