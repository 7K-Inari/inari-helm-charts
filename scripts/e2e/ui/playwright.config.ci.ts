// CI overrides for the console UI e2e suite (release-e2e.yaml).
// Serial workers + retries, full failure artifacts, JUnit + HTML reports.

import { defineConfig } from "@playwright/test";

import base from "./playwright.config";

export default defineConfig({
  ...base,
  retries: 2,
  workers: 1,
  forbidOnly: true,
  reporter: [
    ["junit", { outputFile: "test-results/junit.xml" }],
    ["html", { outputFolder: "playwright-report", open: "never" }],
  ],
  use: {
    ...base.use,
    screenshot: "only-on-failure",
    video: "retain-on-failure",
    trace: "on-first-retry",
  },
});
