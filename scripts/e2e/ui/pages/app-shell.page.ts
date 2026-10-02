// App-shell page object: console boot gate, tenant switcher/cards, sidebar
// nav, and the "Loading…" waits. No assertions — specs call expect().

import type { Page } from "@playwright/test";

export class AppShellPage {
  constructor(readonly page: Page) {}

  /** Wait until the SPA has booted past its initial "Loading…" gate. */
  async waitForBoot(): Promise<void> {
    // Require non-empty text: on first paint the body is still empty (""),
    // which would trivially pass a plain !== "Loading…" check before the
    // SPA has rendered anything.
    await this.page.waitForFunction(
      () => document.body.innerText.trim().length > 0 && !document.body.innerText.includes("Loading…"),
      { timeout: 45_000 },
    );
  }

  /** Wait until no "Loading…" placeholder remains (post-navigation). */
  async waitPastLoading(): Promise<void> {
    await this.page.waitForFunction(
      () => !document.body.innerText.includes("Loading…"),
      { timeout: 15_000 },
    );
  }

  /** Click a tenant card on the switcher home by its display name. */
  async openTenant(name: string): Promise<void> {
    await this.page.getByRole("link", { name: new RegExp(name) }).first().click();
    await this.waitPastLoading();
  }

  /** Navigate via a sidebar link (exact name match, e.g. "Access"). */
  async nav(name: string): Promise<void> {
    await this.page.getByRole("link", { name, exact: true }).first().click();
  }

  /**
   * Open the "Create organization" page via the header tenant switcher
   * (inari-ui src/layout/tenant-switcher.tsx — the menu item renders only
   * for callers with canCreateOrganizations).
   */
  async openCreateOrganization(): Promise<void> {
    await this.page.getByRole("button", { name: "Tenant context switcher" }).click();
    await this.page.getByRole("menuitem", { name: "Create organization" }).click();
  }
}
