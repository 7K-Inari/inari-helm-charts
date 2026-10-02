// Access console landing page object: tab strip (Members / Teams & Roles /
// Roles / Identity) shared by the four RBAC tab pages. No assertions.

import type { Locator, Page } from "@playwright/test";

import { AppShellPage } from "../app-shell.page";

export class AccessPage {
  readonly shell: AppShellPage;

  constructor(readonly page: Page) {
    this.shell = new AppShellPage(page);
  }

  /** Open the Access section via the sidebar. */
  async goto(): Promise<void> {
    await this.shell.nav("Access");
  }

  /** Switch to a tab by its visible label. */
  tab(label: string): Locator {
    return this.page.getByRole("link", { name: label, exact: true }).first();
  }

  async selectTab(label: string): Promise<void> {
    await this.tab(label).click();
  }
}
