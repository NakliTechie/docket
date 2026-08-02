# Docket operator and product guide

This guide is the source of truth for the product surfaces that an operator
configures after deployment. The live OpenAPI document at
`/api/v1/openapi.json`, the Roles & permissions screen, and the connector picker
remain authoritative when code and prose differ.

## Product shape

Docket has three independently entitled pillars:

- **Service desk:** portal, live-chat, email/API/IVR intake, routing, business-calendar SLA,
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
11 fixed roles are:

| Role | Intended use and principal authority |
|---|---|
| `super_admin` | Cross-tenant platform operator; every permission. Grant only to the hosting/operator team. |
| `client_admin` | Tenant administrator; manages users, service/CRM/Work configuration, knowledge lifecycles, records, reports, approvals, audit, and connector invocation, but not platform settings, connector administration, or machine credentials. |
| `customer_service_supervisor` | Support team lead; manages queues, routing, SLAs, macros, cases, contacts, operational exports, and approved connector invocation. |
| `finance` | Read access across cases, contacts, CRM, and Work; operational/sales exports and finance read/write. |
| `sales` | Contact, lead, and deal work; pipeline read, sequence enrollment, sales reporting, plus read access to cases and Work. |
| `customer_service` | Case and contact operations, Work read/write, operational reports, and approved connector invocation. |
| `technical` | Case/contact read, Work read/write, operational reports, knowledge read, webhook management, and connector read/operate. |
| `decision_reviewer` | Maker-checker reviewer; reviews connector approvals and appeals, runs decisions, and reads supporting records and audit history. |
| `knowledge_manager` | Owns knowledge drafting, review, publication, retirement, and categorisation without user or platform administration. |
| `auditor` | Read-only oversight across service, CRM, Work, knowledge, audit, and operational/sales exports. |
| `readonly` | Read-only cases, contacts, leads, deals, pipelines, Work, and sales reports. |

Role grants are rank-bounded: an administrator cannot assign a role above their
own tier. `super_admin` is the only cross-tenant role; `client_admin` is the
normal top role inside one customer. First-time staff SSO users default to
`customer_service` unless an explicit, validated IdP role mapping selects
another assignable role.

The wider Salesforce/Freshdesk/Jira role research and the reasons behind this
inventory are recorded in
`plan/_archive/role-inventory-and-market-research-2026-07-30.md`; the current
maintenance snapshot is `plan/role-inventory-current-2026-08-02.md`.

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
| `config:read`, `config:write` | Service-desk, CRM, Work, knowledge, and settings configuration endpoints as allowed by the endpoint policy. |
| `audit:read` | Audit verification and reporting endpoints. |
| `webhooks:manage` | Webhook endpoint and delivery administration. |
| `connectors:read`, `connectors:invoke` | Inspect connectors or invoke enabled connector actions. |

The bearer must pass **both** its scope and the projected application policy;
tenant entitlements apply as a third gate. Identity management—users, API
tokens, and service accounts—is deliberately unavailable to service accounts.
Use `/api/v1/openapi.json` for the complete route and schema inventory. The MCP
catalog is derived from the same document and removes operations disabled by
the tenant's features; MCP creates no additional authority.

Remote AI clients connect at `/api/v1/mcp`. Docket publishes protected-resource
and authorization-server metadata, supports dynamic client registration, and
requires authorization code with PKCE S256 for staff-delegated access. Access
tokens are bound to the MCP resource; rotating refresh tokens require the
`offline_access` scope. The consented OAuth scopes intersect with the user's
role permissions and tenant entitlements. Client-specific setup and the six
packaged workflows are documented in `docs/CONNECT-MCP.md`; the distributable
Agent Skill is in `skills/docket/`.

`connectors:invoke` is a coarse prerequisite, not an action grant. Each service
account also needs an explicit connector/action grant selected in Admin →
Service accounts. Removing the scope or disabling an action makes that action
undiscoverable and non-invokable for the account.

Mutating Work custom-field configuration requires `work:manage` alongside
`config:write`. This keeps workspace administration separate from service-desk
and CRM configuration authority.

## Governed custom fields

Admin → Custom fields manages typed fields for cases, contacts, leads, deals,
and work items. Service-desk supervisors manage case fields. Client admins
manage CRM and Work fields. Keys are immutable API contracts; deactivate a
field to retain historical values without offering it on new forms.

Fields support short or long text, integers, decimals, booleans, dates, and
single- or multi-select vocabularies. Required fields validate every write path.
Reportable fields appear in the distribution report and its CSV export when the
actor holds both resource-read and report-export authority. Console forms, REST
payloads, generic CSV imports, and Salesforce mappings share the same coercion
and validation rules. Record changes retain actor-attributed audit entries.

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

## Knowledge lifecycle

Knowledge articles have `draft`, `under_review`, `published`, and `retired` states plus
`internal` or `public` visibility. Only published articles ground the agent.
Published public articles also appear in the customer portal. Retiring an
article removes it from both surfaces without deleting its history.

Every content, status, language, visibility, or taxonomy change creates an
immutable version row and advances the article's current-version pointer. Admin
→ Knowledge → article title shows the full history, including prior content and
the staff author when available. The API exposes the same history at
`GET /api/v1/reference_docs/{id}/versions`; dedicated publish and retire actions
are also documented in OpenAPI.

Translations are independent locale variants linked by one translation key.
Use **Add translation** from an article rather than creating an unrelated
article. Portal search prefers the visitor's selected language and falls back
to English when that article has no matching variant. Each variant keeps its
own lifecycle, URL, attachments, and version history.

**Manage categories** opens the knowledge-only taxonomy. Categories can nest to
any depth; moving a category updates its displayed path. Deleting a category
detaches its directly assigned articles and records that change as a new article
version. Case categories remain separate because they control routing and AI
auto-resolution.

The public article page records one helpful/not-helpful vote per browser and
article version. Docket stores a one-way visitor-token digest rather than an IP
address. Editing or republishing creates a new version with a fresh score while
retaining older version feedback for audit and analysis.

Portal → Live chat creates a normal case and carries public replies over Action
Cable. Its bearer is stored only as a digest and expires after 24 inactive
hours. Admin → Settings → AI can enable a knowledge answer on this surface.
That option is off by default. The public assistant retrieves only published,
public articles; internal articles and case text from other customers never
enter its prompt. Low-confidence or ungrounded output is not sent.

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
public, tokenized, and suppresses future delivery. Sequence steps support day
and hour waits, optional business-calendar timing, email, SMS, calls, and manual
tasks. Calls and tasks enter the assigned rep's Activity queue. Email receipts
record unique opens, signed-link clicks, and replies. A reply whose From address
matches the enrolled recipient cancels later steps and logs a completed email Activity.
Configure the sequence reply domain under Admin → Settings → Intake so inbound
mail routes `sequence+token` addresses back to this deployment.
Delivered sequence email and SMS receipts appear on the Customer 360 activity
timeline. Skipped or failed deliveries do not appear as customer touches.

Contact, lead, and deal pages share a chronological seller conversation. A rep
can send email from the record when outbound SMTP is available. Each record also
shows a signed `crm+token` BCC address. Add that address to a message sent from a
staff user's registered email to record the outbound copy without sending it
again. Customer replies sent to the same address record as inbound only when the
From address matches the record's contact or lead email. Route both `crm+*` and
`sequence+*` recipients at the configured reply domain into Action Mailbox.

WhatsApp and Telegram handles are identity fields in this release. Their CRM
conversation entries can be imported by a connector. Docket does not send a
WhatsApp or Telegram message from the record composer.

Campaigns provide first-touch attribution without an external analytics service.
Create an active campaign with a unique `utm_campaign`, then use that value in
links to `/inquiry` or a configured web-to-lead form. Docket stores UTM source,
medium, campaign, term, content, landing page, and referrer in structured lead
fields. Lead conversion copies the first touch to its deal. The Sales report
shows windowed lead count, deal count, won count, and currency-separated won
value per campaign. A capture form can supply a fallback active campaign when
its links do not carry UTM parameters.

## Connectors, credentials, webhooks, and effectors

The application registry contains **66** provider implementations. The admin
connector picker is the canonical list. A connector starts in `draft`, stores
non-secret config separately from encrypted credentials, and cannot sync,
ingest, or invoke until it is active and configured. OAuth providers also need
a completed authorization-code connection. `paused`, `error`, and `draft` are
traffic kill switches in every direction.

Pull connectors map into contacts, leads, deals, or cases using an explicit
identity field and target-specific required fields. Active governed custom
fields appear in the connector mapping form and use the same typed validation
as console, API, and import writes. Scheduled sync runs every five minutes and
selects only connectors whose configured interval is due.
Inbound messaging connectors verify their provider signature before creating
or threading a case. Outbound Docket webhooks use `whsec_…` HMAC-SHA256 secrets,
publish no internal notes, and retain delivery attempts with retry history.

The `Telephony / IVR webhook` connector accepts provider-neutral call events at
the connector webhook URL. Sign the raw JSON body with the connector's webhook
secret and send `X-Docket-Signature: sha256=<hex HMAC-SHA256>`. A single event
uses this envelope:

```json
{
  "provider_call_id": "call-100",
  "from_number": "+919876500001",
  "to_number": "18001234",
  "status": "completed",
  "duration_seconds": 82,
  "recording_url": "https://voice.example.in/recordings/call-100",
  "ivr_answers": { "language": "hi", "topic": "pension" },
  "transcript": "My pension is delayed.",
  "started_at": "2026-08-02T10:00:00Z",
  "ended_at": "2026-08-02T10:01:22Z"
}
```

`provider_call_id` and `from_number` are required. A first callback creates one
phone case. Later callbacks update its call state, duration, transcript, and
recording reference without duplicating the case. Terminal states do not
regress when callbacks arrive out of order. Docket stores the provider URL as a
reference; it does not download the recording. Configure retention and access
controls at the voice provider.

Shared credentials are tenant-local encrypted bags for a key/licence reused by
multiple connectors. A connector's own secret wins over the shared value.
Secrets and OAuth token bundles are redacted from logs and audit changesets.

Connector actions are deny-by-default: only explicitly enabled actions are
visible to an agent. Reads may run autonomously; writes normally enter the
human approval queue; irreversible or decision-of-record actions require a
reason and cannot be silently auto-approved. Optional per-agent/per-connector
rolling budgets cap action volume. Every proposal, approval, rejection, and
observation is audited. Admin → Connector invocations is the operational log.

The 66 providers are implementation- and stub-tested, not collectively
production-certified. Before relying on a provider, make one authenticated
read/write round trip in a non-production vendor account and record the result.

## Decisioning and appeals

Decisioning runs hourly or on demand over tenant-owned data. Autonomous signals
apply only reversible actions; `confirm` and `of_record` proposals wait for a
reviewer. Built-in rules flag recent low-CSAT churn risk, open-SLA-breach risk,
and customers with active SLA coverage; imported or legacy cases can receive a
human-confirmed suggestion from the existing routing-rule catalogue. These are
explainable defaults, not predictive ML scores.

A decision of record requires a reasoned order and is contestable. Signed-in
customers can inspect decisions concerning themselves or their cases under
Portal → My decisions and file one pending appeal per decision. Internal CRM
decisions remain outside that customer scope.
Admin → Appeals lets an authorized reviewer record grounds, uphold the decision,
or overturn it; supported effects are reversed while the decision and appeal
history remain audited. The Dashboard reports approval, rejection, and upheld-
appeal override rates per rule for the selected decision cohort.

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
