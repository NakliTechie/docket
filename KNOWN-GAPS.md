# Known Gaps

Stubbed or deferred items, with severity. Empty is the goal.

- **Keycloak live-flow tests not executed in the build container** (severity: low). The build environment has no Docker daemon, so the containerised-Keycloak OIDC tests (staff role-mapping, customer CIF-claim mapping) could not be run here. Everything they exercise is covered by OmniAuth test-mode integration tests in the default suite; the live harness ships ready to run: `bin/keycloak-test` locally, and the `keycloak-sso` job in `.github/workflows/ci.yml` runs it on every push. SAML is exercised in test mode only (Keycloak SAML client config not included).
