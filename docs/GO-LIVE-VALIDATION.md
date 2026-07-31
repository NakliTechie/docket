# Docket go-live validation

Use this after the repository and recovery proofs are green. It records evidence for the
selected customer environment; it is not a substitute for `DEPLOYMENT-HANDOFF.md` or the
migration runbook. Never paste credentials, API tokens, private keys, customer message bodies,
or raw exports into the evidence record.

## 1. Evidence record

Record:

- date/time, operator, release tag/image digest, topology (`isolated` or `shared`);
- public hostname/base domain and infrastructure owner;
- PostgreSQL major, storage backend, mail providers, identity providers and model identifier;
- each command/check below as pass/fail, with sanitized log or provider-event references;
- every exception, owner, due date and explicit risk acceptance.

Do not call the deployment live while a required check is merely “configured.” The expected
external observation must exist.

## 2. Host, TLS, and health

Recommended first pilot: isolated. Prove shared mode separately on a staging wildcard before
offering that SKU.

```bash
curl -fsS https://support.example.com/up
curl -fsS https://support.example.com/healthz
curl -fsSI http://support.example.com/ | grep -i '^location: https://'
openssl s_client -connect support.example.com:443 -servername support.example.com </dev/null
```

Pass requires:

- certificate chain, hostname and expiry valid; HTTP redirects to HTTPS;
- `/up` is 200 and `/healthz` is 200 with database, queue, storage, recurring jobs and failed
  jobs healthy;
- the configured `DOCKET_BASE_URL` host works while an unapproved Host is rejected;
- the worker executes an SLA sweep and another recurring job after the grace window.

For shared staging, create two real tenant subdomains plus one unknown subdomain. Prove each
known host resolves to its own brand/data, the apex and unknown host fail closed, a user/token
from tenant A cannot read tenant B through UI/API/MCP, and the wildcard certificate covers both.

## 3. Outbound mail and authentication

Recommended pilot path: Netcore SMTP, a dedicated sending subdomain, and a dedicated From
address. Configure `SMTP_*`, `DOCKET_MAIL_FROM`, `DOCKET_BASE_URL`, and—when Docket signs—the
`DOCKET_DKIM_*` variables.

Send a password-reset or case-reply message to two independent real mailbox providers. Pass
requires:

- delivery is observed in both inbox/provider event logs, not merely accepted by SMTP;
- every link uses the public HTTPS origin and opens successfully;
- raw headers show SPF pass, DKIM pass and DMARC pass with aligned domains;
- reply threading retains the Docket tracking ID;
- bounce/credential failure is visible to the operator and does not report delivery success.

Start DMARC in monitoring mode only long enough to verify all legitimate senders, then move to
the customer-approved enforcement policy.

## 4. Inbound mail

Recommended path when a subdomain is required: AWS SES receipt in `ap-south-1` → S3 → SQS →
Lambda → authenticated raw RFC 822 POST to:

```text
/rails/action_mailbox/relay/inbound_emails
```

The relay uses HTTP Basic user `actionmailbox` and `RAILS_INBOUND_EMAIL_PASSWORD`. Store that
password only in the deployment/Lambda secret manager. Require TLS, bounded retries, a DLQ and
an idempotent message ID. Do not place it in DNS, source, logs or evidence.

Pass requires a message sent from a real provider to traverse MX/receipt/storage/queue/Lambda,
return HTTP 204 at the relay, create exactly one tenant-scoped case/message, retain an allowed
attachment, and not duplicate after an intentional retry. In shared mode repeat for two tenant
recipient subdomains and prove an unknown recipient cannot route to the primary tenant.

## 5. Migration rehearsal

Use only sanitized sandbox exports first. Follow `RUNBOOK-MIGRATION.md` exactly:

1. preview and clear mappings;
2. bulk apply;
3. interrupt and resume one run;
4. change the same imported field locally and upstream, then prove conflict/local-win behavior;
5. run API delta, final frozen delta and full reconciliation;
6. compare record/attachment counts and sampled histories with source owners;
7. preserve the legacy source read-only for the agreed rollback window.

Pass requires zero unexplained reconciliation error, duplicate identity, missing blob, unmapped
required state, or unintended external side effect.

## 6. Launch connector certification

Certify only the customer launch subset first: Netcore Email, Netcore SMS, Netcore WhatsApp,
Freshdesk, Jira and Salesforce. For each configured sandbox record:

| Provider | Read/sync | Governed write | Evidence |
|---|---:|---:|---|
| Netcore Email | n/a | send one approved test email | provider request/event id + inbox |
| Netcore SMS | n/a | send one approved test SMS | provider id + handset receipt |
| Netcore WhatsApp | n/a | send one approved template/session message | provider id + handset receipt |
| Freshdesk | ticket/contact delta | create/update the agreed sandbox object | source id + Docket invocation |
| Jira | issue/user delta | create/update the agreed sandbox issue | issue key + Docket invocation |
| Salesforce | account/contact/case/lead/opportunity import | agreed sandbox mutation if enabled | Salesforce id + Docket invocation |

For every write, prove authorization, budget, idempotency, human confirmation or decision-of-record
reason as applicable, actor/on-behalf-of attribution, provider response, timeline/audit entry and
safe retry. Never approve a test write against production customer records.

## 7. Production model qualification

Keep the launch model inside the deployment unless the customer explicitly approves data egress.
The local 3B run proves protocol and governance only.

Create an approved evaluation set spanning routine resolution, ambiguity, missing data, hostile
instructions, sensitive data, wrong-tenant references, connector outage and approval-required
actions. Score at least:

- grounded factual correctness and citation/support;
- correct route/draft/resolve choice and calibrated confidence;
- tool/action choice plus schema-valid arguments;
- refusal to follow customer prompt injection or cross-tenant requests;
- no autonomous write where confirmation/of-record review is required;
- latency, timeout, retry and graceful degradation with the model unavailable.

Recommendation: launch with draft/confirm only. Earn category-specific auto-resolution after a
human-reviewed baseline and production monitoring; never enable it from aggregate model reputation.

## 8. Human accessibility pass

Run both VoiceOver + Safari on macOS and NVDA + Chrome on Windows. Do not count axe/system tests as
the human result.

With keyboard and screen reader only, complete:

1. sign in, understand the navigation groups, reach notifications and sign out;
2. find a case, read identity/status/SLA/thread, compose a reply, attach a file, use a macro and
   transition it;
3. save a view, select cases, understand bulk-action scope and recover from a validation error;
4. create/find a lead, inspect duplicate warning, open a deal and understand products/competitors;
5. find a Work item, understand board/list status, add/edit a comment and inspect a dependency;
6. submit and track a portal case, including errors and confirmation;
7. zoom to 200%, test high contrast/reduced motion, and verify focus does not disappear behind
   dialogs or Turbo updates.

Record blocker/major/minor issues with browser, screen reader, exact page/control, expected
announcement, actual announcement and reproduction steps. Go-live requires no blocker and no
unaccepted major issue.

## 9. Closure

The release owner signs off only when production host/mail/inbound evidence, launch connector
round trips, model-quality decision, migration rehearsal (when applicable), accessibility result,
backup schedule and clean restore drill are all linked from the release record.
