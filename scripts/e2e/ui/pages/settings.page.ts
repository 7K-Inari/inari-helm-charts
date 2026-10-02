// Settings console page object: sidebar entry, the admin-filtered settings
// nav, and the "Read-only (org viewer)" notice shown by settings write pages
// to non-admins (inari-ui src/pages/settings/settings-nav.ts and
// src/pages/settings/components/section-header.tsx). No assertions.

import type { Locator, Page } from "@playwright/test";

import { AppShellPage } from "./app-shell.page";

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

  /** Link inside the settings nav (filtered by isAdmin server-side role). */
  navLink(label: string): Locator {
    return this.page
      .getByRole("navigation", { name: "Settings" })
      .getByRole("link", { name: label, exact: true });
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
