// Settings console landing page object: the inner nav (SettingsLayout in
// inari-ui src/pages/settings/settings-layout.tsx) shared by every settings
// sub-page, plus the "Read-only (org viewer)" notice shown by settings write
// pages to non-admins (src/pages/settings/components/section-header.tsx).
// No assertions.

import type { Locator, Page } from "@playwright/test";

import { AppShellPage } from "../app-shell.page";

export class SettingsPage {
  static readonly READ_ONLY_NOTICE = "Read-only (org viewer)";

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

  /** Section heading (h1) of a settings page. */
  heading(title: string): Locator {
    return this.page.getByRole("heading", { name: title, exact: true });
  }

  /** Notice rendered in place of write controls for non-admins. */
  readOnlyNotice(): Locator {
    return this.page.getByText(SettingsPage.READ_ONLY_NOTICE, { exact: true }).first();
  }
}
