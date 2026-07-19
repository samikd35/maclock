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

export type ExactPageScope = {
  type: "exactPage";
  hostname: string;
  pathname: string;
  search: string;
  lastAllowedUrl: string;
  pendingNavigation?: PendingAllowedNavigation;
};

export type NavigationScope = CurrentWebsiteScope | ExactPageScope;

type FeedbackInput = {
  now: number;
  lastFeedbackAt: number | null;
  feedbackIntervalMs: number;
};

export type CommittedNavigationInput = FeedbackInput & {
  scope: NavigationScope;
  candidateUrl: string;
  documentId: string;
};

export type CommittedNavigationDecision =
  | {
      kind: "allow";
      nextScope: NavigationScope;
      shouldNotify: false;
      nextFeedbackAt: number | null;
    }
  | {
      kind: "restore";
      restoreUrl: string;
      nextScope: NavigationScope;
      shouldNotify: boolean;
      nextFeedbackAt: number | null;
    };

export type OpenedTabInput = FeedbackInput & {
  scope: NavigationScope;
  candidateUrl: string | undefined;
  hasGraceExpired: boolean;
};

export type OpenedTabDecision =
  | { kind: "wait" }
  | { kind: "transfer"; destinationUrl: string }
  | {
      kind: "close";
      shouldNotify: boolean;
      nextFeedbackAt: number | null;
    };

export type StartingNavigationDetails = {
  initialUrl: string;
  liveUrl: string | undefined;
  liveDocumentIsComplete: boolean;
};

export type StartingCurrentWebsiteInput = StartingNavigationDetails;

export type StartingNavigationInput = StartingNavigationDetails & {
  type: NavigationScope["type"];
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

export function createExactPageScope(initialUrl: string): ExactPageScope {
  const parsed = requireWebURL(initialUrl);
  return {
    type: "exactPage",
    hostname: normalizeHostname(parsed.hostname),
    pathname: parsed.pathname,
    search: parsed.search,
    lastAllowedUrl: parsed.href,
  };
}

export function createStartingCurrentWebsiteScope(
  input: StartingCurrentWebsiteInput,
): CurrentWebsiteScope {
  const scope = createStartingNavigationScope({
    ...input,
    type: "currentWebsite",
  });
  if (scope.type !== "currentWebsite") {
    throw new Error("Current Website scope construction failed");
  }
  return scope;
}

export function createStartingNavigationScope(
  input: StartingNavigationInput,
): NavigationScope {
  const scope = createNavigationScope(input.type, input.initialUrl);
  if (
    !input.liveDocumentIsComplete ||
    input.liveUrl === undefined ||
    !isWithinNavigationScope(scope, input.liveUrl)
  ) {
    return scope;
  }
  return {
    ...scope,
    lastAllowedUrl: requireWebURL(input.liveUrl).href,
  };
}

export function canStartCurrentWebsiteEnforcement(
  input: StartingCurrentWebsiteInput,
): boolean {
  return canStartNavigationEnforcement({
    ...input,
    type: "currentWebsite",
  });
}

export function canStartNavigationEnforcement(
  input: StartingNavigationInput,
): boolean {
  if (input.liveDocumentIsComplete || input.liveUrl === undefined) {
    return true;
  }
  const scope = createNavigationScope(input.type, input.initialUrl);
  return !isWithinNavigationScope(scope, input.liveUrl);
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

export function isWithinNavigationScope(
  scope: NavigationScope,
  candidateUrl: string,
): boolean {
  const parsed = parseWebURL(candidateUrl);
  if (
    parsed === null ||
    normalizeHostname(parsed.hostname) !== scope.hostname
  ) {
    return false;
  }
  switch (scope.type) {
    case "currentWebsite":
      return true;
    case "exactPage":
      return parsed.pathname === scope.pathname && parsed.search === scope.search;
  }
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
  return isValidPendingNavigation(candidate as CurrentWebsiteScope);
}

export function isValidNavigationScope(
  value: unknown,
): value is NavigationScope {
  if (isValidCurrentWebsiteScope(value)) {
    return true;
  }
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }
  const candidate = value as Record<string, unknown>;
  const allowedKeys = new Set([
    "type",
    "hostname",
    "pathname",
    "search",
    "lastAllowedUrl",
    "pendingNavigation",
  ]);
  if (
    Object.keys(candidate).some((key) => !allowedKeys.has(key)) ||
    candidate.type !== "exactPage" ||
    typeof candidate.hostname !== "string" ||
    typeof candidate.pathname !== "string" ||
    !candidate.pathname.startsWith("/") ||
    typeof candidate.search !== "string" ||
    (candidate.search !== "" && !candidate.search.startsWith("?")) ||
    typeof candidate.lastAllowedUrl !== "string"
  ) {
    return false;
  }
  const scope = candidate as ExactPageScope;
  if (
    parseWebURL(scope.lastAllowedUrl)?.href !== scope.lastAllowedUrl ||
    !isWithinNavigationScope(scope, scope.lastAllowedUrl)
  ) {
    return false;
  }
  return isValidPendingNavigation(scope);
}

export function decideCommittedNavigation(
  input: CommittedNavigationInput,
): CommittedNavigationDecision {
  const candidate = parseWebURL(input.candidateUrl);
  if (
    candidate !== null &&
    isWithinNavigationScope(input.scope, candidate.href)
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

export function completeNavigationScope(
  scope: NavigationScope,
  documentId: string,
  completedUrl: string,
): NavigationScope {
  const pending = scope.pendingNavigation;
  const completed = parseWebURL(completedUrl);
  if (
    pending === undefined ||
    pending.documentId !== documentId ||
    completed === null ||
    completed.href !== pending.url ||
    !isWithinNavigationScope(scope, completed.href)
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
    !input.hasGraceExpired &&
    isUnresolvedOpenedTabURL(candidate)
  ) {
    return { kind: "wait" };
  }
  if (
    candidate !== undefined &&
    isWithinNavigationScope(input.scope, candidate)
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

function isUnresolvedOpenedTabURL(candidate: string | undefined): boolean {
  return (
    candidate === undefined || candidate === "" || candidate === "about:blank"
  );
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
  scope: NavigationScope,
): NavigationScope {
  if (scope.pendingNavigation === undefined) {
    return scope;
  }
  const { pendingNavigation: _, ...stableScope } = scope;
  return stableScope as NavigationScope;
}

function isValidPendingNavigation(scope: NavigationScope): boolean {
  if (scope.pendingNavigation === undefined) {
    return true;
  }
  if (
    typeof scope.pendingNavigation !== "object" ||
    scope.pendingNavigation === null ||
    Array.isArray(scope.pendingNavigation)
  ) {
    return false;
  }
  const pending = scope.pendingNavigation as Record<string, unknown>;
  return (
    Object.keys(pending).sort().join(",") === "documentId,url" &&
    typeof pending.documentId === "string" &&
    pending.documentId.length > 0 &&
    new TextEncoder().encode(pending.documentId).length <= 128 &&
    typeof pending.url === "string" &&
    parseWebURL(pending.url)?.href === pending.url &&
    isWithinNavigationScope(scope, pending.url)
  );
}

function requireWebURL(value: string): URL {
  const parsed = parseWebURL(value);
  if (parsed === null) {
    throw new Error("A navigation scope requires an HTTP or HTTPS URL");
  }
  return parsed;
}

function createNavigationScope(
  type: NavigationScope["type"],
  initialUrl: string,
): NavigationScope {
  return type === "currentWebsite"
    ? createCurrentWebsiteScope(initialUrl)
    : createExactPageScope(initialUrl);
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
