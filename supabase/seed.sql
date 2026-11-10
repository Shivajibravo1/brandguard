-- =============================================================================
-- LOCAL DEMO SEED DATA. Runs only on the local Supabase stack
-- (`supabase start` / `supabase db reset`). Never run on a hosted project.
--
-- Everything here is demo data:
--   * Two demo tenants and two demo users (local test credentials below).
--   * "Northwind Small Finance Bank" is fictional. Its domains use the reserved
--     .example ending, so they can never belong to a real organisation.
--     Add your own brand in Brand setup to see live detections.
--   * Incidents with source = 'sample' are invented examples for channels that
--     are not built yet (social, apps, email). The UI labels them SAMPLE.
--     Live domain incidents come from the crt.sh watcher, not from this file.
--
-- Local demo logins (local stack only):
--   analyst@tenant-a.brandguard.test / ZxlA0S-GPDD_1dLJ   (Tenant A, analyst)
--   analyst@tenant-b.brandguard.test / 9XwBsTfbsLnBbYXD   (Tenant B, analyst)
--   admin@tenant-a.brandguard.test   / eS8sTE9qhQdT92Q_   (Tenant A, admin: can edit Brand setup)
-- =============================================================================

-- Demo users -------------------------------------------------------------------
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new
) values
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated',
   'analyst@tenant-a.brandguard.test', extensions.crypt('ZxlA0S-GPDD_1dLJ', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"full_name":"Demo Analyst A"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated',
   'analyst@tenant-b.brandguard.test', extensions.crypt('9XwBsTfbsLnBbYXD', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"full_name":"Demo Analyst B"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-0000-0000-0000000000a0', 'authenticated', 'authenticated',
   'admin@tenant-a.brandguard.test', extensions.crypt('eS8sTE9qhQdT92Q_', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"full_name":"Demo Admin A"}', now(), now(), '', '', '', '');

insert into auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
values
  (gen_random_uuid(), 'd0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-0000000000a1',
   '{"sub":"d0000000-0000-0000-0000-0000000000a1","email":"analyst@tenant-a.brandguard.test","email_verified":true}', 'email', now(), now(), now()),
  (gen_random_uuid(), 'd0000000-0000-0000-0000-0000000000b1', 'd0000000-0000-0000-0000-0000000000b1',
   '{"sub":"d0000000-0000-0000-0000-0000000000b1","email":"analyst@tenant-b.brandguard.test","email_verified":true}', 'email', now(), now(), now()),
  (gen_random_uuid(), 'd0000000-0000-0000-0000-0000000000a0', 'd0000000-0000-0000-0000-0000000000a0',
   '{"sub":"d0000000-0000-0000-0000-0000000000a0","email":"admin@tenant-a.brandguard.test","email_verified":true}', 'email', now(), now(), now());

-- Tenants and membership -------------------------------------------------------
insert into public.tenants (id, name, plan) values
  ('a0000000-0000-0000-0000-000000000001', 'DEMO Tenant A', 'professional'),
  ('b0000000-0000-0000-0000-000000000001', 'DEMO Tenant B', 'starter');

insert into public.tenant_members (tenant_id, user_id, role) values
  ('a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-0000000000a0', 'admin'),
  ('a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-0000000000a1', 'analyst'),
  ('b0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-0000000000b1', 'analyst');

-- Brands -----------------------------------------------------------------------
-- Tenant A protects a fictional bank. Live scans of a real brand start once an
-- admin adds that brand and its official assets in Brand setup.
insert into public.brands (id, tenant_id, name, keywords) values
  ('a1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001',
   'Northwind Small Finance Bank (fictional)', '{northwindbank}');

-- Official assets of the fictional bank. Website and email domains also fill
-- brands.legitimate_domains automatically (migration 0003).
insert into public.brand_assets (tenant_id, brand_id, asset_type, platform, value, label, publisher)
select 'a0000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', t, p, v, l, pub
from (values
  ('website'::public.brand_asset_type, '', 'northwindbank.example', null, null),
  ('email_domain', '', 'northwindbank.example', null, null),
  ('mobile_app', 'apple', '1000000001', 'Northwind Mobile Banking', 'Northwind Small Finance Bank'),
  ('mobile_app', 'google', 'com.northwindbank.mobile', 'Northwind Mobile Banking', 'Northwind Small Finance Bank'),
  ('social', 'x', 'northwind_sfb_demo', null, null),
  ('social', 'linkedin', 'northwind-sfb-demo', null, null)
) as a(t, p, v, l, pub);

-- Tenant B has an invented brand with no live monitoring (isolation demo only).
insert into public.brands (id, tenant_id, name, keywords, legitimate_domains, is_active) values
  ('b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'SAMPLE Brand B',
   '{samplebrandb}', '{samplebrandb.example}', false);

-- SAMPLE incidents for channels not built yet ------------------------------------
insert into public.incidents
  (tenant_id, brand_id, channel, title, source, source_ref, severity, status, risk_score, score_category, score_explanation, details, detected_at)
values
  ('a0000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'social',
   'Fake support account using the brand logo', 'sample', 'sample-social-1', 'high', 'investigating', 78, 'social_impersonation',
   'SAMPLE: Profile copies the brand logo and asks users to message a support line. Account created 3 days ago.',
   '{"sample": true, "platform": "X"}', now() - interval '5 hours'),
  ('a0000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'social',
   'Executive impersonation profile', 'sample', 'sample-social-2', 'medium', 'new', 61, 'executive_impersonation',
   'SAMPLE: Profile uses an executive''s name and photo with no verification badge.',
   '{"sample": true, "platform": "LinkedIn"}', now() - interval '1 day'),
  ('a0000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'app',
   'Lookalike wallet app in a third-party store', 'sample', 'sample-app-1', 'critical', 'investigating', 91, 'rogue_app',
   'SAMPLE: App reuses the brand icon and name and requests SMS read permission.',
   '{"sample": true, "store": "Third-party APK site"}', now() - interval '2 days'),
  ('a0000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'email',
   'Spoofed sender failing DMARC', 'sample', 'sample-email-1', 'high', 'new', 72, 'email_spoofing',
   'SAMPLE: 214 messages from an unknown IP failed SPF and DKIM while using the brand domain in the From address.',
   '{"sample": true, "source_ip": "203.0.113.45"}', now() - interval '8 hours'),
  ('b0000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'domain',
   'Lookalike domain for SAMPLE Brand B', 'sample', 'sample-b-domain-1', 'high', 'new', 70, 'typosquat',
   'SAMPLE: Visible only to Tenant B. Used to demonstrate tenant isolation.',
   '{"sample": true}', now() - interval '3 hours');
