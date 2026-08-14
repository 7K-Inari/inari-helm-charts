# inari-helm-charts

Deployment charts for Inari: control-plane umbrella chart, agent chart, platform-cluster baseline chart, day-0 bootstrap (plan §6 #10, §9 M0).

Stack: Helm (chart releases as OCI)

Part of the **Inari** multi-tenant Internal Developer Platform (GitHub org `7K-Inari`).
Canonical architecture & development plan: [inari-docs/docs/architecture/inari-platform-plan.md](https://github.com/7K-Inari/inari-docs/blob/main/docs/architecture/inari-platform-plan.md)

## Quickstart (day-0 bootstrap)

Prereqs: `docker`, `kind`, `kubectl`, `helm` (v3.18+), `jq`.

```sh
make dev-up     # kind cluster + umbrella chart + readiness waits + smoke check
make dev-down   # tear down
```

`charts/inari-platform` installs Keycloak (realm `inari`), PostgreSQL
(CloudNativePG), NATS (JetStream) and OpenFGA. `inari-server` /
`inari-operator` ship as disabled stubs until their images exist
(`--set inariServer.enabled=true` later).

## Backup / restore / DR drill

```sh
make backup                          # tarball into ./backups/
make restore BACKUP=backups/…tgz     # restore onto an existing stack
make dr-drill BACKUP=backups/…tgz    # fresh kind cluster -> restore -> verify (M0 gate)
```

See [docs/backup-restore.md](docs/backup-restore.md).

## Development

```sh
make lint    # helm lint + chart-testing
make test    # helm-unittest
```

Charts are published as OCI artifacts to `oci://ghcr.io/7k-inari/charts` on
`v*` tags (tag must match the chart version).
