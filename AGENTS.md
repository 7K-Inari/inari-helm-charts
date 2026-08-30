# inari-helm-charts — Agent Guide

GitOps composition + e2e for Inari: ArgoCD Application definitions (gitops/), the platform-config glue chart (charts/platform-config), day-0 bootstrap (plan §6 #10, §9 M0).

Stack: ArgoCD sync waves over Helm charts (chart releases as OCI)

## Key architecture constraints
- **Day-0 bootstrap: Inari must never require Inari to install** — scripted first-platform-cluster install lives here (§12.1/1).
- gitops/ composes: Keycloak (realm `inari`), PostgreSQL (CNPG), NATS, OpenFGA via ArgoCD Applications; inari-operator/inari-server/inari-console charts are released from their component repos and consumed as OCI (§4.2).
- Backup/restore runbook coverage: PostgreSQL, OpenFGA store, Keycloak config, NATS — a tested restore is an M0 exit criterion (§9 M0, §12.1/1).
- Charts published as OCI artifacts; lint + template tests in CI (chart-testing).

## Conventions
- Conventional Commits; SemVer releases; container images/artifacts cosign-signed (once CI exists).
- Releases: release-please in PR-only mode (manifest mode, one component per chart path). Pushes to `main` open/update a Release PR with `Chart.yaml` bumps (via `x-release-please-version` annotations) and per-chart CHANGELOGs. Merging the Release PR triggers `release.yaml`, which creates per-chart tags (`<chart>-vX.Y.Z`, e.g. `platform-config-v0.2.0`), GitHub Releases, and publishes charts to `oci://ghcr.io/7k-inari/inari-helm-charts/charts`. Charts version independently — never bump `version:`/`appVersion:` in `Chart.yaml` by hand.
- Write tests for new behavior; keep changes minimal and focused.
- Canonical architecture & development plan: https://github.com/7K-Inari/inari-docs/blob/main/docs/architecture/inari-platform-plan.md (section references below point into it).

## Platform design principles (apply everywhere)
1. Tenant-aware to the core — every object carries a tenant ID; every API decision is tenant-scoped.
2. Zero tenant credentials on the hub — no tenant kubeconfigs or cloud keys in the control plane.
3. Pull, never push — agents dial out; the control plane never initiates connections into tenant networks.
4. Desired state, eventually reconciled — GitOps/CR-based mutations, not imperative RPCs.
5. The catalog is a projection of reality — capabilities are discovered, not declared.
6. Small kernel, everything else extension.
7. Modular monolith first — strict internal module boundaries.
