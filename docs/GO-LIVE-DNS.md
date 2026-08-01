# Docket go-live DNS record set (pilot)

Copy-pasteable DNS for the Chunk C pilot. Two independent zones are covered:

- **(a) Isolated pilot host** — the sovereign single-tenant instance (one hostname, no
  wildcard). This is the recommended first pilot per `GO-LIVE-VALIDATION.md` §2.
- **(b) Shared staging base domain** — a separate multi-tenant instance that proves
  wildcard subdomain routing. Kept deliberately apart from the pilot buyer's data.

Mail plumbing is the same shape for both: **Netcore SMTP outbound**, **Cloudflare DNS**
for SPF/DKIM/DMARC, **AWS SES inbound in `ap-south-1`** relaying into Action Mailbox.
Netcore, SES, and Cloudflare are named here as the concrete providers; the app itself
only reads the generic `SMTP_*` / relay / DKIM seams documented in
`DEPLOYMENT-HANDOFF.md` (§ Environment variables). This file does **not** re-document
those env vars — see `RUNBOOK-GO-LIVE.md` and `ALLOWED-HOSTS-CONFIG.md`.

> **Placeholders.** Every `<ANGLE_BRACKET>` value must be filled from a provider console
> (Netcore, AWS SES, or Cloudflare). Nothing below should ship with a placeholder still
> in it. Values that must come from a console are flagged `OWNER-EXECUTED` in
> `RUNBOOK-GO-LIVE.md`.

> **Cloudflare gotcha.** Proxy (orange-cloud) must be **OFF / DNS-only** for every mail
> record: all MX records and any mail A/AAAA host. Only the web app's A/AAAA (and the
> shared wildcard) may stay proxied — and the shared web host needs a **real wildcard
> TLS certificate** for `*.staging.example.com`, not Cloudflare's edge cert alone if you
> terminate TLS at your own origin.

---

## Naming used in the examples

Replace the example domains with the customer's real names before publishing the zone.

| Placeholder in examples | Meaning | Example value used below |
|---|---|---|
| pilot app host | isolated pilot web/app hostname (drives `DOCKET_BASE_URL`) | `support.pilot.example.com` |
| pilot sending domain | dedicated outbound From subdomain | `mail.pilot.example.com` |
| pilot inbound domain | domain SES receives on (the `To:` of customer replies) | `support.pilot.example.com` |
| staging base domain | shared wildcard base (`DOCKET_BASE_DOMAIN`) | `staging.example.com` |
| staging sending domain | shared outbound From subdomain | `mail.staging.example.com` |

The **inbound domain** is the one whose MX points at SES. For the isolated pilot it is
typically the same host customers reply to. For shared staging the inbound domain is the
base domain (so `support@acme.staging.example.com` resolves tenant `acme` — see
`GO-LIVE-VALIDATION.md` §4).

---

## (a) Isolated pilot host

### Table — all records for the isolated pilot

| Type | Name (host) | Value / target | TTL | Proxy | Source of value |
|---|---|---|---|---|---|
| A | `support.pilot.example.com` | `<PILOT_ORIGIN_IPV4>` | auto | proxied OK | your host/load balancer |
| AAAA | `support.pilot.example.com` | `<PILOT_ORIGIN_IPV6>` (if any) | auto | proxied OK | your host/load balancer |
| TXT (SPF) | `mail.pilot.example.com` | `v=spf1 include:<NETCORE_SPF_INCLUDE> ~all` | auto | n/a | **Netcore** — confirm exact include token |
| CNAME (DKIM, Netcore) | `<NETCORE_SELECTOR>._domainkey.mail.pilot.example.com` | `<NETCORE_SELECTOR>.dkim.netcorecloud.net.` | auto | DNS-only | **Netcore** — selector + target |
| MX (SES inbound) | `support.pilot.example.com` | `10 inbound-smtp.ap-south-1.amazonaws.com.` | auto | DNS-only | AWS SES (ap-south-1) |
| TXT (SES verify) | `_amazonses.support.pilot.example.com` | `<SES_VERIFICATION_TOKEN>` | auto | DNS-only | **AWS SES** console |
| CNAME (SES DKIM 1) | `<SES_TOKEN_1>._domainkey.support.pilot.example.com` | `<SES_TOKEN_1>.dkim.amazonses.com.` | auto | DNS-only | **AWS SES** Easy DKIM |
| CNAME (SES DKIM 2) | `<SES_TOKEN_2>._domainkey.support.pilot.example.com` | `<SES_TOKEN_2>.dkim.amazonses.com.` | auto | DNS-only | **AWS SES** Easy DKIM |
| CNAME (SES DKIM 3) | `<SES_TOKEN_3>._domainkey.support.pilot.example.com` | `<SES_TOKEN_3>.dkim.amazonses.com.` | auto | DNS-only | **AWS SES** Easy DKIM |
| TXT (DMARC) | `_dmarc.pilot.example.com` | `v=DMARC1; p=none; rua=mailto:dmarc-reports@pilot.example.com; adkim=s; aspf=s` | auto | DNS-only | you (start monitoring) |

Notes on the isolated set:

- **One SPF record per domain.** If `mail.pilot.example.com` already has an SPF TXT,
  merge the `include:<NETCORE_SPF_INCLUDE>` token into the existing record — never add a
  second SPF TXT.
- **DKIM has two independent signers.** Netcore signs outbound at its relay
  (`<NETCORE_SELECTOR>._domainkey.mail.pilot.example.com`). SES publishes its own three
  Easy-DKIM CNAMEs on the **inbound** domain for its own receiving/verification. They are
  distinct and both are expected.
- **App-level DKIM is normally OFF for the pilot.** Because Netcore signs outbound, leave
  `DOCKET_DKIM_*` unset. Only if you sign in-app instead of at Netcore, publish:
  `TXT <DOCKET_DKIM_SELECTOR>._domainkey.mail.pilot.example.com = v=DKIM1; k=rsa; p=<PUBKEY>`
  (see `OPERATOR-GUIDE.md` § Vault key setup and rotation for the app-level DKIM DNS
  instructions — do not enable both).
- **DMARC is published once at the organizational domain** (`_dmarc.pilot.example.com`),
  not per host. Start `p=none` with `rua` reporting; tighten only after SPF+DKIM align on
  every sender (see the tighten path at the bottom of this file).

### Cloudflare-zone-style list — isolated pilot

```dns
; --- web app -----------------------------------------------------------------
support.pilot.example.com.                 A     <PILOT_ORIGIN_IPV4>        ; proxied OK
; support.pilot.example.com.               AAAA  <PILOT_ORIGIN_IPV6>       ; proxied OK (if used)

; --- Netcore SMTP outbound (mail.pilot.example.com) --------------------------
mail.pilot.example.com.                    TXT   "v=spf1 include:<NETCORE_SPF_INCLUDE> ~all"
; TODO(Netcore): paste the selector + target Netcore gives you. Typical shape:
<NETCORE_SELECTOR>._domainkey.mail.pilot.example.com.  CNAME  <NETCORE_SELECTOR>.dkim.netcorecloud.net.   ; DNS-only
; If Netcore hands you a raw public key instead of a CNAME, publish it as:
; <NETCORE_SELECTOR>._domainkey.mail.pilot.example.com.  TXT  "v=DKIM1; k=rsa; p=<NETCORE_PUBKEY>"

; --- AWS SES inbound (ap-south-1), receiving on support.pilot.example.com -----
support.pilot.example.com.                 MX    10 inbound-smtp.ap-south-1.amazonaws.com.   ; DNS-only
_amazonses.support.pilot.example.com.      TXT   "<SES_VERIFICATION_TOKEN>"                  ; DNS-only
<SES_TOKEN_1>._domainkey.support.pilot.example.com.  CNAME  <SES_TOKEN_1>.dkim.amazonses.com.  ; DNS-only
<SES_TOKEN_2>._domainkey.support.pilot.example.com.  CNAME  <SES_TOKEN_2>.dkim.amazonses.com.  ; DNS-only
<SES_TOKEN_3>._domainkey.support.pilot.example.com.  CNAME  <SES_TOKEN_3>.dkim.amazonses.com.  ; DNS-only

; --- DMARC (organizational domain, monitoring first) -------------------------
_dmarc.pilot.example.com.                  TXT   "v=DMARC1; p=none; rua=mailto:dmarc-reports@pilot.example.com; adkim=s; aspf=s"   ; DNS-only
```

---

## (b) Shared staging base domain + wildcard host

Shared mode requires `DOCKET_DEPLOYMENT_MODE=shared` and `DOCKET_BASE_DOMAIN=staging.example.com`
(see `ALLOWED-HOSTS-CONFIG.md`). The web tier answers on `*.staging.example.com`; inbound
mail arrives as `<tenant-subdomain>@staging.example.com` so `CasesMailbox` can derive the
tenant from the recipient subdomain (`GO-LIVE-VALIDATION.md` §4).

### Table — all records for shared staging

| Type | Name (host) | Value / target | TTL | Proxy | Source of value |
|---|---|---|---|---|---|
| A | `*.staging.example.com` | `<STAGING_ORIGIN_IPV4>` | auto | proxied OK (needs real wildcard cert) | your host/load balancer |
| A | `staging.example.com` (apex/base) | `<STAGING_ORIGIN_IPV4>` | auto | proxied OK | your host/load balancer |
| TXT (SPF) | `mail.staging.example.com` | `v=spf1 include:<NETCORE_SPF_INCLUDE> ~all` | auto | n/a | **Netcore** — confirm include token |
| CNAME (DKIM, Netcore) | `<NETCORE_SELECTOR>._domainkey.mail.staging.example.com` | `<NETCORE_SELECTOR>.dkim.netcorecloud.net.` | auto | DNS-only | **Netcore** — selector + target |
| MX (SES inbound) | `staging.example.com` | `10 inbound-smtp.ap-south-1.amazonaws.com.` | auto | DNS-only | AWS SES (ap-south-1) |
| TXT (SES verify) | `_amazonses.staging.example.com` | `<SES_VERIFICATION_TOKEN>` | auto | DNS-only | **AWS SES** console |
| CNAME (SES DKIM 1) | `<SES_TOKEN_1>._domainkey.staging.example.com` | `<SES_TOKEN_1>.dkim.amazonses.com.` | auto | DNS-only | **AWS SES** Easy DKIM |
| CNAME (SES DKIM 2) | `<SES_TOKEN_2>._domainkey.staging.example.com` | `<SES_TOKEN_2>.dkim.amazonses.com.` | auto | DNS-only | **AWS SES** Easy DKIM |
| CNAME (SES DKIM 3) | `<SES_TOKEN_3>._domainkey.staging.example.com` | `<SES_TOKEN_3>.dkim.amazonses.com.` | auto | DNS-only | **AWS SES** Easy DKIM |
| TXT (DMARC) | `_dmarc.staging.example.com` | `v=DMARC1; p=none; rua=mailto:dmarc-reports@staging.example.com; adkim=s; aspf=s` | auto | DNS-only | you (start monitoring) |

Notes on the shared set:

- **Wildcard A + explicit base A.** `*.staging.example.com` catches tenant subdomains;
  an explicit record for the base itself is kept so the apex resolves (it should
  fail-closed at the app layer to 404 — `GO-LIVE-VALIDATION.md` §2, not at DNS).
- **Wildcard TLS is mandatory.** Provision a real `*.staging.example.com` certificate. A
  single-host cert will break tenant subdomains.
- **SES receives on the base domain**, so a single MX + one SES identity verification
  serves every tenant subdomain recipient. You do **not** publish per-subdomain MX.
- **Prove isolation.** Create at least two real tenant rows (two subdomains) and test one
  **unknown** subdomain — it must 404 and must not route inbound mail to the primary
  tenant (`GO-LIVE-VALIDATION.md` §2, §4).

### Cloudflare-zone-style list — shared staging

```dns
; --- web app (wildcard + base) ----------------------------------------------
*.staging.example.com.                     A     <STAGING_ORIGIN_IPV4>     ; proxied OK — needs real *.staging cert
staging.example.com.                       A     <STAGING_ORIGIN_IPV4>     ; proxied OK

; --- Netcore SMTP outbound (mail.staging.example.com) ------------------------
mail.staging.example.com.                  TXT   "v=spf1 include:<NETCORE_SPF_INCLUDE> ~all"
; TODO(Netcore): paste the selector + target Netcore gives you.
<NETCORE_SELECTOR>._domainkey.mail.staging.example.com.  CNAME  <NETCORE_SELECTOR>.dkim.netcorecloud.net.  ; DNS-only

; --- AWS SES inbound (ap-south-1), receiving on staging.example.com ----------
staging.example.com.                       MX    10 inbound-smtp.ap-south-1.amazonaws.com.   ; DNS-only
_amazonses.staging.example.com.            TXT   "<SES_VERIFICATION_TOKEN>"                   ; DNS-only
<SES_TOKEN_1>._domainkey.staging.example.com.  CNAME  <SES_TOKEN_1>.dkim.amazonses.com.  ; DNS-only
<SES_TOKEN_2>._domainkey.staging.example.com.  CNAME  <SES_TOKEN_2>.dkim.amazonses.com.  ; DNS-only
<SES_TOKEN_3>._domainkey.staging.example.com.  CNAME  <SES_TOKEN_3>.dkim.amazonses.com.  ; DNS-only

; --- DMARC (monitoring first) -----------------------------------------------
_dmarc.staging.example.com.                TXT   "v=DMARC1; p=none; rua=mailto:dmarc-reports@staging.example.com; adkim=s; aspf=s"  ; DNS-only
```

---

## DMARC tighten path (both zones)

Per `GO-LIVE-VALIDATION.md` §3, start in monitoring, then enforce:

1. **`p=none`** (published above) — collect `rua` aggregate reports. Confirm every
   legitimate sender (Netcore relay, any transactional path) shows **SPF pass + DKIM pass
   with aligned domains**.
2. **`p=quarantine`** with an optional `pct=` ramp once alignment is clean for the full
   reporting window.
3. **`p=reject`** as the customer-approved end state.

Only advance a stage after the previous stage's reports are clean. Do not skip straight to
`reject`.

## Provider-console placeholder checklist

Before the zone is considered complete, every item below must be replaced with a real
value pulled from the named console (each is `OWNER-EXECUTED` in `RUNBOOK-GO-LIVE.md`):

- [ ] `<NETCORE_SPF_INCLUDE>` — Netcore SMTP sending-domain SPF include token.
- [ ] `<NETCORE_SELECTOR>` (+ target) — Netcore DKIM selector CNAME/TXT.
- [ ] `<SES_VERIFICATION_TOKEN>` — AWS SES domain-verification TXT.
- [ ] `<SES_TOKEN_1..3>` — AWS SES Easy-DKIM CNAME triplet.
- [ ] `<PILOT_ORIGIN_IPV4>` / `<STAGING_ORIGIN_IPV4>` — origin/load-balancer address.
- [ ] `dmarc-reports@…` mailbox exists and is monitored.
