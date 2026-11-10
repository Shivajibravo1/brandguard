-- =============================================================================
-- BrandGuard by MySolution
-- Migration 0004: lookalike domain monitoring (website monitor)
--
-- The scanner service (dnstwist) generates lookalike names for each official
-- website domain, keeps the registered ones and adds evidence: DNS records,
-- registration date, and what the home page shows. N8N passes one scan result
-- per official domain to public.ingest_lookalike_domains(), which scores each
-- lookalike from 0 to 100 with plain-English reasons and creates or updates
-- incidents. Only the service role (N8N) may call it.
--
-- Re-scans keep evidence and scores current. An open incident is reported for
-- alerting again only when its risk score rises by 10 points or more (for
-- example a parked domain that starts showing a login page).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Registered domain: add Indian second-level endings. Indian banks are moving
-- to the bank-only ending .bank.in (for example examplesfb.bank.in), so
-- "bank.in" must be treated as an ending, not as the bank's own domain.
-- -----------------------------------------------------------------------------
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
           'ae.org','com.de',
           'bank.in','fin.in','net.in','org.in','firm.in','gen.in','ind.in','gov.in','nic.in','ac.in','edu.in','res.in')
      then array_to_string(p[array_length(p, 1) - 2 : array_length(p, 1)], '.')
    else array_to_string(p[array_length(p, 1) - 1 : array_length(p, 1)], '.')
  end
  from parts;
$$;

-- -----------------------------------------------------------------------------
-- Rule-based score for one registered lookalike domain
--
-- p_row: one item of the scanner's "registered" list, for example
--   {"domain": "emlratesnbd.com", "fuzzer": "homoglyph", "dns_a": ["1.2.3.4"],
--    "dns_mx": ["mx.example.net"], "whois_created": "2026-10-01",
--    "web_live": true, "web_final_host": "emlratesnbd.com",
--    "web_parked": false, "web_mentions_brand": true, "web_password_field": true}
-- -----------------------------------------------------------------------------
create or replace function public.score_lookalike_domain(
  p_row       jsonb,
  p_official  text[],
  p_as_of     date default current_date
)
returns table (risk_score smallint, severity public.severity_level, category text, explanation text)
language plpgsql
immutable
as $$
declare
  v_domain     text := lower(p_row ->> 'domain');
  v_fuzzer     text := coalesce(p_row ->> 'fuzzer', '');
  v_has_web    boolean := jsonb_array_length(coalesce(p_row -> 'dns_a', '[]')) + jsonb_array_length(coalesce(p_row -> 'dns_aaaa', '[]')) > 0;
  v_has_mx     boolean := jsonb_array_length(coalesce(p_row -> 'dns_mx', '[]')) > 0;
  v_live       boolean := coalesce((p_row ->> 'web_live')::boolean, false);
  v_final_host text := lower(nullif(p_row ->> 'web_final_host', ''));
  v_parked     boolean := coalesce((p_row ->> 'web_parked')::boolean, false);
  v_mentions   boolean := coalesce((p_row ->> 'web_mentions_brand')::boolean, false);
  v_password   boolean := coalesce((p_row ->> 'web_password_field')::boolean, false);
  v_created    date;
  v_redirects_official boolean;
  v_score      integer := 25;
  v_reasons    text[] := '{}';
  v_category   text;
begin
  begin
    v_created := (p_row ->> 'whois_created')::date;
  exception when others then
    v_created := null;
  end;
  v_redirects_official := v_live and v_final_host is not null
                          and v_final_host <> v_domain
                          and public.is_legitimate_host(v_final_host, p_official);

  -- How the name was made
  if v_fuzzer in ('homoglyph', 'cyrillic') then
    v_score := v_score + 20;
    v_category := 'homoglyph';
    v_reasons := array_append(v_reasons, 'Uses look-alike characters, so it is very hard to tell apart from your domain.');
  elsif v_fuzzer = 'dictionary' then
    v_score := v_score + 15;
    v_category := 'combosquatting';
    v_reasons := array_append(v_reasons, 'Combines your brand with an extra word (for example login, online or support), a common phishing pattern.');
  elsif v_fuzzer = 'subdomain' then
    v_score := v_score - 10;
    v_category := 'unrelated_parent_domain';
    v_reasons := array_append(v_reasons, format('The name sits under the separate domain %s, which may belong to an unrelated owner. Usually a coincidence; check before acting.', public.registered_domain(v_domain)));
  elsif v_fuzzer = 'tld-swap' then
    v_score := v_score + 5;
    v_category := 'other_domain_ending';
    v_reasons := array_append(v_reasons, format('Same name on another domain ending (.%s). Brands often register these themselves; confirm the owner.', split_part(v_domain, '.', -1)));
  else
    v_score := v_score + 10;
    v_category := 'typosquatting';
    v_reasons := array_append(v_reasons, format('A small typing mistake away from your domain (%s).', replace(nullif(v_fuzzer, ''), '-', ' ')));
  end if;

  -- What the website shows
  if v_redirects_official then
    v_score := v_score - 45;
    v_category := 'brand_owned_redirect';
    v_reasons := array_append(v_reasons, format('Redirects to your official site %s, so it is most likely owned by you (a defensive registration). Confirm and mark it as a false positive.', v_final_host));
  else
    if v_password then
      v_score := v_score + 25;
      v_category := 'possible_phishing_page';
      v_reasons := array_append(v_reasons, 'The home page shows a password field: possible fake login page.');
    end if;
    if v_live and v_mentions and not v_parked then
      v_score := v_score + 15;
      v_reasons := array_append(v_reasons, 'The live website mentions your brand name.');
    end if;
    if v_parked then
      v_score := v_score - 15;
      if v_category not in ('possible_phishing_page') then v_category := 'parked_lookalike'; end if;
      v_reasons := array_append(v_reasons, 'Shows a parked or "for sale" page. Not active now, but it could be switched on at any time.');
    elsif v_live and not v_mentions and not v_password then
      v_score := v_score + 5;
      v_reasons := array_append(v_reasons, 'A website is live on this domain.');
    end if;
  end if;

  -- Email capability
  if v_has_mx and not v_redirects_official then
    v_score := v_score + 15;
    v_reasons := array_append(v_reasons, 'Has mail servers (MX records), so it can send and receive email that looks like it comes from you.');
  end if;

  if not v_has_web and not v_has_mx then
    v_score := v_score - 10;
    v_reasons := array_append(v_reasons, 'Registered, but has no website or mail server yet.');
  end if;

  -- Age of the registration
  if v_created is not null then
    if v_created >= p_as_of - 90 then
      v_score := v_score + 20;
      v_reasons := array_append(v_reasons, format('Registered recently (%s). New lookalikes are the most likely to be used in attacks.', v_created));
    elsif v_created >= p_as_of - 365 then
      v_score := v_score + 10;
      v_reasons := array_append(v_reasons, format('Registered within the last year (%s).', v_created));
    elsif v_created < p_as_of - 1826 then
      v_score := v_score - 5;
      v_reasons := array_append(v_reasons, format('Registered more than 5 years ago (%s), which lowers the likelihood of an active campaign.', v_created));
    end if;
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
-- Ingest one scanner result (one official domain) for one brand
--
-- p_scan: {"domain": "examplebank.in", "generated": 1650,
--          "registered": [ ...rows as above... ], "engine": "dnstwist 20250130"}
-- Returns incidents that should be alerted: new ones, and open ones whose
-- risk rose by 10 points or more ("change" says which).
-- -----------------------------------------------------------------------------
create or replace function public.ingest_lookalike_domains(p_brand_id uuid, p_scan jsonb)
returns table (tenant_id uuid, incident_id uuid, asset text, risk_score smallint,
               severity public.severity_level, explanation text, change text)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_brand     public.brands%rowtype;
  v_run_id    uuid;
  v_row       jsonb;
  v_domain    text;
  v_origin    text := lower(p_scan ->> 'domain');
  v_score     record;
  v_details   jsonb;
  v_existing  public.incidents%rowtype;
  v_new_id    uuid;
  v_ip        inet;
  v_created   timestamptz;
  v_checked   integer := 0;
  v_new       integer := 0;
begin
  select * into v_brand from public.brands where id = p_brand_id and is_active;
  if not found then
    raise exception 'Brand % not found or inactive', p_brand_id;
  end if;
  if coalesce(jsonb_typeof(p_scan -> 'registered'), '') <> 'array' or v_origin is null then
    raise exception 'p_scan must contain "domain" and a "registered" array';
  end if;

  insert into public.scan_runs (tenant_id, brand_id, source, certificates_checked)
  values (v_brand.tenant_id, v_brand.id, 'dnstwist', greatest(coalesce((p_scan ->> 'generated')::integer, 0), 0))
  returning id into v_run_id;

  for v_row in select value from jsonb_array_elements(p_scan -> 'registered') loop
    v_domain := lower(trim(v_row ->> 'domain'));
    if v_domain is null or v_domain = '' then continue; end if;
    -- Never report the customer's own official domains
    if public.is_legitimate_host(v_domain, v_brand.legitimate_domains) then continue; end if;
    v_checked := v_checked + 1;

    select * into v_score from public.score_lookalike_domain(v_row, v_brand.legitimate_domains);
    v_details := v_row || jsonb_build_object('lookalike_of', v_origin, 'engine', p_scan ->> 'engine',
                                             'scoring', 'rule-based v1', 'checked_at', now());

    begin
      v_created := (v_row ->> 'whois_created')::timestamptz;
    exception when others then
      v_created := null;
    end;
    begin
      v_ip := (v_row -> 'dns_a' ->> 0)::inet;
    exception when others then
      v_ip := null;
    end;

    v_new_id := null;
    insert into public.incidents (
      tenant_id, brand_id, channel, title, source, source_ref, severity, status,
      risk_score, score_category, score_explanation, scored_at, details
    ) values (
      v_brand.tenant_id, v_brand.id, 'domain', 'Lookalike domain: ' || v_domain, 'dnstwist', v_domain,
      v_score.severity, 'new', v_score.risk_score, v_score.category, v_score.explanation, now(), v_details
    )
    on conflict (tenant_id, channel, source, source_ref) do nothing
    returning id into v_new_id;

    if v_new_id is not null then
      v_new := v_new + 1;
      tenant_id := v_brand.tenant_id; incident_id := v_new_id; asset := v_domain;
      risk_score := v_score.risk_score; severity := v_score.severity;
      explanation := v_score.explanation; change := 'new';
      return next;
    else
      select * into v_existing from public.incidents i
       where i.tenant_id = v_brand.tenant_id and i.channel = 'domain'
         and i.source = 'dnstwist' and i.source_ref = v_domain;
      update public.incidents i
         set risk_score = v_score.risk_score, severity = v_score.severity,
             score_category = v_score.category, score_explanation = v_score.explanation,
             scored_at = now(), details = v_details
       where i.id = v_existing.id
         and (i.risk_score is distinct from v_score.risk_score or i.score_explanation is distinct from v_score.explanation);
      if v_existing.status in ('new', 'investigating', 'takedown', 'monitoring')
         and v_score.risk_score >= coalesce(v_existing.risk_score, 0) + 10 then
        tenant_id := v_brand.tenant_id; incident_id := v_existing.id; asset := v_domain;
        risk_score := v_score.risk_score; severity := v_score.severity;
        explanation := v_score.explanation;
        change := format('risk increased from %s to %s', v_existing.risk_score, v_score.risk_score);
        return next;
      end if;
    end if;

    insert into public.domains (tenant_id, brand_id, incident_id, domain, tld, similarity,
                                registered_at, registrar, hosting_ip, status)
    values (v_brand.tenant_id, v_brand.id, coalesce(v_new_id, v_existing.id), v_domain,
            substring(v_domain from '\.([a-z0-9-]+)$'), v_score.risk_score,
            v_created, v_row ->> 'whois_registrar', v_ip,
            case when v_score.risk_score >= 60 then 'flagged' else 'watching' end)
    on conflict (tenant_id, domain) do update
      set last_seen_at = now(),
          similarity   = excluded.similarity,
          registered_at = coalesce(excluded.registered_at, domains.registered_at),
          registrar     = coalesce(excluded.registrar, domains.registrar),
          hosting_ip    = coalesce(excluded.hosting_ip, domains.hosting_ip),
          incident_id   = coalesce(domains.incident_id, excluded.incident_id);
  end loop;

  update public.scan_runs
     set finished_at = now(), candidates_found = v_checked, new_incidents = v_new, status = 'success'
   where id = v_run_id;
end;
$$;

revoke execute on function public.ingest_lookalike_domains(uuid, jsonb) from public, anon, authenticated;
grant  execute on function public.ingest_lookalike_domains(uuid, jsonb) to service_role;
