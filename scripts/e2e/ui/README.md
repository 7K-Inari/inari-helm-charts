# scripts/e2e/ui — console UI e2e (Playwright Test)

Browser-level e2e for the Inari console, run by `release-e2e.yaml` on **both**
HA matrix legs after golden-path and the api-schema suite. Replaces the
former `scripts/e2e/ui-smoke.mjs` raw-Playwright script.

## Layout

```
scripts/e2e/ui/
├── playwright.config.ts        # local defaults (list reporter, no retries)
├── playwright.config.ci.ts     # CI: retries 2, workers 1, screenshot/video/trace on failure, JUnit + HTML + JSON
├── report-flakes.mjs           # post-processes the JSON report: logs + writes test-results/flake-report.json
├── report-flakes.test.mjs      # unit tests (node --test) — fixture with flaky/failed/passed cases
├── quarantine-issues.mjs       # NIGHTLY ONLY: files/dedupes `e2e-flake` issues for tests flaky
│                             #   in 2+ nightly runs within 7 days
├── quarantine-issues.test.mjs  # unit tests (node --test) for the aggregation/dedupe logic
├── fixtures/
│   ├── auth.ts                 # persona registry (5 personas) + KC two-step login helper
│   ├── auth.setup.ts           # setup project: saves .auth/<persona>.json for every persona
│   └── org.ts                  # unique-name factories: e2e-<runId>-<seq>[-<kind>]
├── seed/
│   ├── seed-personas.mjs       # IDEMPOTENT persona seed (KC users + org join + role memberships
│   │                           #   via the inari-server API + inari-ui redirect whitelist)
│   └── seed-personas.test.mjs  # unit tests for the seed's decision logic (node --test)
├── helpers/
│   ├── env.ts                  # env contract (UI_BASE, KC_HOST, KC_URL, TENANT_NAME, ...)
│   ├── poll.ts                 # poll(fn, { timeout, interval }) — see the polling RULE below
│   └── api.ts                  # thin inari-server REST client (direct-grant token; reads +
│   │                           #   DELETE for spec-owned cleanup only + raw() for
│   │                           #   negative-path assertions — see rule 5 below)
├── pages/
│   ├── login.page.ts           # KC 26 two-step form (username → submit → password)
│   ├── app-shell.page.ts       # boot gate, tenant cards, sidebar nav, "Loading…" waits
│   └── access/                 # Access section + Members / Teams & Roles / Roles / Identity tabs
└── specs/
    ├── smoke/
    │   └── access-tabs.spec.ts # @p0 @smoke — the four RBAC tabs render their markers
    └── rbac/
        ├── role-lifecycle.spec.ts # @p0 @rbac — custom role CRUD, team→role mapping,
        │                          #   propagation to e2e-member's /me/permissions,
        │                          #   delete-in-use 409, cleanup
        └── builtin-protection.spec.ts # @p0 @rbac — built-in role rename/delete 409s (UI + API)
                                       #   and the tenant.admin last-admin guardrail (P0-3/P0-4)
```

The role-lifecycle spec's propagation step polls `GET /me/permissions` with
`e2e-member`'s token for up to **120s** (5s interval) — that budget covers
the OrgTeamSync interval plus the `/me/permissions` cache TTL and dominates
the spec's ~90s expected runtime; the describe sets a 180s test timeout so
the project default (60s) can't kill the poll.

## Running locally

Requires a running golden-path stack (`cd scripts/e2e/stack && KEEP_CLUSTER=true go test -tags=e2e -count=1 -timeout 40m ./...`).

```sh
kubectl -n inari port-forward svc/inari-console 18080:80 &
kubectl -n inari port-forward svc/inari-server 18090:8080 &
kubectl -n inari port-forward svc/keycloak-service 18091:8080 &
node scripts/e2e/ui/seed/seed-personas.mjs   # idempotent; safe to re-run
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

## Personas

Seeded by `seed/seed-personas.mjs` (run as a workflow step between stack
bring-up and the Playwright run; idempotent — safe to re-run against a kept
cluster). One per ADR-0013 built-in role, plus the role-less member:

| User | Password | Role | Purpose | Mutation policy |
|---|---|---|---|---|
| `dev-admin` | `dev-admin` | `admin` (platform-admins, E2E Org creator) | default `chromium` project identity; seeded by the golden-path stack suite (`suite/seed.go`) | never touched by specs |
| `e2e-operator` | `e2e-operator` | `operator` (Platform Engineer) | operator-scope RBAC coverage | **specs must never change the assignment** |
| `e2e-editor` | `e2e-editor` | `editor` (Developer) | developer-scope RBAC coverage | **specs must never change the assignment** |
| `e2e-viewer` | `e2e-viewer` | `viewer` | read-only RBAC surface | **specs must never change the assignment** |
| `e2e-member` | `e2e-member` | *(none)* | org member with no role/team — propagation target for the role-lifecycle spec | owned by the role-lifecycle spec, which **must restore it to role-less** (afterEach/afterAll) |

Role assignment goes through the real inari-server membership API
(`PUT /api/v1/tenants/{org}/members/{subject}` with a built-in `roleId`) —
never KC groups, never direct DB — so seeding doubles as a membership-path
signal. The seed fails fast if that API misbehaves (P0-class, not a seed
bug).

## Rules for spec authors

1. **Poll after every mutation.** No spec ever asserts immediately after a
   mutation. All propagation — the OrgTeamSync interval, the
   `/me/permissions` cache, the PEP TTL — is observed via
   `helpers/poll.ts` with an explicit timeout/interval.
2. **No assertions in page objects.** `pages/` exposes stable
   `getByRole`/`getByLabel` locators and intent-level actions; specs own
   every `expect()`.
3. **Tags.** Priority tags `@p0`/`@p1`/`@p2`, suite tags like `@smoke`, and
   `@quarantine` for known-flaky specs. The release gate greps `@p0` and
   inverts `@quarantine` (a quarantined test NEVER blocks a release); the
   nightly (`e2e-nightly.yaml`) runs the full `@p0|@p1|@p2` set including
   `@quarantine`. Flake → issue → quarantine lifecycle: see "Flakiness
   containment" in `scripts/e2e/README.md`.
4. **Personas are fixed, spec objects are unique.** Never mutate the role
   personas' assignments or `dev-admin` (see the table above); only
   `e2e-member`'s role may change, and only inside the role-lifecycle spec.
   Spec-created objects (orgs/teams/roles) go through the `fixtures/org.ts`
   unique-name factory — never create fixed-name objects that could collide
   with the seed.
5. **API client is read-only — except `raw()`.** `ApiClient.get/post` are for
   setup/assertion reads. The sole exception is `raw()`, which returns the
   status without throwing and exists only for negative-path assertions where
   the spec's subject IS the rejection (e.g. the 409 guardrails in
   `specs/rbac/`). Never use `raw()` to set up state or to bypass the UI for
   behavior a spec is meant to exercise through the console.

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
- **inari-ui client redirect whitelist.** The realm re-import wipes the
  `inari-ui` client's redirect URIs / web origins every run, so
  `seed/seed-personas.mjs` re-adds `http://127.0.0.1:8080/*` before the
  Playwright run. The seed owns this — do not re-add it to the workflow or
  the suite.
