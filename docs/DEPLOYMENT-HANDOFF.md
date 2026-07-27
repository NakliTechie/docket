# Docket — deployment handoff

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
docker compose up --build -d
```

First boot migrates the database and creates a break-glass admin
(`admin@docket.local`). If you don't set `DOCKET_ADMIN_PASSWORD`, a random one is
generated and **printed once** in the boot logs — capture it, then change it.

**Do not ship the compose file's default `SECRET_KEY_BASE`.** Set it explicitly
(above). It signs sessions and password-reset tokens; a known value means anyone
can forge both.

**`DOCKET_SEED_DEMO` must be unset or `false` in production.** It seeds demo
staff accounts with known passwords.

### Environment variables

| Variable | Needed | Notes |
|---|---|---|
| `SECRET_KEY_BASE` | **always** | Generate per deploy. Never reuse, never default. |
| `DOCKET_BASE_URL` | **always** | Public URL. SSO redirect URIs and emailed links are built from it. |
| `DOCKET_ALLOWED_HOSTS` | **always** | Comma-separated hostnames the app will answer to. |
| `DOCKET_ADMIN_PASSWORD` | first boot | Otherwise printed once in the logs. |
| `DOCKET_DEPLOYMENT_MODE` | shared only | `isolated` (default) or `shared`. |
| `DOCKET_BASE_DOMAIN` | shared only | The domain subdomains hang off. |
| `DOCKET_FORCE_SSL` | prod | Leave on. Only disable behind a TLS-terminating proxy that sets `X-Forwarded-Proto`. |
| `DOCKET_SEED_DEMO` | never in prod | Demo accounts with known passwords. |
| `DOCKET_STAFF_OIDC_*` / `DOCKET_STAFF_SAML_*` | if SSO | Or set them per tenant in Settings — see §5. |

## 3. Turn on what the customer bought

Modules are per tenant, set at **Admin → Tenants → Modules**:

- `service_desk` (+ `kb`, `approvals`, `portal`)
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
   set the default queue and default SLA policy in Settings.
2. **Branding** — brand name, so the product doesn't say "Docket" to their users.
3. **Outbound SMTP** — host, port, credentials, from-address. Without this no
   case reply, password reset or sequence email leaves the building.
4. **Users** — invite real staff and assign functional roles
   (`super_admin`, `client_admin`, `finance`, `sales`, `customer_service`,
   `technical`, `readonly`).
5. **Work module** — one project per team; each seeds its own board columns.
   Set WIP limits on the project's edit screen if they want them.

## 5. SSO (optional, but expect it for enterprise)

Both an OIDC and a SAML plane, for staff and (separately) customers. Configure
per tenant in Settings, or deploy-wide via `DOCKET_STAFF_OIDC_*`.

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

All three importers read an **export file** — no vendor credentials, nothing
called live. Every one **defaults to a dry run** that reports exactly what it
would do, including every source value it has no mapping for. Nothing is written
until you pass `APPLY=1`.

```bash
# Dry run first — always.
bin/rails docket:import:jira FILE=/tmp/jira-export.json
bin/rails docket:import:freshdesk FILE=/tmp/freshdesk-export.json
bin/rails docket:import:kanzen FILE=/tmp/board.kanzen.json KEY=OPS

# Then commit.
bin/rails docket:import:jira FILE=/tmp/jira-export.json APPLY=1
```

Add `TENANT=<slug>` in shared mode. Add `PROJECT=KEY` to the Jira import to
force everything into one project instead of deriving projects from issue keys.

**Read the `UNMAPPED` lines before you apply.** They name every status, issue
type or priority the importer had no rule for; those rows fall back to a default,
which is often wrong. Supply a mapping or fix it after import — but decide
knowingly.

Imports are **idempotent** — Jira on the issue key, Freshdesk on the ticket id —
so a run that fails halfway can simply be run again.

Recommended order: **Freshdesk → Jira → CRM data**, because tickets create the
contacts that later records attach to.

## 7. Before you call it live

- [ ] `docker compose up --build` clean from scratch, and the app serves.
- [ ] The in-Puma worker actually fires: an SLA sweep runs, a sequence email
      sends. (These are cron-shaped; if they don't run, nothing tells you.)
- [ ] Outbound mail lands in a real inbox — not just "no error in the log".
- [ ] Inbound email intake, **if wanted**: SMTP relay → Action Mailbox at
      `/rails/action_mailbox/relay/inbound_emails`.
- [ ] TLS terminates correctly and `DOCKET_FORCE_SSL` is on.
- [ ] The break-glass admin password has been changed from whatever first boot used.
- [ ] Backups: the database is the whole product. The audit log is a hash chain —
      a partial restore is detectable, which is the point.

## 8. Known gaps — tell the customer before they find them

- **The 68 connectors are doc-verified, not live-tested.** Every one is
  implemented against the vendor's documented API and unit-tested against a
  stub, but none has made an authenticated call with real credentials. Validate
  the ones a customer actually depends on before relying on them.
- **Shared-mode wildcard DNS/TLS is unproven on real infrastructure** (§1).
- **The AI layer has only been run against a fake model client.** Point it at a
  real endpoint and re-check before promising anything about it.
- **A screen-reader pass has not been done.** Automated accessibility checks
  (axe-core) are green; that is not the same as usable.
- **Sprint burndown is data-only** — velocity and cycle time are computed, but
  there is no chart yet.

## 9. Where to look when something breaks

| Symptom | Look at |
|---|---|
| SSO bounces to "single sign-on failed" | Boot logs for `Authentication failure!` — the reason follows it. Then §5. |
| A module's pages 404 for everyone | Admin → Tenants → Modules. A 404 here means "not entitled", by design. |
| API returns `403 feature_disabled` | Same — the response body names the module. |
| Emails not sending | SMTP settings, then whether the in-Puma worker is running. |
| Recurring jobs not firing | `config/recurring.yml` + the worker; sweeps are per tenant and skip tenants without the relevant module. |
| An import did the wrong thing | Re-run the dry run and read `UNMAPPED`. Imports are idempotent; fix the mapping and re-apply. |
