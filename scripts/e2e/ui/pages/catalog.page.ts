// Catalog browse page object. Marker heading ("Catalog") comes from inari-ui
// src/pages/catalog/catalog-browse.tsx. No assertions.

import type { Locator, Page } from "@playwright/test";

import { AppShellPage } from "./app-shell.page";

export class CatalogPage {
  static readonly LABEL = "Catalog";

  readonly shell: AppShellPage;

  constructor(readonly page: Page) {
    this.shell = new AppShellPage(page);
  }

  /** Open the Catalog via the sidebar. */
  async goto(): Promise<void> {
    await this.shell.nav(CatalogPage.LABEL);
  }

  /** Heading that renders once the browse page is up. */
  marker(): Locator {
    return this.page.getByRole("heading", { name: CatalogPage.LABEL, exact: true });
  }
}
