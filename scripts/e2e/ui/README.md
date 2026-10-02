# scripts/e2e/ui — console UI e2e (Playwright Test)

Browser-level e2e for the Inari console, run by `release-e2e.yaml` on **both**
HA matrix legs after golden-path and the api-schema suite. Replaces the
former `scripts/e2e/ui-smoke.mjs` raw-Playwright script.

## Layout

```
scripts/e2e/ui/
├── playwright.config.ts        # local defaults (list reporter, no retries)
├── playwright.config.ci.ts     # CI: retries 2, workers 1, screenshot/video/trace on failure, JUnit + HTML
├── fixtures/
│   ├── auth.ts                 # persona registry + KC two-step login helper
│   ├── auth.setup.ts           # setup project: saves .auth/<persona>.json (dev-admin only for now)
│   └── org.ts                  # unique org-name factory: e2e-<runId>-<seq>
├── helpers/
│   ├── env.ts                  # env contract (UI_BASE, KC_HOST, KC_URL, TENANT_NAME, ...)
│   ├── poll.ts                 # poll(fn, { timeout, interval }) — see the polling RULE below
│   └── api.ts                  # thin inari-server REST client (direct-grant token; reads only)
├── pages/
│   ├── login.page.ts           # KC 26 two-step form (username → submit → password)
│   ├── app-shell.page.ts       # boot gate, tenant cards, sidebar nav, "Loading…" waits
│   └── access/                 # Access section + Members / Teams & Roles / Roles / Identity tabs
└── specs/
    └── smoke/
        └── access-tabs.spec.ts # @p0 @smoke — the four RBAC tabs render their markers
```

## Running locally

Requires a running golden-path stack (`KEEP_CLUSTER=true bash scripts/e2e/golden-path.sh`).

```sh
kubectl -n inari port-forward svc/inari-console 18080:80 &
kubectl -n inari port-forward svc/inari-server 18090:8080 &
kubectl -n inari port-forward svc/keycloak-service 18091:8080 &
node scripts/e2e/lib/ui-proxy.mjs &          # merges console + API onto :8080
helm upgrade inari-console charts/inari-console --namespace inari \
  --reuse-values --set keycloakUrl=http://127.0.0.1:18091   # see constraints below

cd scripts/e2e/ui
npm ci
npx playwright install --with-deps chromium
npx playwright test                          # local config
npx playwright test --config playwright.config.ci.ts --grep @p0 --grep-invert @quarantine
```

Env knobs (same names/defaults as the old script): `UI_BASE`
(default `http://127.0.0.1:8080`), `KC_HOST` (`127.0.0.1:18091`), `KC_URL`
(non-browser token/API calls, default `http://$KC_HOST`), `E2E_USER` /
`E2E_PASSWORD` (`dev-admin`), `TENANT_NAME` (`E2E Org`), `API_BASE`
(default `$UI_BASE`).

## Rules for spec authors

1. **Poll after every mutation.** No spec ever asserts immediately after a
   mutation. All propagation — the OrgTeamSync interval, the
   `/me/permissions` cache, the PEP TTL — is observed via
   `helpers/poll.ts` with an explicit timeout/interval.
2. **No assertions in page objects.** `pages/` exposes stable
   `getByRole`/`getByLabel` locators and intent-level actions; specs own
   every `expect()`.
3. **Tags.** Priority tags `@p0`/`@p1`/`@p2`, suite tags like `@smoke`, and
   `@quarantine` for known-flaky specs (CI greps `@p0` and inverts
   `@quarantine`).

## Key constraints (learned the hard way — do not "fix")

- **Browser-reachable `keycloakUrl`, service-DNS issuer.** The console
  chart's `keycloakUrl` must be reachable *from the browser*, so the workflow
  helm-upgrades it to the port-forward (`http://127.0.0.1:18091`). Issued
  tokens keep the converged service-DNS issuer, which the server accepts —
  do not try to align them.
- **Single-origin topology is required.** The server sends no CORS headers
  (never needed in production, where the gateway routes `/api/v1` and `/` on
  one host). In kind, `../lib/ui-proxy.mjs` merges console + API onto
  `:8080` to reproduce that topology for the browser; `UI_BASE` must point at
  the proxy, not the console forward.
- **inari-ui client redirect whitelist.** The workflow adds
  `http://127.0.0.1:8080/*` to the realm-imported `inari-ui` Keycloak
  client's redirect URIs / web origins before the run. That step stays in
  the workflow until the W3 seed script absorbs it — do not move it into the
  suite.
