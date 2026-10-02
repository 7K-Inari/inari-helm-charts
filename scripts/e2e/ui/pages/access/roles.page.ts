// Access → Roles tab page object. Marker text ("Built-in") comes from
// inari-ui src/pages/access/roles-tab.tsx. No assertions.

import type { Locator, Page } from "@playwright/test";

export class RolesTabPage {
  static readonly LABEL = "Roles";
  static readonly MARKER = "Built-in";

  constructor(readonly page: Page) {}

  /** Text that renders once the tab's data has loaded. */
  marker(): Locator {
    return this.page.getByText(RolesTabPage.MARKER).first();
  }

  /** Table row for a role, located by its display name. */
  roleRow(displayName: string): Locator {
    return this.page.getByRole("row", { name: displayName });
  }

  /** "Built-in" badge inside a role row. */
  builtinBadge(row: Locator): Locator {
    return row.getByText("Built-in", { exact: true });
  }

  /** Edit button inside a role row. */
  editButton(row: Locator): Locator {
    return row.getByRole("button", { name: "Edit", exact: true });
  }

  /**
   * Delete button inside a role row. Only rendered for custom roles
   * (roles-tab.tsx gates it on `!role.builtin`); specs assert absence.
   */
  deleteButton(row: Locator): Locator {
    return row.getByRole("button", { name: "Delete", exact: true });
  }

  /** Open the role editor for a row. */
  async openEditor(row: Locator): Promise<void> {
    await this.editButton(row).click();
  }

  /** "Name" input inside the role editor card. */
  editorNameInput(): Locator {
    return this.page.locator("#role-name");
  }

  /** Cancel button inside the role editor card. */
  editorCancelButton(): Locator {
    return this.page.getByRole("button", { name: "Cancel", exact: true });
  }
}
