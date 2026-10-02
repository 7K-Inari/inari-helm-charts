// Setup project: authenticate each wired persona via the real Keycloak login
// and save .auth/<persona>.json. Only dev-admin for now; later waves add one
// setup test (and matching project) per additional persona.

import { test as setup } from "@playwright/test";

import { loginAsPersona, PERSONAS } from "./auth";

setup("authenticate dev-admin", async ({ page }) => {
  await loginAsPersona(page, PERSONAS.devAdmin);
});
