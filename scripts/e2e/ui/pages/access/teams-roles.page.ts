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
}
