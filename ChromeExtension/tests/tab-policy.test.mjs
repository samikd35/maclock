import assert from "node:assert/strict";
import test from "node:test";
import {
  chooseInitialAvailableTabsByWindow,
  decideTabActivation,
} from "../dist/tab-policy.js";

test("start activates an Available Tab Target in every selected Chrome window", () => {
  assert.deepEqual(
    chooseInitialAvailableTabsByWindow([
      { tabId: 41, windowId: 9, isActive: false },
      { tabId: 42, windowId: 9, isActive: true },
      { tabId: 43, windowId: 10, isActive: false },
      { tabId: 44, windowId: 11, isActive: true },
    ]),
    [42, 43, 44],
  );
});

test("each selected tab can become the most recently activated Available Tab Target", () => {
  assert.deepEqual(
    decideTabActivation({
      availableTabIds: [7, 8],
      attemptedTabId: 8,
      lastActivatedAvailableTabId: 7,
      now: 10_000,
      lastFeedbackAt: 8_000,
      feedbackIntervalMs: 2_000,
    }),
    {
      restoreTabId: null,
      closeAttemptedTab: false,
      shouldNotify: false,
      nextFeedbackAt: 8_000,
      nextLastActivatedAvailableTabId: 8,
    },
  );
});

test("an unapproved activation restores the most recent available target", () => {
  assert.deepEqual(
    decideTabActivation({
      availableTabIds: [7, 8],
      attemptedTabId: 99,
      lastActivatedAvailableTabId: 8,
      now: 10_000,
      lastFeedbackAt: null,
      feedbackIntervalMs: 2_000,
    }),
    {
      restoreTabId: 8,
      closeAttemptedTab: false,
      shouldNotify: true,
      nextFeedbackAt: 10_000,
      nextLastActivatedAvailableTabId: 8,
    },
  );
});

test("closure falls back without broadening another tab policy", () => {
  assert.deepEqual(
    decideTabActivation({
      availableTabIds: [7],
      attemptedTabId: 99,
      lastActivatedAvailableTabId: 8,
      now: 10_500,
      lastFeedbackAt: 10_000,
      feedbackIntervalMs: 2_000,
    }),
    {
      restoreTabId: 7,
      closeAttemptedTab: false,
      shouldNotify: false,
      nextFeedbackAt: 10_000,
      nextLastActivatedAvailableTabId: 7,
    },
  );
});

test("when every selected tab closed an unapproved new tab cannot broaden access", () => {
  assert.deepEqual(
    decideTabActivation({
      availableTabIds: [],
      attemptedTabId: 99,
      lastActivatedAvailableTabId: null,
      now: 10_000,
      lastFeedbackAt: null,
      feedbackIntervalMs: 2_000,
    }),
    {
      restoreTabId: null,
      closeAttemptedTab: true,
      shouldNotify: true,
      nextFeedbackAt: 10_000,
      nextLastActivatedAvailableTabId: null,
    },
  );
});
