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
2. **Sequence depth.** Steps are email + SMS only, despite WhatsApp/Telegram
   connectors existing in the catalogue. `sequence_deliveries` track
   delivered/failed but no opens/clicks → no campaign analytics. **A reply
   does not stop an enrollment** (cancel is manual, unsubscribe, or
   consent-loss only) — a correctness gap, not a feature gap.
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
3. Reply stops sequences — small, correctness.
4. Sales tasks/reminders + deal notes — small schema, daily-workflow hole.
5. WhatsApp/Telegram sequence steps + sequence touches on the 360 timeline —
   the India-appropriate answer to Breakcold's multichannel story, on
   connectors already built.
6. Longer-term: per-contact unified conversation view (already named as
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
