# Competitive Review

Point-in-time reviews of adjacent commercial offerings against the implemented
product, recording what they ship, where Docket already matches or exceeds
them, and which gaps are real roadmap candidates versus deliberate posture
decisions. Method note: vendor sites that block automated fetching are sourced
from their own pages via search snippets plus third-party reviews; claims that
could not be verified in Docket's code are not made.

---

## Breakcold — AI-native sales CRM (reviewed 2026-08-01)

Compared: [breakcold.com/features](https://www.breakcold.com/features) and the
MCP offering at [breakcold.com/crm-mcp](https://www.breakcold.com/crm-mcp)
against Docket `1.3.0-alpha.1` + unreleased head (branch state of 2026-08-01).

### What Breakcold is

An AI-native *seller's* CRM for SMB/agency outbound. Two bets:

1. **Every conversation channel a rep uses, unified.** Email, LinkedIn,
   Telegram, WhatsApp, calls and meetings sync into one inbox (sorted by deal
   priority), with a social-engagement feed (prospect posts, job changes,
   company news) and in-CRM LinkedIn engagement (like/comment/DM).
2. **AI agents as first-class users.** A hosted MCP server exposing 55 tools
   generated from their public OpenAPI contract; OAuth *and* bearer auth; a
   packaged MIT-licensed Agent Skill shipping six named workflows
   (stalled-thread triage, pipeline auto-move — never backward, workspace-aware
   reports, prospect-research-to-record notes, inbound contact detection at a
   95% confidence rule, bootstrap-CRM-from-website-URL); setup guides for 17 AI
   clients (Claude.ai/Desktop/Code, ChatGPT, Copilot, …).

Plus the expected core: unlimited kanban pipelines, email campaigns with
open-rate analytics, tasks/reminders/notes/activity history, tags/lists/
segmentation, enrichment via LinkedIn + Zapier.

### Where Docket already matches or exceeds

- Pipelines/stages/deals/leads, sequences with enrollments + unsubscribe
  handling, sales reports, custom fields + reports, duplicate review/merge,
  lead capture forms, routing rules, products/line items, competitors with
  loss reporting, quotes — the CRM skeleton is at or past parity.
- MCP **architecture** parity: Docket also derives its tool catalogue from the
  OpenAPI document (`Mcp::Catalog`), and is better hardened — per-tenant
  entitlement filtering at both `tools/list` and `tools/call`, plus a
  deny-list keeping credential/identity plumbing out of agent reach.
- CRM-side agentic automation exists (`lead_score`, `stalled_deal`,
  `reengage_stale_lead` decisioning rules, confirm-gated) — Breakcold markets
  this loudly; Docket has the substrate with stronger governance (decision
  classes, audit).
- Everything Breakcold doesn't have: service desk, work tracker, audit chain,
  entitlements, sovereignty/self-hosting, i18n.

### Gaps (verified in code, not assumed)

1. **The seller conversation layer — the biggest functional gap.** WhatsApp/
   Telegram/email exist only as *case intake*; a lead or deal has no
   conversation view. Contacts/leads carry no social identities (no
   LinkedIn/X handle, no messaging handle, no job title). Deals have no notes
   field, no next-step/follow-up date, no task or reminder object. No call or
   meeting objects.
2. **Sequence channel depth.** Steps cover email, SMS, rep calls, and manual
   tasks with hour/business-calendar timing. Email receipts cover opens,
   signed-link clicks, and authenticated replies; a reply stops later steps.
   WhatsApp/Telegram remain case-intake channels rather than sequence steps.
3. **Conversation-signal AI.** Breakcold's AI acts on inbox signals (reply →
   advance stage, create follow-up task, enrich record). Docket's rules are
   dwell-time-based because there is no seller conversation stream to watch;
   gap 1 is the prerequisite.
4. **MCP packaging and reach — cheapest, highest leverage.** Docket's MCP auth
   is bearer-only (`/oauth/token` is client-credentials): fine from Claude
   Code/API, but **cannot be added as a claude.ai or ChatGPT custom
   connector**, which require authorization-code OAuth (+ PKCE + dynamic
   client registration). No packaged agent skill, no per-client setup guides,
   no MCP prompts/resources, three lines in the operator guide. Breakcold gets
   MCP-directory discoverability; Docket is invisible there.
5. **360 timeline omits sequence touches.** "What did we last send this
   person" is not answerable from the customer-360.
6. **Social selling + third-party enrichment — likely a deliberate no.** The
   social feed and in-CRM LinkedIn engagement rest on unofficial LinkedIn
   access (no compliant API exists); enrichment implies data egress. Both
   conflict with the sovereignty/no-egress posture, and LinkedIn is the wrong
   channel for the Indian ICP (WhatsApp-first). Record the decision in
   `DECISIONS.md` rather than carrying these as silent gaps.

### Priorities (respecting posture)

1. MCP OAuth: authorization-code + PKCE + dynamic client registration — makes
   "the buyer's own copilots connect natively" true for claude.ai/ChatGPT.
2. Packaged `docket` Agent Skill + per-client setup guides — the tools and
   decisioning rules exist; wrapping 5–6 named workflows is documentation-
   weight work with outsized positioning value.
3. Deal notes and next-step reminders — the shared Activity queue covers calls
   and tasks, but deal-specific planning remains thin.
4. WhatsApp/Telegram sequence steps + sequence touches on the 360 timeline —
   the India-appropriate answer to Breakcold's multichannel story, on
   connectors already built.
5. Longer-term: per-contact unified conversation view (already named as
   roadmap debt in the vision doc) — prerequisite for conversation-signal
   automation.

### Sources

Vendor: [features](https://www.breakcold.com/features),
[crm-mcp](https://www.breakcold.com/crm-mcp),
[skill blog](https://www.breakcold.com/blog/breakcold-skill-best-ai-crm-agent),
[unified inbox](https://www.breakcold.com/features/crm-unified-inbox-linkedin-email),
[setup guides repo](https://github.com/breakcold/mcp).
Third-party: [Capterra](https://www.capterra.com/p/10011093/Breakcold/),
[Salesforge](https://www.salesforge.ai/directory/sales-tools/breakcold),
[Pixelo](https://pixelodigital.com/tools/breakcold.html),
[Prospecting Manual](https://prospectingmanual.com/engagement-crm/breakcold/),
[Woodpecker](https://woodpecker.co/blog/breakcold/).

---

## Zoho suite, minus email — offerings + pricing (reviewed 2026-08-01)

Compared: the Zoho-branded business suite (Zoho One scope, excluding the email
family — Mail, TeamInbox, SalesInbox, ZeptoMail) against Docket
`1.3.0-alpha.1` + head. ManageEngine (ITSM) and Site24x7 are sibling
divisions, not in scope here.

### What the suite is

~50 seat-licensed SaaS apps. The set that overlaps Docket:

- **Service**: Desk (flagship helpdesk: SLAs, Blueprint process automation,
  KB, portal), SalesIQ (live chat/chatbots), Voice + PhoneBridge (telephony/
  CTI), Assist/Lens (remote support), FSM (field service).
- **Sales**: CRM (pipelines, forecasting, workflow, Zia scoring), Bigin (SMB
  pipeline CRM), Bookings, Forms, Sign + Contracts, Motivator, Thrive.
- **Work**: Projects (Gantt, dependencies, timesheets), Sprints, BugTracker,
  Qntrl (BPM).
- **Platform**: Analytics (self-service + embedded BI), Creator (low-code),
  Flow (iPaaS, ~900 connectors), RPA, Catalyst (pro-code), DataPrep.
- **AI (July 2025 onward)**: Zia LLM (in-house, runs in Zoho DCs), 25+
  prebuilt Zia Agents, Agent Studio (no-code builder over 700+ actions),
  Agent Marketplace, and an MCP server exposing action libraries of 15+ apps.

Breadth beyond Docket's scope (deliberately, per vision §2): finance
(Books/Billing/Payroll/Inventory/Payments — GST-native), HR (People/Recruit/
Shifts/Workerly), marketing (Campaigns/Marketing Automation/Social/…),
collaboration (Cliq/WorkDrive/office suite). India posture: INR pricing,
local datacenters, swadeshi positioning — procurement will read Zoho as the
"Indian sovereign-ish" choice.

### Pricing shape (annual billing; India ex-GST)

Seat-counted everywhere; freemium at the bottom; ~20% premium for monthly.

- **Zoho One**: ₹1,500/employee/mo all-employee (US $37) — every person on
  payroll must be licensed; flexible-user is ₹3,500 (US $90), ~2.3×.
- **CRM**: ₹800 / ₹1,400 / ₹2,400 / ₹2,600 per user/mo
  (Standard/Professional/Enterprise/Ultimate); free to 3 users.
- **Desk**: ₹420 / ₹800 / ₹1,400 / ₹2,400 per agent/mo; light agents ₹345;
  free plan for 3 agents. **CRM Plus** bundle ₹4,200/user/mo.
- **AI**: assistive Zia bundled in upper tiers; agentic Zia (Agents/Agent
  Studio) metered via Zia credits on top of seats.
- Scale math for the RFP story: 1,000 Desk Enterprise agents = ₹2.88 crore/yr
  recurring; a 50,000-employee org on Zoho One all-employee = ₹90 crore/yr.
  Zoho is the *price floor* incumbent (Desk Enterprise ≈ $29 vs Service Cloud
  $165+): Docket's argument against them is not "cheaper" but "no seat line
  item at all, on your own infrastructure, with auditable code" — residency
  is not sovereignty.

### Where Docket matches or exceeds

- **Desk core**: intake parity a grievance/support deployment needs (portal,
  email, API, WhatsApp/Telegram/SMS), declarative + scheduled routing
  including round-robin and least-loaded assignment (`case_routing.rb`,
  `lead_routing.rb`), business-calendar SLA, maker-checker approvals, CSAT,
  KB, macros, collision presence, merge/split, saved views + bulk actions.
- **Work seam**: the case↔work escalation seam (`WorkLink`,
  `Work::Escalation`) is deeper than Zoho's Desk↔Projects integration.
- **Suite level**: one identity, one audit log, one API across pillars vs
  per-app consoles; hash-chained tamper-evident audit; AGPL; self-hosted;
  zero per-seat licensing; MCP over the *entire* API surface (Zoho's MCP
  exposes curated actions of 15+ apps); AI on operator-owned models inside
  the deployment vs Zia LLM inside Zoho's datacenters.

### Gaps (verified in code)

1. **Real-time intake channels.** No live-chat widget — there are no
   ActionCable consumer channels (only presence via polling); a SalesIQ-class
   portal chat with optional KB-grounded bot is a standard line in service
   RFPs. No inbound telephony/IVR→case flow — IVR is an unscheduled roadmap
   candidate; telephony connectors (Exotel/Twilio/Plivo…) are outbound
   effectors only. Zoho Voice/PhoneBridge makes this table stakes.
2. **Rep email sync on CRM.** No per-user mailbox sync or BCC-to-CRM;
   reinforces Breakcold gap 1 (seller conversation layer). Same build.
3. **Work-module planning depth.** No Gantt/dependency-scheduling view, no
   workload/resource view, and no time tracking anywhere (no time-entry
   model). Burndown absence already recorded in KNOWN-GAPS. Zoho Projects
   leads with exactly these; decide which are in-scope for a tracker whose
   anchor is the case↔work seam, and record the rest as non-goals.
4. **Self-service BI.** Fixed reports + CSV + API vs Analytics' ad-hoc
   dashboards and NL queries. The sovereign answer half-exists already: the
   buyer owns the Postgres — document "read replica + Metabase/Superset" as
   the BI story in OPERATOR-GUIDE (a Metabase connector is already in the
   catalogue) instead of building a BI engine.
5. **No-code builders.** Blueprint / Guided Conversations / Creator / Flow /
   Agent Studio vs Docket's rules-table-and-code-registry posture. The "no
   visual flow builder" decision is locked for routing and stays; the
   external-automation answer is the existing Zapier/Make/n8n webhook
   connectors (n8n self-hosted fits the sovereignty story) — document it.
   The one surface worth a UX pass short of a builder: operator-facing
   registration of agent actions.
6. **Native mobile apps.** Zoho ships apps for every product; Docket is
   responsive web only. Matters for field scenarios; mostly not for console
   staff. Decide and record.
7. **Extension marketplace.** Zoho's ecosystem moat. Docket's equivalents are
   the connector catalogue, MCP, and AGPL forkability — a positioning answer,
   not a near-term roadmap item.

### Posture calls to record in DECISIONS.md

Forecasting, territory management, CPQ beyond the existing quotes/line-items,
marketing automation, and finance/HR/collaboration breadth remain non-goals
(vision §2 holds; a Zoho CRM OAuth connector already exists for coexistence).
Recording them keeps the sales conversation ready: Zoho wins breadth by
design; Docket wins depth-of-pillar, sovereignty, auditability, and the
deleted seat line.

### Priorities (respecting posture)

1. Portal live-chat widget, optionally KB-grounded bot via the existing agent
   layer — the missing intake channel RFPs actually list.
2. Inbound telephony/IVR adapter (call → case with recording reference) —
   promote the unscheduled roadmap item.
3. BI positioning: read-replica + Metabase/Superset recipe in OPERATOR-GUIDE.
4. Work-module: explicit decision on timesheets and Gantt/dependencies
   (build small or declare out); burndown already tracked in KNOWN-GAPS.
5. Rep email sync rides with the Breakcold conversation-layer priority.

### Sources

Vendor (via search; zoho.com blocks automated fetch):
[Zoho One plan details](https://www.zoho.com/one/plan-details.html),
[Zia LLM / Agent Studio / MCP launch](https://www.businesswire.com/news/home/20250717118204/en/Zoho-Launches-Zia-LLM-and-Deepens-AI-Portfolio-with-Prebuilt-Agents-Custom-Agent-Builder-MCP-and-Marketplace).
Third-party: [Zenatta pricing guide](https://zenatta.com/zoho-pricing-guide-2025/),
[ITforSME — Zoho One India](https://www.itforsme.in/pricing/zoho-one-india),
[ITforSME — Zoho CRM India](https://www.itforsme.in/pricing/zoho-crm-india),
[Codroid — CRM India INR](https://codroiditlabs.com/zoho-crm-pricing-india/),
[Codroid — Zoho One 2026](https://codroiditlabs.com/zoho-one-pricing-guide-2026/),
[ProductGrowth — Desk India](https://productgrowth.in/tools/customer-support/zoho-desk/),
[Futurum — agent interoperability](https://futurumgroup.com/insights/zoho-unveils-zia-llm-no%E2%80%91code-agent-studio-and-open-agent-interoperability/),
[Zenatta — Zoho One apps](https://zenatta.com/zoho-one-all-46-apps/),
[CRM Masters — apps list](https://crm-masters.com/zoho-one-applications/).
