# inari-helm-charts

GitOps composition and end-to-end testing for the Inari platform cluster:
ArgoCD Application definitions (`gitops/`), the `platform-config` glue chart
(`charts/platform-config`), day-0 bootstrap and backup/restore/DR tooling
(plan §6 #10, §9 M0).

Stack: ArgoCD (App-of-Apps-style sync waves) + Helm charts released as OCI.

Part of the **Inari** multi-tenant Internal Developer Platform (GitHub org `7K-Inari`).
Canonical architecture & development plan: [inari-docs/docs/architecture/inari-platform-plan.md](https://github.com/7K-Inari/inari-docs/blob/main/docs/architecture/inari-platform-plan.md)

## Layout

- `gitops/` — ArgoCD Applications composing the platform from component
  charts (see [gitops/README.md](gitops/README.md) for the sync-wave table).
- `charts/platform-config` — the only chart in this repo: CNPG PostgreSQL
  Cluster + db secrets, Keycloak instance and realm `inari` glue (realm
  import/sync/verify as ArgoCD PostSync hooks). Published to
  `oci://ghcr.io/7k-inari/inari-helm-charts/charts` via release-please.
- `scripts/` — day-0 bootstrap, backup/restore, DR drill.
- Component charts (`inari-operator`, `inari-operator-crds`, `inari-server`,
  `inari-console`) live in and are released from their component repos.

## Quickstart (day-0 bootstrap)

Prereqs: `docker`, `kind`, `kubectl`, `jq`.

```sh
make dev-up     # kind cluster + ArgoCD + gitops/ apps + readiness waits + smoke check
make dev-down   # tear down
```

The composed stack provides Keycloak (realm `inari`), PostgreSQL
(CloudNativePG), NATS (JetStream) and OpenFGA, plus `inari-operator`,
`inari-server` and `inari-console` Applications once their charts are
published by the component repos.

## Backup / restore / DR drill

```sh
make backup                          # tarball into ./backups/
make restore BACKUP=backups/…tgz     # restore onto an existing stack
make dr-drill BACKUP=backups/…tgz    # fresh kind cluster -> restore -> verify (M0 gate)
```

See [docs/backup-restore.md](docs/backup-restore.md).

## Development

```sh
make lint    # helm lint + chart-testing + gitops manifest validation
make test    # helm-unittest
```

`charts/platform-config` is published as an OCI artifact to
`oci://ghcr.io/7k-inari/inari-helm-charts/charts` by `release.yaml` (release-please tags).
