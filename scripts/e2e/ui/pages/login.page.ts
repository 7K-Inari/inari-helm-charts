// Keycloak 26 login form page object. The default KC 26 theme is a two-step
// flow: username page first, then the password page after submit. Fields are
// name=username / name=password; the submit button is #kc-login (with
// input/button[type=submit] as fallback selectors).

import type { Locator, Page } from "@playwright/test";

import { KC_HOST, UI_BASE } from "../helpers/env";

export class LoginPage {
  readonly usernameInput: Locator;
  readonly passwordInput: Locator;
  readonly submitButton: Locator;

  constructor(readonly page: Page) {
    this.usernameInput = page.locator('input[name="username"]');
    this.passwordInput = page.locator('input[name="password"]');
    this.submitButton = page
      .locator('#kc-login, input[type="submit"], button[type="submit"]')
      .first();
  }

  /** Navigate to the console and wait until KC redirects us to its host. */
  async gotoViaApp(): Promise<void> {
    await this.page.goto("/", { waitUntil: "domcontentloaded" });
    await this.page.waitForURL((url) => url.host === KC_HOST, { timeout: 30_000 });
  }

  /** Complete the two-step login and land back on the console origin. */
  async login(username: string, password: string): Promise<void> {
    await this.usernameInput.fill(username);
    await this.submitButton.click();
    await this.passwordInput.waitFor({ timeout: 30_000 });
    await this.passwordInput.fill(password);
    await this.submitButton.click();
    await this.page.waitForURL((url) => url.origin === new URL(UI_BASE).origin, {
      timeout: 30_000,
    });
  }
}
