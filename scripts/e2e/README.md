# scripts/e2e — end-to-end suite map

Canonical home of the Inari e2e suites (relocated from the inari-server
repo's `e2e/` directory). `.github/workflows/release-e2e.yaml` is the CI gate
that runs them. Docs/markdown-only changes pushed to a Release PR
intentionally skip the e2e jobs (the workflow's `gate` job detects them and
reports success) — e2e "not running" on such pushes is expected, not a CI
outage. Suites are organized by surface (per the approved e2e
architecture plan §1, "Unified testing folder structure"):

```
scripts/e2e/
├── golden-path.sh            # full-stack kind gate, PROVISION-ONLY (shell→Go migration phase 1:
│                             #   it brings the stack up and writes a handoff file; stack/ asserts)
├── ui/                       # console UI e2e (Playwright Test suite; see ui/README.md)
├── api/
│   └── api_schema_e2e_test.go    # API ↔ OpenAPI schema conformance (Go, tag e2e)
├── kubectl/
│   └── kubectl-access.sh         # control-plane-only kubectl access scenario
├── lib/
│   └── ui-proxy.mjs              # single-origin shim shared by the UI suites
└── stack/                      # golden-path assertion suite (self-contained Go module, tag e2e)
    ├── main_test.go              # TestGoldenPath entry: ordered subtests per phase
    ├── suite/                    # tenant / cluster / RBAC / policy / disruption (E2E_HA=1) phases
    ├── internal/                 # thin wrappers: poll, kube, kind, kc, inariapi, fga (CLI exec only)
    └── testdata/
        └── nats-values.yaml      # HA NATS JetStream values consumed by golden-path.sh
```

## Suite map

| Suite | Path | Runner | CI trigger | Gating |
|---|---|---|---|---|
| Golden path provisioning (fast) | `golden-path.sh` (`INARI_HA=false`) | bash script on kind | `release-e2e.yaml` job `golden-path` (matrix `ha: false`) on Release PRs | Yes — Release-PR gate |
| Golden path provisioning (HA) | `golden-path.sh` (`INARI_HA=true`) | bash script on kind | `release-e2e.yaml` job `golden-path` (matrix `ha: true`) on Release PRs | Yes — Release-PR gate |
| Golden path assertions (Go) | `stack/` (`suite/`, E2E_HA=1 unlocks disruption subtests) | `go test -tags=e2e ./scripts/e2e/stack/...` on the provisioned kind stack | `release-e2e.yaml` step "Run golden-path Go assertions (stack suite)" on BOTH HA matrix legs (right after provisioning) | Yes — Release-PR gate |
| API schema conformance | `api/api_schema_e2e_test.go` | `go test -tags=e2e` inside the inari-server checkout at the pinned tag | `release-e2e.yaml` step "Run api-schema e2e against the live stack" (after the stack suite) | Yes — Release-PR gate |
| Console UI e2e | `ui/` (Playwright Test) + `lib/ui-proxy.mjs` + `ui/seed/seed-personas.mjs` | `npx playwright test --config playwright.config.ci.ts --grep @p0 --grep-invert @quarantine` in `ui/` | `release-e2e.yaml` step "Run console UI e2e (Playwright)" on BOTH HA matrix legs (after api-schema) | Yes — Release-PR gate |
| Console UI e2e (full, incl. quarantine) | `ui/` (Playwright Test) | `npx playwright test --config playwright.config.ci.ts --grep "@p0\|@p1\|@p2"` (includes `@quarantine`, `continue-on-error`) | `.github/workflows/e2e-nightly.yaml` (cron 03:17 UTC + `workflow_dispatch`) | No — nightly only, non-blocking |
| kubectl access | `kubectl/kubectl-access.sh` | bash script (docker etcd + kube-apiserver; no kind) | not wired into CI yet | No — manual scenario |

## Flakiness containment

The gate NEVER runs a quarantined test — the direct analog of inari-server's
`flaky` build-tag convention.

- **Gate command in effect** (release-e2e.yaml, both HA legs):
  `npx playwright test --config playwright.config.ci.ts --grep @p0 --grep-invert @quarantine`.
  CI runs with `retries: 2`, so a test that passes only after a retry is
  green in the gate but recorded as a flake candidate.
- **Flake reporter** (`ui/report-flakes.mjs`): post-processes the Playwright
  JSON report after every CI run (gate + nightly), logs a summary, and
  writes `test-results/flake-report.json` (test title, file, run id,
  timestamp, branch). Artifacts: `ui-e2e-flakes-ha-<bool>` on gate runs
  (7-day retention), `ui-e2e-flakes-nightly` on nightly runs (14-day
  retention, plus full Playwright HTML/JUnit results).
- **Quarantine policy** (manual part): when an `e2e-flake` issue is triaged,
  tag the test `@quarantine` in its spec title. Quarantined tests are
  excluded from the gate (`--grep-invert @quarantine`) and run only in the
  nightly. De-quarantine (remove the tag, close the issue) once the test
  has been stable in the nightly for ~2 weeks.
- **Quarantine automation** (`ui/quarantine-issues.mjs`, nightly only):
  aggregates the last 7 days of `ui-e2e-flakes-*` artifacts; a test flaky in
  2+ nightly runs within the window gets an issue titled
  `[flake] <test path> — <test title>` labeled `e2e-flake`. Dedupe is by
  test path: an open issue for the same path gets a comment with the new
  occurrences instead of a duplicate.

## Running locally

### Golden path (kind full stack)

Prereqs: `docker`, `kind`, `kubectl`, `helm`, `jq`, `git`, Go, plus checkouts
of the `inari-agent` and `inari-operator` repos next to this one (or set
`AGENT_CHART_DIR` / `OPERATOR_CHART_DIR` explicitly). Build the e2e images
first (`inari/server:e2e` from inari-server, `inari/agent:e2e` from
inari-agent). For the HA assertions also set `SERVER_MIGRATIONS_DIR` to the
inari-server checkout's `internal/db/migrations`.

Two steps (shell→Go migration phase 1): the script provisions and writes a
handoff file; the Go stack suite asserts against the deployed stack:

```sh
KEEP_CLUSTER=true E2E_HANDOFF_PATH=/tmp/inari-e2e-handoff.json \
  bash scripts/e2e/golden-path.sh                     # provision (add INARI_HA=true for the HA stack)
E2E_HANDOFF_PATH=/tmp/inari-e2e-handoff.json \
  go test -tags=e2e -count=1 ./scripts/e2e/stack/...  # assert (add E2E_HA=1 for disruption subtests)
```

`KEEP_CLUSTER=true` (or any `E2E_HANDOFF_PATH`) keeps the kind cluster and
the git host dir alive for the Go suite. Without `E2E_HANDOFF_PATH` the
script provisions and tears down exactly as before, with no assertions.

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
console/server/Keycloak (18080/18090/18091), run the persona seed (idempotent
— also whitelists the browser origin on the `inari-ui` Keycloak client),
point the console chart's `keycloakUrl` at the forward, start
`lib/ui-proxy.mjs`, then run the Playwright suite:

```sh
node scripts/e2e/ui/seed/seed-personas.mjs   # personas + inari-ui whitelist
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
