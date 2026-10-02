// Persona registry + login helper for the Playwright setup-project pattern.
//
// Each persona logs in once per run through the REAL Keycloak 26 two-step UI
// flow (username → submit → password) and saves its storageState to
// .auth/<persona>.json; test projects reuse the file via `storageState` in
// playwright.config.ts. Only the dev-admin persona is wired to a project for
// now — later waves add operator/editor/viewer/member by appending an entry
// to PERSONAS and a matching setup spec + project.

import type { Page } from "@playwright/test";

import { LoginPage } from "../pages/login.page";

export interface Persona {
  /** storageState file stem under .auth/ (e.g. "dev-admin"). */
  name: string;
  username: string;
  password: string;
}

export const PERSONAS: Record<string, Persona> = {
  // Provisioned by golden-path.sh (platform-admins group, E2E Org creator).
  devAdmin: {
    name: "dev-admin",
    username: process.env.E2E_USER || "dev-admin",
    password: process.env.E2E_PASSWORD || "dev-admin",
  },
  // Later waves: operator, editor, viewer, member.
};

export function authFile(persona: Persona): string {
  return `.auth/${persona.name}.json`;
}

/**
 * Drive a fresh page through the console's OIDC redirect and the KC two-step
 * login, then persist storageState for `persona`.
 */
export async function loginAsPersona(page: Page, persona: Persona): Promise<void> {
  const login = new LoginPage(page);
  await login.gotoViaApp();
  await login.login(persona.username, persona.password);
  // The SPA still shows its "Loading…" gate while it fetches /me/* with the
  // fresh token; storageState is only useful once the session is fully
  // established, so wait for boot before saving. Require non-empty text:
  // right after the OIDC redirect the body is still empty (""), which would
  // trivially pass a plain !== "Loading…" check before the SPA has even
  // processed the callback and persisted its tokens.
  await page.waitForFunction(
    () => document.body.innerText.trim().length > 0 && !document.body.innerText.includes("Loading…"),
    { timeout: 45_000 },
  );
  await page.context().storageState({ path: authFile(persona) });
}
