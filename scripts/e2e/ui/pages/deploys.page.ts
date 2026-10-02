// Deploys (resource inventory) page object. The sidebar label is "Deploys";
// the page heading is "Resources" (inari-ui
// src/pages/resources/resource-list.tsx). No assertions.

import type { Locator, Page } from "@playwright/test";

import { AppShellPage } from "./app-shell.page";

export class DeploysPage {
  static readonly LABEL = "Deploys";
  static readonly HEADING = "Resources";

  readonly shell: AppShellPage;

  constructor(readonly page: Page) {
    this.shell = new AppShellPage(page);
  }

  /** Open the Deploys section via the sidebar. */
  async goto(): Promise<void> {
    await this.shell.nav(DeploysPage.LABEL);
  }

  /** Heading that renders once the resource list page is up. */
  marker(): Locator {
    return this.page.getByRole("heading", { name: DeploysPage.HEADING, exact: true });
  }
}
