# Backup & Restore Runbook — Inari platform cluster

Covers the M0 backup/restore scope (plan §9 M0, §12.1/1): PostgreSQL, Keycloak
config, OpenFGA store and NATS JetStream. A **tested restore** is an M0 exit
criterion — the DR drill below is that test.

## Scope & strategy

| Component | What is backed up | How | Restore mechanism |
|---|---|---|---|
| PostgreSQL (CNPG) | logical dumps of `inari` + `openfga` databases | `pg_dump --clean --if-exists` from the CNPG primary pod | `psql -f` into the same databases |
| Keycloak | full realm `inari` representation (clients, groups, roles, orgs) | admin REST `partial-export` | delete realm + re-import via admin REST |
| OpenFGA | store, authorization model, tuples | OpenFGA HTTP API | recreate store, write model, write tuples |
| NATS | all JetStream streams | `nats stream backup` (via nats-box pod) | `nats stream restore` |

Logical dumps are chosen for M0 because they restore into *any* Postgres,
which is what makes fresh-cluster DR simple. Post-M0 hardening: CNPG
continuous backup (barman) to object storage for point-in-time recovery —
noted in the chart values as a future extension.

## Archive format

`inari-backup-<UTC timestamp>.tgz`:

```
inari-backup-<ts>/
  manifest.json                      # createdAt, chart version, counts
  postgres/inari.sql                 # logical dump, --clean --if-exists
  postgres/openfga.sql
  keycloak/realm-inari.json          # realm representation
  openfga/stores.json                # may be empty pre-control-plane
  openfga/authorization-models.json  # only if a store existed
  openfga/tuples.json                # only if a store existed
  nats/streams.json                  # stream inventory
  nats/jetstream-backup.tgz          # only if streams existed
```

Empty-component backups are valid: before inari-server exists, OpenFGA has no
store and NATS has no streams; the scripts warn and continue.

## Prerequisites

- `kubectl` context pointing at the platform cluster; `jq`, `tar`, `helm` locally.
- The `nats-box` deployment running in the namespace (enabled by default in
  the umbrella chart) — all in-cluster HTTP/CLI work runs from it.
- Admin password available in secret `inari-db` (chart-managed).

## Procedures

### Take a backup

```sh
make backup                       # writes ./backups/inari-backup-<ts>.tgz
# or
BACKUP_DIR=/mnt/backups scripts/backup.sh /mnt/backups
```

Verify the archive: `tar tzf backups/inari-backup-<ts>.tgz` and check
`manifest.json`.

### Restore onto an existing stack

The target must have the umbrella chart installed and healthy. Logical dumps
are idempotent (`--clean`), so restoring onto a used stack is supported.

```sh
make restore BACKUP=backups/inari-backup-<ts>.tgz
```

### DR drill (M0 exit gate)

Provisions a **fresh** kind cluster, installs the chart, restores the backup
and runs the full smoke verification (workloads, databases, realm, OpenFGA,
JetStream):

```sh
make dr-drill BACKUP=backups/inari-backup-<ts>.tgz
# keep the DR cluster for inspection:
scripts/dr-drill.sh backups/inari-backup-<ts>.tgz --keep
```

Exit code 0 + `DR DRILL PASSED` = restore verified. The DR cluster is deleted
unless `--keep` is passed.

## RPO/RTO notes

- **RPO** = backup cadence (manual for M0; schedule via CI/cron in your
  environment). PITR arrives with CNPG barman (post-M0).
- **RTO** ≈ fresh kind cluster + chart install + restore + verify: the drill
  measures it end-to-end.

## Failure playbook

- `no CNPG primary pod found` — cluster mid-failover; retry once the CNPG
  `Cluster` reports healthy.
- `could not obtain Keycloak admin token` — Keycloak not fully up, or the
  `inari-db` secret was rotated out of band.
- OpenFGA/NATS steps skip with a warning when the backup has no data for them;
  that is expected for pre-control-plane backups.
