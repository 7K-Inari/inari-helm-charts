# scripts/e2e — end-to-end suite map

Canonical home of the Inari e2e suites (relocated from the inari-server
repo's `e2e/` directory). `.github/workflows/release-e2e.yaml` is the CI gate
that runs them. Suites are organized by surface (per the approved e2e
architecture plan §1, "Unified testing folder structure"):

```
scripts/e2e/
├── golden-path.sh            # full-stack kind gate (shell; later waves split it into stack/ Go suites)
├── ui/                       # console UI e2e (Playwright Test suite; see ui/README.md)
├── api/
│   └── api_schema_e2e_test.go    # API ↔ OpenAPI schema conformance (Go, tag e2e)
├── kubectl/
│   └── kubectl-access.sh         # control-plane-only kubectl access scenario
├── lib/
│   └── ui-proxy.mjs              # single-origin shim shared by the UI suites
└── stack/
    └── testdata/
        └── nats-values.yaml      # HA NATS JetStream values consumed by golden-path.sh
```

## Suite map

| Suite | Path | Runner | CI trigger | Gating |
|---|---|---|---|---|
| Golden path (fast) | `golden-path.sh` (`INARI_HA=false`) | bash script on kind | `release-e2e.yaml` job `golden-path` (matrix `ha: false`) on Release PRs | Yes — Release-PR gate |
| Golden path (HA) | `golden-path.sh` (`INARI_HA=true`) | bash script on kind | `release-e2e.yaml` job `golden-path` (matrix `ha: true`) on Release PRs | Yes — Release-PR gate |
| API schema conformance | `api/api_schema_e2e_test.go` | `go test -tags=e2e` inside the inari-server checkout at the pinned tag | `release-e2e.yaml` step "Run api-schema e2e against the live stack" (after golden-path) | Yes — Release-PR gate |
| Console UI e2e | `ui/` (Playwright Test) + `lib/ui-proxy.mjs` | `npx playwright test --config playwright.config.ci.ts --grep @p0 --grep-invert @quarantine` in `ui/` | `release-e2e.yaml` step "Run console UI e2e (Playwright)" on BOTH HA matrix legs (after api-schema) | Yes — Release-PR gate |
| kubectl access | `kubectl/kubectl-access.sh` | bash script (docker etcd + kube-apiserver; no kind) | not wired into CI yet | No — manual scenario |

## Running locally

### Golden path (kind full stack)

Prereqs: `docker`, `kind`, `kubectl`, `helm`, `jq`, `git`, plus checkouts of
the `inari-agent` and `inari-operator` repos next to this one (or set
`AGENT_CHART_DIR` / `OPERATOR_CHART_DIR` explicitly). Build the e2e images
first (`inari/server:e2e` from inari-server, `inari/agent:e2e` from
inari-agent). For `INARI_HA=true` also set `SERVER_MIGRATIONS_DIR` to the
inari-server checkout's `internal/db/migrations`.

```sh
bash scripts/e2e/golden-path.sh                # fast gate
INARI_HA=true bash scripts/e2e/golden-path.sh  # HA gate
KEEP_CLUSTER=true bash scripts/e2e/golden-path.sh  # keep the kind cluster for debugging
```

See the script header for the full env knob list (`HELM_CHARTS_DIR`,
`SERVER_CHART_DIR`, `CONSOLE_CHART_DIR`, `INARI_E2E_CACHE_BACKEND`, ...).

### API schema conformance

Requires a running golden-path stack (keep it up with `KEEP_CLUSTER=true`)
and an inari-server checkout. The driver imports inari-server modules and
reads `dist/openapi.yaml`, so copy it into the checkout and run it there:

```sh
cp scripts/e2e/api/api_schema_e2e_test.go <inari-server>/e2e/
cd <inari-server> && make export-openapi
kubectl -n inari port-forward svc/inari-server 18090:8080 &
kubectl -n inari port-forward svc/keycloak-service 18091:8080 &
E2E_BASE_URL=http://127.0.0.1:18090 \
E2E_KEYCLOAK_URL=http://127.0.0.1:18091 \
E2E_OPENAPI=$PWD/dist/openapi.yaml \
go test -tags=e2e ./e2e/ -run TestAPISchemaConformance -count=1 -v
```

### Console UI e2e

Requires a running golden-path stack. Mirror the workflow step: port-forward
console/server/Keycloak (18080/18090/18091), allow the browser origin on the
`inari-ui` Keycloak client, point the console chart's `keycloakUrl` at the
forward, start `lib/ui-proxy.mjs`, then run the Playwright suite:

```sh
node scripts/e2e/lib/ui-proxy.mjs &   # merges console + API onto :8080
cd scripts/e2e/ui
npm ci
npx playwright install --with-deps chromium
npx playwright test --config playwright.config.ci.ts --grep @p0 --grep-invert @quarantine
```

Failure artifacts (screenshots/videos/traces, JUnit, HTML report) land in
`scripts/e2e/ui/test-results/` and `scripts/e2e/ui/playwright-report/`. See
`ui/README.md` for the layout, spec-author rules, and topology constraints.

### kubectl access

Prereqs: `docker`, `kubectl`, `kubelogin`. Runs a control-plane-only
scenario (docker etcd + kube-apiserver + Keycloak) — no kind needed:

```sh
bash scripts/e2e/kubectl/kubectl-access.sh
```
