// Settings → Git page object (tenant state repo + commit policy). Markup
// from inari-ui src/pages/settings/org/git.tsx. No assertions.

import type { Locator, Page } from "@playwright/test";

export class GitConfigSettingsPage {
  static readonly LABEL = "Git";
  static readonly SAVED_TEXT = "Git config saved.";

  constructor(readonly page: Page) {}

  /** Transient success card rendered after a successful PUT. */
  savedMessage(): Locator {
    return this.page.getByText(GitConfigSettingsPage.SAVED_TEXT, { exact: true });
  }

  /** Error card rendered when the PUT fails. */
  errorMessage(): Locator {
    return this.page.locator(".text-destructive").first();
  }

  repoInput(): Locator {
    return this.page.getByLabel("Repository", { exact: true });
  }

  baseBranchInput(): Locator {
    return this.page.getByLabel("Base branch", { exact: true });
  }

  commitPolicySelect(): Locator {
    return this.page.getByLabel("Commit policy", { exact: true });
  }

  saveButton(): Locator {
    return this.page.getByRole("button", { name: "Save", exact: true });
  }

  async setRepo(repo: string): Promise<void> {
    await this.repoInput().fill(repo);
  }

  async setBaseBranch(branch: string): Promise<void> {
    await this.baseBranchInput().fill(branch);
  }

  async setCommitPolicy(policy: "direct" | "pull_request"): Promise<void> {
    await this.commitPolicySelect().selectOption(policy);
  }

  async save(): Promise<void> {
    await this.saveButton().click();
  }
}
