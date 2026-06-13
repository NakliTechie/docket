# Known Gaps

Stubbed or deferred items, with severity. Empty is the goal.

- ~~Keycloak live-flow tests not executed in the build container~~ **Executed 2026-06-10 on a real Docker host — found and fixed three stacked bugs** (swd-forced HTTPS discovery; Turbo intercepting the SSO form POST; CSP `form-action 'self'` blocking the IdP redirect — the latter two were real product bugs invisible to the test-mode suite) plus a realm fixture that referenced undefined client scopes. Both live flows now pass: `bin/keycloak-test`. SAML remains test-mode only (Keycloak SAML client config not included).
- ~~`docker compose build` not executed in the build container~~ **Executed 2026-06-10 on a real Docker host** — image built clean, Postgres prepared/seeded, full 12-check smoke passed against the compose instance (`SMOKE_BASE_URL=… bin/smoke`; remote-target mode needed a fix: the API token is now minted inside the app container).
- **Email intake requires deployment-side ingress configuration** (severity: info, by design). Action Mailbox processing, threading, anti-spoofing, and attachment filtering are implemented and tested; wiring an SMTP relay/ingress (e.g. Postfix → `/rails/action_mailbox/relay/inbound_emails`) is environment-specific and documented in the Rails guides — not something a self-contained compose file can do for you.
- **Accessibility: automated coverage only** (severity: info). axe-core (WCAG 2.1 A/AA rule sets) runs in the system suite against ten key surfaces with zero violations; a manual screen-reader walkthrough (NVDA/VoiceOver) by a human tester remains worthwhile before a GIGW-audited deployment.

## AI / connector effector layer (opt-in, off the deploy critical path)

The connector framework is an agent **effector layer** (invoke/scope/approval + budgeted autonomy + delegation-ID + decision-class). It is fully unit/integration tested, but the following are validated against test doubles rather than the live world:

- **Connectors tested against stubs, not live external APIs** (severity: info). The four shipped providers (`http_json`, `slack_webhook`, `msg91`, `razorpay`) are tested against stubbed HTTP responses; none has been exercised against a real Slack / MSG91 / Razorpay endpoint. Validate against live credentials before relying on any in production.
- **Agent dispatch loop run only with the `fake` LLM client** (severity: info). `Connectors::AgentRunner` + `Llm::HttpClient#chat_with_tools` are driven by `Llm::FakeClient` in tests; the end-to-end "tool-use turn → `Connectors::Invoke.call`" loop has not been run against a real model endpoint.
- **No OAuth2 token-refresh seam on the credential vault** (severity: info, deferred). Current connectors use static credentials / webhooks. An OAuth2 refresh seam must be designed before the first OAuth provider (Salesforce / HubSpot / M365 / Google).
- **Decision-class doctrine is judicially untested for AI in India** (severity: info). The autonomous / confirm / of_record gating is grounded in administrative-law principles (reasoned-order duty, non-fettering, audi alteram partem), not in case law applying them to AI-influenced decisions — monitor (e.g. SC Draft AI Regs for Courts 2026).
