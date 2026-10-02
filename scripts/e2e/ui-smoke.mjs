#!/usr/bin/env node
// Console UI smoke (Playwright, chromium headless) for the kind stack.
//
// Drives a real browser through the Keycloak login and the Access console —
// the only coverage that exercises the SPA's OIDC flow, tenant switcher, and
// the RBAC role-engine screens (Members, Teams & Roles, Roles, Identity)
// against the deployed stack. Run by the release-e2e golden-path job after
// the api-schema step, behind scripts/e2e/lib/ui-proxy.mjs (single-origin shim).
//
// Env:
//   UI_BASE       console entry URL (through ui-proxy; default http://127.0.0.1:8080)
//   KC_HOST       host:port the browser is redirected to for login (default 127.0.0.1:18091)
//   E2E_USER      Keycloak username (default dev-admin — provisioned by golden-path.sh)
//   E2E_PASSWORD  Keycloak password (default dev-admin)
//   TENANT_NAME   tenant card display name to click (default "E2E Org")
//   SHOT_DIR      screenshot directory on failure (default /tmp/ui-smoke)

import { chromium } from "playwright";

const UI_BASE = process.env.UI_BASE || "http://127.0.0.1:8080";
const KC_HOST = process.env.KC_HOST || "127.0.0.1:18091";
const USER = process.env.E2E_USER || "dev-admin";
const PASS = process.env.E2E_PASSWORD || "dev-admin";
const TENANT_NAME = process.env.TENANT_NAME || "E2E Org";
const SHOT_DIR = process.env.SHOT_DIR || "/tmp/ui-smoke";

// Tab label → text that must render once the tab's data has loaded. These
// strings come from the role-engine console (inari-ui #85): the Roles tab
// and the "Manage roles" matrix exist only there, so this doubles as the
// regression guard for the stale-bundle incident of 2026-10-01.
const TABS = [
  ["Members", "Org-wide membership"],
  ["Teams & Roles", "Assign each team a role"],
  ["Roles", "Built-in"],
  ["Identity", "OIDC Clients"],
];

const failures = [];

async function shot(page, name) {
  try {
    await page.screenshot({ path: `${SHOT_DIR}/${name}.png` });
  } catch {
    /* best effort */
  }
}

const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  page.on("pageerror", (err) => console.log("PAGEERROR", err.message));

  // Login: the SPA redirects to Keycloak; authenticate; land back on the
  // console. KC 26 login theme fields are name=username / name=password.
  await page.goto(`${UI_BASE}/`, { waitUntil: "domcontentloaded" });
  await page.waitForURL((url) => url.host === KC_HOST, { timeout: 30000 });
  // KC 26 default theme is a two-step login: username page first, then the
  // password page after submit.
  await page.fill('input[name="username"]', USER);
  await page.locator('#kc-login, input[type="submit"], button[type="submit"]').first().click();
  await page.waitForSelector('input[name="password"]', { timeout: 30000 });
  await page.fill('input[name="password"]', PASS);
  await page.locator('#kc-login, input[type="submit"], button[type="submit"]').first().click();
  await page.waitForURL((url) => url.origin === new URL(UI_BASE).origin, { timeout: 30000 });
  await page.waitForFunction(() => document.body.innerText !== "Loading…", { timeout: 45000 });
  console.log("ui-smoke: login OK, console booted");

  // Tenant switcher home → click the tenant card.
  await page.getByRole("link", { name: new RegExp(TENANT_NAME) }).first().click();
  await page.waitForFunction(() => !document.body.innerText.includes("Loading…"), {
    timeout: 15000,
  });

  // Sidebar → Access.
  await page.getByRole("link", { name: "Access", exact: true }).first().click();

  for (const [tab, marker] of TABS) {
    const link = page.getByRole("link", { name: tab, exact: true }).first();
    if ((await link.count()) === 0) {
      console.log(`ui-smoke: FAIL tab "${tab}" — nav link not found`);
      failures.push(tab);
      await shot(page, `missing-${tab.replace(/\W+/g, "-").toLowerCase()}`);
      continue;
    }
    await link.click();
    try {
      await page.waitForSelector(`text=${marker}`, { timeout: 20000 });
      console.log(`ui-smoke: tab "${tab}" OK ("${marker}")`);
    } catch {
      console.log(`ui-smoke: FAIL tab "${tab}" — marker "${marker}" never rendered`);
      failures.push(tab);
      await shot(page, `fail-${tab.replace(/\W+/g, "-").toLowerCase()}`);
    }
  }
} finally {
  await browser.close();
}

if (failures.length) {
  console.log(`ui-smoke: FAILED tabs: ${failures.join(", ")} (screenshots in ${SHOT_DIR})`);
  process.exit(1);
}
console.log("ui-smoke: ALL ACCESS TABS OK");
