import {
  completeCurrentWebsiteNavigation,
  decideCommittedNavigation,
  decideOpenedTab,
} from "./navigation-policy.js";
import {
  TabActivationEnforcement,
  TabActivationStorePort,
  clearTabActivationEnforcement,
  loadTabActivationEnforcement,
  saveTabActivationEnforcement,
} from "./tab-activation-store.js";

export type NavigationEnforcementPlatform = {
  navigateTab(tabId: number, url: string): Promise<void>;
  closeTab(tabId: number): Promise<void>;
  blockedNavigation(profileId: string, tabId: number): void;
};

type DocumentNavigationEvent = {
  tabId: number;
  frameId: number;
  documentId: string;
  url: string;
};

export type NavigationEnforcementEvent =
  | ({ type: "committed" } & DocumentNavigationEvent)
  | ({ type: "completed" } & DocumentNavigationEvent)
  | ({ type: "historyUpdated" } & DocumentNavigationEvent)
  | {
      type: "urlChanged";
      tabId: number;
      url: string;
    }
  | {
      type: "openedTab";
      tabId: number;
      sourceTabId: number | undefined;
      pendingUrl: string | undefined;
      url: string | undefined;
    }
  | {
      type: "openedTabGraceExpired";
      tabId: number;
    };

export type CurrentWebsiteNavigationEnforcerOptions = {
  platform: NavigationEnforcementPlatform;
  store?: TabActivationStorePort;
  now?: () => number;
  feedbackIntervalMs?: number;
};

export class CurrentWebsiteNavigationEnforcer {
  private operationTail: Promise<void> = Promise.resolve();
  private lastFeedbackAt: number | null = null;
  private readonly handledOpenedTabs = new Set<number>();
  private readonly pendingOpenedTabs = new Set<number>();
  private readonly platform: NavigationEnforcementPlatform;
  private readonly store: TabActivationStorePort | undefined;
  private readonly now: () => number;
  private readonly feedbackIntervalMs: number;

  constructor(options: CurrentWebsiteNavigationEnforcerOptions) {
    this.platform = options.platform;
    this.store = options.store;
    this.now = options.now ?? Date.now;
    this.feedbackIntervalMs = options.feedbackIntervalMs ?? 2_000;
  }

  start(enforcement: TabActivationEnforcement): Promise<void> {
    return this.serialized(async () => {
      this.lastFeedbackAt = null;
      this.handledOpenedTabs.clear();
      this.pendingOpenedTabs.clear();
      await this.save(enforcement);
    });
  }

  stop(): Promise<void> {
    return this.serialized(async () => {
      this.lastFeedbackAt = null;
      this.handledOpenedTabs.clear();
      this.pendingOpenedTabs.clear();
      await this.clear();
    });
  }

  handle(event: NavigationEnforcementEvent): Promise<void> {
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
      }
    });
  }

  private async handleObservedURL(
    enforcement: TabActivationEnforcement,
    event: Extract<NavigationEnforcementEvent, { type: "urlChanged" }>,
  ): Promise<void> {
    if (event.tabId !== enforcement.tabId) {
      return;
    }
    const decision = decideCommittedNavigation({
      scope: enforcement.navigationScope,
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
    await this.save({
      ...enforcement,
      navigationScope: decision.nextScope,
    });
    await this.platform.navigateTab(enforcement.tabId, decision.restoreUrl);
    this.publishBlockedNoticeIfNeeded(enforcement, decision.shouldNotify);
  }

  private async handleCommitted(
    enforcement: TabActivationEnforcement,
    event: DocumentNavigationEvent,
  ): Promise<void> {
    if (event.frameId !== 0 || event.tabId !== enforcement.tabId) {
      return;
    }
    const decision = decideCommittedNavigation({
      scope: enforcement.navigationScope,
      candidateUrl: event.url,
      documentId: event.documentId,
      now: this.now(),
      lastFeedbackAt: this.lastFeedbackAt,
      feedbackIntervalMs: this.feedbackIntervalMs,
    });
    this.lastFeedbackAt = decision.nextFeedbackAt;
    await this.save({
      ...enforcement,
      navigationScope: decision.nextScope,
    });
    if (decision.kind === "restore") {
      await this.platform.navigateTab(enforcement.tabId, decision.restoreUrl);
      this.publishBlockedNoticeIfNeeded(enforcement, decision.shouldNotify);
    }
  }

  private async handleCompleted(
    enforcement: TabActivationEnforcement,
    event: DocumentNavigationEvent,
  ): Promise<void> {
    if (event.frameId !== 0 || event.tabId !== enforcement.tabId) {
      return;
    }
    const nextScope = completeCurrentWebsiteNavigation(
      enforcement.navigationScope,
      event.documentId,
      event.url,
    );
    if (nextScope !== enforcement.navigationScope) {
      await this.save({ ...enforcement, navigationScope: nextScope });
    }
  }

  private async handleHistoryUpdate(
    enforcement: TabActivationEnforcement,
    event: DocumentNavigationEvent,
  ): Promise<void> {
    if (event.frameId !== 0 || event.tabId !== enforcement.tabId) {
      return;
    }
    const wasPendingDocument =
      enforcement.navigationScope.pendingNavigation?.documentId ===
      event.documentId;
    const decision = decideCommittedNavigation({
      scope: enforcement.navigationScope,
      candidateUrl: event.url,
      documentId: event.documentId,
      now: this.now(),
      lastFeedbackAt: this.lastFeedbackAt,
      feedbackIntervalMs: this.feedbackIntervalMs,
    });
    this.lastFeedbackAt = decision.nextFeedbackAt;
    if (decision.kind === "restore") {
      await this.save({
        ...enforcement,
        navigationScope: decision.nextScope,
      });
      await this.platform.navigateTab(enforcement.tabId, decision.restoreUrl);
      this.publishBlockedNoticeIfNeeded(enforcement, decision.shouldNotify);
      return;
    }
    if (wasPendingDocument) {
      await this.save({
        ...enforcement,
        navigationScope: decision.nextScope,
      });
      return;
    }
    const completedScope = completeCurrentWebsiteNavigation(
      decision.nextScope,
      event.documentId,
      event.url,
    );
    await this.save({ ...enforcement, navigationScope: completedScope });
  }

  private async handleOpenedTab(
    enforcement: TabActivationEnforcement,
    event: Extract<NavigationEnforcementEvent, { type: "openedTab" }>,
  ): Promise<void> {
    if (
      (event.sourceTabId !== enforcement.tabId &&
        !this.pendingOpenedTabs.has(event.tabId)) ||
      this.handledOpenedTabs.has(event.tabId)
    ) {
      return;
    }
    const decision = decideOpenedTab({
      scope: enforcement.navigationScope,
      candidateUrl: event.pendingUrl ?? event.url,
      hasGraceExpired: false,
      now: this.now(),
      lastFeedbackAt: this.lastFeedbackAt,
      feedbackIntervalMs: this.feedbackIntervalMs,
    });
    if (decision.kind === "wait") {
      this.rememberPendingOpenedTab(event.tabId);
      return;
    }
    this.pendingOpenedTabs.delete(event.tabId);
    if (decision.kind === "transfer") {
      await this.platform.navigateTab(
        enforcement.tabId,
        decision.destinationUrl,
      );
    } else {
      this.lastFeedbackAt = decision.nextFeedbackAt;
    }
    await this.platform.closeTab(event.tabId);
    this.rememberHandledOpenedTab(event.tabId);
    if (decision.kind === "close") {
      this.publishBlockedNoticeIfNeeded(enforcement, decision.shouldNotify);
    }
  }

  private async handleOpenedTabGraceExpired(
    enforcement: TabActivationEnforcement,
    tabId: number,
  ): Promise<void> {
    if (!this.pendingOpenedTabs.delete(tabId)) {
      return;
    }
    const decision = decideOpenedTab({
      scope: enforcement.navigationScope,
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
    this.publishBlockedNoticeIfNeeded(enforcement, decision.shouldNotify);
  }

  private publishBlockedNoticeIfNeeded(
    enforcement: TabActivationEnforcement,
    shouldNotify: boolean,
  ): void {
    if (shouldNotify) {
      this.platform.blockedNavigation(
        enforcement.profileId,
        enforcement.tabId,
      );
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

  private rememberPendingOpenedTab(tabId: number): void {
    this.pendingOpenedTabs.add(tabId);
    if (this.pendingOpenedTabs.size > 512) {
      const oldest = this.pendingOpenedTabs.values().next().value;
      if (oldest !== undefined) {
        this.pendingOpenedTabs.delete(oldest);
      }
    }
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
