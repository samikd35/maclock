import assert from "node:assert/strict";
import test from "node:test";
import {
  chooseWindowsToMinimizeAtStart,
  findInitiallyMinimizedWindowIds,
  chooseInitialAvailableTabsByWindow,
  decideChromeActivation,
} from "../dist/tab-policy.js";

test("start captures only uncovered restorable Chrome windows", () => {
  assert.deepEqual(
    chooseWindowsToMinimizeAtStart(
      [
        { windowId: 7, state: "normal" },
        { windowId: 8, state: "maximized" },
        { windowId: 9, state: "fullscreen" },
        { windowId: 10, state: "minimized" },
      ],
      [7, 9],
    ),
    [{ windowId: 8, previousState: "maximized" }],
  );
});

test("start remembers windows that were already minimized", () => {
  assert.deepEqual(
    findInitiallyMinimizedWindowIds([
      { windowId: 7, state: "normal" },
      { windowId: 8, state: "minimized" },
      { windowId: 9, state: "minimized" },
    ]),
    [8, 9],
  );
});

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

test("every tab in an allowed Chrome window is available without becoming precise", () => {
  assert.deepEqual(
    decideChromeActivation({
      allowedWindowIds: [9],
      availableTabIds: [7],
      attemptedTabId: 90,
      attemptedWindowId: 9,
      lastActivatedTarget: { type: "tab", tabId: 7 },
      now: 10_000,
      lastFeedbackAt: 8_000,
      feedbackIntervalMs: 2_000,
    }),
    {
      restoreTarget: null,
      closeAttemptedTab: false,
      shouldNotify: false,
      nextFeedbackAt: 8_000,
      nextLastActivatedTarget: { type: "window", windowId: 9 },
    },
  );
});

test("an uncovered Chrome window restores the most recent broad window", () => {
  assert.deepEqual(
    decideChromeActivation({
      allowedWindowIds: [9],
      availableTabIds: [7, 8],
      attemptedTabId: 99,
      attemptedWindowId: 12,
      lastActivatedTarget: { type: "window", windowId: 9 },
      now: 10_000,
      lastFeedbackAt: null,
      feedbackIntervalMs: 2_000,
    }),
    {
      restoreTarget: { type: "window", windowId: 9 },
      closeAttemptedTab: false,
      shouldNotify: true,
      nextFeedbackAt: 10_000,
      nextLastActivatedTarget: { type: "window", windowId: 9 },
    },
  );
});

test("a precise tab in an uncovered window remains independently available", () => {
  assert.deepEqual(
    decideChromeActivation({
      allowedWindowIds: [9],
      availableTabIds: [7, 8],
      attemptedTabId: 8,
      attemptedWindowId: 12,
      lastActivatedTarget: { type: "window", windowId: 9 },
      now: 10_500,
      lastFeedbackAt: 10_000,
      feedbackIntervalMs: 2_000,
    }),
    {
      restoreTarget: null,
      closeAttemptedTab: false,
      shouldNotify: false,
      nextFeedbackAt: 10_000,
      nextLastActivatedTarget: { type: "tab", tabId: 8 },
    },
  );
});

test("closure falls back to another configured target without broadening policy", () => {
  assert.deepEqual(
    decideChromeActivation({
      allowedWindowIds: [9],
      availableTabIds: [7],
      attemptedTabId: 99,
      attemptedWindowId: 12,
      lastActivatedTarget: { type: "tab", tabId: 8 },
      now: 10_000,
      lastFeedbackAt: null,
      feedbackIntervalMs: 2_000,
    }),
    {
      restoreTarget: { type: "window", windowId: 9 },
      closeAttemptedTab: false,
      shouldNotify: true,
      nextFeedbackAt: 10_000,
      nextLastActivatedTarget: { type: "window", windowId: 9 },
    },
  );
});

test("when every browser target closed a new tab cannot broaden access", () => {
  assert.deepEqual(
    decideChromeActivation({
      allowedWindowIds: [],
      availableTabIds: [],
      attemptedTabId: 99,
      attemptedWindowId: 12,
      lastActivatedTarget: null,
      now: 10_000,
      lastFeedbackAt: null,
      feedbackIntervalMs: 2_000,
    }),
    {
      restoreTarget: null,
      closeAttemptedTab: true,
      shouldNotify: true,
      nextFeedbackAt: 10_000,
      nextLastActivatedTarget: null,
    },
  );
});
