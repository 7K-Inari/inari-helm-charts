// Access → Members tab page object. Marker text ("Org-wide membership") and
// the Teams section markup come from inari-ui
// src/pages/access/members-tab.tsx. No assertions.

import type { Locator, Page } from "@playwright/test";

export class MembersTabPage {
  static readonly LABEL = "Members";
  static readonly MARKER = "Org-wide membership";

  constructor(readonly page: Page) {}

  /** Text that renders once the tab's data has loaded. */
  marker(): Locator {
    return this.page.getByText(MembersTabPage.MARKER).first();
  }

  /** Card for a team in the Teams section (anchored on the slug text). */
  teamCard(teamName: string): Locator {
    return this.page
      .getByText(teamName, { exact: true })
      .locator("xpath=ancestor::*[contains(@class,'border')][1]");
  }

  /** A member entry inside a team's expanded Members panel. */
  memberEntry(teamName: string, memberText: string): Locator {
    return this.teamCard(teamName).getByText(memberText).first();
  }

  /** Create a team via the "Create team" form (role select left at its
   *  default; the Teams & Roles matrix owns team→role mapping). */
  async createTeam(name: string): Promise<void> {
    await this.page.locator("#team-name").fill(name);
    await this.page.getByRole("button", { name: "Create", exact: true }).click();
  }

  /** Expand a team's Members panel. */
  async showMembers(teamName: string): Promise<void> {
    await this.teamCard(teamName).getByRole("button", { name: "Members" }).click();
  }

  /** Add an org member to a team via the debounced search picker. */
  async addMemberToTeam(teamName: string, query: string): Promise<void> {
    await this.page.locator(`#picker-${teamName}`).fill(query);
    // The picker debounces 250ms before the result list renders.
    await this.page
      .getByRole("button", { name: new RegExp(query) })
      .first()
      .click();
  }

  /** Delete a team (removes its membership and role mapping). */
  async deleteTeam(teamName: string): Promise<void> {
    await this.teamCard(teamName).getByRole("button", { name: "Delete" }).click();
  }
}
