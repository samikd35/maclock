import assert from "node:assert/strict";
import test from "node:test";
import { ChromeTabEnforcementCoordinator } from "../dist/navigation-enforcement.js";
import {
  createCurrentWebsiteScope,
  createExactPageScope,
} from "../dist/navigation-policy.js";
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
    (await storedTarget(harness.store, 41)).navigationScope.lastAllowedUrl,
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
    (await storedTarget(harness.store, 41)).navigationScope.lastAllowedUrl,
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
    stored.availableTargets[0].navigationScope.lastAllowedUrl,
    "http://work.example:8080/next?step=2",
  );
  assert.deepEqual(harness.navigations, []);
  assert.deepEqual(harness.closedTabs, []);
});

test("history changes before completion remain pending", async () => {
  const harness = makeHarness();
  await harness.enforcer.start(makeEnforcement());

  await harness.enforcer.handle({
    type: "committed",
    tabId: 41,
    frameId: 0,
    documentId: "loading-document",
    url: "https://work.example/loading",
  });
  await harness.enforcer.handle({
    type: "historyUpdated",
    tabId: 41,
    frameId: 0,
    documentId: "loading-document",
    url: "https://work.example/loading?state=changed",
  });

  const pending = await loadTabActivationEnforcement(harness.store);
  assert.equal(
    pending.availableTargets[0].navigationScope.lastAllowedUrl,
    "https://work.example/project",
  );
  assert.deepEqual(pending.availableTargets[0].navigationScope.pendingNavigation, {
    documentId: "loading-document",
    url: "https://work.example/loading?state=changed",
  });

  await harness.enforcer.handle({
    type: "completed",
    tabId: 41,
    frameId: 0,
    documentId: "loading-document",
    url: "https://work.example/loading?state=changed",
  });
  assert.equal(
    (await storedTarget(harness.store, 41)).navigationScope.lastAllowedUrl,
    "https://work.example/loading?state=changed",
  );
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
    (await storedTarget(harness.store, 41)).navigationScope.lastAllowedUrl,
    "https://work.example/project",
  );
});

test("opened links transfer or close without expanding the immutable tab", async () => {
  const harness = makeHarness();
  await harness.enforcer.start(makeEnforcement());

  await harness.enforcer.handle({
    type: "openedTab",
    tabId: 90,
    sourceTabId: 41,
    pendingUrl: "https://work.example/continued",
    url: "about:blank",
  });
  await harness.enforcer.handle({
    type: "openedTab",
    tabId: 91,
    sourceTabId: 41,
    pendingUrl: "https://video.example/watch",
    url: "about:blank",
  });

  assert.deepEqual(harness.navigations, [
    [41, "https://work.example/continued"],
  ]);
  assert.deepEqual(harness.closedTabs, [90, 91]);
  assert.equal(
    (await loadTabActivationEnforcement(harness.store)).availableTargets[0].tabId,
    41,
  );
});

test("a navigation target source works without a retained tab opener", async () => {
  const harness = makeHarness();
  await harness.enforcer.start(makeEnforcement());

  await harness.enforcer.handle({
    type: "openedTab",
    tabId: 92,
    sourceTabId: 41,
    pendingUrl: "https://work.example/from-noopener",
    url: undefined,
  });

  assert.deepEqual(harness.navigations, [
    [41, "https://work.example/from-noopener"],
  ]);
  assert.deepEqual(harness.closedTabs, [92]);
});

test("a completed blank child waits for its first real destination", async () => {
  const harness = makeHarness();
  await harness.enforcer.start(makeEnforcement());

  await harness.enforcer.handle({
    type: "openedTab",
    tabId: 93,
    sourceTabId: 41,
    pendingUrl: "about:blank",
    url: "about:blank",
  });
  assert.deepEqual(harness.closedTabs, []);

  await harness.enforcer.handle({
    type: "openedTab",
    tabId: 93,
    sourceTabId: undefined,
    pendingUrl: undefined,
    url: "https://work.example/resolved",
  });

  assert.deepEqual(harness.navigations, [
    [41, "https://work.example/resolved"],
  ]);
  assert.deepEqual(harness.closedTabs, [93]);
});

test("an unresolved blank child closes when its grace period expires", async () => {
  const harness = makeHarness();
  await harness.enforcer.start(makeEnforcement());

  await harness.enforcer.handle({
    type: "openedTab",
    tabId: 94,
    sourceTabId: 41,
    pendingUrl: "about:blank",
    url: "about:blank",
  });
  await harness.enforcer.handle({
    type: "openedTabGraceExpired",
    tabId: 94,
  });

  assert.deepEqual(harness.closedTabs, [94]);
  assert.deepEqual(harness.blockedNotices, [["profile_one", 41]]);
});

test("a completed blank child closes after resolving cross-scope", async () => {
  const harness = makeHarness();
  await harness.enforcer.start(makeEnforcement());

  await harness.enforcer.handle({
    type: "openedTab",
    tabId: 95,
    sourceTabId: 41,
    pendingUrl: "about:blank",
    url: "about:blank",
  });
  await harness.enforcer.handle({
    type: "openedTab",
    tabId: 95,
    sourceTabId: undefined,
    pendingUrl: undefined,
    url: "https://video.example/resolved",
  });

  assert.deepEqual(harness.navigations, []);
  assert.deepEqual(harness.closedTabs, [95]);
  assert.deepEqual(harness.blockedNotices, [["profile_one", 41]]);
});

test("mixed scopes remain independent across tabs and Chrome windows", async () => {
  const harness = makeHarness();
  const enforcement = makeEnforcement();
  enforcement.availableTargets.push({
    tabId: 42,
    windowId: 10,
    navigationScope: createExactPageScope(
      "https://docs.example/reference?v=1#overview",
    ),
  });
  await harness.enforcer.start(enforcement);

  await harness.enforcer.handle({
    type: "committed",
    tabId: 42,
    frameId: 0,
    documentId: "fragment-reload",
    url: "https://docs.example/reference?v=1#details",
  });
  await harness.enforcer.handle({
    type: "completed",
    tabId: 42,
    frameId: 0,
    documentId: "fragment-reload",
    url: "https://docs.example/reference?v=1#details",
  });
  await harness.enforcer.handle({
    type: "committed",
    tabId: 42,
    frameId: 0,
    documentId: "changed-query",
    url: "https://docs.example/reference?v=2",
  });

  assert.deepEqual(harness.navigations, [
    [42, "https://docs.example/reference?v=1#details"],
  ]);
  assert.equal(
    (await storedTarget(harness.store, 42)).navigationScope.lastAllowedUrl,
    "https://docs.example/reference?v=1#details",
  );
  assert.equal(
    (await storedTarget(harness.store, 41)).navigationScope.lastAllowedUrl,
    "https://work.example/project",
  );
});

test("activation, attachment, and closure update only runtime availability", async () => {
  const harness = makeHarness();
  const enforcement = makeEnforcement();
  enforcement.availableTargets.push({
    tabId: 42,
    windowId: 10,
    navigationScope: createExactPageScope(
      "https://docs.example/reference?v=1",
    ),
  });
  await harness.enforcer.start(enforcement);

  await harness.enforcer.handle({ type: "activated", tabId: 42 });
  await harness.enforcer.handle({
    type: "attached",
    tabId: 42,
    windowId: 12,
  });
  assert.equal(
    (await storedTarget(harness.store, 42)).windowId,
    12,
  );
  await harness.enforcer.handle({ type: "removed", tabId: 42 });
  await harness.enforcer.handle({ type: "activated", tabId: 99 });

  const stored = await loadTabActivationEnforcement(harness.store);
  assert.deepEqual(stored.availableTargets.map((target) => target.tabId), [41]);
  assert.equal(stored.lastActivatedAvailableTabId, 41);
  assert.deepEqual(harness.activations, [41]);
  assert.deepEqual(harness.closedTargetNotices, [["profile_one", 42]]);
  assert.deepEqual(
    harness.activationNotices,
    [["profile_one", 99, 41]],
  );
});

test("a duplicated or attached unapproved identity never joins the allowlist", async () => {
  const harness = makeHarness();
  await harness.enforcer.start(makeEnforcement());

  await harness.enforcer.handle({
    type: "openedTab",
    tabId: 90,
    sourceTabId: undefined,
    pendingUrl: "https://work.example/project",
    url: "https://work.example/project",
  });
  await harness.enforcer.handle({
    type: "attached",
    tabId: 90,
    windowId: 9,
  });
  await harness.enforcer.handle({ type: "activated", tabId: 90 });

  assert.deepEqual(
    (await loadTabActivationEnforcement(harness.store)).availableTargets.map(
      (target) => target.tabId,
    ),
    [41],
  );
  assert.deepEqual(harness.activations, [41]);
  assert.deepEqual(harness.navigations, []);
});

test("a replaced selected identity is removed before its replacement activates", async () => {
  const harness = makeHarness();
  const enforcement = makeEnforcement();
  enforcement.availableTargets.push({
    tabId: 42,
    windowId: 10,
    navigationScope: createExactPageScope(
      "https://docs.example/reference?v=1",
    ),
  });
  await harness.enforcer.start(enforcement);

  await harness.enforcer.handle({
    type: "replaced",
    addedTabId: 142,
    removedTabId: 42,
  });

  assert.deepEqual(
    (await loadTabActivationEnforcement(harness.store)).availableTargets.map(
      (target) => target.tabId,
    ),
    [41],
  );
  assert.deepEqual(harness.activations, [41]);
  assert.deepEqual(harness.closedTargetNotices, [["profile_one", 42]]);
});

test("concurrent navigation and activation effects stay serialized", async () => {
  let releaseNavigation;
  const navigationCanFinish = new Promise((resolve) => {
    releaseNavigation = resolve;
  });
  const harness = makeHarness({ navigationCanFinish });
  const enforcement = makeEnforcement();
  enforcement.availableTargets.push({
    tabId: 42,
    windowId: 10,
    navigationScope: createExactPageScope(
      "https://docs.example/reference?v=1",
    ),
  });
  await harness.enforcer.start(enforcement);

  const blockedNavigation = harness.enforcer.handle({
    type: "committed",
    tabId: 41,
    frameId: 0,
    documentId: "blocked",
    url: "https://video.example/watch",
  });
  const blockedActivation = harness.enforcer.handle({
    type: "activated",
    tabId: 99,
  });
  releaseNavigation();
  await Promise.all([blockedNavigation, blockedActivation]);

  assert.deepEqual(harness.navigations, [
    [41, "https://work.example/project"],
  ]);
  assert.deepEqual(harness.activations, [41]);
});

test("a target that disappears before a restore falls back without failing open", async () => {
  const harness = makeHarness({ unavailableActivationTabIds: [42] });
  const enforcement = makeEnforcement();
  enforcement.availableTargets.push({
    tabId: 42,
    windowId: 10,
    navigationScope: createExactPageScope(
      "https://docs.example/reference?v=1",
    ),
  });
  enforcement.lastActivatedAvailableTabId = 42;
  await harness.enforcer.start(enforcement);

  await harness.enforcer.handle({ type: "activated", tabId: 99 });

  assert.deepEqual(harness.activations, [42, 41]);
  assert.deepEqual(
    (await loadTabActivationEnforcement(harness.store)).availableTargets.map(
      (target) => target.tabId,
    ),
    [41],
  );
  assert.deepEqual(harness.closedTargetNotices, [["profile_one", 42]]);
  assert.deepEqual(harness.activationNotices, [["profile_one", 99, 41]]);
});

test("a target that closes during navigation restore is removed cleanly", async () => {
  const harness = makeHarness({ unavailableNavigationTabIds: [42] });
  const enforcement = makeEnforcement();
  enforcement.availableTargets.push({
    tabId: 42,
    windowId: 10,
    navigationScope: createExactPageScope(
      "https://docs.example/reference?v=1",
    ),
  });
  await harness.enforcer.start(enforcement);

  await harness.enforcer.handle({
    type: "committed",
    tabId: 42,
    frameId: 0,
    documentId: "closed-during-restore",
    url: "https://video.example/watch",
  });

  assert.deepEqual(harness.navigations, [
    [42, "https://docs.example/reference?v=1"],
  ]);
  assert.deepEqual(
    (await loadTabActivationEnforcement(harness.store)).availableTargets.map(
      (target) => target.tabId,
    ),
    [41],
  );
  assert.deepEqual(harness.closedTargetNotices, [["profile_one", 42]]);
  assert.deepEqual(harness.blockedNotices, []);
});

test("atomic start confirmation precedes a closure event raised by start effects", async () => {
  const lifecycleEvents = [];
  const harness = makeHarness({ lifecycleEvents });
  let removal;

  await harness.enforcer.start(makeEnforcement(), async () => {
    removal = harness.enforcer.handle({ type: "removed", tabId: 41 });
    lifecycleEvents.push("confirmed");
  });
  await removal;

  assert.deepEqual(lifecycleEvents, ["confirmed", "closed:41"]);
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
    availableTargets: [
      {
        tabId: 41,
        windowId: 9,
        navigationScope: createCurrentWebsiteScope(
          "https://work.example/project",
        ),
      },
    ],
    lastActivatedAvailableTabId: 41,
  };
}

async function storedTarget(store, tabId) {
  const enforcement = await loadTabActivationEnforcement(store);
  return enforcement.availableTargets.find((target) => target.tabId === tabId);
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
  const activations = [];
  const activationNotices = [];
  const closedTargetNotices = [];
  let currentTime = 10_000;
  const enforcer = new ChromeTabEnforcementCoordinator({
    store,
    platform: {
      async navigateTab(tabId, url) {
        if (options.navigationCanFinish !== undefined) {
          await options.navigationCanFinish;
        }
        navigations.push([tabId, url]);
        return !(options.unavailableNavigationTabIds ?? []).includes(tabId);
      },
      async closeTab(tabId) {
        closedTabs.push(tabId);
      },
      async activateTab(tabId) {
        activations.push(tabId);
        return !(options.unavailableActivationTabIds ?? []).includes(tabId);
      },
      blockedNavigation(profileId, tabId) {
        blockedNotices.push([profileId, tabId]);
      },
      blockedTabActivation(profileId, attemptedTabId, availableTabId) {
        activationNotices.push([profileId, attemptedTabId, availableTabId]);
      },
      tabTargetClosed(profileId, tabId) {
        closedTargetNotices.push([profileId, tabId]);
        options.lifecycleEvents?.push(`closed:${tabId}`);
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
    activations,
    activationNotices,
    closedTargetNotices,
  };
}
