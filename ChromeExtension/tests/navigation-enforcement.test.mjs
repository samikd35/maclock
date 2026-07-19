import assert from "node:assert/strict";
import test from "node:test";
import { CurrentWebsiteNavigationEnforcer } from "../dist/navigation-enforcement.js";
import { createCurrentWebsiteScope } from "../dist/navigation-policy.js";
import { loadTabActivationEnforcement } from "../dist/tab-activation-store.js";

test("cross-host commits restore the selected tab and publish bounded feedback", async () => {
  const harness = makeHarness();
  await harness.enforcer.start(makeEnforcement());

  await harness.enforcer.handle({
    type: "committed",
    tabId: 41,
    frameId: 0,
    documentId: "cross-host",
    url: "https://video.example/watch?v=1",
  });
  await harness.enforcer.handle({
    type: "committed",
    tabId: 41,
    frameId: 0,
    documentId: "rapid-cross-host",
    url: "https://social.example/feed",
  });

  assert.deepEqual(harness.navigations, [
    [41, "https://work.example/project"],
    [41, "https://work.example/project"],
  ]);
  assert.deepEqual(harness.blockedNotices, [["profile_one", 41]]);
  assert.equal(
    (await loadTabActivationEnforcement(harness.store)).navigationScope
      .lastAllowedUrl,
    "https://work.example/project",
  );
});

test("a tab URL observation blocks special schemes even without webNavigation", async () => {
  const harness = makeHarness();
  await harness.enforcer.start(makeEnforcement());

  await harness.enforcer.handle({
    type: "urlChanged",
    tabId: 41,
    url: "chrome://settings/",
  });

  assert.deepEqual(harness.navigations, [
    [41, "https://work.example/project"],
  ]);
  assert.deepEqual(harness.blockedNotices, [["profile_one", 41]]);
});

test("tab URL observations do not promote an incomplete same-site page", async () => {
  const harness = makeHarness();
  await harness.enforcer.start(makeEnforcement());

  await harness.enforcer.handle({
    type: "urlChanged",
    tabId: 41,
    url: "https://work.example/loading",
  });

  assert.deepEqual(harness.navigations, []);
  assert.equal(
    (await loadTabActivationEnforcement(harness.store)).navigationScope
      .lastAllowedUrl,
    "https://work.example/project",
  );
});

test("a matching completed document becomes the Last Allowed Page", async () => {
  const harness = makeHarness();
  await harness.enforcer.start(makeEnforcement());

  await harness.enforcer.handle({
    type: "committed",
    tabId: 41,
    frameId: 0,
    documentId: "same-host",
    url: "http://work.example:8080/next?step=2",
  });
  await harness.enforcer.handle({
    type: "completed",
    tabId: 41,
    frameId: 0,
    documentId: "same-host",
    url: "http://work.example:8080/next?step=2",
  });

  const stored = await loadTabActivationEnforcement(harness.store);
  assert.equal(
    stored.navigationScope.lastAllowedUrl,
    "http://work.example:8080/next?step=2",
  );
  assert.deepEqual(harness.navigations, []);
  assert.deepEqual(harness.closedTabs, []);
});

test("subframe navigation never changes or restores the top-level tab", async () => {
  const harness = makeHarness();
  await harness.enforcer.start(makeEnforcement());

  await harness.enforcer.handle({
    type: "committed",
    tabId: 41,
    frameId: 7,
    documentId: "embedded-video",
    url: "https://video.example/embed",
  });

  assert.deepEqual(harness.navigations, []);
  assert.equal(
    (await loadTabActivationEnforcement(harness.store)).navigationScope
      .lastAllowedUrl,
    "https://work.example/project",
  );
});

test("opened links transfer or close without expanding the immutable tab", async () => {
  const harness = makeHarness();
  await harness.enforcer.start(makeEnforcement());

  await harness.enforcer.handle({
    type: "openedTab",
    tabId: 90,
    openerTabId: 41,
    pendingUrl: "https://work.example/continued",
    url: "about:blank",
    isComplete: false,
  });
  await harness.enforcer.handle({
    type: "openedTab",
    tabId: 91,
    openerTabId: 41,
    pendingUrl: "https://video.example/watch",
    url: "about:blank",
    isComplete: false,
  });

  assert.deepEqual(harness.navigations, [
    [41, "https://work.example/continued"],
  ]);
  assert.deepEqual(harness.closedTabs, [90, 91]);
  assert.equal(
    (await loadTabActivationEnforcement(harness.store)).tabId,
    41,
  );
});

test("stop remains final when a blocked navigation effect is in flight", async () => {
  let releaseNavigation;
  const navigationCanFinish = new Promise((resolve) => {
    releaseNavigation = resolve;
  });
  const harness = makeHarness({ navigationCanFinish });
  await harness.enforcer.start(makeEnforcement());

  const blocked = harness.enforcer.handle({
    type: "committed",
    tabId: 41,
    frameId: 0,
    documentId: "cross-host",
    url: "https://video.example/watch",
  });
  const stopped = harness.enforcer.stop();
  releaseNavigation();
  await Promise.all([blocked, stopped]);

  assert.equal(await loadTabActivationEnforcement(harness.store), null);
});

function makeEnforcement() {
  return {
    profileId: "profile_one",
    tabId: 41,
    windowId: 9,
    navigationScope: createCurrentWebsiteScope(
      "https://work.example/project",
    ),
  };
}

function makeHarness(options = {}) {
  const values = {};
  const store = {
    async get() {
      return { ...values };
    },
    async set(items) {
      Object.assign(values, items);
    },
    async remove(key) {
      delete values[key];
    },
  };
  const navigations = [];
  const closedTabs = [];
  const blockedNotices = [];
  let currentTime = 10_000;
  const enforcer = new CurrentWebsiteNavigationEnforcer({
    store,
    platform: {
      async navigateTab(tabId, url) {
        if (options.navigationCanFinish !== undefined) {
          await options.navigationCanFinish;
        }
        navigations.push([tabId, url]);
      },
      async closeTab(tabId) {
        closedTabs.push(tabId);
      },
      blockedNavigation(profileId, tabId) {
        blockedNotices.push([profileId, tabId]);
      },
    },
    now: () => {
      const result = currentTime;
      currentTime += 500;
      return result;
    },
    feedbackIntervalMs: 2_000,
  });
  return {
    enforcer,
    store,
    navigations,
    closedTabs,
    blockedNotices,
  };
}
