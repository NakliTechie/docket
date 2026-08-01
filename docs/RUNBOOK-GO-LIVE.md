# Runbook — Docket pilot go-live

Ordered operator runbook for the Chunk C pilot. It sequences the DNS from
`GO-LIVE-DNS.md`, the env from the real app config surface, and the validation checks
already written in `GO-LIVE-VALIDATION.md`. It does **not** duplicate the full env-var
reference (`DEPLOYMENT-HANDOFF.md` § Environment variables), the vault/DKIM detail
(`OPERATOR-GUIDE.md` § Vault key setup and rotation), or the restore drill mechanics
(`RUNBOOK-BACKUP.md`) — it points at them.

Locked topology for this pilot:

- **Isolated single-tenant sovereign instance** for the pilot buyer (recommended first
  pilot, `GO-LIVE-VALIDATION.md` §2).
- **A separate shared multi-tenant staging base domain** to prove wildcard routing —
  kept apart from the buyer's instance and data.

Locked mail: **Netcore SMTP outbound**, **Cloudflare DNS** for SPF/DKIM/DMARC, **AWS SES
inbound in `ap-south-1`** relaying raw RFC 822 into the Action Mailbox relay endpoint.

> **OWNER-EXECUTED.** Any step tagged **OWNER-EXECUTED** is billable, credential-bearing,
> or an irreversible outward action (provisioning cloud resources, minting secrets,
> publishing DNS, sending real mail). The operator/account owner performs these directly;
> this runbook never asks anyone to hand credentials to a third party. Never paste
> credentials, private keys, SES tokens, or the inbound-relay password into source, logs,
> DNS, or the go-live evidence record.

---

## 0. Pre-requisites (before any cutover)

- [ ] Release tag / image digest chosen and the repository + recovery proofs are green
      (this runbook starts where `GO-LIVE-VALIDATION.md` §1 begins recording evidence).
- [ ] Hosting/origin provisioned for both instances; TLS certs available:
      a single-host cert for the isolated pilot and a **real `*.staging.example.com`
      wildcard cert** for shared staging. **OWNER-EXECUTED** (billable infra).
- [ ] Cloudflare zone access for the pilot domain(s). **OWNER-EXECUTED.**
- [ ] Netcore SMTP account provisioned; sending subdomain, SMTP host, username, password,
      the SPF include token, and DKIM selector obtained from the Netcore console.
      **OWNER-EXECUTED** (billable, credential-bearing).
- [ ] AWS SES enabled in **`ap-south-1`**, out of the sandbox if you must send to
      arbitrary recipients, with the receiving domain identity created (verification TXT +
      Easy-DKIM triplet issued). **OWNER-EXECUTED** (billable, credential-bearing).
- [ ] Secret material generated out-of-band and stored in your secret manager (not in the
      repo, not in backups — `RUNBOOK-BACKUP.md` § What this does not cover):
      `SECRET_KEY_BASE`, the vault keyring (`DOCKET_VAULT_KEYS` JSON or a `0600`
      `DOCKET_VAULT_KEYS_PATH` file), `RAILS_INBOUND_EMAIL_PASSWORD`,
      `DOCKET_BACKUP_SIGNING_KEY`. **OWNER-EXECUTED.**
- [ ] One shared vault keyring decided for **all replicas** of a given instance (encryption
      keys derive from `Docket::VaultKeyring`, not the stock Rails encryption envs —
      `config/initializers/active_record_encryption.rb`).

---

## 1. Set environment — isolated pilot host

Example host `support.pilot.example.com`; sending subdomain `mail.pilot.example.com`.
Set these on the pilot instance (var names are exactly what the app reads —
`config/environments/production.rb`, `config/initializers/tenancy.rb`).

```sh
# --- topology ---------------------------------------------------------------
DOCKET_DEPLOYMENT_MODE=isolated        # or omit; 'isolated' is the default
DOCKET_BASE_URL=https://support.pilot.example.com
                                       # validated origin: http(s), no userinfo/path/query
                                       # /fragment or the app RAISES at boot. Drives the
                                       # allowed-host list, mailer links, and SSO redirect.
DOCKET_ALLOWED_HOSTS=                  # optional extra proxy/IP aliases, comma-separated.
                                       # The DOCKET_BASE_URL host is auto-allowed already.
# DOCKET_BASE_DOMAIN is NOT set in isolated mode (no subdomain routing).

# --- TLS --------------------------------------------------------------------
# Leave DOCKET_FORCE_SSL unset to keep force_ssl + assume_ssl ON (sovereign default).
# Set to the literal string 'false' ONLY behind a TLS-terminating proxy that sets
# X-Forwarded-Proto.
# DOCKET_FORCE_SSL=false

# --- secrets / encryption (OWNER-EXECUTED) ---------------------------------
SECRET_KEY_BASE=<64+ hex>              # or let the Docker entrypoint persist
                                       # storage/secret_key_base (SECRET_KEY_BASE_PATH).
DOCKET_VAULT_KEYS=<versioned JSON keyring>
# ...or instead:
# DOCKET_VAULT_KEYS_PATH=storage/vault_keys.json   # 0600 file, one keyring across replicas

# --- Netcore SMTP outbound (OWNER-EXECUTED creds) --------------------------
SMTP_ADDRESS=<Netcore relay host, e.g. smtp.netcorecloud.net>   # if UNSET, mail is
                                       # SILENTLY DISCARDED (delivery_method :docket_null)
SMTP_PORT=587
SMTP_USERNAME=<Netcore SMTP user>      # presence flips authentication to :login
SMTP_PASSWORD=<Netcore SMTP password>
# SMTP_STARTTLS=                        # leave unset -> STARTTLS on; set 'false' only on trusted nets
DOCKET_MAIL_FROM=no-reply@mail.pilot.example.com   # dedicated sending-subdomain From.
                                       # (Setting 'outbound_email_from' overrides this at runtime.)

# --- inbound relay password (OWNER-EXECUTED) -------------------------------
RAILS_INBOUND_EMAIL_PASSWORD=<shared secret for the SES->relay bridge>
                                       # enables Action Mailbox :relay ingress. HTTP Basic
                                       # user is 'actionmailbox', password is this value.

# --- app-level DKIM: normally UNSET for the pilot (Netcore signs) -----------
# DOCKET_DKIM_DOMAIN / DOCKET_DKIM_SELECTOR / DOCKET_DKIM_PRIVATE_KEY(_PATH) — leave unset.
```

Only these five `SMTP_*` vars configure Netcore — there is no `SMTP_DOMAIN`/HELO/TLS-verify
var; point them at Netcore's relay and you are done.

## 2. Set environment — shared staging host

Example base domain `staging.example.com`; sending subdomain `mail.staging.example.com`.
Same secret/SMTP/relay shape as §1 (one shared keyring across replicas), plus the shared
routing vars:

```sh
DOCKET_DEPLOYMENT_MODE=shared
DOCKET_BASE_DOMAIN=staging.example.com     # REQUIRED in shared mode. Enables the
                                           # '.staging.example.com' wildcard allowed-host
                                           # AND subdomain->tenant resolution.
DOCKET_BASE_URL=https://app.staging.example.com   # a real tenant subdomain origin
DOCKET_ALLOWED_HOSTS=                      # optional extras; the '.base-domain' wildcard is
                                           # appended automatically in shared mode.
# DOCKET_FORCE_SSL unset (ON) — needs the real *.staging.example.com wildcard cert.
# SECRET_KEY_BASE / DOCKET_VAULT_KEYS(_PATH) — same as §1, one shared keyring.
# SMTP_* / DOCKET_MAIL_FROM / RAILS_INBOUND_EMAIL_PASSWORD — same shape.
```

Then create **at least two real tenant rows** (two subdomains) and keep one **unknown**
subdomain to test fail-closed 404 (`GO-LIVE-VALIDATION.md` §2). A wrong
`DOCKET_DEPLOYMENT_MODE` value (anything but `isolated`/`shared`) makes the app **RAISE at
boot** — verified fail-fast, not a silent misconfig.

See `ALLOWED-HOSTS-CONFIG.md` for the exact allowed-host resolution rules and worked
examples for both modes.

## 3. DNS + TLS cutover  — OWNER-EXECUTED

1. Publish the record set from `GO-LIVE-DNS.md` in Cloudflare for the correct zone
   (a = isolated pilot, b = shared staging). **OWNER-EXECUTED** (publishing DNS).
2. Keep proxy **DNS-only** for every mail record (all MX, mail A/AAAA). Web A/AAAA and the
   `*.staging` wildcard may stay proxied.
3. Confirm the DKIM/verification records resolve **before** activating SES receipt or
   sending real mail (SES will not confirm the identity until its CNAMEs resolve; Netcore
   will not sign until its selector resolves).
4. Ensure TLS: single-host cert for the isolated pilot, real wildcard cert for shared
   staging. Verify with `openssl s_client` (`GO-LIVE-VALIDATION.md` §2).

## 4. SES inbound receipt rule + relay wiring  — OWNER-EXECUTED

Wire AWS SES (ap-south-1) to POST the raw message into the app's relay endpoint. Path is
fixed by the app:

```text
POST /rails/action_mailbox/relay/inbound_emails
```

HTTP Basic — user `actionmailbox`, password = `RAILS_INBOUND_EMAIL_PASSWORD` (the same
value set in §1/§2). Recommended bridge (per `GO-LIVE-VALIDATION.md` §4): **SES receipt →
S3 → SQS → Lambda → authenticated raw RFC 822 POST** to the relay URL.

Receipt-rule requirements (so `CasesMailbox` accepts the mail — `app/mailboxes/cases_mailbox.rb`):

- [ ] Deliver the **raw MIME** message. Preserve the original `From`, `Subject`, and
      `Message-ID` headers. Do **not** use alias/forwarding that rewrites `From` — it
      defeats sender-match threading.
- [ ] The bridge must set HTTP Basic `actionmailbox:<RAILS_INBOUND_EMAIL_PASSWORD>`, require
      TLS, use bounded retries + a DLQ, and be idempotent on `Message-ID`. Store the
      password only in the Lambda/deployment secret manager — never in DNS, source, logs,
      or evidence. **OWNER-EXECUTED** (credential-bearing).
- [ ] Shared mode: recipients must be `<tenant-subdomain>@staging.example.com` so the
      mailbox derives the tenant from the subdomain; an unknown recipient must **not** route
      to the primary tenant. Isolated mode uses `Tenant.primary`.
- [ ] The receiving tenant must have the **`service_desk`** feature or the mail is bounced.

App-side inbound behavior to expect (do not "fix" these — they are the contract):

- A mail whose `From` is unparseable is **bounced**.
- To thread onto an existing case, the `Subject` must contain a tracking id matching
  `DKT-XXXX-XXXX` **and** the `From` must equal the case contact's email; otherwise a
  **new** case opens.
- Attachments are filtered by the attachable allowlist/size validation.

## 5. Verification checklist (reuse existing tooling — do not duplicate)

Record every check as pass/fail in the `GO-LIVE-VALIDATION.md` §1 evidence record.

- [ ] **Smoke test.** Run `bin/smoke` against the deployed instance:
      `SMOKE_BASE_URL=https://support.pilot.example.com bin/smoke`. It files a portal case,
      replies/resolves via API, registers a webhook, and verifies the audit hash chain —
      the real create/reply/resolve handlers, not a bypass. Expect `PASS`.
- [ ] **Host / TLS / health.** `GO-LIVE-VALIDATION.md` §2 — `/up` and `/healthz` are 200
      (health checks bypass host authorization by design), HTTP→HTTPS redirect works, the
      `DOCKET_BASE_URL` host is accepted while an unapproved Host is rejected. For shared
      staging: two tenant subdomains resolve to their own data, apex + unknown subdomain
      fail closed, no A→B cross-tenant read, wildcard cert covers both.
- [ ] **Outbound mail + auth.** `GO-LIVE-VALIDATION.md` §3 — send to two independent real
      providers; confirm inbox delivery (not just SMTP accept), SPF **pass** + DKIM **pass**
      + DMARC **pass** with aligned domains, links use the HTTPS origin, threading keeps the
      `DKT-XXXX-XXXX` id, and a bounce is visible (no false "delivered"). **OWNER-EXECUTED**
      (sends real mail).
- [ ] **Inbound mail.** `GO-LIVE-VALIDATION.md` §4 — a real provider message traverses
      MX/receipt/S3/SQS/Lambda, returns 204 at the relay, creates exactly one tenant-scoped
      case, retains an allowed attachment, and does not duplicate on an intentional retry.
      Shared: repeat for two tenant recipient subdomains and prove an unknown recipient
      cannot reach the primary tenant.
- [ ] **Backup + restore drill.** Run `bin/backup`, then a full `bin/restore` rehearsal
      (`DOCKET_RESTORE_CONFIRM=yes`) per `RUNBOOK-BACKUP.md` § The drill. Confirm secrets
      (`SECRET_KEY_BASE`, vault keys) are held out-of-band and are **not** expected in the
      backup. **OWNER-EXECUTED** (touches real data/keys).
- [ ] **Migration rehearsal** (if the pilot migrates off an old stack) —
      `GO-LIVE-VALIDATION.md` §5 / `RUNBOOK-MIGRATION.md`, sanitized sandbox exports first.
- [ ] **Accessibility.** For this pilot the human a11y pass is **deferred to a pre-launch
      gate**; **axe-core in CI is the current a11y signal**. The full human VoiceOver/NVDA
      pass in `GO-LIVE-VALIDATION.md` §8 is the pre-launch gate, not a Chunk-C blocker —
      record it as deferred with an owner and due date in the evidence record.

## 6. Rollback

- **DNS.** The cutover is DNS-driven; the fastest rollback is to revert the Cloudflare
  records (drop MX / restore prior A) — but published records propagate on TTL, so keep
  TTLs low during cutover. **OWNER-EXECUTED.**
- **Inbound.** To stop inbound routing immediately, disable the SES receipt rule (or the
  Lambda) — the relay simply stops receiving. Unsetting `RAILS_INBOUND_EMAIL_PASSWORD`
  disables the ingress at the app, but do that only alongside stopping the bridge.
- **Outbound.** Unsetting `SMTP_ADDRESS` reverts delivery to `:docket_null` (mail silently
  discarded) — use only as a deliberate hold, and know that senders get no error.
- **Data.** For a data-level rollback use the restore path in `RUNBOOK-BACKUP.md`
  (`bin/restore`, `DOCKET_RESTORE_CONFIRM=yes`). Preserve the legacy source read-only for
  the agreed rollback window if migrating (`GO-LIVE-VALIDATION.md` §5).
- Do not call the deployment live while any required check is merely "configured" — the
  external observation must exist (`GO-LIVE-VALIDATION.md` §1).

## 7. Closure

Release owner signs off only when host/TLS, outbound, inbound, smoke, backup/restore, and
(where applicable) migration evidence are linked from the release record, and the deferred
a11y gate has an owner + due date (`GO-LIVE-VALIDATION.md` §9).
