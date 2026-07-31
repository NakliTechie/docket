# Runbook — backup and restore

A backup nobody has restored is a hope, not a backup. This runbook ends with a
drill, and the drill ends with a proof.

## What has to be backed up

Docket runs **four** Postgres databases and keeps attachments **on disk**:

| What | Where | Lose it and… |
|---|---|---|
| `primary` | `DATABASE_URL` | everything: cases, work, CRM, users, the audit chain |
| `cache` | `CACHE_DATABASE_URL` | rebuildable; back it up anyway, it is cheap |
| `queue` | `QUEUE_DATABASE_URL` | in-flight and failed jobs, and the record of what failed |
| `cable` | `CABLE_DATABASE_URL` | live-update channels; rebuildable |
| attachments and generated secrets | `storage/` volume | uploaded files and, in default Compose, `secret_key_base` plus `vault_keys.json` |

The README used to suggest a single `pg_dump` of the primary. That silently
loses three databases and every attachment.

## Taking a backup

```bash
bin/backup /var/backups/docket
```

Set `DOCKET_BACKUP_SIGNING_KEY` to a private 64-character hexadecimal key kept
outside the backup destination (for example in the host secret manager). The
same key is required by `bin/restore`. Backup directories and files are created
with private permissions, and restore authenticates the signed checksum
manifest before it overwrites any database.

The production image includes PostgreSQL 16 `pg_dump`/`pg_restore`, matching the
Compose database major. For a Compose deployment, mount an encrypted host or
remote-backup filesystem outside `/rails/storage` (nesting the destination in
the storage volume would make the storage archive contain itself):

```bash
docker compose run --rm --no-deps \
  -v /var/backups/docket:/backups \
  app bin/backup /backups
```

Writes `docket-<UTC timestamp>/` containing four `.dump` files (custom format —
compressed and selectively restorable), `storage.tar.gz`, and a `MANIFEST.txt`.
It exits non-zero if any part fails, so a half-finished backup cannot look
successful to a cron job.

**Schedule it.** The script is committed; scheduling is the operator's, because
where backups go is a decision only you can make. A daily cron is the usual
answer:

```
15 2 * * *  cd /srv/docket && DATABASE_URL=… bin/backup /var/backups/docket >> /var/log/docket-backup.log 2>&1
```

**Get them off the box.** A backup on the same disk as the database survives
nothing worth surviving. Sync to object storage or another host.

## Restoring

```bash
DOCKET_RESTORE_CONFIRM=yes bin/restore /var/backups/docket/docket-20260728T021500Z
```

For Compose, stop the web process first and run the restore in a one-off app
container against the target database and storage volume:

```bash
docker compose stop app
docker compose run --rm --no-deps \
  -e DOCKET_RESTORE_CONFIRM=yes \
  -v /var/backups/docket:/backups:ro \
  app bin/restore /backups/docket-20260728T021500Z
docker compose up -d app
```

It refuses to run without `DOCKET_RESTORE_CONFIRM=yes` — restore overwrites live
databases and should not be one keystroke away.

The last thing it does is `bin/rails audit:verify`, which walks the audit hash
chain and compares its head hash and row count with the external checkpoint
bundled beside the database dump. In-place edits break the chain; tail deletion
or a full wipe disagrees with the checkpoint. All three are detected here.

For an existing deployment upgrading from a release without the external
checkpoint, inspect and verify the chain once, then deliberately initialize it:

```bash
DOCKET_AUDIT_CHECKPOINT_CONFIRM=yes bin/rails audit:checkpoint:init
```

Do not use that command to silence a mismatch: it blesses the current state and
therefore refuses to overwrite an existing checkpoint.

## The drill — do this before go-live, then quarterly

1. Take a backup on the live host.
2. Restore it onto a **clean** host or an empty database.
3. Boot the app against the restored data.
4. `bin/rails audit:verify` — must PASS.
5. Sign in, open a case, open a work item, download an attachment. (Attachments
   are the part most likely to be quietly missing.)
6. Write down how long steps 2–5 took. **That number is your RTO**, and it is
   the only honest one you have.

Record your intended RTO/RPO here once measured:

| | Target | Measured | When |
|---|---|---|---|
| RPO (data you can afford to lose) | e.g. 24h | — | — |
| RTO (time to be serving again) | e.g. 4h | — | — |

### Local release-artifact reference (2026-08-01)

An isolated Compose source stack backed up all four databases plus its storage volume in
**6.89s**. A second clean stack restored a **35-entry** audit chain and the exact bytes of
an attached text file in **4.69s**, then served a healthy `/healthz` in another **4.55s**.
Clean stack provisioning itself took **8.57s**, so active clean-target-to-serving work was
**17.81s** (or **9.24s** when the clean target already exists). The restored target then
passed the complete 12-step release smoke. These local, tiny-dataset numbers verify the
procedure; they are not a production RTO/RPO commitment. Measure again with representative
Netcore volume, storage, networking, and off-site backup media.

## What this does not cover

- **Point-in-time recovery.** These are nightly snapshots. If you need "restore
  to 14:32", enable Postgres WAL archiving — a database-level concern, not an
  application one.
- **Off-site replication and encryption at rest** — your infrastructure's job.
- **Externally managed secrets.** Default Compose generates `secret_key_base`
  and `vault_keys.json` in the storage volume, so both are present in
  `storage.tar.gz`; the backup must therefore be encrypted and access-controlled
  as secret material. If you supply `SECRET_KEY_BASE`, `DOCKET_VAULT_KEYS`, or a
  `DOCKET_VAULT_KEYS_PATH` outside `DOCKET_STORAGE_DIR`, they are not captured.
  Retain the exact session secret and every still-readable vault-key version
  alongside the matching backup generation. A different session secret
  invalidates sessions/tokens; a missing vault key makes encrypted connector,
  OAuth, shared-credential, and SSO values unreadable.
