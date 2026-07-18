import assert from "node:assert/strict";
import test from "node:test";
import { NativeCommandQueue } from "../dist/native-command-queue.js";
import {
  clearTabActivationEnforcement,
  loadTabActivationEnforcement,
  saveTabActivationEnforcement,
} from "../dist/tab-activation-store.js";
import { collectTabSnapshots } from "../dist/tab-snapshot.js";

test("serializes an end command behind an in-flight begin command", async () => {
  let releaseBegin;
  const beginCanFinish = new Promise((resolve) => {
    releaseBegin = resolve;
  });
  let enforced = false;
  const queue = new NativeCommandQueue(async () => {
    assert.fail("command failed");
  });

  queue.enqueue(async () => {
    await beginCanFinish;
    enforced = true;
  });
  queue.enqueue(async () => {
    enforced = false;
  });
  releaseBegin();
  await queue.drain();

  assert.equal(enforced, false);
});

test("runs local fail-open cleanup when a native command fails", async () => {
  let releaseBegin;
  const beginCanFinish = new Promise((resolve) => {
    releaseBegin = resolve;
  });
  let enforced = false;
  let cleanedUp = false;
  const queue = new NativeCommandQueue(async () => {
    enforced = false;
    cleanedUp = true;
  });

  queue.enqueue(async () => {
    await beginCanFinish;
    enforced = true;
  });
  queue.enqueue(async () => {
    throw new Error("malformed native command");
  });
  releaseBegin();
  await queue.drain();

  assert.equal(enforced, false);
  assert.equal(cleanedUp, true);
});

test("tab activation storage is isolated behind its port", async () => {
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
  const enforcement = { profileId: "profile_one", tabId: 41, windowId: 9 };

  await saveTabActivationEnforcement(enforcement, store);
  assert.deepEqual(await loadTabActivationEnforcement(store), enforcement);
  await clearTabActivationEnforcement(store);
  assert.equal(await loadTabActivationEnforcement(store), null);
});

test("tab snapshots use injected Chrome and favicon ports", async () => {
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const snapshots = await collectTabSnapshots("profile_one", {
    async queryTabs() {
      return [{
        id: 41,
        windowId: 9,
        title: "Project plan",
        url: "https://work.example/project",
        active: true,
        incognito: false,
      }];
    },
    async loadFavicon(pageURL) {
      assert.equal(pageURL, "https://work.example/project");
      return { ok: true, bytes: png };
    },
  });

  assert.equal(snapshots.length, 1);
  assert.equal(snapshots[0].tabId, 41);
  assert.match(snapshots[0].faviconDataUrl, /^data:image\/png;base64,/);
});
