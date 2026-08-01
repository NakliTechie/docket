# Allowed hosts + deployment mode — quick config note

Focused reference for the exact host-authorization and tenancy config values, isolated vs
shared. This is the "what do I actually set" companion to `GO-LIVE-DNS.md` and
`RUNBOOK-GO-LIVE.md`; the full env-var table lives in `DEPLOYMENT-HANDOFF.md`.

Var names and behavior are exactly what the app reads —
`config/environments/production.rb` (host authorization, lines ~142–152) and
`config/initializers/tenancy.rb` (mode validation).

## How the allowed-host list is built

Rails' `config.hosts` is assembled at boot from:

1. **`DOCKET_BASE_URL`** — its host is added automatically. This is the primary knob; you
   rarely need anything else. `DOCKET_BASE_URL` must be a valid `http(s)` origin with **no
   userinfo, path, query, or fragment**, or the app **raises at boot**.
2. **`DOCKET_ALLOWED_HOSTS`** — optional comma-separated extra hostnames (whitespace
   trimmed, blanks dropped). Use for proxy/load-balancer aliases or a bare IP.
3. **`DOCKET_HOST`** — legacy/compat single host, also appended if set. Prefer
   `DOCKET_BASE_URL`.
4. **Shared wildcard** — only when `DOCKET_DEPLOYMENT_MODE=shared` **and**
   `DOCKET_BASE_DOMAIN` is set, the app appends `.<DOCKET_BASE_DOMAIN>` (leading dot),
   which Rails treats as a wildcard matching the base domain **and every subdomain**.

`/up` and `/healthz` are **excluded** from host authorization, so health checks always
pass regardless of Host header.

> **Legacy caveat.** If `DOCKET_ALLOWED_HOSTS`, `DOCKET_HOST`, **and** `DOCKET_BASE_URL`
> are all unset, Rails keeps its unrestricted default (no host authorization). For any
> real deployment, always set `DOCKET_BASE_URL`.

## Deployment mode

`DOCKET_DEPLOYMENT_MODE` (`config/initializers/tenancy.rb`):

- Defaults to `isolated`.
- Only `isolated` or `shared` are accepted — **any other value raises at boot** (fail-fast
  on typos).
- `shared` sets `ActsAsTenant.require_tenant = true` (fails closed on unscoped queries);
  `isolated` is lenient because there is exactly one tenant row.

`DOCKET_BASE_DOMAIN` is **required in shared mode** (it drives both the wildcard allowed
host and subdomain→tenant resolution) and is **unused in isolated mode**.

---

## Isolated (sovereign single-tenant pilot)

One host, no wildcard, no subdomain routing.

```sh
DOCKET_DEPLOYMENT_MODE=isolated        # or omit — isolated is the default
DOCKET_BASE_URL=https://support.pilot.example.com
DOCKET_ALLOWED_HOSTS=                   # optional extras only; base-url host is auto-added
# DOCKET_BASE_DOMAIN  — DO NOT SET in isolated mode
```

Worked example — pilot host `support.pilot.example.com` reached through a proxy that also
answers on an internal alias `pilot-lb.internal`:

```sh
DOCKET_DEPLOYMENT_MODE=isolated
DOCKET_BASE_URL=https://support.pilot.example.com
DOCKET_ALLOWED_HOSTS=pilot-lb.internal
```

Resulting `config.hosts` effectively allows: `support.pilot.example.com` (from base URL)
and `pilot-lb.internal` (extra). Any other Host is rejected. `Tenant.resolve_by_host`
returns the singleton `Tenant.primary` for every request — there is no subdomain parsing.

---

## Shared (multi-tenant wildcard staging)

Wildcard host + subdomain→tenant resolution.

```sh
DOCKET_DEPLOYMENT_MODE=shared
DOCKET_BASE_DOMAIN=staging.example.com          # REQUIRED
DOCKET_BASE_URL=https://app.staging.example.com # a real tenant subdomain origin
DOCKET_ALLOWED_HOSTS=                            # optional; wildcard is auto-added
```

Worked example — base domain `staging.example.com` with tenants `acme` and `globex`:

```sh
DOCKET_DEPLOYMENT_MODE=shared
DOCKET_BASE_DOMAIN=staging.example.com
DOCKET_BASE_URL=https://app.staging.example.com
```

Resulting `config.hosts` includes `.staging.example.com` (wildcard) — so
`acme.staging.example.com`, `globex.staging.example.com`, and the base itself all pass host
authorization. Then per request:

- `acme.staging.example.com` → subdomain label `acme` → `Tenant.active.find_by(subdomain: 'acme')`.
- `globex.staging.example.com` → tenant `globex`.
- `unknown.staging.example.com` → no active tenant → `nil` → controller returns **404**
  (fail closed).
- `staging.example.com` (base/apex) → no subdomain label → fail closed.

Subdomain rules (`app/models/tenant.rb`): the host is lowercased and trailing-dot stripped;
with `DOCKET_BASE_DOMAIN` set it must end with `.staging.example.com`, and the label before
it must match `[a-z0-9][a-z0-9-]*`. The same resolver feeds CORS
(`lib/docket/cors.rb`), SSO (`app/services/sso.rb`), tenant URL building
(`lib/docket/tenant_url.rb`), and inbound mail tenant derivation
(`app/mailboxes/cases_mailbox.rb`).

To prove the wildcard: create **≥2 real tenant rows** and test **one unknown subdomain**
(must 404) — see `GO-LIVE-VALIDATION.md` §2.

---

## TLS reminder

`DOCKET_FORCE_SSL` is a single switch: `force_ssl` + `assume_ssl` are **ON by default**
(sovereign posture) and disabled only when `DOCKET_FORCE_SSL` is exactly the string
`false` — set that only behind a TLS-terminating proxy that sets `X-Forwarded-Proto`.
Shared mode needs a real `*.staging.example.com` wildcard certificate.

## At a glance

| Setting | Isolated pilot | Shared staging |
|---|---|---|
| `DOCKET_DEPLOYMENT_MODE` | `isolated` (or unset) | `shared` |
| `DOCKET_BASE_DOMAIN` | unset | `staging.example.com` (required) |
| `DOCKET_BASE_URL` | `https://support.pilot.example.com` | `https://app.staging.example.com` |
| Wildcard in `config.hosts`? | no | yes (`.staging.example.com`, auto) |
| Host resolution | always `Tenant.primary` | subdomain → tenant; unknown → 404 |
| TLS cert | single host | real `*.staging.example.com` wildcard |
| Bad mode value | — | boot **raises** (fail-fast) |
