// Settings console landing page object: the inner nav (SettingsLayout in
// inari-ui src/pages/settings/settings-layout.tsx) shared by every settings
// sub-page. No assertions.

import type { Locator, Page } from "@playwright/test";

import { AppShellPage } from "../app-shell.page";

export class SettingsPage {
  readonly shell: AppShellPage;

  constructor(readonly page: Page) {
    this.shell = new AppShellPage(page);
  }

  /** Open the Settings section via the sidebar. */
  async goto(): Promise<void> {
    await this.shell.nav("Settings");
  }

  /** Inner settings nav ("Tenant/Org", "Identity", ... sections). */
  navItem(label: string): Locator {
    return this.page
      .getByRole("navigation", { name: "Settings", exact: true })
      .getByRole("link", { name: label, exact: true })
      .first();
  }

  /** Switch to a sub-page by its visible nav label (e.g. "Profile", "Git"). */
  async selectItem(label: string): Promise<void> {
    await this.navItem(label).click();
  }
}
