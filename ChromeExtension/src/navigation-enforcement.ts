import {
  completeNavigationScope,
  decideCommittedNavigation,
  decideOpenedTab,
} from "./navigation-policy.js";
import {
  TabActivationEnforcement,
  TabActivationStorePort,
  AvailableTabTarget,
  clearTabActivationEnforcement,
  loadTabActivationEnforcement,
  saveTabActivationEnforcement,
} from "./tab-activation-store.js";
import { decideTabActivation } from "./tab-policy.js";

export type ChromeTabEnforcementPlatform = {
  navigateTab(tabId: number, url: string): Promise<boolean>;
  closeTab(tabId: number): Promise<void>;
  activateTab(tabId: number): Promise<boolean>;
  blockedNavigation(profileId: string, tabId: number): void;
  blockedTabActivation(
    profileId: string,
    attemptedTabId: number,
    availableTabId: number | null,
  ): void;
  tabTargetClosed(profileId: string, tabId: number): void;
};

type DocumentNavigationEvent = {
  tabId: number;
  frameId: number;
  documentId: string;
  url: string;
};

export type ChromeTabEnforcementEvent =
  | ({ type: "committed" } & DocumentNavigationEvent)
  | ({ type: "completed" } & DocumentNavigationEvent)
  | ({ type: "historyUpdated" } & DocumentNavigationEvent)
  | { type: "urlChanged"; tabId: number; url: string }
  | {
      type: "openedTab";
      tabId: number;
      sourceTabId: number | undefined;
      pendingUrl: string | undefined;
      url: string | undefined;
    }
  | { type: "openedTabGraceExpired"; tabId: number }
  | { type: "activated"; tabId: number }
  | { type: "removed"; tabId: number }
  | { type: "attached"; tabId: number; windowId: number }
  | { type: "replaced"; addedTabId: number; removedTabId: number };

export type ChromeTabEnforcementCoordinatorOptions = {
  platform: ChromeTabEnforcementPlatform;
  store?: TabActivationStorePort;
  now?: () => number;
  feedbackIntervalMs?: number;
};

/**
 * Owns every event that can change the runtime Available Tab Targets.
 * Keeping these operations on one queue prevents activation, navigation,
 * attachment, replacement, and closure callbacks from racing one another.
 */
export class ChromeTabEnforcementCoordinator {
  private operationTail: Promise<void> = Promise.resolve();
  private lastFeedbackAt: number | null = null;
  private readonly handledOpenedTabs = new Set<number>();
  private readonly pendingOpenedTabs = new Map<number, number>();
  private readonly platform: ChromeTabEnforcementPlatform;
  private readonly store: TabActivationStorePort | undefined;
  private readonly now: () => number;
  private readonly feedbackIntervalMs: number;

  constructor(options: ChromeTabEnforcementCoordinatorOptions) {
    this.platform = options.platform;
    this.store = options.store;
    this.now = options.now ?? Date.now;
    this.feedbackIntervalMs = options.feedbackIntervalMs ?? 2_000;
  }

  start(
    enforcement: TabActivationEnforcement,
    establish?: () => Promise<void>,
  ): Promise<void> {
    return this.serialized(async () => {
      this.resetTransientState();
      await this.save(enforcement);
      await establish?.();
    });
  }

  stop(): Promise<void> {
    return this.serialized(async () => {
      this.resetTransientState();
      await this.clear();
    });
  }

  handle(event: ChromeTabEnforcementEvent): Promise<void> {
    return this.serialized(async () => {
      const enforcement = await this.load();
      if (enforcement === null) {
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
          await this.handleActivation(enforcement, event.tabId);
          return;
        case "removed":
          await this.handleRemoved(enforcement, event.tabId);
          return;
        case "attached":
          await this.handleAttached(enforcement, event.tabId, event.windowId);
          return;
        case "replaced": {
          const next = await this.removeTarget(
            enforcement,
            event.removedTabId,
          );
          await this.handleActivation(next, event.addedTabId);
          return;
        }
      }
    });
  }

  private async handleObservedURL(
    enforcement: TabActivationEnforcement,
    event: Extract<ChromeTabEnforcementEvent, { type: "urlChanged" }>,
  ): Promise<void> {
    const target = findTarget(enforcement, event.tabId);
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
    enforcement: TabActivationEnforcement,
    event: DocumentNavigationEvent,
  ): Promise<void> {
    const target = findTarget(enforcement, event.tabId);
    if (event.frameId !== 0 || target === undefined) {
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
    enforcement: TabActivationEnforcement,
    event: DocumentNavigationEvent,
  ): Promise<void> {
    const target = findTarget(enforcement, event.tabId);
    if (event.frameId !== 0 || target === undefined) {
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
    enforcement: TabActivationEnforcement,
    event: DocumentNavigationEvent,
  ): Promise<void> {
    const target = findTarget(enforcement, event.tabId);
    if (event.frameId !== 0 || target === undefined) {
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
    enforcement: TabActivationEnforcement,
    event: Extract<ChromeTabEnforcementEvent, { type: "openedTab" }>,
  ): Promise<void> {
    if (this.handledOpenedTabs.has(event.tabId)) {
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
    enforcement: TabActivationEnforcement,
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
    enforcement: TabActivationEnforcement,
    attemptedTabId: number,
  ): Promise<void> {
    let current = enforcement;
    let shouldNotify = false;
    while (true) {
      const decision = decideTabActivation({
        availableTabIds: current.availableTargets.map((target) => target.tabId),
        attemptedTabId,
        lastActivatedAvailableTabId: current.lastActivatedAvailableTabId,
        now: this.now(),
        lastFeedbackAt: this.lastFeedbackAt,
        feedbackIntervalMs: this.feedbackIntervalMs,
      });
      shouldNotify = shouldNotify || decision.shouldNotify;
      this.lastFeedbackAt = decision.nextFeedbackAt;
      if (
        decision.nextLastActivatedAvailableTabId !==
        current.lastActivatedAvailableTabId
      ) {
        current = {
          ...current,
          lastActivatedAvailableTabId:
            decision.nextLastActivatedAvailableTabId,
        };
        await this.save(current);
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
      if (decision.restoreTabId === null) {
        return;
      }
      if (await this.platform.activateTab(decision.restoreTabId)) {
        if (shouldNotify) {
          this.platform.blockedTabActivation(
            current.profileId,
            attemptedTabId,
            decision.restoreTabId,
          );
        }
        return;
      }
      current = await this.removeTarget(current, decision.restoreTabId);
    }
  }

  private async handleRemoved(
    enforcement: TabActivationEnforcement,
    tabId: number,
  ): Promise<void> {
    this.pendingOpenedTabs.delete(tabId);
    await this.removeTarget(enforcement, tabId);
  }

  private async removeTarget(
    enforcement: TabActivationEnforcement,
    tabId: number,
  ): Promise<TabActivationEnforcement> {
    if (findTarget(enforcement, tabId) === undefined) {
      return enforcement;
    }
    const availableTargets = enforcement.availableTargets.filter(
      (target) => target.tabId !== tabId,
    );
    const lastActivatedAvailableTabId =
      enforcement.lastActivatedAvailableTabId !== tabId &&
      availableTargets.some(
        (target) => target.tabId === enforcement.lastActivatedAvailableTabId,
      )
        ? enforcement.lastActivatedAvailableTabId
        : (availableTargets[0]?.tabId ?? null);
    const next = {
      ...enforcement,
      availableTargets,
      lastActivatedAvailableTabId,
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
    enforcement: TabActivationEnforcement,
    tabId: number,
    windowId: number,
  ): Promise<void> {
    const target = findTarget(enforcement, tabId);
    if (target === undefined || target.windowId === windowId) {
      return;
    }
    await this.save(replacingTarget(enforcement, target, {
      ...target,
      windowId,
    }));
  }

  private async restoreTargetOrRemove(
    enforcement: TabActivationEnforcement,
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

  private serialized(operation: () => Promise<void>): Promise<void> {
    const result = this.operationTail.then(operation);
    this.operationTail = result.catch(() => {});
    return result;
  }

  private load(): Promise<TabActivationEnforcement | null> {
    return this.store === undefined
      ? loadTabActivationEnforcement()
      : loadTabActivationEnforcement(this.store);
  }

  private save(enforcement: TabActivationEnforcement): Promise<void> {
    return this.store === undefined
      ? saveTabActivationEnforcement(enforcement)
      : saveTabActivationEnforcement(enforcement, this.store);
  }

  private clear(): Promise<void> {
    return this.store === undefined
      ? clearTabActivationEnforcement()
      : clearTabActivationEnforcement(this.store);
  }
}

function findTarget(
  enforcement: TabActivationEnforcement,
  tabId: number,
): AvailableTabTarget | undefined {
  return enforcement.availableTargets.find((target) => target.tabId === tabId);
}

function replacingTarget(
  enforcement: TabActivationEnforcement,
  existing: AvailableTabTarget,
  replacement: AvailableTabTarget,
): TabActivationEnforcement {
  return {
    ...enforcement,
    availableTargets: enforcement.availableTargets.map((target) =>
      target === existing ? replacement : target,
    ),
  };
}
