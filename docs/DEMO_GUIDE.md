# BrandGuard Local Demo Guide

BrandGuard by Shivaji, PM. Architecture: `docs/ARCHITECTURE.md`. Security controls: `docs/SECURITY.md`.

Local demo only. Everything runs on this PC in Docker. Nothing is published.

## What the demo shows

| Feature | Status |
|---|---|
| Brand setup: the customer enters official websites, email domains, mobile apps and social accounts | Live |
| Website monitor: daily lookalike domain scan of every official website (typos, look-alike characters, brand plus words such as kyc or login, other domain endings), with registration date, mail servers and a home page check | Live |
| Live lookalike detection from crt.sh (Certificate Transparency search) every 15 minutes | Live |
| Rule-based risk score (0 to 100) with a plain-English reason for every finding | Live |
| Email alert digest for new high-risk findings (score 60 or more) | Live, delivered to the local Mailpit inbox |
| Dashboard and Incidents views, takedown records, status changes, manual incident reports | Live |
| Two demo tenants that cannot see each other's data | Live |
| Social, mobile app and email channels | SAMPLE data only (clearly labelled) |

Demo brand: "Northwind Small Finance Bank", which is fictional (its domains use the reserved `.example` ending). To see live detections, sign in as the Tenant A admin and add a real brand you are authorised to monitor in Brand setup.

## Start the demo

Requires Docker Desktop to be running ("Engine running") and a `.env` file with every value from `.env.example` filled in, including a long random `SCANNER_TOKEN` (the scanner refuses to start without it).

Security check before a demo on a shared network: the Supabase CLI publishes ports 54321 to 54325 on all network interfaces. Make sure Windows Firewall blocks inbound connections to them (see `docs/SECURITY.md`, risk R1).

1. Start the database (local Supabase):
   ```
   npx supabase@3.1.0 start
   ```
2. Start N8N and the lookalike scanner (detection workflows):
   ```
   docker compose -f docker-compose.n8n.yml up -d --build
   ```
3. Start the web app:
   ```
   npm --prefix web run dev
   ```

## Open

| What | Address |
|---|---|
| BrandGuard web app | http://localhost:5173 |
| Alert emails (Mailpit inbox) | http://127.0.0.1:54324 |
| N8N workflow editor | http://localhost:5678 (this PC only; first visit asks you to create a local owner account) |
| Database admin (Supabase Studio) | http://127.0.0.1:54323 |

Demo logins are listed at the top of `supabase/seed.sql`:

| Login | Sees |
|---|---|
| admin@tenant-a.brandguard.test | DEMO Tenant A as admin: can add brands and assets in Brand setup |
| analyst@tenant-a.brandguard.test | DEMO Tenant A: detections plus SAMPLE items (Brand setup is read-only) |
| analyst@tenant-b.brandguard.test | DEMO Tenant B: one SAMPLE item only (proves isolation) |

## Suggested demo script (7 minutes)

1. Sign in as the Tenant A admin. Open **Brand setup** and click **Add brand**. Enter the company name and main website, then add its email domain, app store links and social profile links. Pasted links are cleaned automatically (for example an App Store link becomes the app id). Official domains are never alerted on.
2. Open the Dashboard. Show critical count, brand risk ring, live alert feed, CT log.
3. Click **Critical incidents**. Open the top finding and read the risk explanation.
4. Show the evidence: **View certificate on crt.sh** for certificate findings, or the **ICANN registration record** for website monitor findings.
5. Click **Start takedown**. Show the toast and the **Active takedowns** panel on the Dashboard.
6. Open the Mailpit inbox and show the alert email.
7. Sign out, sign in as Tenant B. Show that none of Tenant A's data is visible.

## Run a scan immediately

Website monitor (runs daily at 06:00 UTC; a full run takes several minutes):
```
MSYS_NO_PATHCONV=1 docker exec -e N8N_RUNNERS_BROKER_PORT=5690 brandguard-n8n n8n execute --id=bgLookalikeWatch1
```

Certificate search (runs every 15 minutes). To run it now:
```
MSYS_NO_PATHCONV=1 docker exec -e N8N_RUNNERS_BROKER_PORT=5690 brandguard-n8n n8n execute --id=bgCrtshWatcher01
```
Or open the workflow in the N8N editor and click **Execute workflow**.

## Stop the demo

```
docker compose -f docker-compose.n8n.yml down
npx supabase@3.1.0 stop
```
Data is kept between restarts. To reset the database to the demo seed: `npx supabase@3.1.0 db reset`.

## Run the database tests

```
bash supabase/tests/run_tests.sh
```

## Known limits of the demo

- Brand setup stores apps and social accounts, but only websites are monitored so far. Email protection checks, app store search and social search are the next build steps.
- The website monitor checks registered lookalikes only once a day, and its home page check reads the HTML only (no screenshots yet). Pages built entirely with JavaScript may look empty.
- The scanner uses Docker's own DNS resolver. On this PC, sending lookups straight from Docker to public resolvers (1.1.1.1, 8.8.8.8) dropped most queries, so that is off by default (`SCANNER_NAMESERVERS` in `.env` turns it back on). A scan of one website takes about 1 to 5 minutes.
- Names on `.bank.in` can only be registered by licensed banks, so the monitor scans the matching `.in` name across other endings instead.
- Scoring is rule-based (v1). AI scoring is a later phase.
- Brand-owned domains not in the brand's legitimate domain list can appear as low-risk findings; mark them **False positive**.
- crt.sh is a free community service and is sometimes slow or down; failed scans are logged in red in the CT log panel.
- Evidence upload, the PDF reports and the other views from the prototype are not built yet.
