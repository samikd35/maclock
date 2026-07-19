export type PendingAllowedNavigation = {
  documentId: string;
  url: string;
};

export type CurrentWebsiteScope = {
  type: "currentWebsite";
  hostname: string;
  lastAllowedUrl: string;
  pendingNavigation?: PendingAllowedNavigation;
};

type FeedbackInput = {
  now: number;
  lastFeedbackAt: number | null;
  feedbackIntervalMs: number;
};

export type CommittedNavigationInput = FeedbackInput & {
  scope: CurrentWebsiteScope;
  candidateUrl: string;
  documentId: string;
};

export type CommittedNavigationDecision =
  | {
      kind: "allow";
      nextScope: CurrentWebsiteScope;
      shouldNotify: false;
      nextFeedbackAt: number | null;
    }
  | {
      kind: "restore";
      restoreUrl: string;
      nextScope: CurrentWebsiteScope;
      shouldNotify: boolean;
      nextFeedbackAt: number | null;
    };

export type OpenedTabInput = FeedbackInput & {
  scope: CurrentWebsiteScope;
  candidateUrl: string | undefined;
  isComplete: boolean;
};

export type OpenedTabDecision =
  | { kind: "wait" }
  | { kind: "transfer"; destinationUrl: string }
  | {
      kind: "close";
      shouldNotify: boolean;
      nextFeedbackAt: number | null;
    };

export function createCurrentWebsiteScope(
  initialUrl: string,
): CurrentWebsiteScope {
  const parsed = requireWebURL(initialUrl);
  return {
    type: "currentWebsite",
    hostname: normalizeHostname(parsed.hostname),
    lastAllowedUrl: parsed.href,
  };
}

export function isWithinCurrentWebsite(
  scope: CurrentWebsiteScope,
  candidateUrl: string,
): boolean {
  const parsed = parseWebURL(candidateUrl);
  return (
    parsed !== null &&
    normalizeHostname(parsed.hostname) === scope.hostname
  );
}

export function isValidCurrentWebsiteScope(
  value: unknown,
): value is CurrentWebsiteScope {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }
  const candidate = value as Record<string, unknown>;
  const allowedKeys = new Set([
    "type",
    "hostname",
    "lastAllowedUrl",
    "pendingNavigation",
  ]);
  if (
    Object.keys(candidate).some((key) => !allowedKeys.has(key)) ||
    candidate.type !== "currentWebsite" ||
    typeof candidate.hostname !== "string" ||
    typeof candidate.lastAllowedUrl !== "string"
  ) {
    return false;
  }
  const stableURL = parseWebURL(candidate.lastAllowedUrl);
  if (
    stableURL === null ||
    stableURL.href !== candidate.lastAllowedUrl ||
    normalizeHostname(stableURL.hostname) !== candidate.hostname
  ) {
    return false;
  }
  if (candidate.pendingNavigation === undefined) {
    return true;
  }
  if (
    typeof candidate.pendingNavigation !== "object" ||
    candidate.pendingNavigation === null ||
    Array.isArray(candidate.pendingNavigation)
  ) {
    return false;
  }
  const pending = candidate.pendingNavigation as Record<string, unknown>;
  if (
    Object.keys(pending).sort().join(",") !== "documentId,url" ||
    typeof pending.documentId !== "string" ||
    pending.documentId.length === 0 ||
    new TextEncoder().encode(pending.documentId).length > 128 ||
    typeof pending.url !== "string"
  ) {
    return false;
  }
  const pendingURL = parseWebURL(pending.url);
  return (
    pendingURL !== null &&
    pendingURL.href === pending.url &&
    normalizeHostname(pendingURL.hostname) === candidate.hostname
  );
}

export function decideCommittedNavigation(
  input: CommittedNavigationInput,
): CommittedNavigationDecision {
  const candidate = parseWebURL(input.candidateUrl);
  if (
    candidate !== null &&
    normalizeHostname(candidate.hostname) === input.scope.hostname
  ) {
    return {
      kind: "allow",
      nextScope: {
        ...input.scope,
        pendingNavigation: {
          documentId: input.documentId,
          url: candidate.href,
        },
      },
      shouldNotify: false,
      nextFeedbackAt: input.lastFeedbackAt,
    };
  }

  const feedback = decideFeedback(input);
  return {
    kind: "restore",
    restoreUrl: input.scope.lastAllowedUrl,
    nextScope: withoutPendingNavigation(input.scope),
    shouldNotify: feedback.shouldNotify,
    nextFeedbackAt: feedback.nextFeedbackAt,
  };
}

export function completeCurrentWebsiteNavigation(
  scope: CurrentWebsiteScope,
  documentId: string,
  completedUrl: string,
): CurrentWebsiteScope {
  const pending = scope.pendingNavigation;
  const completed = parseWebURL(completedUrl);
  if (
    pending === undefined ||
    pending.documentId !== documentId ||
    completed === null ||
    completed.href !== pending.url ||
    normalizeHostname(completed.hostname) !== scope.hostname
  ) {
    return scope;
  }
  return {
    ...withoutPendingNavigation(scope),
    lastAllowedUrl: completed.href,
  };
}

export function decideOpenedTab(input: OpenedTabInput): OpenedTabDecision {
  const candidate = input.candidateUrl;
  if (
    !input.isComplete &&
    (candidate === undefined || candidate === "" || candidate === "about:blank")
  ) {
    return { kind: "wait" };
  }
  if (
    candidate !== undefined &&
    isWithinCurrentWebsite(input.scope, candidate)
  ) {
    return {
      kind: "transfer",
      destinationUrl: requireWebURL(candidate).href,
    };
  }
  const feedback = decideFeedback(input);
  return {
    kind: "close",
    shouldNotify: feedback.shouldNotify,
    nextFeedbackAt: feedback.nextFeedbackAt,
  };
}

function decideFeedback(input: FeedbackInput): {
  shouldNotify: boolean;
  nextFeedbackAt: number | null;
} {
  const shouldNotify =
    input.lastFeedbackAt === null ||
    input.now - input.lastFeedbackAt >= input.feedbackIntervalMs;
  return {
    shouldNotify,
    nextFeedbackAt: shouldNotify ? input.now : input.lastFeedbackAt,
  };
}

function withoutPendingNavigation(
  scope: CurrentWebsiteScope,
): CurrentWebsiteScope {
  if (scope.pendingNavigation === undefined) {
    return scope;
  }
  const { pendingNavigation: _, ...stableScope } = scope;
  return stableScope;
}

function requireWebURL(value: string): URL {
  const parsed = parseWebURL(value);
  if (parsed === null) {
    throw new Error("Current Website requires an HTTP or HTTPS URL");
  }
  return parsed;
}

function parseWebURL(value: string): URL | null {
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    return null;
  }
  if (
    (parsed.protocol !== "http:" && parsed.protocol !== "https:") ||
    parsed.hostname.length === 0
  ) {
    return null;
  }
  return parsed;
}

function normalizeHostname(hostname: string): string {
  return hostname.toLowerCase().replace(/\.+$/, "");
}
