// Unit tests for the pure decision logic in seed-personas.mjs (node --test).
// The HTTP/Kubernetes side effects are not covered here — they are exercised
// by the release-e2e golden-path job against a live kind stack.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  PERSONAS,
  mergeClientRedirects,
  planRoleAssignments,
  requireBuiltinRoles,
} from "./seed-personas.mjs";

const ORIGIN = "http://127.0.0.1:8080";

describe("PERSONAS", () => {
  it("seeds exactly the four non-admin personas, three with built-in roles", () => {
    assert.deepEqual(
      PERSONAS.map((p) => [p.username, p.role]),
      [
        ["e2e-operator", "operator"],
        ["e2e-editor", "editor"],
        ["e2e-viewer", "viewer"],
        ["e2e-member", null],
      ],
    );
  });

  it("passwords equal usernames (dev-admin convention)", () => {
    for (const p of PERSONAS) assert.equal(p.password, p.username);
  });
});

describe("mergeClientRedirects", () => {
  it("adds the browser origin to a client that lacks it", () => {
    const client = { redirectUris: ["http://localhost/*"], webOrigins: ["+"] };
    const out = mergeClientRedirects(client, ORIGIN);
    assert.equal(out.changed, true);
    assert.deepEqual(out.body.redirectUris, ["http://localhost/*", `${ORIGIN}/*`]);
    assert.deepEqual(out.body.webOrigins, ["+", ORIGIN]);
  });

  it("is a no-op when the origin is already present (idempotent rerun)", () => {
    const client = { redirectUris: [`${ORIGIN}/*`], webOrigins: [ORIGIN] };
    const out = mergeClientRedirects(client, ORIGIN);
    assert.equal(out.changed, false);
    assert.deepEqual(out.body.redirectUris, [`${ORIGIN}/*`]);
    assert.deepEqual(out.body.webOrigins, [ORIGIN]);
  });

  it("tolerates missing arrays on the client representation", () => {
    const out = mergeClientRedirects({}, ORIGIN);
    assert.deepEqual(out.body.redirectUris, [`${ORIGIN}/*`]);
    assert.deepEqual(out.body.webOrigins, [ORIGIN]);
  });
});

describe("requireBuiltinRoles", () => {
  const roles = [
    { id: "r-admin", name: "admin", builtin: true },
    { id: "r-operator", name: "operator", builtin: true },
    { id: "r-editor", name: "editor", builtin: true },
    { id: "r-viewer", name: "viewer", builtin: true },
    { id: "r-custom", name: "custom-x", builtin: false },
  ];

  it("maps every built-in role name to its id", () => {
    assert.deepEqual(requireBuiltinRoles(roles), {
      admin: "r-admin",
      operator: "r-operator",
      editor: "r-editor",
      viewer: "r-viewer",
    });
  });

  it("fails loudly when a built-in is missing (P0-class signal)", () => {
    const broken = roles.filter((r) => r.name !== "viewer");
    assert.throws(() => requireBuiltinRoles(broken), /viewer/);
  });
});

describe("planRoleAssignments", () => {
  const ids = { "e2e-operator": "u-op", "e2e-editor": "u-ed", "e2e-viewer": "u-vi", "e2e-member": "u-me" };

  it("assigns roles only to members that lack them", () => {
    const members = [
      { userId: "u-op", roles: ["operator"] }, // already seeded
      { userId: "u-ed", roles: [] },
      // u-vi not yet projected into the server (KC join still propagating)
      { userId: "u-me", roles: [] },
    ];
    const plan = planRoleAssignments(PERSONAS, ids, members);
    assert.deepEqual(
      plan.assignments.map((a) => [a.username, a.userId, a.role]),
      [
        ["e2e-editor", "u-ed", "editor"],
        ["e2e-viewer", "u-vi", "viewer"],
      ],
    );
    assert.deepEqual(plan.skipped, ["e2e-operator"]);
    assert.equal(plan.memberLeak, null);
  });

  it("flags a role on e2e-member as a spec leak (never auto-fixed)", () => {
    const members = [{ userId: "u-me", roles: ["viewer"] }];
    const plan = planRoleAssignments(PERSONAS, ids, members);
    assert.equal(plan.assignments.length, 3);
    assert.deepEqual(plan.memberLeak, ["viewer"]);
  });
});
