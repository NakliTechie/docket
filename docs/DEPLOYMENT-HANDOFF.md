# Docket — deployment handoff

## Release and migration policy

Docket uses SemVer and `vMAJOR.MINOR.PATCH` tags; the running release is defined
in `lib/docket/version.rb` and changes are in `CHANGELOG.md`. Production schema
work is forward-only and follows expand/backfill/switch/contract. Additive,
backward-compatible schema lands first, backfills run in bounded batches, code
switches only after old and new versions can coexist, and destructive cleanup
waits at least one compatible release. Rollback after contraction is a tested
backup restore, not a down migration.

Compose runs `bin/release` (`db:prepare`) in its one-shot `migrate` service. The
app service is not started until it succeeds; web-container boot itself never
changes schema or seed data. A newly created database receives the idempotent
base seed once; an existing database is migrated without reseeding.

The production image must carry libvips 8.13 or newer. Rails/Active Storage
8.1.3.1 enforces the secure untrusted-loader boundary introduced after
CVE-2026-66066; do not replace the image's `libvips` package with an older build.

Everything needed to stand Docket up on a server, in the order you'll need it.
Written for whoever runs the deploy, not for whoever wrote the code.

**What Docket is:** one Rails application that replaces a service desk
(Freshdesk-class), a CRM (Salesforce-class) and a work tracker (Jira/Linear-class).
Which of those a given customer gets is a per-tenant switch, not a different build.

---

## 1. Pick the topology first — it changes the DNS and TLS work

| | **Dedicated** (`isolated`) | **Shared SaaS** (`shared`) |
|---|---|---|
| Tenants per deploy | one | many |
| How a request finds its tenant | it's the only one | **subdomain** (`acme.example.com`) |
| DNS | one A record | **wildcard** `*.example.com` |
| TLS | one certificate | **wildcard certificate** |
| Set with | `DOCKET_DEPLOYMENT_MODE=isolated` (default) | `DOCKET_DEPLOYMENT_MODE=shared` + `DOCKET_BASE_DOMAIN=example.com` |

`isolated` is the default and the simpler deploy: one organisation, one database,
nothing of anyone else's in it. Start there unless you're explicitly running
multi-customer infrastructure.

> **Shared mode needs the wildcard DNS *and* the wildcard certificate before
> anyone can log in.** An unknown subdomain is answered with 404 by design, so a
> missing DNS entry looks exactly like a broken app. This is the one thing in
> shared mode that has never been proven on real infrastructure — it is tested
> at the request level only. Budget time to verify it.

## 2. Bring it up

```bash
SECRET_KEY_BASE=$(openssl rand -hex 64) \
DOCKET_ADMIN_PASSWORD='<choose one>' \
DOCKET_BASE_URL=https://support.example.com \
POSTGRES_PASSWORD=$(openssl rand -hex 16) docker compose up --build -d
```

The release service creates the base tenant, break-glass admin, and day-one
defaults when the database is first created. `DOCKET_ADMIN_PASSWORD` is passed
only to that one-shot service, not the long-running app. If it is omitted, read
the random password once with `docker compose logs migrate`, capture it, then
change it. Container restarts and later migrations do not re-run seeds.

**Do not ship the compose file's default `SECRET_KEY_BASE`.** Set it explicitly
(above). It signs sessions and password-reset tokens; a known value means anyone
can forge both.

For a demo only, use a separate explicit command with
`DOCKET_ALLOW_DEMO_SEED=1`; never run it against production data.

### Environment variables

| Variable | Needed | Notes |
|---|---|---|
| `SECRET_KEY_BASE` | **always** | Generate per deploy. Never reuse, never default. |
| `DOCKET_BASE_URL` | **always** | Public URL. SSO redirect URIs and emailed links are built from it. |
| `DOCKET_ALLOWED_HOSTS` | optional extras | Comma-separated additional hostnames. The host in `DOCKET_BASE_URL` is allowed automatically. |
| `DOCKET_ADMIN_PASSWORD` | first creation | Otherwise printed once in the migrate-service logs; never passed to the web process. |
| `DOCKET_DEPLOYMENT_MODE` | shared only | `isolated` (default) or `shared`. |
| `DOCKET_BASE_DOMAIN` | shared only | The domain subdomains hang off. |
| `DOCKET_FORCE_SSL` | prod | Leave on. Only disable behind a TLS-terminating proxy that sets `X-Forwarded-Proto`. |
| `DOCKET_ALLOW_DEMO_SEED` | demo command only | Explicitly permits fictional accounts with known passwords. Never set on the web service. |
| `DOCKET_VAULT_KEYS` / `DOCKET_VAULT_KEYS_PATH` | prod | Versioned credential-encryption keys. Default Compose generates a 0600 storage file; use one shared keyring across every replica. |
| `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` | if mail | No `SMTP_ADDRESS` means external delivery is disabled. `SMTP_STARTTLS=false` is for exceptional trusted networks only. |
| `DOCKET_DKIM_DOMAIN`, `DOCKET_DKIM_SELECTOR`, `DOCKET_DKIM_PRIVATE_KEY[_PATH]` | if signing mail | Publish matching DNS; key path must be 0600 and RSA at least 2048-bit. |
| `RAILS_INBOUND_EMAIL_PASSWORD` | if inbound mail | Shared secret used by the production relay ingress at `/rails/action_mailbox/relay/inbound_emails`. |
| `DOCKET_STAFF_OIDC_*` / `DOCKET_STAFF_SAML_*` | if SSO | Or set them per tenant in Settings — see §5. |

## 3. Turn on what the customer bought

Modules are per tenant, set at **Admin → Tenants → Modules**:

- `service_desk` (+ `kb`, `portal`)
- `approvals` (cross-module maker-checker governance)
- `crm` (+ `sequences`)
- `work` (+ `sprints`)
- `decisioning`, `connectors`, `mcp`

Presets: `full`, `service_only`, `crm_only`, `work_only`. **Netcore gets `full`.**

Everything defaults to ON, so a dedicated deploy that never touches this screen
behaves exactly as it would if the feature didn't exist. Turning a module off
removes it completely — its pages 404, its API answers `403 feature_disabled`,
no role can reach it, and its background jobs stop running for that tenant.

## 4. Day-one configuration (a fresh deploy starts empty)

A non-demo deploy has no queues, no categories, no SLA policies. Before handing
it to users:

1. **Service desk** — at least one queue, a few categories, one SLA policy, and
   one business calendar with holidays/hours; attach it to the SLA policy and
   set the default queue and default SLA policy in Settings.
2. **Branding** — brand name, so the product doesn't say "Docket" to their users.
3. **Outbound SMTP** — host, port, credentials, from-address. Without this no
   case reply, password reset or sequence email leaves the building.
4. **Users** — invite real staff and assign functional roles
   (`super_admin`, `client_admin`, `customer_service_supervisor`, `finance`,
   `sales`, `customer_service`, `technical`, `decision_reviewer`,
   `knowledge_manager`, `auditor`, `readonly`).
5. **Work module** — one project per team; each seeds its own board columns.
   Set WIP limits/default assignment rules and reusable onboarding templates.
6. **CRM module** — pipeline/stages, public lead-capture forms and consent text,
   governed contact/lead/deal fields, catalog/competitors, seller conversations,
   and sequences. Set the inbound CRM/sequence reply domain. Route `crm+*` and
   `sequence+*` recipients into Action Mailbox. Test signed BCC capture from a
   registered staff address and a matching customer reply before use.
   Test unsubscribe, reply-stop, open tracking, and signed click tracking before use.
   Create active campaign records before publishing UTM-tagged inquiry links.
7. **Notifications/CSAT** — choose the SLA risk window and whether notifications
   also send email; enable CSAT only after SMTP is proven.
8. **Optional BI** — provision a separately secured read replica of the primary
   database for self-hosted Metabase or Superset. Do not attach BI to the
   writable primary. Shared deployments need database-enforced tenant isolation
   or separate per-tenant extracts; dashboard filters are not isolation.

The exact 11-role inventory, 17 API scopes, daily workflow, and all operator
surfaces are in [OPERATOR-GUIDE.md](OPERATOR-GUIDE.md).

Use [GO-LIVE-VALIDATION.md](GO-LIVE-VALIDATION.md) for the production evidence
record: TLS/health, authenticated outbound and inbound mail, migration rehearsal,
the six-provider launch connector subset, model quality, and human screen-reader
journeys.

## 5. SSO (optional, but expect it for enterprise)

Staff sign-on supports OIDC or SAML; the separately guarded customer portal
supports OIDC. Configure per tenant in Settings, or use the matching deploy-wide
environment variables.

Three things that have bitten before and will bite again:

- **Redirect URIs must match `DOCKET_BASE_URL` exactly**, including scheme.
- **The IdP's origin must be reachable** — the app adds it to the CSP
  `form-action` automatically, but a proxy that rewrites CSP will break the
  redirect silently.
- **In shared mode, per-tenant SSO settings are read from the request host.**
  If SSO reports "not configured" for a tenant that clearly configured it, the
  request is arriving without the expected subdomain — check the proxy's
  `Host` header before touching the config.

## 6. Migrating a customer off their old stack

Freshdesk, Jira, Salesforce, generic CSV, and KanZen imports all default to a
**dry run**. Freshdesk and Jira can consume either a streaming export file or
their paginated API. State and role mappings are explicit: an unknown state is
reported and its record is skipped, never dropped into a guessed default.

```bash
# Dry run first — always.
bin/rails docket:import:jira FILE=/tmp/jira-export.json
bin/rails docket:import:freshdesk FILE=/tmp/freshdesk-export.json
bin/rails docket:import:salesforce_preview FILE=/tmp/salesforce.json MAPS=/tmp/salesforce-maps.json
bin/rails docket:import:csv_preview FILE=/tmp/contacts.csv CONTRACT=/tmp/contacts-contract.json
bin/rails docket:import:kanzen FILE=/tmp/board.kanzen.json KEY=OPS

# Then commit.
bin/rails docket:import:jira FILE=/tmp/jira-export.json MAPS=/tmp/jira-maps.json APPLY=1
```

Add `TENANT=<slug>` in shared mode. Add `PROJECT=KEY` to the Jira import to
force everything into one project instead of deriving projects from issue keys.

**Read every `UNMAPPED`, `ERROR`, and `CONFLICT` line before applying.** A dry
run executes model validation and rolls back domain rows. It validates attachment
metadata but deliberately does not download attachment bytes; byte-level storage
validation happens on `APPLY=1`.

Every applied source record receives a durable provider identity. Runs commit in
bounded batches and print a resume token; pass `RESUME_TOKEN=<token>` after an
interruption. Delta runs keep a source watermark. If a Docket user changed a
previously imported field while the provider changed the same field, Docket
keeps the local value and records an explicit conflict instead of overwriting it.

Recommended order: **Freshdesk → Jira → CRM data**, because tickets create the
contacts that later records attach to.

The complete mapping, resume, API, delta-cutover, and reconciliation procedure
is in [RUNBOOK-MIGRATION.md](RUNBOOK-MIGRATION.md).

## 7. Before you call it live

**Repository release proof (2026-08-01):** the production image built with Rails 8.1.3.1,
libvips 8.14.1, and PostgreSQL 16.14 clients; a fresh isolated Compose stack seeded its base
tenant/defaults, reported healthy dependencies, and passed the 12-step smoke; a separate
clean target restored all four databases, the 35-entry audit checkpoint, and attachment
bytes, then passed the smoke again. The local restore-to-serving reference was 9.24s
(17.81s including clean-stack provisioning). This closes artifact/procedure risk, not the
environment-owned SMTP/TLS/DNS/inbound-mail checks below.

- [ ] `docker compose up --build` clean from scratch, and the app serves.
- [ ] The in-Puma worker actually fires: an SLA sweep runs, a sequence email
      sends. (These are cron-shaped; if they don't run, nothing tells you.)
- [ ] Outbound mail lands in a real inbox — not just "no error in the log".
- [ ] SPF, DKIM, and DMARC pass in that mailbox when signed mail is required.
- [ ] Inbound email intake, **if wanted**: SMTP relay → Action Mailbox at
      `/rails/action_mailbox/relay/inbound_emails`.
- [ ] TLS terminates correctly and `DOCKET_FORCE_SSL` is on.
- [ ] `/healthz` is 200 and shows database, queue, storage, recurring jobs, and
      failed-job checks healthy from the production hostname.
- [ ] The break-glass admin password has been changed from the explicit initial seed value.
- [ ] Backups: **`bin/backup <dir>` and `bin/restore <dir>`** — see
      [RUNBOOK-BACKUP.md](RUNBOOK-BACKUP.md). Schedule the backup, get it off the
      box, and **run the restore drill before go-live**. The restore ends with
      `bin/rails audit:verify`, so a partial restore is detected rather than
      assumed.

## 8. Known gaps — tell the customer before they find them

- **The 66 connectors are implementation/stub-tested, not live-certified.** Every one is
  implemented against the vendor's documented API and unit-tested against a
  stub, but none has made an authenticated call with real credentials. Validate
  the ones a customer actually depends on before relying on them.
- **Shared-mode wildcard DNS/TLS is unproven on real infrastructure** (§1).
- **The real AI integration path is proven locally, not production-qualified.** A local
  Ollama `qwen2.5:3b` run exercised the OpenAI-compatible client, agent tool selection,
  auditable connector proposal, human approval gate, and case-timeline logging with
  synthetic data. Validate the chosen production model/endpoint against the pilot's
  quality, latency, privacy, and failure criteria before promising outcomes.
- **A screen-reader pass has not been done.** Automated accessibility checks
  (axe-core) are green; that is not the same as usable.
- **Sprint burndown is data-only** — velocity and cycle time are computed, but
  there is no chart yet.

## 9. Where to look when something breaks

**Start at `/healthz`.** It reports database, queue, storage, recurring-sweep
freshness and failed-job count as JSON, and answers 503 with the failing check
named. (`/up` only proves the process booted.)

| Symptom | Look at |
|---|---|
| Anything at all, at 2am | `curl -s https://host/healthz \| jq` — it names what is broken |
| Jobs seem stuck | `/healthz` → `recurring_jobs.stale` and `failed_jobs.count` |
| SSO bounces to "single sign-on failed" | Boot logs for `Authentication failure!` — the reason follows it. Then §5. |
| A module's pages 404 for everyone | Admin → Tenants → Modules. A 404 here means "not entitled", by design. |
| API returns `403 feature_disabled` | Same — the response body names the module. |
| Emails not sending | SMTP settings, then whether the in-Puma worker is running. |
| Recurring jobs not firing | `config/recurring.yml` + the worker; sweeps are per tenant and skip tenants without the relevant module. |
| An import did the wrong thing | Re-run the dry run and read `UNMAPPED`. Imports are idempotent; fix the mapping and re-apply. |
