import assert from "node:assert/strict";
import test from "node:test";
import {
  completeCurrentWebsiteNavigation,
  canStartCurrentWebsiteEnforcement,
  createCurrentWebsiteScope,
  createStartingCurrentWebsiteScope,
  decideCommittedNavigation,
  decideOpenedTab,
  isWithinCurrentWebsite,
} from "../dist/navigation-policy.js";

test("Current Website accepts only HTTP and HTTPS on the exact hostname", () => {
  const scope = createCurrentWebsiteScope(
    "https://Work.Example./projects/one?view=board#today",
  );

  assert.equal(scope.hostname, "work.example");
  for (const candidate of [
    "https://work.example/another/path?query=yes",
    "http://work.example:8080/temporary",
    "https://work.example/#fragment",
  ]) {
    assert.equal(isWithinCurrentWebsite(scope, candidate), true, candidate);
  }
  for (const candidate of [
    "https://docs.work.example/project",
    "https://work.example.attacker.test/project",
    "https://other.example/project",
    "ftp://work.example/project",
    "chrome://settings",
    "not a url",
  ]) {
    assert.equal(isWithinCurrentWebsite(scope, candidate), false, candidate);
  }
});

test("start promotes only a fully completed live page", () => {
  const loading = createStartingCurrentWebsiteScope({
    initialUrl: "https://work.example/stable",
    liveUrl: "https://work.example/loading",
    liveDocumentIsComplete: false,
  });
  const complete = createStartingCurrentWebsiteScope({
    initialUrl: "https://work.example/stable",
    liveUrl: "https://work.example/complete",
    liveDocumentIsComplete: true,
  });
  const completedCrossHost = createStartingCurrentWebsiteScope({
    initialUrl: "https://work.example/stable",
    liveUrl: "https://video.example/watch",
    liveDocumentIsComplete: true,
  });

  assert.equal(loading.lastAllowedUrl, "https://work.example/stable");
  assert.equal(complete.lastAllowedUrl, "https://work.example/complete");
  assert.equal(
    completedCrossHost.lastAllowedUrl,
    "https://work.example/stable",
  );
  assert.equal(
    canStartCurrentWebsiteEnforcement({
      initialUrl: "https://work.example/stable",
      liveUrl: "https://work.example/loading",
      liveDocumentIsComplete: false,
    }),
    false,
  );
  assert.equal(
    canStartCurrentWebsiteEnforcement({
      initialUrl: "https://work.example/stable",
      liveUrl: "https://video.example/loading",
      liveDocumentIsComplete: false,
    }),
    true,
  );
});

test("a committed cross-host navigation restores the Last Allowed Page", () => {
  const scope = createCurrentWebsiteScope(
    "https://work.example/projects/one?view=board",
  );

  assert.deepEqual(
    decideCommittedNavigation({
      scope,
      candidateUrl: "https://video.example/watch?v=1",
      documentId: "document-cross-host",
      now: 10_000,
      lastFeedbackAt: null,
      feedbackIntervalMs: 2_000,
    }),
    {
      kind: "restore",
      restoreUrl: "https://work.example/projects/one?view=board",
      nextScope: scope,
      shouldNotify: true,
      nextFeedbackAt: 10_000,
    },
  );
});

test("Last Allowed Page advances only after the matching document completes", () => {
  const original = createCurrentWebsiteScope(
    "https://work.example/projects/one",
  );
  const committed = decideCommittedNavigation({
    scope: original,
    candidateUrl: "https://work.example/projects/two?view=list",
    documentId: "document-two",
    now: 10_000,
    lastFeedbackAt: null,
    feedbackIntervalMs: 2_000,
  });
  assert.equal(committed.kind, "allow");

  const stale = completeCurrentWebsiteNavigation(
    committed.nextScope,
    "document-one",
    "https://work.example/projects/one",
  );
  assert.deepEqual(stale, committed.nextScope);

  const completed = completeCurrentWebsiteNavigation(
    committed.nextScope,
    "document-two",
    "https://work.example/projects/two?view=list",
  );
  assert.equal(
    completed.lastAllowedUrl,
    "https://work.example/projects/two?view=list",
  );
  assert.equal(completed.pendingNavigation, undefined);
});

test("a redirect that commits outside Current Website cannot replace the stable page", () => {
  const original = createCurrentWebsiteScope(
    "https://work.example/projects/one",
  );
  const redirecting = decideCommittedNavigation({
    scope: original,
    candidateUrl: "https://work.example/leaving",
    documentId: "redirected-document",
    now: 10_000,
    lastFeedbackAt: null,
    feedbackIntervalMs: 2_000,
  });
  assert.equal(redirecting.kind, "allow");

  const finalCommit = decideCommittedNavigation({
    scope: redirecting.nextScope,
    candidateUrl: "https://video.example/watch",
    documentId: "redirected-document",
    now: 10_100,
    lastFeedbackAt: null,
    feedbackIntervalMs: 2_000,
  });
  assert.equal(finalCommit.kind, "restore");
  assert.equal(
    finalCommit.restoreUrl,
    "https://work.example/projects/one",
  );
  assert.equal(finalCommit.nextScope.pendingNavigation, undefined);
});

test("same-scope links transfer into the original tab and cross-scope links close", () => {
  const scope = createCurrentWebsiteScope("https://work.example/start");

  assert.deepEqual(
    decideOpenedTab({
      scope,
      candidateUrl: "https://work.example/continued?step=2",
      hasGraceExpired: false,
      now: 10_000,
      lastFeedbackAt: null,
      feedbackIntervalMs: 2_000,
    }),
    {
      kind: "transfer",
      destinationUrl: "https://work.example/continued?step=2",
    },
  );
  assert.deepEqual(
    decideOpenedTab({
      scope,
      candidateUrl: "https://video.example/watch",
      hasGraceExpired: false,
      now: 10_000,
      lastFeedbackAt: null,
      feedbackIntervalMs: 2_000,
    }),
    {
      kind: "close",
      shouldNotify: true,
      nextFeedbackAt: 10_000,
    },
  );
  assert.deepEqual(
    decideOpenedTab({
      scope,
      candidateUrl: "about:blank",
      hasGraceExpired: false,
      now: 10_000,
      lastFeedbackAt: null,
      feedbackIntervalMs: 2_000,
    }),
    { kind: "wait" },
  );
});

test("rapid blocked navigations keep restoring but rate-limit their notice", () => {
  const scope = createCurrentWebsiteScope("https://work.example/start");
  const first = decideCommittedNavigation({
    scope,
    candidateUrl: "https://video.example/one",
    documentId: "one",
    now: 10_000,
    lastFeedbackAt: null,
    feedbackIntervalMs: 2_000,
  });
  const second = decideCommittedNavigation({
    scope,
    candidateUrl: "https://social.example/two",
    documentId: "two",
    now: 10_500,
    lastFeedbackAt: first.nextFeedbackAt,
    feedbackIntervalMs: 2_000,
  });

  assert.equal(first.kind, "restore");
  assert.equal(first.shouldNotify, true);
  assert.equal(second.kind, "restore");
  assert.equal(second.restoreUrl, "https://work.example/start");
  assert.equal(second.shouldNotify, false);
  assert.equal(second.nextFeedbackAt, 10_000);
});
