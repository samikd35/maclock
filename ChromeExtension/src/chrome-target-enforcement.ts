import {
  completeNavigationScope,
  decideCommittedNavigation,
  decideOpenedTab,
} from "./navigation-policy.js";
import {
  ChromeTargetEnforcement,
  ChromeTargetStateStorePort,
  StoredChromeTargetState,
  AvailableTabTarget,
  clearStoredChromeTargetState,
  loadStoredChromeTargetState,
  saveStoredChromeTargetState,
} from "./chrome-target-enforcement-store.js";
import {
  ChromeTargetReference,
  RestorableChromeWindowState,
  decideChromeActivation,
} from "./tab-policy.js";

export type ChromeTargetEnforcementPlatform = {
  navigateTab(tabId: number, url: string): Promise<boolean>;
  closeTab(tabId: number): Promise<void>;
  activateTab(tabId: number): Promise<boolean>;
  activateWindow(windowId: number): Promise<number | null>;
  captureWindowState(
    windowId: number,
  ): Promise<RestorableChromeWindowState | null>;
  minimizeWindow(windowId: number): Promise<"minimized" | "missing">;
  restoreWindow(
    windowId: number,
    state: RestorableChromeWindowState,
  ): Promise<"restored" | "missing">;
  blockedNavigation(profileId: string, tabId: number): void;
  blockedTabActivation(
    profileId: string,
    attemptedTabId: number,
    availableTabId: number | null,
  ): void;
  tabTargetClosed(profileId: string, tabId: number): void;
  browserWindowTargetClosed(profileId: string, windowId: number): void;
  restorationFailed(profileId: string, windowIds: number[]): void;
};

type DocumentNavigationEvent = {
  tabId: number;
  frameId: number;
  documentId: string;
  url: string;
};

export type ChromeTargetEnforcementEvent =
  | ({ type: "committed" } & DocumentNavigationEvent)
  | ({ type: "completed" } & DocumentNavigationEvent)
  | ({ type: "historyUpdated" } & DocumentNavigationEvent)
  | { type: "urlChanged"; tabId: number; url: string }
  | {
      type: "openedTab";
      tabId: number;
      windowId?: number;
      sourceTabId: number | undefined;
      pendingUrl: string | undefined;
      url: string | undefined;
    }
  | { type: "openedTabGraceExpired"; tabId: number }
  | { type: "activated"; tabId: number; windowId?: number }
  | { type: "removed"; tabId: number }
  | {
      type: "attached";
      tabId: number;
      windowId: number;
      url?: string;
      isActive?: boolean;
    }
  | {
      type: "replaced";
      addedTabId: number;
      addedWindowId?: number;
      removedTabId: number;
    }
  | { type: "windowRemoved"; windowId: number };

export type ChromeTargetEnforcementCoordinatorOptions = {
  platform: ChromeTargetEnforcementPlatform;
  store?: ChromeTargetStateStorePort;
  now?: () => number;
  feedbackIntervalMs?: number;
};

/**
 * Owns every event that can change runtime Available Browser Window Targets
 * or Available Tab Targets.
 * Keeping these operations on one queue prevents activation, navigation,
 * attachment, replacement, and closure callbacks from racing one another.
 */
export class ChromeTargetEnforcementCoordinator {
  private operationTail: Promise<void> = Promise.resolve();
  private lastFeedbackAt: number | null = null;
  private readonly handledOpenedTabs = new Set<number>();
  private readonly pendingOpenedTabs = new Map<number, number>();
  private readonly platform: ChromeTargetEnforcementPlatform;
  private readonly store: ChromeTargetStateStorePort | undefined;
  private readonly now: () => number;
  private readonly feedbackIntervalMs: number;

  constructor(options: ChromeTargetEnforcementCoordinatorOptions) {
    this.platform = options.platform;
    this.store = options.store;
    this.now = options.now ?? Date.now;
    this.feedbackIntervalMs = options.feedbackIntervalMs ?? 2_000;
  }

  start(
    enforcement: ChromeTargetEnforcement,
    establish?: () => Promise<void>,
  ): Promise<void> {
    return this.serialized(async () => {
      this.resetTransientState();
      const previous = await this.load();
      if (previous !== null && !(await this.attemptRestoration(previous))) {
        throw new Error("Previous Chrome window restoration is incomplete");
      }
      await this.save(enforcement);
      await establish?.();
    });
  }

  stop(): Promise<void> {
    return this.serialized(async () => {
      this.resetTransientState();
      const enforcement = await this.load();
      if (enforcement !== null) {
        await this.attemptRestoration(enforcement);
      } else {
        await this.clear();
      }
    });
  }

  retryPendingRestoration(): Promise<boolean> {
    return this.serialized(async () => {
      const enforcement = await this.load();
      if (enforcement === null || enforcement.state === "active") {
        return true;
      }
      return this.attemptRestoration(enforcement);
    });
  }

  handle(event: ChromeTargetEnforcementEvent): Promise<void> {
    return this.serialized(async () => {
      const enforcement = await this.load();
      if (enforcement === null || enforcement.state !== "active") {
        return;
      }
      switch (event.type) {
        case "committed":
          await this.handleCommitted(enforcement, event);
          return;
        case "completed":
          await this.handleCompleted(enforcement, event);
          return;
        case "historyUpdated":
          await this.handleHistoryUpdate(enforcement, event);
          return;
        case "urlChanged":
          await this.handleObservedURL(enforcement, event);
          return;
        case "openedTab":
          await this.handleOpenedTab(enforcement, event);
          return;
        case "openedTabGraceExpired":
          await this.handleOpenedTabGraceExpired(enforcement, event.tabId);
          return;
        case "activated":
          await this.handleActivation(
            enforcement,
            event.tabId,
            event.windowId,
          );
          return;
        case "removed":
          await this.handleRemoved(enforcement, event.tabId);
          return;
        case "attached":
          await this.handleAttached(
            enforcement,
            event.tabId,
            event.windowId,
            event.url,
            event.isActive ?? false,
          );
          return;
        case "replaced": {
          const next = await this.removeTarget(
            enforcement,
            event.removedTabId,
          );
          await this.handleActivation(
            next,
            event.addedTabId,
            event.addedWindowId,
          );
          return;
        }
        case "windowRemoved": {
          await this.removeWindowTarget(enforcement, event.windowId);
          return;
        }
      }
    });
  }

  private async handleObservedURL(
    enforcement: ChromeTargetEnforcement,
    event: Extract<ChromeTargetEnforcementEvent, { type: "urlChanged" }>,
  ): Promise<void> {
    const target = findNavigationScopedTarget(enforcement, event.tabId);
    if (target === undefined) {
      return;
    }
    const decision = decideCommittedNavigation({
      scope: target.navigationScope,
      candidateUrl: event.url,
      documentId: "tabs.onUpdated",
      now: this.now(),
      lastFeedbackAt: this.lastFeedbackAt,
      feedbackIntervalMs: this.feedbackIntervalMs,
    });
    if (decision.kind === "allow") {
      return;
    }
    this.lastFeedbackAt = decision.nextFeedbackAt;
    const nextEnforcement = replacingTarget(enforcement, target, {
      ...target,
      navigationScope: decision.nextScope,
    });
    await this.save(nextEnforcement);
    if (!(await this.restoreTargetOrRemove(
      nextEnforcement,
      target,
      decision.restoreUrl,
    ))) {
      return;
    }
    this.publishBlockedNavigationIfNeeded(
      enforcement.profileId,
      target.tabId,
      decision.shouldNotify,
    );
  }

  private async handleCommitted(
    enforcement: ChromeTargetEnforcement,
    event: DocumentNavigationEvent,
  ): Promise<void> {
    const target = findNavigationScopedTarget(enforcement, event.tabId);
    if (
      event.frameId !== 0 ||
      target === undefined
    ) {
      return;
    }
    const decision = decideCommittedNavigation({
      scope: target.navigationScope,
      candidateUrl: event.url,
      documentId: event.documentId,
      now: this.now(),
      lastFeedbackAt: this.lastFeedbackAt,
      feedbackIntervalMs: this.feedbackIntervalMs,
    });
    this.lastFeedbackAt = decision.nextFeedbackAt;
    const nextEnforcement = replacingTarget(enforcement, target, {
      ...target,
      navigationScope: decision.nextScope,
    });
    await this.save(nextEnforcement);
    if (decision.kind === "restore") {
      if (!(await this.restoreTargetOrRemove(
        nextEnforcement,
        target,
        decision.restoreUrl,
      ))) {
        return;
      }
      this.publishBlockedNavigationIfNeeded(
        enforcement.profileId,
        target.tabId,
        decision.shouldNotify,
      );
    }
  }

  private async handleCompleted(
    enforcement: ChromeTargetEnforcement,
    event: DocumentNavigationEvent,
  ): Promise<void> {
    const target = findNavigationScopedTarget(enforcement, event.tabId);
    if (
      event.frameId !== 0 ||
      target === undefined
    ) {
      return;
    }
    const nextScope = completeNavigationScope(
      target.navigationScope,
      event.documentId,
      event.url,
    );
    if (nextScope !== target.navigationScope) {
      await this.save(replacingTarget(enforcement, target, {
        ...target,
        navigationScope: nextScope,
      }));
    }
  }

  private async handleHistoryUpdate(
    enforcement: ChromeTargetEnforcement,
    event: DocumentNavigationEvent,
  ): Promise<void> {
    const target = findNavigationScopedTarget(enforcement, event.tabId);
    if (
      event.frameId !== 0 ||
      target === undefined
    ) {
      return;
    }
    const wasPendingDocument =
      target.navigationScope.pendingNavigation?.documentId === event.documentId;
    const decision = decideCommittedNavigation({
      scope: target.navigationScope,
      candidateUrl: event.url,
      documentId: event.documentId,
      now: this.now(),
      lastFeedbackAt: this.lastFeedbackAt,
      feedbackIntervalMs: this.feedbackIntervalMs,
    });
    this.lastFeedbackAt = decision.nextFeedbackAt;
    if (decision.kind === "restore" || wasPendingDocument) {
      const nextEnforcement = replacingTarget(enforcement, target, {
        ...target,
        navigationScope: decision.nextScope,
      });
      await this.save(nextEnforcement);
      if (decision.kind === "restore") {
        if (!(await this.restoreTargetOrRemove(
          nextEnforcement,
          target,
          decision.restoreUrl,
        ))) {
          return;
        }
        this.publishBlockedNavigationIfNeeded(
          enforcement.profileId,
          target.tabId,
          decision.shouldNotify,
        );
      }
      return;
    }
    const completedScope = completeNavigationScope(
      decision.nextScope,
      event.documentId,
      event.url,
    );
    await this.save(replacingTarget(enforcement, target, {
      ...target,
      navigationScope: completedScope,
    }));
  }

  private async handleOpenedTab(
    enforcement: ChromeTargetEnforcement,
    event: Extract<ChromeTargetEnforcementEvent, { type: "openedTab" }>,
  ): Promise<void> {
    if (this.handledOpenedTabs.has(event.tabId)) {
      return;
    }
    if (
      event.windowId !== undefined &&
      enforcement.allowedWindowIds.includes(event.windowId)
    ) {
      this.pendingOpenedTabs.delete(event.tabId);
      this.rememberHandledOpenedTab(event.tabId);
      return;
    }
    const sourceTabId =
      event.sourceTabId !== undefined &&
      findTarget(enforcement, event.sourceTabId) !== undefined
        ? event.sourceTabId
        : this.pendingOpenedTabs.get(event.tabId);
    if (sourceTabId === undefined) {
      return;
    }
    const sourceTarget = findTarget(enforcement, sourceTabId);
    if (sourceTarget === undefined) {
      this.pendingOpenedTabs.delete(event.tabId);
      await this.platform.closeTab(event.tabId);
      this.rememberHandledOpenedTab(event.tabId);
      return;
    }
    const decision = decideOpenedTab({
      scope: sourceTarget.navigationScope,
      candidateUrl: event.pendingUrl ?? event.url,
      hasGraceExpired: false,
      now: this.now(),
      lastFeedbackAt: this.lastFeedbackAt,
      feedbackIntervalMs: this.feedbackIntervalMs,
    });
    if (decision.kind === "wait") {
      this.rememberPendingOpenedTab(event.tabId, sourceTarget.tabId);
      return;
    }
    this.pendingOpenedTabs.delete(event.tabId);
    if (decision.kind === "transfer") {
      const didTransfer = await this.platform.navigateTab(
        sourceTarget.tabId,
        decision.destinationUrl,
      );
      if (!didTransfer) {
        await this.removeTarget(enforcement, sourceTarget.tabId);
      }
    } else {
      this.lastFeedbackAt = decision.nextFeedbackAt;
    }
    await this.platform.closeTab(event.tabId);
    this.rememberHandledOpenedTab(event.tabId);
    if (decision.kind === "close") {
      this.publishBlockedNavigationIfNeeded(
        enforcement.profileId,
        sourceTarget.tabId,
        decision.shouldNotify,
      );
    }
  }

  private async handleOpenedTabGraceExpired(
    enforcement: ChromeTargetEnforcement,
    tabId: number,
  ): Promise<void> {
    const sourceTabId = this.pendingOpenedTabs.get(tabId);
    if (sourceTabId === undefined) {
      return;
    }
    this.pendingOpenedTabs.delete(tabId);
    const sourceTarget = findTarget(enforcement, sourceTabId);
    if (sourceTarget === undefined) {
      await this.platform.closeTab(tabId);
      this.rememberHandledOpenedTab(tabId);
      return;
    }
    const decision = decideOpenedTab({
      scope: sourceTarget.navigationScope,
      candidateUrl: undefined,
      hasGraceExpired: true,
      now: this.now(),
      lastFeedbackAt: this.lastFeedbackAt,
      feedbackIntervalMs: this.feedbackIntervalMs,
    });
    if (decision.kind !== "close") {
      return;
    }
    this.lastFeedbackAt = decision.nextFeedbackAt;
    await this.platform.closeTab(tabId);
    this.rememberHandledOpenedTab(tabId);
    this.publishBlockedNavigationIfNeeded(
      enforcement.profileId,
      sourceTarget.tabId,
      decision.shouldNotify,
    );
  }

  private async handleActivation(
    enforcement: ChromeTargetEnforcement,
    attemptedTabId: number,
    attemptedWindowId: number | undefined,
  ): Promise<void> {
    let current = enforcement;
    let shouldNotify = false;
    while (true) {
      const decision = decideChromeActivation({
        allowedWindowIds: current.allowedWindowIds,
        availableTabIds: current.availableTargets.map((target) => target.tabId),
        attemptedTabId,
        attemptedWindowId,
        lastActivatedTarget: current.lastActivatedTarget,
        now: this.now(),
        lastFeedbackAt: this.lastFeedbackAt,
        feedbackIntervalMs: this.feedbackIntervalMs,
      });
      shouldNotify = shouldNotify || decision.shouldNotify;
      this.lastFeedbackAt = decision.nextFeedbackAt;
      if (
        !sameTargetReference(
          decision.nextLastActivatedTarget,
          current.lastActivatedTarget,
        )
      ) {
        current = {
          ...current,
          lastActivatedTarget: decision.nextLastActivatedTarget,
        };
        await this.save(current);
      }
      if (
        attemptedWindowId !== undefined &&
        !isWindowCovered(current, attemptedWindowId)
      ) {
        current = await this.minimizeWindow(current, attemptedWindowId);
      }
      if (decision.closeAttemptedTab) {
        await this.platform.closeTab(attemptedTabId);
        if (shouldNotify) {
          this.platform.blockedTabActivation(
            current.profileId,
            attemptedTabId,
            null,
          );
        }
        return;
      }
      if (decision.restoreTarget === null) {
        return;
      }
      const restoredTabId = await this.activateTarget(decision.restoreTarget);
      if (restoredTabId !== null) {
        if (shouldNotify) {
          this.platform.blockedTabActivation(
            current.profileId,
            attemptedTabId,
            restoredTabId,
          );
        }
        return;
      }
      current = decision.restoreTarget.type === "window"
        ? await this.removeWindowTarget(
            current,
            decision.restoreTarget.windowId,
          )
        : await this.removeTarget(current, decision.restoreTarget.tabId);
    }
  }

  private async activateTarget(
    target: ChromeTargetReference,
  ): Promise<number | null> {
    if (target.type === "window") {
      return this.platform.activateWindow(target.windowId);
    }
    return (await this.platform.activateTab(target.tabId))
      ? target.tabId
      : null;
  }

  private async handleRemoved(
    enforcement: ChromeTargetEnforcement,
    tabId: number,
  ): Promise<void> {
    this.pendingOpenedTabs.delete(tabId);
    await this.removeTarget(enforcement, tabId);
  }

  private async removeTarget(
    enforcement: ChromeTargetEnforcement,
    tabId: number,
  ): Promise<ChromeTargetEnforcement> {
    if (findTarget(enforcement, tabId) === undefined) {
      return enforcement;
    }
    const availableTargets = enforcement.availableTargets.filter(
      (target) => target.tabId !== tabId,
    );
    const lastActivatedTarget =
      enforcement.lastActivatedTarget?.type !== "tab" ||
      enforcement.lastActivatedTarget.tabId !== tabId
        ? enforcement.lastActivatedTarget
        : firstAvailableTarget(enforcement.allowedWindowIds, availableTargets);
    const next = {
      ...enforcement,
      availableTargets,
      lastActivatedTarget,
    };
    await this.save(next);
    for (const [openedTabId, sourceTabId] of this.pendingOpenedTabs) {
      if (sourceTabId === tabId) {
        this.pendingOpenedTabs.delete(openedTabId);
        await this.platform.closeTab(openedTabId);
        this.rememberHandledOpenedTab(openedTabId);
      }
    }
    this.platform.tabTargetClosed(enforcement.profileId, tabId);
    return next;
  }

  private async handleAttached(
    enforcement: ChromeTargetEnforcement,
    tabId: number,
    windowId: number,
    url: string | undefined,
    isActive: boolean,
  ): Promise<void> {
    const target = findTarget(enforcement, tabId);
    let next = enforcement;
    if (target !== undefined && target.windowId !== windowId) {
      next = replacingTarget(enforcement, target, {
        ...target,
        windowId,
      });
      await this.save(next);
    }
    if (target !== undefined && url !== undefined) {
      await this.handleObservedURL(next, {
        type: "urlChanged",
        tabId,
        url,
      });
      const current = await this.load();
      if (current === null || current.state !== "active") {
        return;
      }
      next = current;
    }
    if (isActive) {
      await this.handleActivation(next, tabId, windowId);
    }
  }

  private async removeWindowTarget(
    enforcement: ChromeTargetEnforcement,
    windowId: number,
  ): Promise<ChromeTargetEnforcement> {
    const wasAllowed = enforcement.allowedWindowIds.includes(windowId);
    const wasMinimized = enforcement.minimizedWindows.some(
      (window) => window.windowId === windowId,
    );
    if (!wasAllowed && !wasMinimized) {
      return enforcement;
    }
    const allowedWindowIds = enforcement.allowedWindowIds.filter(
      (candidate) => candidate !== windowId,
    );
    const lastActivatedTarget =
      enforcement.lastActivatedTarget?.type !== "window" ||
      enforcement.lastActivatedTarget.windowId !== windowId
        ? enforcement.lastActivatedTarget
        : firstAvailableTarget(allowedWindowIds, enforcement.availableTargets);
    const next = {
      ...enforcement,
      allowedWindowIds,
      minimizedWindows: enforcement.minimizedWindows.filter(
        (window) => window.windowId !== windowId,
      ),
      initiallyMinimizedWindowIds:
        enforcement.initiallyMinimizedWindowIds.filter(
          (candidate) => candidate !== windowId,
        ),
      lastActivatedTarget,
    };
    await this.save(next);
    if (wasAllowed) {
      this.platform.browserWindowTargetClosed(enforcement.profileId, windowId);
    }
    return next;
  }

  private async minimizeWindow(
    enforcement: ChromeTargetEnforcement,
    windowId: number,
  ): Promise<ChromeTargetEnforcement> {
    if (enforcement.initiallyMinimizedWindowIds.includes(windowId)) {
      await this.platform.minimizeWindow(windowId);
      return enforcement;
    }
    if (enforcement.minimizedWindows.some(
      (window) => window.windowId === windowId,
    )) {
      await this.platform.minimizeWindow(windowId);
      return enforcement;
    }
    const previousState = await this.platform.captureWindowState(windowId);
    if (previousState === null) {
      return enforcement;
    }
    const next = {
      ...enforcement,
      minimizedWindows: [
        ...enforcement.minimizedWindows,
        { windowId, previousState },
      ],
    };
    await this.save(next);
    await this.platform.minimizeWindow(windowId);
    return next;
  }

  private async attemptRestoration(
    enforcement: StoredChromeTargetState,
  ): Promise<boolean> {
    const unresolvedRestorations = [];
    for (const window of enforcement.minimizedWindows) {
      try {
        await this.platform.restoreWindow(
          window.windowId,
          window.previousState,
        );
      } catch {
        unresolvedRestorations.push(window);
      }
    }
    const unresolvedInitiallyMinimizedWindowIds = [];
    for (const windowId of enforcement.initiallyMinimizedWindowIds) {
      try {
        await this.platform.minimizeWindow(windowId);
      } catch {
        unresolvedInitiallyMinimizedWindowIds.push(windowId);
      }
    }
    if (
      unresolvedRestorations.length === 0 &&
      unresolvedInitiallyMinimizedWindowIds.length === 0
    ) {
      await this.clear();
      return true;
    }
    await this.save({
      state: "restorationPending",
      profileId: enforcement.profileId,
      initiallyMinimizedWindowIds: unresolvedInitiallyMinimizedWindowIds,
      minimizedWindows: unresolvedRestorations,
    });
    this.platform.restorationFailed(
      enforcement.profileId,
      [
        ...unresolvedRestorations.map((window) => window.windowId),
        ...unresolvedInitiallyMinimizedWindowIds,
      ],
    );
    return false;
  }

  private async restoreTargetOrRemove(
    enforcement: ChromeTargetEnforcement,
    target: AvailableTabTarget,
    restoreUrl: string,
  ): Promise<boolean> {
    if (await this.platform.navigateTab(target.tabId, restoreUrl)) {
      return true;
    }
    await this.removeTarget(enforcement, target.tabId);
    return false;
  }

  private publishBlockedNavigationIfNeeded(
    profileId: string,
    tabId: number,
    shouldNotify: boolean,
  ): void {
    if (shouldNotify) {
      this.platform.blockedNavigation(profileId, tabId);
    }
  }

  private rememberHandledOpenedTab(tabId: number): void {
    this.handledOpenedTabs.add(tabId);
    if (this.handledOpenedTabs.size > 512) {
      const oldest = this.handledOpenedTabs.values().next().value;
      if (oldest !== undefined) {
        this.handledOpenedTabs.delete(oldest);
      }
    }
  }

  private rememberPendingOpenedTab(tabId: number, sourceTabId: number): void {
    this.pendingOpenedTabs.set(tabId, sourceTabId);
    if (this.pendingOpenedTabs.size > 512) {
      const oldest = this.pendingOpenedTabs.keys().next().value;
      if (oldest !== undefined) {
        this.pendingOpenedTabs.delete(oldest);
      }
    }
  }

  private resetTransientState(): void {
    this.lastFeedbackAt = null;
    this.handledOpenedTabs.clear();
    this.pendingOpenedTabs.clear();
  }

  private serialized<Result>(
    operation: () => Promise<Result>,
  ): Promise<Result> {
    const result = this.operationTail.then(operation);
    this.operationTail = result.then(
      () => {},
      () => {},
    );
    return result;
  }

  private load(): Promise<StoredChromeTargetState | null> {
    return this.store === undefined
      ? loadStoredChromeTargetState()
      : loadStoredChromeTargetState(this.store);
  }

  private save(enforcement: StoredChromeTargetState): Promise<void> {
    return this.store === undefined
      ? saveStoredChromeTargetState(enforcement)
      : saveStoredChromeTargetState(enforcement, this.store);
  }

  private clear(): Promise<void> {
    return this.store === undefined
      ? clearStoredChromeTargetState()
      : clearStoredChromeTargetState(this.store);
  }
}

function findTarget(
  enforcement: ChromeTargetEnforcement,
  tabId: number,
): AvailableTabTarget | undefined {
  return enforcement.availableTargets.find((target) => target.tabId === tabId);
}

function findNavigationScopedTarget(
  enforcement: ChromeTargetEnforcement,
  tabId: number,
): AvailableTabTarget | undefined {
  const target = findTarget(enforcement, tabId);
  return target !== undefined &&
      !enforcement.allowedWindowIds.includes(target.windowId)
    ? target
    : undefined;
}

function isWindowCovered(
  enforcement: ChromeTargetEnforcement,
  windowId: number,
): boolean {
  return enforcement.allowedWindowIds.includes(windowId) ||
    enforcement.availableTargets.some((target) => target.windowId === windowId);
}

function replacingTarget(
  enforcement: ChromeTargetEnforcement,
  existing: AvailableTabTarget,
  replacement: AvailableTabTarget,
): ChromeTargetEnforcement {
  return {
    ...enforcement,
    availableTargets: enforcement.availableTargets.map((target) =>
      target === existing ? replacement : target,
    ),
  };
}

function firstAvailableTarget(
  allowedWindowIds: number[],
  availableTargets: AvailableTabTarget[],
): ChromeTargetReference | null {
  const windowId = allowedWindowIds[0];
  if (windowId !== undefined) {
    return { type: "window", windowId };
  }
  const tabId = availableTargets[0]?.tabId;
  return tabId === undefined ? null : { type: "tab", tabId };
}

function sameTargetReference(
  lhs: ChromeTargetReference | null,
  rhs: ChromeTargetReference | null,
): boolean {
  if (lhs === null || rhs === null) {
    return lhs === rhs;
  }
  if (lhs.type !== rhs.type) {
    return false;
  }
  return lhs.type === "window"
    ? lhs.windowId === (rhs as { type: "window"; windowId: number }).windowId
    : lhs.tabId === (rhs as { type: "tab"; tabId: number }).tabId;
}
