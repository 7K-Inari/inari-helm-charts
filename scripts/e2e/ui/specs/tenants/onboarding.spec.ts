// @p1 @tenants — tenant onboarding through the console UI (e2e plan P1-4).
//
// As dev-admin: open the header tenant switcher → "Create organization",
// submit the form with a unique slug (e2e-<runId>-<seq>-onb), land in the
// new tenant context, assert the four Access console tabs render their
// markers (same markers as the @p0 smoke spec), and confirm via the API
// that the org exists with the expected metadata. The duplicate-slug step
// then re-submits the same slug and asserts the server-side 409 surfaces as
// the field-level slug error (no silent failure).
//
// LEFTOVER ORG — INTENTIONAL: this spec does NOT delete the org it creates.
// P1-5 (tenant switching) needs a second org to switch between and discovers
// this one by name convention (see below). CI runs on a fresh kind cluster
// per workflow run, so leftovers are harmless.
//
// P1-5 discovery convention: the slug matches `e2e-<runId>-*-onb`
// (uniqueName("onb") from fixtures/org.ts) and the display name is
// `E2E <slug>`; resolve it via GET /api/v1/tenants filtering on the
// "-onb" suffix (never hard-code the seq).
//
// Onboarding is async end to end — the Keycloak organization claim only
// lists the new org after a forced token refresh, and OrgTeamSync provisions
// the org's teams/built-in roles on an interval — so EVERY step below polls
// (helpers/poll.ts); nothing asserts immediately after clicking Create.
//
// Timeout budget: expected runtime ~60s, dominated by the landing/tab
// propagation polls. The describe-level 180s test timeout keeps the project
// default (60s) from killing them.

import { expect, test, type Page } from "@playwright/test";

import { uniqueName } from "../../fixtures/org";
import { ApiClient } from "../../helpers/api";
import { poll } from "../../helpers/poll";
import { AccessPage } from "../../pages/access/access.page";
import { IdentityTabPage } from "../../pages/access/identity.page";
import { MembersTabPage } from "../../pages/access/members.page";
import { RolesTabPage } from "../../pages/access/roles.page";
import { TeamsRolesTabPage } from "../../pages/access/teams-roles.page";
import { AppShellPage } from "../../pages/app-shell.page";
import { CreateOrganizationPage } from "../../pages/organizations/create-organization.page";

const SLUG = uniqueName("onb");
const DISPLAY_NAME = `E2E ${SLUG}`;

interface ListedTenants {
  tenants?:
    | {
        slug: string;
        displayName: string;
        status: string;
        keycloakOrgId: string;
        createdAt: string;
      }[]
    | null;
}

/**
 * Land in the new tenant's context. The SPA force-refreshes the KC token
 * before navigating, but if the organization claim still lags, the tenant
 * context falls back to /all/overview — so retry the navigation until the
 * URL sticks on the new slug.
 */
async function landInTenant(page: Page): Promise<AppShellPage> {
  const shell = new AppShellPage(page);
  await poll(
    async () => {
      if (!page.url().includes(`/${SLUG}/`)) {
        await page.goto(`/${SLUG}/overview`, { waitUntil: "domcontentloaded" });
        await shell.waitForBoot();
      }
      expect(page).toHaveURL(new RegExp(`/${SLUG}/overview`), { timeout: 5_000 });
      return true;
    },
    { timeout: 60_000, interval: 5_000, message: `landing in /${SLUG}/overview` },
  );
  return shell;
}

test.describe.serial("tenant onboarding via the console UI @p1 @tenants", () => {
  test.setTimeout(180_000);

  test("create a new organization through the console UI", async ({ page }) => {
    const shell = new AppShellPage(page);
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await shell.waitForBoot();

    await shell.openCreateOrganization();
    const createOrg = new CreateOrganizationPage(page);
    await expect(createOrg.heading()).toBeVisible();

    await createOrg.createOrganization(DISPLAY_NAME, SLUG);

    // Async: forced KC token refresh + organization-claim propagation before
    // the tenant context accepts the new slug (see landInTenant).
    await landInTenant(page);
    await expect(page.getByText(new RegExp(`Tenant\\s+${SLUG}`))).toBeVisible();
  });

  test("Access console tabs render in the new tenant", async ({ page }) => {
    await landInTenant(page);
    const access = new AccessPage(page);
    await access.goto();

    const tabs = [
      { label: MembersTabPage.LABEL, marker: () => new MembersTabPage(page).marker() },
      { label: TeamsRolesTabPage.LABEL, marker: () => new TeamsRolesTabPage(page).marker() },
      { label: RolesTabPage.LABEL, marker: () => new RolesTabPage(page).marker() },
      { label: IdentityTabPage.LABEL, marker: () => new IdentityTabPage(page).marker() },
    ];

    for (const { label, marker } of tabs) {
      await test.step(`tab "${label}"`, async () => {
        // Async: the tab APIs (and the Roles tab's built-in rows) only
        // return data once KC organization creation + OrgTeamSync have run
        // for the fresh org, so poll instead of asserting right away.
        await poll(
          async () => {
            await access.selectTab(label);
            await expect(marker()).toBeVisible({ timeout: 5_000 });
            return true;
          },
          {
            timeout: 90_000,
            interval: 5_000,
            message: `tab "${label}" marker in org ${SLUG}`,
          },
        );
      });
    }
  });

  test("the organization exists via the API with the expected metadata", async () => {
    const api = await ApiClient.forPersona();
    const org = await poll(
      async () => {
        const body = await api.get<ListedTenants>("/api/v1/tenants");
        const match = (body.tenants ?? []).find((t) => t.slug === SLUG);
        // keycloakOrgId is only set once the async KC organization
        // provisioning has run — requiring it here (not just asserting after
        // the poll) is what actually waits out that propagation.
        expect(match?.keycloakOrgId, `org ${SLUG} with keycloakOrgId`).toBeTruthy();
        return match!;
      },
      { timeout: 60_000, interval: 5_000, message: `org ${SLUG} listed via API` },
    );
    expect(org.displayName).toBe(DISPLAY_NAME);
    expect(org.status).toBeTruthy();
    expect(org.createdAt).toBeTruthy();
    expect(org.createdAt).toBeTruthy();
  });

  test("duplicate slug surfaces the 409 as a field-level error", async ({ page }) => {
    const shell = new AppShellPage(page);
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await shell.waitForBoot();

    await shell.openCreateOrganization();
    const createOrg = new CreateOrganizationPage(page);
    await expect(createOrg.heading()).toBeVisible();

    // Same slug as the org created above → server rejects with 409, which
    // the UI must surface on the slug field (not silently swallow).
    await createOrg.createOrganization(`E2E ${SLUG} duplicate`, SLUG);

    await expect(createOrg.slugError()).toBeVisible();
    await expect(createOrg.slugError()).not.toBeEmpty();
    // No navigation happened and the form is usable again.
    await expect(page).toHaveURL(/\/create-organization$/);
    await expect(createOrg.submitButton()).toBeEnabled();
  });
});
