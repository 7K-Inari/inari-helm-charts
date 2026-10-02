// App-shell page object: console boot gate, tenant switcher/cards, sidebar
// nav, and the "Loading…" waits. No assertions — specs call expect().

import type { Page } from "@playwright/test";

export class AppShellPage {
  constructor(readonly page: Page) {}

  /** Wait until the SPA has booted past its initial "Loading…" gate. */
  async waitForBoot(): Promise<void> {
    await this.page.waitForFunction(() => document.body.innerText !== "Loading…", {
      timeout: 45_000,
    });
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
}
