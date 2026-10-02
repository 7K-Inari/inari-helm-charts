// Access → Identity tab page object. Marker text ("OIDC Clients") comes from
// inari-ui src/pages/access/access-page.tsx (IdentityTab). No assertions.

import type { Locator, Page } from "@playwright/test";

export class IdentityTabPage {
  static readonly LABEL = "Identity";
  static readonly MARKER = "OIDC Clients";

  constructor(readonly page: Page) {}

  /** Text that renders once the tab's data has loaded. */
  marker(): Locator {
    return this.page.getByText(IdentityTabPage.MARKER).first();
  }
}
