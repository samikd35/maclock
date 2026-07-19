import assert from "node:assert/strict";
import test from "node:test";
import {
  closeTabIfPresent,
  isMissingChromeTabError,
} from "../dist/chrome-tab-effects.js";

test("closing an already-disappeared candidate tab is idempotent", async () => {
  await closeTabIfPresent(91, {
    async removeTab() {
      throw new Error("No tab with id: 91");
    },
    async tabExists() {
      return false;
    },
  });
});

test("a real candidate-tab close failure remains visible", async () => {
  const failure = new Error("Tabs API unavailable");

  await assert.rejects(
    closeTabIfPresent(91, {
      async removeTab() {
        throw failure;
      },
      async tabExists() {
        return true;
      },
    }),
    failure,
  );
});

test("only Chrome's missing-tab errors are classified as disappearance", () => {
  assert.equal(
    isMissingChromeTabError(new Error("No tab with id: 91.")),
    true,
  );
  assert.equal(
    isMissingChromeTabError(new Error("Extension context invalidated.")),
    false,
  );
});
