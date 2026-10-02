// Access → Teams & Roles tab page object. Marker text ("Assign each team a
// role") comes from inari-ui src/pages/access/role-matrix.tsx. No assertions.

import type { Locator, Page } from "@playwright/test";

export class TeamsRolesTabPage {
  static readonly LABEL = "Teams & Roles";
  static readonly MARKER = "Assign each team a role";

  constructor(readonly page: Page) {}

  /** Text that renders once the tab's data has loaded. */
  marker(): Locator {
    return this.page.getByText(TeamsRolesTabPage.MARKER).first();
  }

  /** Per-team role select (`aria-label="Role for {display}"`). */
  roleSelect(teamDisplay: string): Locator {
    return this.page.getByLabel(`Role for ${teamDisplay}`);
  }

  /** "Save changes" button (whole-set PUT of the draft). */
  saveButton(): Locator {
    return this.page.getByRole("button", { name: "Save changes", exact: true });
  }

  /** "Discard" button, visible only while a dirty draft exists. */
  discardButton(): Locator {
    return this.page.getByRole("button", { name: "Discard", exact: true });
  }

  /** Tab-level error card showing the server's rejection message. */
  errorCard(): Locator {
    return this.page.locator(".text-destructive").first();
  }

  /** Assign a role to a team and submit the whole-set save. */
  async assignAndSave(teamDisplay: string, roleDisplayName: string): Promise<void> {
    await this.roleSelect(teamDisplay).selectOption({ label: roleDisplayName });
    await this.saveButton().click();
  }
}
