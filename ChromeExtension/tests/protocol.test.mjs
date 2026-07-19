import assert from "node:assert/strict";
import test from "node:test";
import {
  EXTENSION_ID,
  PROTOCOL_VERSION,
  fitTabsToNativeMessageBudget,
  makeBlockedTabActivation,
  makeBlockedNavigation,
  makeEnforcementError,
  makeEnforcementStarted,
  makeBrowserWindowTargetClosed,
  makeHello,
  makeTabTargetClosed,
  parseNativeMessage,
} from "../dist/protocol.js";

test("creates the fixed identity handshake", () => {
  assert.equal(PROTOCOL_VERSION, 4);
  assert.deepEqual(makeHello("profile_one"), {
    version: PROTOCOL_VERSION,
    type: "hello",
    extensionId: EXTENSION_ID,
    profileId: "profile_one",
  });
});

test("creates a content-free blocked navigation notice", () => {
  assert.deepEqual(makeBlockedNavigation("profile_one", 41), {
    version: 4,
    type: "blockedNavigation",
    profileId: "profile_one",
    tabId: 41,
  });
});

test("identifies the Available Tab Target for a blocked activation", () => {
  assert.deepEqual(makeBlockedTabActivation("profile_one", 90, 41), {
    version: 4,
    type: "blockedTabActivation",
    profileId: "profile_one",
    attemptedTabId: 90,
    availableTabId: 41,
  });
});

test("confirms atomic enforcement with broad windows and exact tabs", () => {
  assert.deepEqual(makeEnforcementStarted("profile_one", [9], [41, 42]), {
    version: 4,
    type: "enforcementStarted",
    profileId: "profile_one",
    windowIds: [9],
    tabIds: [41, 42],
  });
});

test("creates a content-free closed browser window notice", () => {
  assert.deepEqual(makeBrowserWindowTargetClosed("profile_one", 9), {
    version: 4,
    type: "browserWindowTargetClosed",
    profileId: "profile_one",
    windowId: 9,
  });
});

test("creates a content-free closed target notice", () => {
  assert.deepEqual(makeTabTargetClosed("profile_one", 41), {
    version: 4,
    type: "tabTargetClosed",
    profileId: "profile_one",
    tabId: 41,
  });
});

test("reports a loading selected tab without browsing content", () => {
  assert.deepEqual(makeEnforcementError("profile_one", "targetNotReady"), {
    version: 4,
    type: "enforcementError",
    profileId: "profile_one",
    code: "targetNotReady",
  });
});

test("drops optional favicon data before exceeding the native message budget", () => {
  const tabs = fitTabsToNativeMessageBudget(
    "profile_one",
    [
      {
        tabId: 1,
        windowId: 1,
        title: "Documentation",
        url: "https://example.com/docs",
        faviconDataUrl: `data:image/png;base64,${"A".repeat(2_000)}`,
        active: true,
        incognito: false,
      },
    ],
    400,
  );

  assert.equal(tabs.length, 1);
  assert.equal(tabs[0].faviconDataUrl, undefined);
  assert.ok(
    new TextEncoder().encode(JSON.stringify({
      version: 4,
      type: "tabsSnapshot",
      profileId: "profile_one",
      tabs,
    })).length <= 400,
  );
});

test("accepts one atomic broad-window and mixed-scope command", () => {
  const command = {
    version: 4,
    type: "beginEnforcement",
    profileId: "profile_one",
    targets: [
      {
        type: "window",
        windowId: 8,
      },
      {
        type: "tab",
        tabId: 41,
        windowId: 9,
        navigationScope: {
          type: "currentWebsite",
          initialUrl: "https://work.example/project?view=board",
        },
      },
      {
        type: "tab",
        tabId: 42,
        windowId: 10,
        navigationScope: {
          type: "exactPage",
          initialUrl: "https://docs.example/reference?v=1#heading",
        },
      },
    ],
  };

  assert.deepEqual(parseNativeMessage(command), command);
});

test("rejects malformed, duplicate, extra, and unsupported commands", () => {
  for (const value of [
    { version: 3, type: "endEnforcement", profileId: "profile_one" },
    {
      version: 4,
      type: "endEnforcement",
      profileId: "profile_one",
      extra: true,
    },
    {
      version: 4,
      type: "beginEnforcement",
      profileId: "bad profile",
      targets: [],
    },
    {
      version: 4,
      type: "beginEnforcement",
      profileId: "profile_one",
      targets: [{
        type: "tab",
        tabId: 1,
        windowId: 1,
        navigationScope: {
          type: "currentWebsite",
          initialUrl: "chrome://settings",
        },
      }],
    },
    {
      version: 4,
      type: "beginEnforcement",
      profileId: "profile_one",
      targets: [
        {
          type: "tab",
          tabId: 1,
          windowId: 1,
          navigationScope: {
            type: "currentWebsite",
            initialUrl: "https://one.example",
          },
        },
        {
          type: "tab",
          tabId: 1,
          windowId: 2,
          navigationScope: {
            type: "exactPage",
            initialUrl: "https://two.example/page",
          },
        },
      ],
    },
    {
      version: 4,
      type: "beginEnforcement",
      profileId: "profile_one",
      targets: [
        { type: "window", windowId: 9 },
        {
          type: "tab",
          tabId: 1,
          windowId: 9,
          navigationScope: {
            type: "currentWebsite",
            initialUrl: "https://one.example",
          },
        },
      ],
    },
    { version: 4, type: "unknown", profileId: "profile_one" },
  ]) {
    assert.throws(() => parseNativeMessage(value));
  }
});
