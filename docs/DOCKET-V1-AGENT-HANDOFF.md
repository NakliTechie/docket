# Docket — v1.0 Agent Handoff

Companion to `DOCKET-VISION-AND-ROADMAP.md`. This document is the complete instruction set for the implementing agent. Read both before writing code.

---

## 0. AUTONOMY MANDATE — READ FIRST

**This project runs autonomously, end to end, with little to no human intervention.** Execution happens in a Claude cloud container. The human reviews a *finished, smoke-testable v1.0* — not intermediate states.

Operating rules:

1. **Run to completion.** Work through every gate (G1→G4) in sequence without stopping for approval between gates. Self-verify each gate's artifacts, log the verification, continue.
2. **Decide, don't ask.** All naming, implementation choices, library selection within the locked stack, schema details, UI layout, refactors, debugging strategies, and alternative approaches are the agent's authority. When a decision is needed and not locked in this document: make the call that best serves the locked decisions, record it in `DECISIONS.md` (one line: decision, reason, date), and proceed.
3. **Escalate only for** (the complete list):
   - A locked decision in this document is impossible or contradicts another locked decision.
   - A new **paid** or **network-restricted** dependency is genuinely required (free, permissively-licensed gems/packages from rubygems/npm are pre-approved — install freely).
   - Scope ambiguity that literally blocks all forward progress on every remaining workstream. If one workstream blocks, switch to another and note it.
4. **Maximise completion before review.** The review target is: human runs the smoke script, clicks through a seeded demo, reads `DECISIONS.md`, done. Anything that would force the human to debug, configure, or fill gaps is unfinished work.
5. **If something fails repeatedly**, try a different approach. Three distinct failed approaches on a non-core feature → stub it cleanly, mark it in `KNOWN-GAPS.md`, move on. Core features (case CRUD, intake, audit, API) may not be stubbed.

---

## 1. Repo / build / deploy

- Repo: `docket` (new, standalone). Conventional Rails 8 app layout. Licence file: AGPL-3.0.
- Stack (locked): **Ruby on Rails 8, Hotwire (Turbo + Stimulus), importmaps (no node build step), Postgres primary / SQLite for dev-demo, Solid Queue, Solid Cache, Propshaft.** No Redis. No webpack/esbuild. No SPA framework.
- Auth: Rails 8 built-in authentication generator for local accounts, plus dual SSO (§5A). No Devise.
- Deployment deliverable: `docker-compose.yml` (app + Postgres) that boots to a working seeded instance with one command. Document exact commands in README.
- Ruby/Rails versions: latest stable available in the container at build time; record exact versions in `DECISIONS.md`.

## 2. Core objects (locked schema shape; columns are agent's call)

- **Contact** — a citizen/customer. Identity fields, channel handles (email, phone), org link optional, `external_id` (unique, nullable) for the operator's own customer identifier (e.g. a bank CIF) — the join key for headless integration and customer SSO.
- **Organisation** — department/branch/company a contact belongs to.
- **Case** — the anchor object. Subject, description, channel of origin, status, priority, category, queue, assignee, SLA policy, public tracking ID (unguessable, citizen-friendly format e.g. `DKT-7F3K-92QX`).
- **Queue** — routing bucket with membership.
- **SLAPolicy** — first-response + resolution targets per priority; timers and breach flags.
- **Message** — threaded on Case: public reply, internal note, or agent (AI) turn. Direction + author type recorded.
- **User** — staff. Roles: `admin`, `supervisor`, `agent`, `readonly`. Enforce via a single authorisation layer (Pundit or hand-rolled policy objects — agent's call, pick one, use it everywhere).
- **AuditEntry** — see §6.

Case statuses (locked): `new → triaged → in_progress → waiting_on_citizen → resolved → closed`, plus `reopened`. Transitions enforced in one state-machine location.

## 3. Intake channels (v1.0: exactly two)

1. **Public web portal**: two entry paths. (a) Anonymous: no-login grievance/request form → returns tracking ID; public status-check page by tracking ID + email/phone verification challenge. (b) **Customer SSO** (when configured, §5A): "Log in via <bank>" OIDC flow against the deployment's customer IdP; the OIDC subject/claim maps to `Contact.external_id`, and a logged-in customer sees their full case list and files pre-attributed cases — no tracking-ID dance. Anonymous path always remains available (non-customers and walk-in grievances). Hindi/English toggle on the portal.
2. **Inbound email**: Action Mailbox. Parse to new Case or thread onto existing via tracking ID in subject. Attachments stored via Active Storage (local disk in v1.0).

No SMS, no IVR, no chat widget in v1.0. Schema must not preclude them (channel is an enum, extensible).

## 4. Agentic resolution layer (the differentiator — build carefully)

- **Adapter interface first**: a single `LlmClient` abstraction speaking the OpenAI-compatible chat-completions API. Two configs: (a) in-deployment endpoint URL (Ollama/vLLM) — **default**; (b) BYOK external provider — present, off by default, enabling it requires an explicit admin toggle labelled with a data-egress warning.
- **Grounding**: retrieval over (a) closed resolved cases, (b) admin-uploaded reference docs (text/markdown/PDF-extracted-text). Keep retrieval simple and dependency-light: Postgres full-text search is sufficient for v1.0. No vector DB.
- **Confidence gating (locked)** — three actions, conservative defaults:
  - `route`: classify + assign queue/category/priority (always on).
  - `draft`: propose a reply for human review (default for all categories).
  - `resolve`: send reply + resolve case autonomously (OFF by default; enabled per-category by an admin once they trust it).
- Every agent turn is a `Message` with full prompt/response logged on the case. The agent never deletes or edits prior messages. Resolve-don't-deflect: the agent's goal is resolution; it must always offer "talk to a human" and immediately route on request.
- **Staff AI assist** (same LlmClient, console-side): one-click thread summarisation, sentiment flag on incoming messages, suggested reply in the composer (insert-and-edit, never auto-send). All assist outputs ephemeral except where the staff member commits them; suggested-reply usage noted in audit.
- v1.1 forward-compatibility: the gating model (`route`/`draft`/`resolve`) must be designed so a fourth invokable type — **action** (admin-registered outbound HTTP call) — slots in without rework. Do not build actions in v1.0; do not preclude them.
- If no model endpoint is configured, the entire AI layer degrades silently to off — Docket must be fully usable as a non-AI case manager.
- Demo/seed mode: ship a `FakeLlmClient` returning canned plausible outputs so the demo and tests run with no model present.

## 5. API — the agent face (non-negotiable)

- REST JSON API covering **every** object and every action the UI can perform. Versioned under `/api/v1/`.
- Auth, two shapes:
  - **Per-user API tokens** (revocable, admin UI for issuance) — human/staff tooling.
  - **Service accounts** — OAuth2 client-credentials machine-to-machine tokens with **scopes** (e.g. `cases:write`, `cases:read`, `contacts:write`, `webhooks:manage`). This is how the bank's own systems (netbanking, mobile app, branch CRM, IVR backend — whatever they run) call Docket headlessly. Admin UI for creating service accounts, scoping, rotation, revocation.
- **On-behalf-of pattern**: a scoped service account may create/read cases attributed to a Contact by `external_id` (e.g. the bank's netbanking app files a complaint for logged-in customer CIF 447192 → Docket upserts/links the Contact and threads the case under their 360). Attribution recorded in the audit log as `service_account X on behalf of contact Y`.
- **Outbound webhooks**: HMAC-SHA256-signed POSTs on case lifecycle events (created, status change, message added, SLA breach, resolved). Per-endpoint secret, retry with backoff, delivery log in admin UI. This is how bank systems react to Docket without polling.
- **CORS**: admin-configurable origin allowlist so the bank's own web properties can call the API browser-side where they choose to.
- Generated OpenAPI 3 spec served at `/api/v1/openapi.json` (rswag or equivalent — agent's call).
- **NakliPoster collection JSON** covering the full API surface — including a service-account on-behalf-of flow and a webhook-receiver test — committed at `docs/docket-api.nakliposter.json`.

## 5A. SSO — dual identity planes (v1.0, locked)

Two independent identity planes, never mixed:

1. **Staff SSO (internal)** — bank employees sign into the Docket console via the deployment's corporate IdP. **OIDC primary** (omniauth_openid_connect), **SAML 2.0 also shipped** (banks run ADFS). Test both against a containerised Keycloak in CI. JIT user provisioning on first SSO login with default role `agent` (admin promotes); role mapping from an IdP claim/attribute is configurable. Local password auth remains available as break-glass and for deployments without an IdP.
2. **Customer SSO (external)** — the public portal trusts the deployment's *customer* IdP via OIDC (the identity behind netbanking/mobile login). Configured claim → `Contact.external_id` mapping. Customer SSO grants portal-level access only (own cases); it can never reach the staff console — enforce as separate session scopes/guards, separate cookies.

Config for both lives in admin settings (issuer URL, client ID/secret, claim mappings), env-overridable for compose deployments. If neither IdP is configured, both planes silently fall back to v1.0 defaults (local staff auth; anonymous portal).

## 6. Audit log (headline feature)

- Append-only `AuditEntry` on every mutation of Case, Message, Contact, User, and settings: actor, action, before/after diff (JSON), timestamp.
- **Hash-chained**: each entry stores `sha256(previous_hash + canonical_entry_json)`. A rake task verifies the chain end-to-end and reports the first break. Expose chain-verification status on an admin page.
- No destructive deletes anywhere on audited models: soft-delete only.
- **Activity & Usage view** (admin, served from the audit log + sessions): per-user action counts and history, login/SSO history, case volume by queue and staff, date-range filter, CSV export. This is the deployment owner's internal "who's doing what" — it replaces any notion of vendor telemetry and must be clearly framed as the deployment's own data, never transmitted anywhere.

## 7. Design tokens / UI

- **Agent console**: the staff case view is a keyboard-first unified workspace — case thread + contact 360 side-by-side, `j/k`/next-case navigation, single-key status/assign shortcuts, command palette for queue jumps. Document all bindings in the in-app help modal; resolve conflicts in favour of common browser/screen-reader bindings.
- **Macros**: admin-managed canned responses with variable interpolation (contact name, tracking ID), insertable in the composer. Plain Message records when used — no special casing downstream.
- Clean, dense, government-legible. System font stack, generous contrast, no decorative animation. Single CSS file of custom properties as the token source; no Tailwind, no CSS framework.
- Icons: inline SVG sprite (Lucide-style outline set, vendored — no icon font, no CDN).
- Every list view: filter + sort + pagination. Every form: inline validation errors.
- Empty states: each major view ships a designed empty state with the next action ("No cases yet — share your portal link"). Error states: friendly message + reference ID, never a raw stack trace outside dev.
- WCAG 2.1 AA: keyboard-navigable throughout, visible focus rings, labels on all inputs, aria on dynamic Turbo regions.
- i18n: all strings through `t()`, `en.yml` + `hi.yml` complete at ship. No hardcoded UI strings.

## 8. Persistence / security posture

- CSP: strict, no inline script (Stimulus + importmaps comply), no external origins except the configured LLM endpoint.
- Secrets via Rails credentials/env only. Nothing secret in repo or seeds.
- **No telemetry, no phone-home, no update-check, no analytics.** Zero outbound calls except configured LLM endpoint and outbound mail. This is a product guarantee — treat as a locked decision.
- File uploads: type-allowlist, size cap, served via redirect not inline-executed.
- Rate-limit the public portal (Rack::Attack) against submission abuse.
- No Aadhaar or biometric fields anywhere in v1.0 schema.

## 9. Gates & artifacts (self-verified; do not wait between gates)

**Forward pass (mandatory between every gate):** before starting the next gate, run a bug-and-security sweep on everything built so far:

1. Full test suite + RuboCop green.
2. **Brakeman** (static security scan) + **bundler-audit** (dependency CVEs) — zero unresolved warnings; justified suppressions logged in `DECISIONS.md`.
3. Adversarial pass on every surface added this gate, attacker's-eye: authz bypass on each new route (wrong role, no session, expired token, out-of-scope service account), IDOR probes (other contact's case via tracking ID guessing, `external_id` confusion, sequential ID leaks), mass-assignment, portal/email-intake injection (XSS in case bodies, header injection), webhook signature forgery/replay, SSO plane-crossing (customer session reaching staff routes), file-upload abuse, rate-limit verification.
4. Fix everything found before proceeding. Each finding + fix gets one line in `FORWARD-PASS.md` (gate, finding, fix, commit). Unfixable-now items go to `KNOWN-GAPS.md` with severity — but security findings on core surfaces (auth, authz, audit, API) may not be deferred.

The forward pass is part of the gate, not optional hygiene: a gate is incomplete until its forward pass is clean.

- **G1 — Foundation**: schema + migrations, auth, RBAC, Case/Contact/Org CRUD, queues, state machine. Artifacts: passing model+policy tests, `DECISIONS.md` started.
- **G2 — Service loop**: public portal, email intake, messaging/replies, agent console (keyboard workspace + macros), SLA timers + breach flags, audit chain + verification task, Activity & Usage admin view. Artifacts: request/system tests covering citizen-submits→agent-replies→resolve→reopen; keyboard-nav system test; chain-verify task green.
- **G3 — Intelligence + integration surface**: LlmClient + FakeLlmClient, grounding, route/draft/resolve gating, staff AI assist (summarise / sentiment / suggested reply), full REST API, service accounts + scopes + on-behalf-of, outbound webhooks, dual SSO (Keycloak-tested), OpenAPI, NakliPoster collection. Artifacts: API tests for every endpoint incl. M2M and on-behalf-of; webhook signing/retry tests; OIDC + SAML staff login and OIDC customer login green against containerised Keycloak; agent-flow and assist tests against FakeLlmClient.
- **G4 — Ship packaging**: docker-compose, seed data (fictional "Directorate of Public Grievances" + a fictional PSB branch: ~8 users, ~60 cases across statuses, KB-style reference docs), `bin/smoke` script (boots, hits portal, files a case, replies via API, verifies audit chain, prints PASS/FAIL summary), README, in-app help modal. Artifacts: clean-clone → one command → seeded working instance, smoke PASS.

Final deliverable set for human review: working repo, `README.md`, `DECISIONS.md`, `KNOWN-GAPS.md` (may be empty), `FORWARD-PASS.md`, smoke script output, NakliPoster collection.

## 10. README scope

Quickstart (compose up → seeded login), portal walkthrough, enabling a real model endpoint (Ollama example), enabling BYOK (with egress warning), staff SSO setup (Keycloak/ADFS examples) + customer SSO setup, service accounts & on-behalf-of integration recipe, webhooks, API token issuance + NakliPoster import, audit-chain verification, backup (pg_dump + storage dir), licence note (AGPL-3.0).

## 11. What NOT to do (hard rules)

- No Salesforce code, trademarks, or UI imitation close enough to invite a claim. "Salesforce alternative" positioning lives in marketing, not in the product or repo.
- No multi-tenancy in the core — ever, not just v1.0. Single-tenant, one organisation, one database. Do not add `tenant_id` columns "for later"; multi-instance hosting is the fleet console's job (v1.2, separate operator product).
- No Redis, no node build step, no SPA, no vector database, no external CSS/JS CDNs.
- No telemetry of any kind (see §8).
- No Aadhaar/biometric handling.
- No per-seat licence enforcement, seat counting, or feature-gating code paths. The core is free; keep it structurally free.
- No new standing documents beyond README, DECISIONS, KNOWN-GAPS, FORWARD-PASS. Absorb everything else into these.

## 12. Standing question

**What is the agent face of this tool?** Already answered structurally (§5: full API parity + in-product AI agent as first consumer) — but re-ask it at every gate: can an external agent do via `/api/v1/` everything a human just gained in the UI this gate? If not, the gate is not done.

## 13. Escalation protocol

If §0.3 triggers: stop the blocked workstream only, write `ESCALATION.md` (what blocked, the two best options, the agent's recommendation), continue all unblocked work, and surface the escalation at the next human touchpoint. Never idle the whole project on a single blocker.
