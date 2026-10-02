// Settings → Organization profile page object. Markup from inari-ui
// src/pages/settings/org/org-profile.tsx. No assertions.

import type { Locator, Page } from "@playwright/test";

export class OrgProfileSettingsPage {
  static readonly LABEL = "Profile";
  static readonly SAVED_TEXT = "Organization profile saved.";

  constructor(readonly page: Page) {}

  /** Transient success card rendered after a successful PATCH. */
  savedMessage(): Locator {
    return this.page.getByText(OrgProfileSettingsPage.SAVED_TEXT, { exact: true });
  }

  /** Error card rendered when the PATCH fails. */
  errorMessage(): Locator {
    return this.page.locator(".text-destructive").first();
  }

  displayNameInput(): Locator {
    return this.page.getByLabel("Display name", { exact: true });
  }

  slugInput(): Locator {
    return this.page.getByLabel("Slug", { exact: true });
  }

  saveButton(): Locator {
    return this.page.getByRole("button", { name: "Save", exact: true });
  }

  async setDisplayName(name: string): Promise<void> {
    await this.displayNameInput().fill(name);
  }

  async save(): Promise<void> {
    await this.saveButton().click();
  }
}
