# Migration and parallel-cutover runbook

This runbook covers Freshdesk, Jira, Salesforce, generic CSV, and KanZen. Run
commands inside the deployed application container. In shared mode, add
`TENANT=<slug>` to every command.

## Safety contract

- Dry run is the default. Domain records are validated and rolled back.
- Dry run validates attachment names, declared sizes, and content types but does
  not download bytes or write blobs.
- Unknown statuses and roles are never guessed. The affected row is skipped and
  appears under `UNMAPPED`/`ERROR`.
- Missing source fields do not erase existing Docket values.
- Re-imports use source identities, not names or body text.
- Concurrent local/source edits produce `ImportConflict` rows and retain the
  local value until an operator resolves the conflict.
- Applied runs commit at most `BATCH_SIZE` rows at a time (default 200). The
  printed resume token restarts after the last committed checkpoint.
- Every durable import command requires `SOURCE_INSTANCE`. Choose one stable,
  non-secret identifier for the vendor account (for example
  `acme-freshdesk`) and reuse it for the file baseline, API deltas, resumes,
  and reconciliation. Never change it when switching transport.
- Only clean, non-dry applied runs advance the API delta watermark. A preview
  or a run with row errors can never make a later apply skip source records.

Before beginning, take a Docket backup, retain an immutable copy of the vendor
export, record its checksum, and agree a source-system write freeze or parallel
delta window.

## Mapping contracts

Jira/Freshdesk mapping files have this shape:

```json
{
  "statuses": {
    "Awaiting Vendor": "In review",
    "8": "waiting_on_customer"
  },
  "roles": {
    "atlassian": "technical",
    "default": "technical",
    "3": "customer_service"
  }
}
```

Jira status targets are exact Docket workflow-state names. Freshdesk status
targets are Docket case-status keys. Role targets must be one of
`super_admin`, `client_admin`, `finance`, `sales`, `customer_service`,
`technical`, or `readonly`. Do not map an external administrator to
`super_admin` unless that person is genuinely a cross-tenant platform operator.

Salesforce uses explicit object-specific maps:

```json
{
  "roles": { "Support Agent": "customer_service" },
  "case_statuses": { "New": "new", "Working": "in_progress", "Closed": "closed" },
  "lead_statuses": { "Open - Not Contacted": "new", "Working - Contacted": "working" },
  "lead_sources": { "Web": "web_form", "Partner Referral": "referral" },
  "opportunity_stages": { "Prospecting": "Sales/New", "Closed Won": "Sales/Won" }
}
```

A generic CSV contract maps target fields to headers and gives value maps for
source vocabularies:

```json
{
  "entity": "contacts",
  "identity_column": "Legacy Contact ID",
  "mapping": {
    "name": "Full Name",
    "email": "Email Address",
    "phone": "Mobile"
  },
  "value_maps": {},
  "defaults": { "preferred_language": "en" }
}
```

Supported CSV entities are `organisations`, `contacts`, `users`, `cases`,
`work_items`, `leads`, and `deals`. Preview rejects unsupported target fields,
missing headers, missing required mappings, and unmapped enum values.

## File dry run and apply

```bash
bin/rails docket:import:freshdesk SOURCE_INSTANCE=acme-freshdesk FILE=/imports/freshdesk.json MAPS=/imports/freshdesk-maps.json
bin/rails docket:import:jira SOURCE_INSTANCE=acme-jira FILE=/imports/jira.json MAPS=/imports/jira-maps.json PROJECT=OPS
bin/rails docket:import:salesforce_preview FILE=/imports/salesforce.json MAPS=/imports/salesforce-maps.json
bin/rails docket:import:csv_preview FILE=/imports/contacts.csv CONTRACT=/imports/contacts-contract.json

# Apply only after the previews are clean and mapping omissions are intentional.
bin/rails docket:import:freshdesk SOURCE_INSTANCE=acme-freshdesk FILE=/imports/freshdesk.json MAPS=/imports/freshdesk-maps.json APPLY=1
bin/rails docket:import:salesforce SOURCE_INSTANCE=acme-salesforce FILE=/imports/salesforce.json MAPS=/imports/salesforce-maps.json APPLY=1
bin/rails docket:import:csv SOURCE_INSTANCE=legacy-crm FILE=/imports/contacts.csv CONTRACT=/imports/contacts-contract.json APPLY=1
```

JSON export arrays are streamed one record at a time. A top-level object may use
`companies`, `agents`, `contacts`, and `tickets` for Freshdesk; `users` and
`issues` for Jira; and `Account`, `User`, `Contact`, `Case`, `Lead`, and
`Opportunity` for Salesforce.

If an apply run stops, copy the printed token and rerun the identical command:

```bash
bin/rails docket:import:freshdesk SOURCE_INSTANCE=acme-freshdesk FILE=/imports/freshdesk.json MAPS=/imports/freshdesk-maps.json \
  APPLY=1 RESUME_TOKEN='<printed token>'
```

Do not change `TENANT`, `SOURCE_INSTANCE`, dry/apply mode, or the source file
while resuming a token.

## Direct API and delta window

Use environment injection from the deployment secret manager; do not put API
tokens in mapping files or shell history.

```bash
bin/rails docket:import:freshdesk_api \
  SOURCE_INSTANCE=acme-freshdesk \
  FRESHDESK_DOMAIN=example.freshdesk.com FRESHDESK_API_KEY="$FRESHDESK_API_KEY" \
  MAPS=/imports/freshdesk-maps.json APPLY=1

bin/rails docket:import:jira_api \
  SOURCE_INSTANCE=acme-jira \
  JIRA_URL=https://example.atlassian.net JIRA_EMAIL=operator@example.com \
  JIRA_API_TOKEN="$JIRA_API_TOKEN" MAPS=/imports/jira-maps.json APPLY=1
```

The next clean applied run starts from the latest clean applied watermark.
Freshdesk always uses an `updated_since` boundary (including for the initial
scan), includes ticket descriptions, sorts by update time, and stops with an
error rather than accepting the vendor's 300-page truncation. Jira adds an
updated-time clause and deterministic `updated, id` ordering to the configured
JQL. Both API adapters persist `(updated_at, stable_id)` checkpoints so a
resume does not skip a shifted ordinal page.
Attachments downloaded from a different CDN origin never receive the source API
authorization header.

Migration API endpoints must use HTTPS. For a temporary trusted-network test
endpoint only, `ALLOW_INSECURE_MIGRATION_HTTP=1` is the explicit escape hatch;
never use it across an untrusted network or with production credentials.

Recommended cutover:

1. Take and checksum the full export.
2. Preview and resolve all required mappings.
3. Apply the bulk import.
4. Run one or more API deltas while the source remains live.
5. Freeze writes in the source.
6. Run the final delta.
7. Export a full source identity inventory and reconcile.
8. Resolve every conflict or document an intentional local win.
9. Open Docket for writes and retain the source read-only for the agreed period.

## Reconciliation

The inventory is a JSON object keyed by Docket source type. Values may be ids or
objects carrying an `id`/`external_id` and `updated_at`:

```json
{
  "ticket": [{ "id": "4321", "updated_at": "2026-07-31T10:00:00Z" }],
  "conversation": ["9876"],
  "contact": ["55"]
}
```

```bash
bin/rails docket:import:reconcile SOURCE=freshdesk SOURCE_INSTANCE=acme-freshdesk INVENTORY=/imports/inventory.json
```

The command exits non-zero for duplicate source ids, missing Docket identities,
missing/deleted targets, source rows newer than the imported watermark, or
unresolved conflicts. A full inventory also fails when Docket identities are
absent from the source. `DELTA=1` treats the inventory as partial and does not
report identities absent from that delta as missing in the source.
