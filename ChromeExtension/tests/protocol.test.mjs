import assert from "node:assert/strict";
import test from "node:test";
import {
  EXTENSION_ID,
  PROTOCOL_VERSION,
  fitTabsToNativeMessageBudget,
  makeHello,
  makeTabActivationStarted,
  parseNativeMessage,
} from "../dist/protocol.js";

test("creates the fixed identity handshake", () => {
  assert.deepEqual(makeHello("profile_one"), {
    version: PROTOCOL_VERSION,
    type: "hello",
    extensionId: EXTENSION_ID,
    profileId: "profile_one",
  });
});

test("confirms Tab Activation Enforcement with exact target identity", () => {
  assert.deepEqual(makeTabActivationStarted("profile_one", 41, 9), {
    version: 1,
    type: "tabActivationStarted",
    profileId: "profile_one",
    tabId: 41,
    windowId: 9,
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
      version: 1,
      type: "tabsSnapshot",
      profileId: "profile_one",
      tabs,
    })).length <= 400,
  );
});

test("accepts a valid begin-enforcement command", () => {
  assert.deepEqual(
    parseNativeMessage({
      version: 1,
      type: "beginEnforcement",
      profileId: "profile_one",
      tabId: 41,
      windowId: 9,
    }),
    {
      version: 1,
      type: "beginEnforcement",
      profileId: "profile_one",
      tabId: 41,
      windowId: 9,
    },
  );
});

test("rejects malformed, extra, and unsupported commands", () => {
  for (const value of [
    { version: 2, type: "endEnforcement", profileId: "profile_one" },
    {
      version: 1,
      type: "endEnforcement",
      profileId: "profile_one",
      extra: true,
    },
    { version: 1, type: "beginEnforcement", profileId: "bad profile", tabId: 1, windowId: 1 },
    { version: 1, type: "unknown", profileId: "profile_one" },
  ]) {
    assert.throws(() => parseNativeMessage(value));
  }
});
