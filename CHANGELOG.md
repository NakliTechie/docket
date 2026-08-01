# Changelog

All notable user-visible and operational changes are recorded here. Docket uses
[Semantic Versioning](https://semver.org/): release tags are signed or annotated
as `vMAJOR.MINOR.PATCH`; previews use `-alpha.N`, `-beta.N`, or `-rc.N`.

## Unreleased

- Upgraded Rails/Active Storage to 8.1.3.1 for CVE-2026-66066
  (GHSA-xr9x-r78c-5hrm); production image processing requires libvips 8.13+.
- Closed fresh-host release gaps found by a real Compose/recovery drill: the
  image now precompiles with a non-secret build-only vault key, ships matching
  PostgreSQL 16 backup clients, and uses `db:prepare` so a new deployment gets
  its base tenant, break-glass admin, and day-one defaults. CI now builds and
  probes the production image.
- Added a dry-run-first, resumable migration product for Freshdesk, Jira,
  Salesforce, generic CSV, and KanZen, including API deltas, attachments,
  durable source identities, conflict handling, and reconciliation.
- Added business-calendar SLA clocks, pause/resume history, risk alerts, a
  consolidated notification inbox, optional notification email, and CSAT.
- Added tenant export/suspend/purge, legal-hold-aware subject erasure, and an
  independently versioned/rotatable encrypted credential keyring.
- Added daily-workflow saved views and safe bulk actions, scheduled routing,
  custom fields/reports, work relations/default assignment, rich replies,
  signatures, collision presence, and case merge/split.
- Added One-Docket search/customer 360, project templates and explicit won-deal
  onboarding, plus work-transition approvals.
- Added CRM lead-capture mapping/provenance/consent, duplicate review and merge,
  products/line items, competitors, and competitor-loss reporting.
- Corrected role, API-scope, connector, backup/restore, migration, privacy,
  automation, and go-live documentation against the implemented registries.

## 1.3.0-alpha.1 — 2026-07-31

- Established the first explicit product version and release convention.
- Added PostgreSQL CI and two-session concurrency coverage.
- Added external audit-chain checkpoints, preflighted four-database restore,
  dependency health probes, request/query deadlines, shared rate-limit state,
  one-shot migrations, and a release smoke gate.
- Hardened MCP context isolation and direct human connector replies.
