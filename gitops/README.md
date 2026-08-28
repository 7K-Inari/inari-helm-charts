# gitops/ — ArgoCD composition of the Inari platform

The platform is composed from independently released component charts; this
directory is the single source of truth for "what runs on a platform
cluster". `make dev-up` (scripts/bootstrap.sh) installs ArgoCD on a kind
cluster and applies these manifests.

## Sync waves

| Wave | Application | Source |
|-----:|-------------|--------|
| -2 | `cnpg` | helm `cloudnative-pg` 0.29.0 (CloudNativePG operator) |
| -2 | `keycloak-operator` | kustomize `gitops/operators/keycloak-operator` (upstream 26.3.2 + cluster-wide patch) |
| -1 | `inari-operator-crds` | OCI `ghcr.io/7k-inari/charts/inari-operator-crds` |
| 0 | `platform-config` | `charts/platform-config` in this repo (CNPG Cluster, `inari-db` secrets, Keycloak CR, realm import + PostSync jobs) |
| 1 | `nats`, `openfga` | upstream helm charts (values lifted from the old umbrella) |
| 2 | `inari-operator` | OCI `ghcr.io/7k-inari/charts/inari-operator` |
| 3 | `inari-server`, `inari-console` | OCI `ghcr.io/7k-inari/charts/...` |

Inside `platform-config`, per-resource sync waves order secrets (-1) → CNPG
Cluster (0) → Keycloak CR (1) → KeycloakRealmImport (2); the client-setup /
realm-sync / realm-verify jobs are ArgoCD `PostSync` hooks (weights 6/7/8)
whose failure fails the Application sync.

## Notes

- `inari-server` / `inari-console` Applications depend on charts published
  by their component repos; bootstrap treats them as optional until the
  chart-move tasks land (the old umbrella deployed them as disabled stubs
  anyway).
- `dataProtection.keepOnUninstall=true` in platform-config marks the CNPG
  Cluster `Prune=false` — enable it for any environment with data.
- Dev passwords live inline in these dev Applications (kind only); real
  installs use `postgresql.auth.existingSecret` (e.g. Vault/ESO).
