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
| attachments | `storage/` volume | **every file anyone ever uploaded** — these are not in Postgres |

The README used to suggest a single `pg_dump` of the primary. That silently
loses three databases and every attachment.

## Taking a backup

```bash
bin/backup /var/backups/docket
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

It refuses to run without `DOCKET_RESTORE_CONFIRM=yes` — restore overwrites live
databases and should not be one keystroke away.

The last thing it does is `bin/rails audit:verify`, which walks the audit hash
chain. **This is the point.** Docket's audit log is a hash chain, so a partial,
truncated or tampered restore breaks it and is *detected here* — not discovered
months later when somebody asks who changed a record.

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

## What this does not cover

- **Point-in-time recovery.** These are nightly snapshots. If you need "restore
  to 14:32", enable Postgres WAL archiving — a database-level concern, not an
  application one.
- **Off-site replication and encryption at rest** — your infrastructure's job.
- **Secrets.** `SECRET_KEY_BASE` is *not* in the backup, and it derives the
  encryption keys for the connector credential vault. Restoring a database with
  a different `SECRET_KEY_BASE` leaves those credentials unreadable. **Store it
  with your backups' access controls, not inside the backup.**
