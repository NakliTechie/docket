# Docket

**Sovereign case-management and citizen/customer-360 platform with an in-deployment agentic resolution layer.**

Docket is the free, public-code answer to proprietary service-cloud + AI-agent suites for the public sector: case intake (web portal, email, API), triage, SLA-tracked lifecycle, a keyboard-first staff console, a tamper-evident hash-chained audit log, a full REST API with machine-to-machine service accounts and signed webhooks, dual SSO (staff + customer identity planes), and an AI layer that runs on **your own model endpoint inside your deployment** — with English and Hindi throughout.

Three guarantees, by construction:

1. **Public funds → public code.** AGPL-3.0. Read, audit, and fork what runs on citizen data.
2. **Data sovereignty.** Single-tenant, self-hosted, operator-owned models. **No telemetry, no phone-home, no update checks, no analytics — ever.** The only outbound connections Docket makes are the LLM endpoint *you* configure and the mail gateway *you* configure.
3. **Zero per-seat licensing.** There is no seat counting anywhere in the code.

---

## Quickstart (Docker Compose)

Requirements: Docker with the compose plugin.

```bash
git clone <this-repo> docket && cd docket
docker compose up --build
```

First boot migrates Postgres, seeds a fictional demo (a Directorate of Public Grievances and a bank branch: 8 staff, ~60 cases, knowledge docs), and serves:

| Surface | URL | Credentials |
| --- | --- | --- |
| Staff console | http://localhost:3000 | `arjun@docket.local` / `docket-demo` (admin) |
| Citizen portal | http://localhost:3000/portal | none needed |
| API | http://localhost:3000/api/v1 | see [API access](#api-access) |
| OpenAPI spec | http://localhost:3000/api/v1/openapi.json | public |

Other demo logins: `sunita@docket.local` (supervisor), `priya@` / `rohan@` / `fatima@` / `deepak@docket.local` (agents), `meena@docket.local` (read-only) — all `docket-demo`.

For a **clean production instance** set environment overrides before `up`:

```bash
DOCKET_SEED_DEMO=false SECRET_KEY_BASE=$(openssl rand -hex 64) \
POSTGRES_PASSWORD=$(openssl rand -hex 16) docker compose up --build -d
```

A break-glass admin (`admin@docket.local` / `DOCKET_ADMIN_PASSWORD`, default `docketadmin`) is always seeded — change that password immediately. Put a TLS-terminating reverse proxy in front and leave `DOCKET_FORCE_SSL` unset (defaults to on).

### Smoke test

```bash
bin/smoke                                   # boots a throwaway instance and checks the loop
SMOKE_BASE_URL=http://localhost:3000 bin/smoke   # against a running compose instance
```

It files a case via the portal, verifies the status challenge, replies and resolves via the API, registers a webhook, and verifies the audit hash chain — printing PASS/FAIL.

### Local development

```bash
bundle install
bin/rails db:prepare db:seed demo:seed
bin/dev          # or: bin/rails server
bin/rails test && bin/rails test:system
```

Development and test run on SQLite; no services needed. System tests use Cuprite — point `BROWSER_PATH` at any Chrome/Chromium if it isn't auto-detected.

---

## Portal walkthrough (citizen side)

- **File a grievance** at `/portal` — name + email or phone, subject, description, attachments. No account. The confirmation screen (and email, if email was given) carries an unguessable tracking ID like `DKT-7F3K-92QX`.
- **Track a case** at `/portal/track` — tracking ID **plus** the email or phone used at filing (a verification challenge; wrong pairs get one generic error). The status page shows public replies only — internal notes never appear — and accepts replies and attachments.
- **Customer SSO** (when configured): a "Log in with your account" button appears; signed-in customers get **My cases** — their full case list and pre-attributed filing with no tracking-ID dance. The anonymous flow always remains available.
- **Email intake**: mail to your configured inbound address opens a case (attachments included); replies keeping the tracking ID in the subject thread onto the case *only when the sender address matches the case contact*.
- Hindi/English toggle is in the header on every page.

## Staff console

Sign in at `/`. The case workspace is keyboard-first — press `?` anywhere for the full key map (j/k/Enter list navigation, single-key status changes, `a` assign-to-me, `n` next case, `m` compose, Ctrl+K command palette). Macros (admin-managed canned responses with `{{contact_name}}`-style variables) insert into the composer. When AI is enabled you also get thread summaries, sentiment flags on incoming messages, and grounded suggested replies — always insert-and-edit, never auto-sent.

---

## Enabling the AI layer

Docket is **fully usable with AI off** (the default). Admin → Settings → *AI / agentic resolution*:

### In-deployment endpoint (recommended, sovereign)

Run any OpenAI-compatible server inside your network — e.g. [Ollama](https://ollama.com):

```bash
docker run -d --name ollama -p 11434:11434 ollama/ollama
docker exec ollama ollama pull llama3
```

Then set: provider mode **In-deployment endpoint**, endpoint URL `http://ollama:11434/v1` (or wherever it lives), model `llama3`. Case text never leaves your infrastructure.

What turns on:

- **route** (always on with AI): new portal/email/API cases are classified into queue/category/priority and triaged, above a confidence threshold you control.
- **draft** (default on): the agent drafts a grounded reply as an *internal note* for human review — one click inserts it into the composer.
- **resolve** (off by default, earned): only for categories where an admin explicitly flips *AI auto-resolve* (Categories page — a deliberate action with its own confirmation and audit entry), and only above the resolve-confidence threshold. Auto-resolved replies always tell the citizen how to reach a human, and any reply reopens the conversation with staff.

Grounding = your uploaded **Knowledge** docs (PDF/text/markdown — text is extracted for retrieval) + previously resolved cases. Every agent step is logged on the case with its full prompt and response. Demo mode (`fake` provider) ships canned outputs so you can see the flow with no model at all.

### BYOK (external provider) — read first

Settings offers a **BYOK** mode for external providers. It requires ticking an explicit acknowledgement because it **sends case text outside your deployment** — in sovereign deployments treat it as a data-egress decision needing approval. It stays completely off otherwise.

---

## Staff SSO (internal IdP)

Admin → Settings → *Staff SSO*. OIDC is primary; SAML 2.0 is also shipped (ADFS). Local password login always remains as break-glass.

**Keycloak (OIDC) example** — create a confidential client `docket-staff` with redirect URI `https://your-docket/auth/staff_oidc/callback`, then set issuer `https://keycloak/realms/<realm>`, client ID and secret. First SSO login provisions the user as an `agent`; map roles automatically by setting *Role claim* (e.g. `groups`) and *Role mapping* (e.g. `{"docket-admins": "admin", "grievance-leads": "supervisor"}`).

**ADFS (SAML) example** — create a relying party with ACS URL `https://your-docket/auth/staff_saml/callback`, then set the IdP SSO URL and the IdP signing certificate (PEM) in settings. The NameID should be the user's email.

All values are env-overridable for compose (`DOCKET_STAFF_OIDC_ISSUER`, `DOCKET_STAFF_OIDC_CLIENT_ID`, `DOCKET_STAFF_OIDC_CLIENT_SECRET`, `DOCKET_STAFF_SAML_IDP_SSO_URL`, `DOCKET_STAFF_SAML_IDP_CERT`, …). Set the *Public base URL* (or `DOCKET_BASE_URL`) so redirect URIs are built correctly.

Live Keycloak round-trips are covered in CI (`.github/workflows/ci.yml`, `keycloak-sso` job) and locally via `bin/keycloak-test`.

## Customer SSO (portal IdP)

Admin → Settings → *Customer SSO*: point the portal at your **customer** identity provider (the login behind netbanking/your app) and name the claim that carries your customer identifier (CIF) — it maps to the contact's **Customer ID** (`external_id`). Signed-in customers see *their own cases only*. The two identity planes are separated by construction: staff sessions live in a signed `session_id` cookie backed by server-side session rows; customer sessions live in the Rails session under a different key. Neither guard reads the other's cookie, so a customer session can never reach the staff console.

---

## API access

Everything the UI can do, the API can do, versioned under `/api/v1` (spec at `/api/v1/openapi.json`).

### Per-user tokens (staff tooling)

Admin → Integrations → *API tokens* → issue against a user. The raw `dkt_…` value is shown exactly once. It carries that user's console permissions:

```bash
curl -H "Authorization: Bearer dkt_…" https://your-docket/api/v1/cases?status=in_progress
```

### Service accounts (your systems, headless)

Admin → Integrations → *Service accounts* → create with the scopes the integration needs (`cases:read`, `cases:write`, `contacts:read/write`, `organisations:*`, `config:*`, `audit:read`, `webhooks:manage`). Exchange the client credentials for a 1-hour bearer:

```bash
curl -X POST https://your-docket/api/v1/oauth/token \
  -d grant_type=client_credentials -d client_id=svc_… -d client_secret=…
```

### On-behalf-of recipe (the netbanking pattern)

A service account with `cases:write` + `contacts:write` files cases attributed to your customer by **your** identifier — Docket upserts/links the contact and threads everything under their 360:

```bash
curl -X POST https://your-docket/api/v1/cases \
  -H "Authorization: Bearer dkts_…" -H "Content-Type: application/json" \
  -d '{
    "on_behalf_of": "CIF447192",
    "contact": {"name": "Ravi Kumar", "email": "ravi@example.com"},
    "case": {"subject": "Card blocked", "message_body": "Filed from netbanking."}
  }'

curl -H "Authorization: Bearer dkts_…" \
  "https://your-docket/api/v1/cases?contact_external_id=CIF447192"
```

The audit log records `service account X on behalf of contact CIF447192` for every such action. Identity management (users, tokens, service accounts) is deliberately *not* reachable with service-account credentials — admin user tokens only.

### NakliPoster collection

Import `docs/docket-api.nakliposter.json` (Postman v2.1 collection schema — works in compatible clients). It covers the full surface, the on-behalf-of flow, and a signed webhook-receiver test; fill in `base_url` and credentials in the collection variables.

## Webhooks

Admin → Integrations → *Webhooks* (or `webhooks:manage` via API): register HTTPS endpoints per event (`case.created`, `case.status_changed`, `case.message_added`, `case.sla_breached`, `case.resolved`). Each endpoint gets a `whsec_…` secret shown once. Deliveries are JSON POSTs:

```
X-Docket-Event: case.created
X-Docket-Delivery: 42
X-Docket-Signature: sha256=<hex HMAC-SHA256 of the raw body with your secret>
```

Verify by recomputing the HMAC over the **raw body**. Non-2xx responses retry up to 6 times with growing backoff; the per-endpoint delivery log shows every attempt. Internal notes are never published.

**CORS**: browser-side API calls from your own web properties are allowed only for origins you list in Settings → *API & integrations*.

## Audit chain

Every mutation appends a hash-chained entry: `sha256(previous_sha + canonical_entry_json)` — tampering with any historical row breaks every hash after it. Verify any time:

```bash
bin/rails audit:verify          # CLI: PASS/FAIL + first break
# Admin → Audit (chain status page)
# GET /api/v1/audit/verification
```

Admin → Activity shows per-user action counts, login/SSO history, and case volume by queue and staff with CSV export — computed entirely from this deployment's own audit log. It is the deployment owner's data and is never transmitted anywhere.

## Backup

Two things hold all state:

```bash
docker compose exec db pg_dump -U docket -Fc docket_production > docket-$(date +%F).dump
docker compose cp app:/rails/storage ./storage-backup-$(date +%F)   # attachments
```

Restore with `pg_restore` into a fresh database plus copying the storage directory back. (On the SQLite dev/demo profile, copy `storage/*.sqlite3` and `storage/` files.)

## Licence

Docket's core is licensed under **AGPL-3.0** (see `LICENSE`): anyone who operates a modified Docket over a network must offer those modifications back to its users. That is the point — public money, public code. Operator tooling built around Docket may be commercial; the core stays free, structurally.

## Project documents

- `DECISIONS.md` — every non-locked implementation decision, one line each.
- `FORWARD-PASS.md` — security findings fixed during gate forward passes.
- `KNOWN-GAPS.md` — honest list of what shipped incomplete.
- `docs/` — the founding vision and the v1.0 build instructions.
