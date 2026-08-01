# Docket operator and product guide

This guide is the source of truth for the product surfaces that an operator
configures after deployment. The live OpenAPI document at
`/api/v1/openapi.json`, the Roles & permissions screen, and the connector picker
remain authoritative when code and prose differ.

## Product shape

Docket has three independently entitled pillars:

- **Service desk:** portal, email/API intake, routing, business-calendar SLA,
  saved views and bulk actions, collision signals, replies and attachments,
  merge/split, CSAT, approvals, knowledge, and reports.
- **CRM:** contacts and organisations, configurable web-to-lead forms,
  duplicate review/merge, leads, pipelines, deals, products and line items,
  competitors, sequences, sales reports, and customer 360.
- **Work:** projects, templates, work items, boards, sprints, assignment rules,
  dependencies/duplicates, comments and watches, reports, and transition
  approvals.

Global search joins cases, contacts, leads, deals, and work items while applying
the caller's policies and tenant entitlements. A won deal can explicitly create
one idempotent onboarding project from a template; it is never automatic.

The feature keys are `service_desk` (`kb`, `portal`), `approvals`, `crm`
(`sequences`), `work` (`sprints`), `decisioning`, `connectors`, and `mcp`.
Entitlements only subtract authority: enabling a module never grants a role a
permission it did not already have.

## Roles

Admin → Roles & permissions renders the exact matrix from the application. The
seven fixed roles are:

| Role | Intended use and principal authority |
|---|---|
| `super_admin` | Cross-tenant platform operator; every permission. Grant only to the hosting/operator team. |
| `client_admin` | Tenant administrator; manages users and service/CRM/Work configuration and records, reports, approvals, audit, and connector invocation, but not platform settings, connector administration, or machine credentials. |
| `finance` | Read access across cases, contacts, CRM, and Work; operational/sales reports and finance read/write. |
| `sales` | Contact, lead, and deal work; pipeline read, sequence enrollment, sales reporting, plus read access to cases and Work. |
| `customer_service` | Case and contact operations, Work read/write, operational reports, and approved connector invocation. |
| `technical` | Case/contact read, Work read/write, operational reports, knowledge, webhook management, and connector read/operate. |
| `readonly` | Read-only cases, contacts, leads, deals, pipelines, Work, and sales reports. |

Role grants are rank-bounded: an administrator cannot assign a role above their
own tier. `super_admin` is the only cross-tenant role; `client_admin` is the
normal top role inside one customer. First-time staff SSO users default to
`customer_service` unless an explicit, validated IdP role mapping selects
another assignable role.

The wider Salesforce/Freshdesk/Jira role research and the reasons behind this
inventory are recorded in
`plan/role-inventory-and-market-research-2026-07-30.md`.

## Service-account API scopes

User tokens (`dkt_…`) inherit the user's console permissions. Service-account
tokens (`dkts_…`) must carry one or more of these exact scopes:

| Scope | Capability |
|---|---|
| `cases:read`, `cases:write` | Read or mutate cases, messages, and case workflow. |
| `contacts:read`, `contacts:write` | Read or mutate contacts. |
| `organisations:read`, `organisations:write` | Read or mutate organisations. |
| `crm:read`, `crm:write` | CRM records, capture-form configuration, catalog, deal products/competitors, and sales operations. |
| `work:read`, `work:write` | Work items, comments, and relations. |
| `work:manage` | Projects, templates, sprints, and Work configuration. |
| `config:read`, `config:write` | Service-desk/settings configuration endpoints as allowed by the endpoint policy. |
| `audit:read` | Audit verification and reporting endpoints. |
| `webhooks:manage` | Webhook endpoint and delivery administration. |
| `connectors:read`, `connectors:invoke` | Inspect connectors or invoke enabled connector actions. |

The bearer must pass **both** its scope and the projected application policy;
tenant entitlements apply as a third gate. Identity management—users, API
tokens, and service accounts—is deliberately unavailable to service accounts.
Use `/api/v1/openapi.json` for the complete route and schema inventory. The MCP
catalog is derived from the same document and removes operations disabled by
the tenant's features; MCP creates no additional authority.

## Business calendars and SLA

Create calendars under Service desk → Business calendars. Each calendar has an
IANA/Rails time zone, one or more weekday working windows, and dated exceptions
that are either closed days or custom hours. Only one calendar is the tenant
default. Attach a calendar to each SLA policy; policies without one fall back to
the default calendar, and a tenant without any calendar uses elapsed clock time.

First-response and resolution deadlines are calculated in business minutes.
The resolution clock pauses while a case is `waiting_on_customer`, resumes with
the stored remaining business minutes, stops on resolution/closure, and starts
a new target on reopen. Clock events retain the start, pause, resume, stop,
recalculation, and breach history. Changing SLA inputs recalculates the live
deadline without erasing history.

The breach and risk sweeps run every five minutes. Settings → Notifications can
set the risk window (1–10,080 business minutes; default 60). A risk/breach goes
to the assignee, then queue members if unassigned, then tenant administrators if
no queue recipient exists.

## Notifications and daily workflow

The header inbox consolidates case/work assignments, exact `@email` mentions,
watched-work changes, and SLA risk/breach alerts. It supports unread filtering,
individual open/read, mark-all-read, a live unread badge, deduplication, and
severity escalation. Settings → Notifications optionally emails newly created
or escalated unread notifications; SMTP must be configured for those emails.

Agents can use My Tickets/My Work, saved personal views, safe bulk actions,
action macros, rich public replies, per-agent signatures, and attachments.
Work watchers receive comment and state-change notifications. Case presence is
advisory, so another agent is visible without locking the record. Merge and
split operations preserve messages, attachments, imported identities, work
links, and lineage; old merged URLs resolve to the canonical case.

## Lead inquiry and CRM setup

The legacy public inquiry lives at `/inquiry`. Admin-managed capture forms live
at `/inquiry/:slug` and map explicitly named input fields to supported lead
fields. Each submission records its form, request provenance, consent channel,
and consent time. A honeypot and request throttling protect the unauthenticated
surface. Duplicate detection is exact on normalized email or phone and only
suggests candidates; a human chooses an auditable merge.

Catalog products and deal line items must use the deal's currency. Once a deal
has line items its currency is locked, and its value is the audited sum of
quantity × unit price. Competitor outcomes feed currency-separated loss
reporting. Sequence enrollment requires recorded email consent; unsubscribe is
public, tokenized, and suppresses future delivery.

## Connectors, credentials, webhooks, and effectors

The application registry contains **65** provider implementations. The admin
connector picker is the canonical list. A connector starts in `draft`, stores
non-secret config separately from encrypted credentials, and cannot sync,
ingest, or invoke until it is active and configured. OAuth providers also need
a completed authorization-code connection. `paused`, `error`, and `draft` are
traffic kill switches in every direction.

Pull connectors map into contacts, leads, deals, or cases using an explicit
identity field and target-specific required fields. Scheduled sync runs every
five minutes and selects only connectors whose configured interval is due.
Inbound messaging connectors verify their provider signature before creating
or threading a case. Outbound Docket webhooks use `whsec_…` HMAC-SHA256 secrets,
publish no internal notes, and retain delivery attempts with retry history.

Shared credentials are tenant-local encrypted bags for a key/licence reused by
multiple connectors. A connector's own secret wins over the shared value.
Secrets and OAuth token bundles are redacted from logs and audit changesets.

Connector actions are deny-by-default: only explicitly enabled actions are
visible to an agent. Reads may run autonomously; writes normally enter the
human approval queue; irreversible or decision-of-record actions require a
reason and cannot be silently auto-approved. Optional per-agent/per-connector
rolling budgets cap action volume. Every proposal, approval, rejection, and
observation is audited. Admin → Connector invocations is the operational log.

The 65 providers are implementation- and stub-tested, not collectively
production-certified. Before relying on a provider, make one authenticated
read/write round trip in a non-production vendor account and record the result.

## Decisioning and appeals

Decisioning runs hourly or on demand over tenant-owned data. Autonomous signals
apply only reversible actions; `confirm` and `of_record` proposals wait for a
reviewer. A decision of record requires a reasoned order and is contestable.
Admin → Appeals lets an authorized reviewer record grounds, uphold the decision,
or overturn it; supported effects are reversed while the decision and appeal
history remain audited.

## Security events and import mode

Admin → Sign-in & security shows failed login, throttled login, and rejected SSO
events. Shared-mode reads are tenant-filtered except for the platform
`super_admin`. These events are operational security telemetry inside the
deployment; they are separate from the domain audit hash chain so a logging
failure cannot break authentication.

Migration imports execute in a thread-local **import mode**: historical data is
reconstructed without re-enacting live side effects. It suppresses customer
mail, notifications, CSAT invitations, webhooks, AI/sentiment work, default
assignment/routing, and work-watch activity caused only by imported history.
Dry run remains the default. See `RUNBOOK-MIGRATION.md` for mappings, resume,
delta cutover, attachments, conflicts, and reconciliation.

## Tenant lifecycle, privacy, and legal hold

Suspending a tenant stops normal tenant traffic and background work while
leaving platform administration available. Before permanent purge, export the
tenant and retain the receipt:

```bash
bin/rails 'docket:tenant:export[acme,/secure/exports/acme]'
```

The export contains tenant-owned rows, attachments, checksums, an audit-chain
head, and a manifest. A purge requires a suspended non-primary tenant, an intact
export/manifest, the receipt id, and exact confirmation:

```bash
CONFIRM_TENANT_PURGE='PURGE acme tenant-export-acme-…' \
  bin/rails 'docket:tenant:purge[acme,RECEIPT_ID]'
```

Purge removes all tenant rows and exclusive blobs, scans for residue, and keeps
only redacted chain-valid audit proof. It is irreversible.

A subject erasure is similarly explicit:

```bash
CONFIRM_PRIVACY_ERASURE='ERASE CONTACT 42 FROM acme' \
  bin/rails 'docket:privacy:erase_contact[acme,42]'
```

Erasure deletes attachments and inbound payloads, pseudonymizes direct content
across linked cases/CRM/Work/sequences/notifications/security events, scans for
identifier residue, and retains a minimal redacted audit trail. An active legal
hold blocks erasure until an authorized release.

## Vault key setup and rotation

Production requires a vault keyring independent from `SECRET_KEY_BASE`. Supply
JSON through `DOCKET_VAULT_KEYS` or a 0600 file at
`DOCKET_VAULT_KEYS_PATH` (default `storage/vault_keys.json`):

```json
{"active":"v1","keys":{"v1":"<64 hex characters from openssl rand -hex 32>"}}
```

Default Compose persists this file in its storage volume, so `bin/backup`
includes it (and the generated `secret_key_base`) in `storage.tar.gz`; treat the
archive as secret material. If the keyring comes from an environment secret or
a path outside the archived storage directory, retain that exact keyring
separately with every backup generation. Losing every readable key makes
connector, shared-credential, OAuth, and SSO secrets unrecoverable.

To rotate without downtime:

1. Add a new unique 32-byte hex key, keep the old key, and set `active` to the
   new version.
2. Deploy/restart every app and worker process with the same two-key ring.
3. Run `bin/rails vault:status` and confirm the intended active/readable
   versions without printing key material.
4. Run `DRY_RUN=true bin/rails vault:reencrypt`, then
   `CONFIRM_VAULT_REENCRYPT=v2 bin/rails vault:reencrypt` (replace `v2`).
5. Verify connector/OAuth/SSO secret reads and take a fresh restore-proven
   backup. Remove the old key only after every encrypted row was rewritten and
   all rollback/backup retention that needs it has expired.

`DOCKET_VAULT_INCLUDE_LEGACY_KEY=true` permits reads of data encrypted by an
older `SECRET_KEY_BASE`-derived key during migration. After re-encryption and
proof, set it to `false`; it is not a long-term rotation mechanism.

For outbound authenticity, DKIM is separate: set `DOCKET_DKIM_DOMAIN`,
`DOCKET_DKIM_SELECTOR`, and exactly one of `DOCKET_DKIM_PRIVATE_KEY` or a 0600
`DOCKET_DKIM_PRIVATE_KEY_PATH`, then publish the matching selector TXT record.
The RSA key must be at least 2048 bits. Validate DKIM, SPF, and DMARC in a real
mailbox before go-live.
