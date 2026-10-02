// Access → Members tab page object. Marker text ("Org-wide membership")
// comes from inari-ui src/pages/access/members-tab.tsx. No assertions.

import type { Locator, Page } from "@playwright/test";

export class MembersTabPage {
  static readonly LABEL = "Members";
  static readonly MARKER = "Org-wide membership";

  constructor(readonly page: Page) {}

  /** Text that renders once the tab's data has loaded. */
  marker(): Locator {
    return this.page.getByText(MembersTabPage.MARKER).first();
  }
}
