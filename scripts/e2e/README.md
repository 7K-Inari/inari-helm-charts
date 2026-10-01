# scripts/e2e — golden-path end-to-end assets

Canonical home of the Inari golden-path e2e (relocated from the inari-server
repo's `e2e/` directory). `.github/workflows/release-e2e.yaml` is the CI gate
that runs them.

- `golden-path.sh` — full-stack kind gate: platform charts → tenant → cluster
  registration → agent connect → capabilities streaming, plus HA disruption
  assertions under `INARI_HA=true`, plus smoke assertions for the
  inari-operator and inari-console charts. Chart locations are parameterized
  via env (`HELM_CHARTS_DIR`, `SERVER_CHART_DIR`, `CONSOLE_CHART_DIR`,
  `AGENT_CHART_DIR`, `OPERATOR_CHART_DIR`, `OPERATOR_CRDS_CHART_DIR`,
  `SERVER_MIGRATIONS_DIR`); see the header comment.
- `kubectl-access.sh` — control-plane-only kubectl access scenario (docker
  etcd + kube-apiserver + Keycloak + kubelogin; no kind needed).
- `nats-values.yaml` — HA NATS JetStream values consumed by `golden-path.sh`.
- `api_schema_e2e_test.go` — Go driver for the console read-endpoint
  api-schema conformance test (build tag `e2e`). It imports inari-server
  modules and reads `dist/openapi.yaml`, so the workflow copies it into the
  inari-server checkout at the pinned tag and runs it there with
  `go test -tags=e2e`.
