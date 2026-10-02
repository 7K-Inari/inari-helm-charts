// Unit tests for the pure decision logic in quarantine-issues.mjs
// (node --test). GitHub API side effects are injected in main() and not
// covered here.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  aggregateFlakes,
  planIssueActions,
  issueTitle,
  MIN_FLAKY_RUNS,
} from "./quarantine-issues.mjs";

const NOW = new Date("2026-10-02T00:00:00Z");
const daysAgo = (n) => new Date(NOW.getTime() - n * 86400_000).toISOString();

const flake = (file, title, line = 1) => ({ title, file, line, retries: 1 });
const report = (runId, timestamp, flakes) => ({
  runId,
  runAttempt: "1",
  runUrl: `https://github.com/x/y/actions/runs/${runId}`,
  branch: "main",
  timestamp,
  flakes,
});

describe("aggregateFlakes", () => {
  it("flags a test flaky in 2+ distinct runs within the window", () => {
    const reports = [
      report("r1", daysAgo(1), [flake("specs/a.spec.ts", "t1")]),
      report("r2", daysAgo(3), [flake("specs/a.spec.ts", "t1")]),
    ];
    const out = aggregateFlakes(reports, { now: NOW, windowDays: 7 });
    assert.equal(out.length, 1);
    assert.equal(out[0].count, 2);
    assert.deepEqual(out[0].runs.map((r) => r.runId).sort(), ["r1", "r2"]);
  });

  it("does not flag a test flaky in only 1 run", () => {
    const reports = [report("r1", daysAgo(1), [flake("specs/a.spec.ts", "t1")])];
    assert.deepEqual(aggregateFlakes(reports, { now: NOW, windowDays: 7 }), []);
  });

  it("counts a run once even with multiple reports (HA matrix legs)", () => {
    const reports = [
      report("r1", daysAgo(1), [flake("specs/a.spec.ts", "t1")]),
      report("r1", daysAgo(1), [flake("specs/a.spec.ts", "t1")]), // other leg
    ];
    assert.deepEqual(aggregateFlakes(reports, { now: NOW, windowDays: 7 }), []);
  });

  it("ignores reports older than the window", () => {
    const reports = [
      report("r1", daysAgo(1), [flake("specs/a.spec.ts", "t1")]),
      report("r2", daysAgo(9), [flake("specs/a.spec.ts", "t1")]),
    ];
    assert.deepEqual(aggregateFlakes(reports, { now: NOW, windowDays: 7 }), []);
  });

  it("keys candidates by file+title so different tests don't merge", () => {
    const reports = [
      report("r1", daysAgo(1), [flake("specs/a.spec.ts", "t1")]),
      report("r2", daysAgo(2), [flake("specs/a.spec.ts", "t2")]),
    ];
    assert.deepEqual(aggregateFlakes(reports, { now: NOW, windowDays: 7 }), []);
  });

  it("uses MIN_FLAKY_RUNS = 2 as the threshold", () => {
    assert.equal(MIN_FLAKY_RUNS, 2);
  });
});

describe("planIssueActions", () => {
  const candidate = {
    file: "specs/a.spec.ts",
    title: "t1",
    count: 3,
    runs: [
      { runId: "r1", runUrl: "https://github.com/x/y/actions/runs/r1", timestamp: daysAgo(1) },
      { runId: "r2", runUrl: "https://github.com/x/y/actions/runs/r2", timestamp: daysAgo(3) },
      { runId: "r3", runUrl: "https://github.com/x/y/actions/runs/r3", timestamp: daysAgo(5) },
    ],
  };

  it("creates a new issue when no open issue covers the test path", () => {
    const actions = planIssueActions([candidate], []);
    assert.equal(actions.length, 1);
    assert.equal(actions[0].action, "create");
    assert.equal(actions[0].title, issueTitle(candidate));
    assert.ok(actions[0].title.includes("specs/a.spec.ts"));
  });

  it("comments on the existing open issue instead of opening a duplicate", () => {
    const issues = [
      { number: 42, title: "[flake] specs/a.spec.ts — t1", state: "open" },
    ];
    const actions = planIssueActions([candidate], issues);
    assert.equal(actions.length, 1);
    assert.equal(actions[0].action, "comment");
    assert.equal(actions[0].issueNumber, 42);
  });

  it("creates a new issue when the matching issue is closed", () => {
    const issues = [
      { number: 42, title: "[flake] specs/a.spec.ts — t1", state: "closed" },
    ];
    const actions = planIssueActions([candidate], issues);
    assert.equal(actions[0].action, "create");
  });

  it("dedupe matches on the test path even if the title text drifted", () => {
    const issues = [
      { number: 7, title: "[flake] specs/a.spec.ts — old title", state: "open" },
    ];
    const actions = planIssueActions([candidate], issues);
    assert.equal(actions[0].action, "comment");
    assert.equal(actions[0].issueNumber, 7);
  });
});
