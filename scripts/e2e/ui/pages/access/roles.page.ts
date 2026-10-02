// Access → Roles tab page object. Marker text ("Built-in") and the editor /
// table markup come from inari-ui src/pages/access/roles-tab.tsx. No
// assertions.

import type { Locator, Page } from "@playwright/test";

export class RolesTabPage {
  static readonly LABEL = "Roles";
  static readonly MARKER = "Built-in";

  constructor(readonly page: Page) {}

  /** Text that renders once the tab's data has loaded. */
  marker(): Locator {
    return this.page.getByText(RolesTabPage.MARKER).first();
  }

  /** Table row for a role (matches display name and/or slug). */
  roleRow(name: string): Locator {
    return this.page.getByRole("row", { name: new RegExp(name) });
  }

  /** Destructive error surface (save/delete API errors, validation). */
  errorMessage(): Locator {
    return this.page.locator(".text-destructive").first();
  }

  /** "New role" button — only rendered while no editor is open, so its
   *  visibility doubles as the "editor closed (save settled)" signal. */
  newRoleButton(): Locator {
    return this.page.getByRole("button", { name: "New role" });
  }

  /** Open the create-role editor. */
  async newRole(): Promise<void> {
    await this.newRoleButton().click();
  }

  /** Open the editor for an existing role. */
  async openEditor(roleName: string): Promise<void> {
    await this.roleRow(roleName).getByRole("button", { name: "Edit" }).click();
  }

  /** Checkbox for one permission slug in the open editor. */
  permissionCheckbox(slug: string): Locator {
    return this.page
      .locator("label", { has: this.page.getByText(slug, { exact: true }) })
      .getByRole("checkbox");
  }

  async togglePermission(slug: string): Promise<void> {
    await this.permissionCheckbox(slug).click();
  }

  /** Fill the editor's scalar fields (all optional; empty string clears). */
  async fillEditor(fields: {
    name?: string;
    displayName?: string;
    description?: string;
  }): Promise<void> {
    if (fields.name !== undefined) {
      await this.page.locator("#role-name").fill(fields.name);
    }
    if (fields.displayName !== undefined) {
      await this.page.locator("#role-display-name").fill(fields.displayName);
    }
    if (fields.description !== undefined) {
      await this.page.locator("#role-description").fill(fields.description);
    }
  }

  /** Submit the open editor ("Create" for new roles, "Save" for edits). */
  async submitEditor(): Promise<void> {
    await this.page.getByRole("button", { name: /^(Create|Save)$/ }).click();
  }

  /**
   * Click Delete on a role's row. The UI guards with window.confirm — the
   * caller must register `page.once("dialog", ...)` before invoking this.
   */
  async deleteRole(roleName: string): Promise<void> {
    await this.roleRow(roleName).getByRole("button", { name: "Delete" }).click();
  }
}
