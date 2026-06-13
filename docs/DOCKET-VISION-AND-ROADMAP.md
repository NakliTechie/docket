# Docket — Vision & Roadmap

**Sovereign case-management and citizen/customer-360 platform with an in-deployment agentic resolution layer. The free, public-code answer to Salesforce Service Cloud + Agentforce for the Indian public sector.**

Track: standalone commercial venture (open-core). Sibling product to Parley — shared chassis and support-agent primitive, separate product, separate datastore, separate deployment story.

---

## 1. Why now

Salesforce India has a dedicated public-sector unit, has launched Agentforce for Public Sector, is in talks with governments on agentic AI for citizen services, and is actively pitching PSBs on agentic layers for customer service (Bhattacharya, IANS, June 2026). The deal shape they are chasing with public money is **service + case management + AI agent** — not pipeline CRM.

Docket contests exactly that deal shape with three arguments procurement cannot ignore:

1. **Public funds → public code.** AGPL-3.0 core. Any department or bank can read, audit, and fork what runs on citizen data.
2. **Data sovereignty by construction.** Self-hosted single-tenant on the buyer's infrastructure (MeghRaj/NIC cloud, bank datacenter, on-prem). The AI layer runs operator-owned models inside the deployment. Zero data egress to any foreign SaaS — not as policy, as architecture.
3. **Zero per-seat licensing.** The line item Salesforce monetises is the line item Docket deletes from the RFP.

## 2. What Docket is

One product, three capabilities:

- **Case management** — intake, triage, lifecycle, SLA, escalation, closure, full audit trail. Grievances, service requests, support tickets: same object, different vocabulary per deployment.
- **Citizen/customer 360** — every contact's full interaction history in one timeline: cases, communications, resolutions. The "single view" Salesforce sells as Customer 360.
- **Agentic resolution** — tier-1 cases resolved conversationally by an agent running on models inside the deployment (Ollama/vLLM endpoint), with confidence gating: resolve / draft-for-human-review / route-to-queue. BYOK frontier escape hatch available but off by default in sovereign deployments. Resolve-don't-deflect — Parley's locked principle, inherited.

What Docket is **not** (not contested): forecasting, CPQ, territory management, AppExchange-style marketplace, marketing automation, Salesforce's integration sprawl. Sales-CRM objects arrive in v1.2 as a module, not the anchor.

## 3. Who buys, who sells

- **Buyer**: Indian PSBs, PSEs, central/state departments, municipal bodies, regulators — anyone with a grievance/service obligation and a data-sovereignty constraint. Secondary: any enterprise wanting Service-Cloud capability without Service-Cloud pricing.
- **Operator/seller model**: Docket core is free. Revenue = managed hosting, deployment, support SLAs, compliance packaging, model fine-tuning services. **Netcore is the first customer and the first seller into PSEs** — they carry the procurement paper, ops, and (where the buyer permits) the comms pipe. The operator framework is open: Netcore is operator #1, not the only possible operator. Frappe/ERPNext is the proven Indian precedent for this motion.
- The comms boundary: in sovereign deployments, outbound email/SMS routes through whatever gateway the buyer configures. Netcore's pipe is a configuration default an operator can set, never a hard dependency.

## 4. Architecture posture

- **Chassis**: Ruby on Rails 8 + Hotwire. Same chassis family as the commerce platform and Parley. Postgres primary; SQLite for dev/demo. Solid Queue + Solid Cache — no Redis, no external dependencies that complicate self-hosting.
- **Two deployment topologies, one codebase** (decision 2026-06-13). *Isolated* — the default and the sovereign procurement asset: one deployment = one organisation = one database, with nothing of another client in it. *Shared* — multiple tenants on shared infrastructure, scoped by `tenant_id` and resolved by subdomain (`acme.docket.app`), for SMBs who can't fund a dedicated instance. The core now carries a `tenant_id` and runs tenant-scoped (`acts_as_tenant`), but an **isolated deploy is the degenerate single-tenant case** — one tenant row, scoping a constant predicate — so "your data, your database, no other client's rows" stays literally true. The mode is set per deploy by `DOCKET_DEPLOYMENT_MODE` (`isolated`|`shared`, default `isolated`); scoping fails closed in shared mode. "Isolation is the product" remains true for the isolated SKU — it is simply no longer the *only* model.
- **Shared primitive**: the support-agent primitive (operator-owned small models, confidence gating, BYOK escape hatch) is shared with Parley at the pattern level. Code reuse where clean; no shared runtime, no shared DB.
- **Agent face is non-negotiable**: every UI action is a REST API call. OpenAPI spec generated. Docket's own AI agent and any external agent consume the same API. NakliPoster collection ships with v1.0.
- **Audit**: append-only, hash-chained audit log on every case mutation (tamper-evident pattern proven in Sunshine). For a government buyer this is a headline feature, not plumbing.
- **i18n**: English + Hindi at v1.0; rails-i18n structure for the rest of the Eighth Schedule over time.
- **a11y**: WCAG 2.1 AA / GIGW-aligned.
- **Licence**: AGPL-3.0 core (consistent with Crate). Operator tooling may be commercial.

## 5. Roadmap

### v1.0 — the deployable anchor
- Core objects: Case, Contact, Organisation/Department, Queue, SLA policy, User/Role.
- Intake: web portal form (public, no-login grievance submission with tracking ID) + inbound email.
- Case lifecycle: statuses, assignment, queues, SLA timers, escalation rules, internal notes, public replies.
- Citizen/customer 360 timeline per contact.
- Agentic resolution layer: in-deployment model endpoint (Ollama/vLLM, OpenAI-compatible API), knowledge grounded on closed-case corpus + uploaded docs, confidence-gated actions, full conversation log on the case.
- Staff agent console: keyboard-first unified workspace — next-case hotkey, macros/canned responses, case + 360 side-by-side.
- AI assist for staff: thread summarisation, sentiment flag, suggested reply in the console (same in-deployment model).
- RBAC (admin / supervisor / agent / read-only), built-in auth.
- Audit log (hash-chained), basic reporting (volume, SLA compliance, resolution rate, agent-vs-human split).
- Activity & Usage admin view: per-user actions, login history, volume by queue/staff, exportable — the deployment owner's "who's doing what", served from the audit log. No vendor telemetry of any kind.
- REST API for all objects + OpenAPI + NakliPoster collection; service accounts (machine-to-machine) and signed webhooks so the bank's own systems can file, read, and react to cases headlessly.
- Dual SSO: staff SSO against the bank's internal IdP (OIDC + SAML); customer SSO on the public portal against the bank's customer identity (OIDC) with anonymous tracking-ID flow retained.
- en + hi.
- Deployment: Docker Compose self-host package, seed/demo data, smoke-test script.

### v1.1 — the service surface + the acting agent
- **Agent actions (v1.1 anchor)** — Agentforce parity. Admin-registered actions: outbound HTTP calls to the operator's own systems via stored credentials (card status lookup, block card, raise reversal, etc.), invokable by the AI under the same confidence gating — `draft` proposes the action for human approval, `resolve` tier executes within per-action limits. Every invocation audited. This converts the AI from answering to acting.
- **MCP server face** — Docket exposed as an MCP server over the existing API, so the buyer's own AI assistants/copilots file, read, and act on cases natively.
- **Approval processes** — maker-checker chains (case closure, waiver/refund approval) as case states + designated approver roles. Banks live on maker-checker.
- **Assignment/workflow rules** — declarative routing (if category/priority/channel → queue, assignee, notify). Simple rules table, deliberately not a visual flow builder.
- Knowledge base (public + internal articles; the agent's grounding corpus becomes a product surface).
- CPGRAMS-compatible import/export.
- Dashboards (department head view), escalation matrices, citizen satisfaction (CSAT) capture.
- SMS intake/notification via pluggable gateway adapter (Netcore adapter = reference implementation).

### v1.2 — the CRM module + the fleet
- Sales objects: Lead, Deal, Pipeline (kanban), Sequence. Sequences route through the configured comms gateway.
- Connector framework (commerce-platform connector as reference; same interface discipline as ShopifyCloneConnector).
- **Fleet console (operator product)**: provisions, upgrades, monitors, and backs up the fleet — either N **isolated** single-tenant instances (Kamal/K8s, one client one database) or **shared**-instance tenants (provisioned via `Tenants::Provisioner` / the in-app super_admin platform console at `/admin/tenants`). Multi-tenancy is delivered both ways: dedicated-instance isolation for sovereign buyers, shared-tenant for SMBs who can't fund a dedicated instance.

### v1.x candidates (unscheduled)
- IVR intake adapter. DigiLocker/API Setu integration (API-ready in v1.0 schema; integration deferred — no Aadhaar data handling until explicitly scoped with legal posture).
- Additional Indian languages.
- Fine-tuned grievance-domain model as an operator-sold artifact (Sieve-pattern pipeline).

## 6. Risks, named

- **Procurement gravity**: govt RFPs are written around incumbents. Mitigation: Netcore carries paper; AGPL + zero-licence-cost reframes the RFP itself.
- **Agent quality floor**: small in-deployment models must clear tier-1 quality honestly (Edge-First honesty rule applies server-side). Confidence gating ships conservative: draft-for-review default, auto-resolve earned per category.
- **Parley cannibalisation**: deliberate. Parley is the brand-helpdesk wedge; Docket is the sovereign-deployment product. If a buyer fits both, Docket wins and that is fine.
