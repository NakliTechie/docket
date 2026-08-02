---
name: docket
description: Operate Docket through its MCP server using governed workflows for case triage and resolution, Customer 360 briefs, lead qualification, decision review, and operational reporting. Use when an agent needs to read or change Docket service-desk, CRM, work, or decisioning records through connected MCP tools.
---

# Docket Operations

Use Docket's MCP prompts and tools to execute auditable operating workflows without bypassing permissions, approval gates, or tenant boundaries.

## Choose a workflow

- Use `triage_case` to assess urgency, SLA state, routing, ownership, and next status.
- Use `resolve_case` to ground a response in messages and published knowledge.
- Use `customer_360` to assemble service, CRM, and work history for one contact.
- Use `qualify_lead` to explain scoring and prepare an explicit conversion decision.
- Use `review_decisions` for maker-checker review and appeal-aware adjudication.
- Use `operational_health` for date-bounded service, sales, work, and decision-quality reporting.

Read [references/workflows.md](references/workflows.md) when selecting tool order or interpreting workflow controls.

## Operating rules

1. Read the subject record before proposing a write.
2. Separate record facts from recommendations.
3. State the exact mutation before calling a write tool.
4. Respect confirmation, approval, and maker-checker gates.
5. Never widen scope after a forbidden response.
6. Report tool errors and partial outcomes without inventing state.

## Tool selection

Start with the named MCP prompt when the client exposes prompts. Otherwise follow the matching workflow in the reference file. Use `docket://operator-guide` for product controls and `docket://openapi` for the tenant-filtered API contract.
