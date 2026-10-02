// Unique organization-name factory for specs that create orgs:
//   e2e-<runId>-<seq>
// runId is GITHUB_RUN_ID in CI (one per workflow run, so reruns of the same
// run share the prefix) or a random hex prefix locally. seq is a monotonic
// counter per worker process.

import { randomBytes } from "node:crypto";

const runId = process.env.GITHUB_RUN_ID || randomBytes(4).toString("hex");
let seq = 0;

export function uniqueOrgName(): string {
  seq += 1;
  return `e2e-${runId}-${seq}`;
}
