# Docket

**Self-hosted, sovereign service desk + CRM + work tracker — one platform, with an in-deployment agentic resolution layer.**

Docket is the free, public-code answer to proprietary service-cloud + AI-agent suites — for any organization that runs support, sales, or engineering work and wants to **own its stack**. Three pillars in one deployment, sharing one identity, one audit log and one API:

- **Service desk** — case intake (web portal, live chat, email, API, IVR, and supported messaging connectors), scheduled/declarative routing, business-calendar SLA, approvals, collaboration, CSAT, and knowledge.
- **CRM** — contacts, organizations, configurable lead capture, reviewed duplicate merge, pipelines, deals, products, competitors, first-touch campaigns, sequences, and sales reporting.
- **Work** — projects and templates, work items (`KEY-123`), assignment rules, relations, comments/watches, kanban boards, sprints, and transition approvals.

They are not three products behind one login: a support case escalates into engineering work and the desk keeps the customer conversation, a won deal can open an onboarding project, and every object shares the contact it belongs to.

Around them: a keyboard-first staff console, a tamper-evident hash-chained audit log, a full REST API with machine-to-machine service accounts and signed webhooks, an MCP server face for agents, dual SSO (staff + customer identity planes), and an AI layer that runs on **your own model endpoint inside your deployment** — with English and Hindi throughout. Private-sector support desks and sales teams work out of the box; government/PSU grievance redressal is a first-class vertical (`DOCKET_SEED_SCENARIO=gov`).

**Every pillar is a switch.** Modules are entitled per tenant, so a customer who bought only the service desk simply does not have a CRM — its pages don't exist for them, its API answers `feature_disabled`, and no role can reach it. The same mechanism serves both SKUs: a dedicated single-tenant server (the default) and shared multi-tenant SaaS. See [docs/DEPLOYMENT-HANDOFF.md](docs/DEPLOYMENT-HANDOFF.md).

Three guarantees, by construction:

1. **Open by construction.** AGPL-3.0 — read, audit, and fork what runs on your customers' data. (For public bodies: public funds → public code.)
2. **Data sovereignty.** Self-hosted, operator-owned models. The default SKU is **single-tenant** — one deployment, one organization, one database, nothing of anyone else's in it. (A shared multi-tenant mode exists for customers who can't fund a dedicated instance; the isolated deploy is the degenerate single-tenant case of it, so the procurement story stays literally true.) **No vendor telemetry, phone-home, update checks, or product analytics.** Outbound traffic is limited to endpoints the operator deliberately configures: mail, identity/model services, connector providers, webhooks, and migration sources.
3. **Zero per-seat licensing.** There is no seat counting anywhere in the code.

---

## Quickstart (Docker Compose)

Requirements: Docker with the compose plugin.

```bash
git clone <this-repo> docket && cd docket

# Try the demo on localhost. Seeding is an explicit one-off operation, never a
# web-container restart side effect:
export POSTGRES_PASSWORD=$(openssl rand -hex 16)
DOCKET_FORCE_SSL=false docker compose up --build -d db migrate
docker compose run --rm -e DOCKET_ALLOW_DEMO_SEED=1 app \
  ./bin/rails db:prepare db:seed demo:seed
DOCKET_FORCE_SSL=false docker compose up
```

The explicit seed command loads a fictional demo — by default **Acme Cloud**, a SaaS support desk (8 staff, dozens of cases across queues, plus leads, deals and knowledge docs). Pass `-e DOCKET_SEED_SCENARIO=retail|gov` to `docker compose run` to select another vertical (default `saas`; `gov` seeds a Directorate of Public Grievances + a bank branch). The app then serves:

| Surface | URL | Credentials |
| --- | --- | --- |
| Staff console | http://localhost:3000 | `arjun@docket.local` / `docket-demo` (admin) |
| Customer portal | http://localhost:3000/portal | none needed |
| API | http://localhost:3000/api/v1 | see [API access](#api-access) |
| OpenAPI spec | http://localhost:3000/api/v1/openapi.json | public |

Other demo logins: `sunita@docket.local` (client admin),
`farah@docket.local` (finance), `sanjay@docket.local` (sales),
`priya@` / `rohan@` / `fatima@` / `deepak@docket.local`
(customer service), `tarun@docket.local` (technical), and
`meena@docket.local` (read-only) — all `docket-demo`.

**Defaults are production-safe.** Web-container startup never migrates or seeds,
SSL is enforced, and a unique `SECRET_KEY_BASE` is generated on first boot
(persisted to the storage volume). The one-shot release service prepares all
four databases; on first creation only, it runs the idempotent base seed for the
tenant, break-glass admin, and day-one defaults. Rich demo accounts are never
created unless explicitly requested. For a real deployment, set the database
password, public origin, initial admin password, and put a TLS-terminating
reverse proxy in front:

```bash
POSTGRES_PASSWORD=$(openssl rand -hex 16) \
SECRET_KEY_BASE=$(openssl rand -hex 64) \
DOCKET_ADMIN_PASSWORD='<choose one>' \
DOCKET_BASE_URL=https://support.example.com \
docker compose up --build -d
```

Compose runs migrations in a one-shot `migrate` service and starts the web app
only after it succeeds. `DOCKET_ADMIN_PASSWORD` is consumed by that first-create
seed but is deliberately not passed to the long-running app container. If it is
omitted, a random password is printed once in `docker compose logs migrate`—
capture it and change it after first login. Restarts and later migrations do not
re-run the seed.

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

**Running the suite on Postgres.** Production runs Postgres, and a few queries differ from SQLite (json has no `LIKE` operator; full-text search uses `tsquery`). Point `DATABASE_URL` at a Postgres database and the `test:` config switches adapter automatically — no edit to `config/database.yml`:

```bash
createdb docket_test   # once
DATABASE_URL=postgres:///docket_test PARALLEL_WORKERS=1 bin/rails db:test:prepare test
```

`PARALLEL_WORKERS=1` avoids a libpq-under-fork crash on macOS; on Linux CI it can be higher. CI runs this as the `test-postgres` job on every push.

---

## Portal walkthrough (customer side)

- **Submit a request** at `/portal` — name + email or phone, subject, description, attachments. No account. The confirmation screen (and email, if email was given) carries an unguessable tracking ID like `DKT-7F3K-92QX`.
- **Track a case** at `/portal/track` — tracking ID **plus** the email or phone used at filing (a verification challenge; wrong pairs get one generic error). The status page shows public replies only — internal notes never appear — and accepts replies and attachments.
- **Live chat** at `/portal/live_chat/new` — starts a realtime case conversation using a 24-hour bearer session. Staff public replies arrive over Action Cable. Admins may enable answers from published public knowledge articles; internal articles never enter the public-bot prompt.
- **Customer SSO** (when configured): a "Log in with your account" button appears; signed-in customers get **My cases** — their full case list and pre-attributed filing with no tracking-ID dance. The anonymous flow always remains available.
- **Email intake**: mail to your configured inbound address opens a case (attachments included); replies keeping the tracking ID in the subject thread onto the case *only when the sender address matches the case contact*.
- Hindi/English toggle is in the header on every page.

## Staff console

Sign in at `/`. The case workspace is keyboard-first — press `?` anywhere for the full key map (j/k/Enter list navigation, single-key status changes, `a` assign-to-me, `n` next case, `m` compose, Ctrl+K command palette). My Tickets/My Work, saved views, safe bulk actions, assignment/mention/watch notifications, case-presence signals, merge/split, action macros, rich replies, signatures, and attachments support the daily queue. When AI is enabled you also get thread summaries, sentiment flags on incoming messages, and grounded suggested replies — always insert-and-edit, never auto-sent.

For the complete product, role, scope, SLA, notification, connector, decisioning,
privacy, and tenant-lifecycle guide, see
[docs/OPERATOR-GUIDE.md](docs/OPERATOR-GUIDE.md).

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
- **resolve** (off by default, earned): only for categories where an admin explicitly flips *AI auto-resolve* (Categories page — a deliberate action with its own confirmation and audit entry), and only above the resolve-confidence threshold. Auto-resolved replies always tell the customer how to reach a human, and any reply reopens the conversation with staff.

Grounding = your published **Knowledge** docs (PDF/text/markdown — text is extracted for retrieval). Every content or lifecycle change retains an immutable article version; locale variants and nested knowledge categories keep the corpus organised. Every agent step is logged on the case with its full prompt and response. Demo mode (`fake` provider) ships canned outputs so you can see the flow with no model at all.

### BYOK (external provider) — read first

Settings offers a **BYOK** mode for external providers. It requires ticking an explicit acknowledgement because it **sends case text outside your deployment** — in sovereign deployments treat it as a data-egress decision needing approval. It stays completely off otherwise.

---

## Staff SSO (internal IdP)

Admin → Settings → *Staff SSO*. OIDC is primary; SAML 2.0 is also shipped (ADFS). Local password login always remains as break-glass.

**Keycloak (OIDC) example** — create a confidential client `docket-staff` with redirect URI `https://your-docket/auth/staff_oidc/callback`, then set issuer `https://keycloak/realms/<realm>`, client ID and secret. First SSO login provisions the user as `customer_service`; map roles automatically by setting *Role claim* (e.g. `groups`) and *Role mapping* (e.g. `{"docket-admins": "client_admin", "sales-team": "sales"}`).

**ADFS (SAML) example** — create a relying party with ACS URL `https://your-docket/auth/staff_saml/callback`, then set the IdP SSO URL and the IdP signing certificate (PEM) in settings. The NameID should be the user's email.

All values are env-overridable for compose (`DOCKET_STAFF_OIDC_ISSUER`, `DOCKET_STAFF_OIDC_CLIENT_ID`, `DOCKET_STAFF_OIDC_CLIENT_SECRET`, `DOCKET_STAFF_SAML_IDP_SSO_URL`, `DOCKET_STAFF_SAML_IDP_CERT`, …). Set the *Public base URL* (or `DOCKET_BASE_URL`) so redirect URIs are built correctly.

Live Keycloak round-trips are covered in CI (`.github/workflows/ci.yml`, `keycloak-sso` job) and locally via `bin/keycloak-test`.

## Customer SSO (portal IdP)

Admin → Settings → *Customer SSO*: point the portal at your **customer** identity provider (the login behind netbanking/your app) and name the claim that carries your customer identifier (CIF) — it maps to the contact's **Customer ID** (`external_id`). Signed-in customers see *their own cases only*. The two identity planes are separated by construction: staff sessions live in a signed `session_id` cookie backed by server-side session rows; customer sessions live in the Rails session under a different key. Neither guard reads the other's cookie, so a customer session can never reach the staff console.

---

## API access

Docket's supported integration API is versioned under `/api/v1`; its live,
tenant-filtered route and schema inventory is `/api/v1/openapi.json`.

### Per-user tokens (staff tooling)

Admin → Integrations → *API tokens* → issue against a user. The raw `dkt_…` value is shown exactly once. It carries that user's console permissions:

```bash
curl -H "Authorization: Bearer dkt_…" https://your-docket/api/v1/cases?status=in_progress
```

### Service accounts (your systems, headless)

Admin → Integrations → *Service accounts* → create with the scopes the integration needs. The exact 17-scope inventory and its policy projection are in the [operator guide](docs/OPERATOR-GUIDE.md#service-account-api-scopes). Exchange the client credentials for a 1-hour bearer:

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

**Attachments** ride along on case create and message create — multipart (`message[files][]`) or pure JSON (`message[attachments]: [{filename, content_type, data}]` with base64 data), under the same type allowlist and 10 MB / 5-file limits as every other surface. Message responses include signed download URLs.

**Reports**: `GET /api/v1/reports/activity?from=&to=` returns the same aggregates as the admin Activity view — per-user action counts, login history, volume by queue/staff, resolution rate, SLA breaches and compliance, AI-vs-human reply split (admin token or `audit:read` scope).

### NakliPoster collection

Import `docs/docket-api.nakliposter.json` (Postman v2.1 collection schema — works in compatible clients). It is a curated service-desk, on-behalf-of, and signed-webhook walkthrough; fill in `base_url` and credentials in the collection variables. Use the live OpenAPI document for the complete surface.

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

## Backup and restore

Production state spans four PostgreSQL databases, attachments, an external
audit checkpoint, and deployment secrets. Use the preflighted
scripts—never a primary-only `pg_dump`:

```bash
bin/backup /var/backups/docket
DOCKET_RESTORE_CONFIRM=yes bin/restore /var/backups/docket/docket-<UTC timestamp>
```

The restore validates the complete set before overwriting anything and finishes
by verifying the audit chain against the captured checkpoint. Default Compose
persists its generated session secret and vault keyring inside the archived
storage volume, so the archive itself is sensitive; externally managed secrets
must be retained separately with matching backup generations. Run a clean-host
restore drill and record the measured RTO before
go-live. See [docs/RUNBOOK-BACKUP.md](docs/RUNBOOK-BACKUP.md).

## Licence

Docket's core is licensed under **AGPL-3.0** (see `LICENSE`): anyone who operates a modified Docket over a network must offer those modifications back to its users. That is the point — public money, public code. Operator tooling built around Docket may be commercial; the core stays free, structurally.

## Project documents

- `DECISIONS.md` — architecture and product decisions.
- `CHANGELOG.md` — user-visible and operational changes by release.
- `docs/OPERATOR-GUIDE.md` — product configuration, roles, scopes, automation,
  lifecycle, privacy, and key rotation.
- `docs/DEPLOYMENT-HANDOFF.md` — production deployment and go-live checklist.
- `docs/GO-LIVE-VALIDATION.md` — production evidence script for mail, connectors,
  model quality, migration, shared hosting, and human accessibility.
- `docs/RUNBOOK-MIGRATION.md` and `docs/RUNBOOK-BACKUP.md` — cutover and recovery.
