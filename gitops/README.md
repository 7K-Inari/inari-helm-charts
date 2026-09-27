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
| -1 | `inari-operator-crds` | OCI `ghcr.io/7k-inari/inari-operator/charts/inari-operator-crds` |
| 0 | `platform-config` | `charts/platform-config` in this repo (CNPG Cluster, `inari-db` secrets, Keycloak CR, realm import + PostSync jobs) |
| 1 | `nats`, `openfga` | upstream helm charts (values lifted from the old umbrella) |
| 2 | `inari-operator` | OCI `ghcr.io/7k-inari/inari-operator/charts/inari-operator` |
| 3 | `inari-server`, `inari-console` | OCI `ghcr.io/7k-inari/<repo>/charts/...` |

Inside `platform-config`, per-resource sync waves order secrets (-1) → CNPG
Cluster (0) → Keycloak CR (1) → KeycloakRealmImport (2); the client-setup /
realm-sync / realm-verify jobs are ArgoCD `PostSync` hooks (weights 6/7/8)
whose failure fails the Application sync.

## Dex / ArgoCD SSO (Wave 3)

- `charts/dex` (this repo, released as OCI) deploys ONE cluster-local Dex per
  tenant cluster: per-user SSO via git social login plus OIDC pass-through to
  Keycloak realm `inari` as confidential client `cluster-<id>-dex`. The
  inari-operator (W3) renders it per tenant cluster — no Dex Application lives
  in gitops/; production Dex config (connectors, static clients) comes only
  from an ESO/Vault-synced Secret (`config.existingSecret`).
- `platform-config` renders those `cluster-<id>-dex` clients into the realm
  import from `keycloak.dexClusters[]` (realm-creation placeholder secrets;
  runtime provisioning/rotation is owned by inari-server, W2).
- ArgoCD per-user SSO: set `argocd.enabled=true` in platform-config values to
  point ArgoCD OIDC at the cluster-local Dex issuer and map Keycloak groups
  (via the Dex `groups` claim) to ArgoCD roles. SSO is then the default login
  path; static `accounts.*` tokens are a documented break-glass fallback only
  (`argocd.breakGlass.staticTokenEnabled`, password set out-of-band via the
  argocd CLI, never stored by the chart).

## Notes

- `inari-server` / `inari-console` Applications depend on charts published
  by their component repos; bootstrap treats them as optional until the
  chart-move tasks land (the old umbrella deployed them as disabled stubs
  anyway).
- `dataProtection.keepOnUninstall=true` in platform-config marks the CNPG
  Cluster `Prune=false` — enable it for any environment with data.
- Dev passwords live inline in these dev Applications (kind only); real
  installs use `postgresql.auth.existingSecret` (e.g. Vault/ESO).
