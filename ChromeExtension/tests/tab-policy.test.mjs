import assert from "node:assert/strict";
import test from "node:test";
import { decideTabActivation } from "../dist/tab-policy.js";

test("an allowed activation remains untouched", () => {
  assert.deepEqual(
    decideTabActivation({
      allowedTabId: 7,
      attemptedTabId: 7,
      now: 10_000,
      lastFeedbackAt: 8_000,
      feedbackIntervalMs: 2_000,
    }),
    { restoreTabId: null, shouldNotify: false, nextFeedbackAt: 8_000 },
  );
});

test("a blocked activation restores the immutable tab and shows feedback", () => {
  assert.deepEqual(
    decideTabActivation({
      allowedTabId: 7,
      attemptedTabId: 99,
      now: 10_000,
      lastFeedbackAt: null,
      feedbackIntervalMs: 2_000,
    }),
    { restoreTabId: 7, shouldNotify: true, nextFeedbackAt: 10_000 },
  );
});

test("blocked feedback is rate limited without weakening restoration", () => {
  assert.deepEqual(
    decideTabActivation({
      allowedTabId: 7,
      attemptedTabId: 99,
      now: 10_500,
      lastFeedbackAt: 10_000,
      feedbackIntervalMs: 2_000,
    }),
    { restoreTabId: 7, shouldNotify: false, nextFeedbackAt: 10_000 },
  );
});
