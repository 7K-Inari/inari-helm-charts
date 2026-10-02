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
}
