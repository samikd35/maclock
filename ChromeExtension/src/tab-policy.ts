export type TabActivationInput = {
  availableTabIds: number[];
  attemptedTabId: number;
  lastActivatedAvailableTabId: number | null;
  now: number;
  lastFeedbackAt: number | null;
  feedbackIntervalMs: number;
};

export type TabActivationDecision = {
  restoreTabId: number | null;
  closeAttemptedTab: boolean;
  shouldNotify: boolean;
  nextFeedbackAt: number | null;
  nextLastActivatedAvailableTabId: number | null;
};

export type AvailableTabAtStart = {
  tabId: number;
  windowId: number;
  isActive: boolean;
};

export function chooseInitialAvailableTabsByWindow(
  targets: AvailableTabAtStart[],
): number[] {
  const targetByWindow = new Map<number, AvailableTabAtStart>();
  for (const target of targets) {
    const existing = targetByWindow.get(target.windowId);
    if (existing === undefined || (!existing.isActive && target.isActive)) {
      targetByWindow.set(target.windowId, target);
    }
  }
  return [...targetByWindow.values()].map((target) => target.tabId);
}

export function decideTabActivation(
  input: TabActivationInput,
): TabActivationDecision {
  if (input.availableTabIds.includes(input.attemptedTabId)) {
    return {
      restoreTabId: null,
      closeAttemptedTab: false,
      shouldNotify: false,
      nextFeedbackAt: input.lastFeedbackAt,
      nextLastActivatedAvailableTabId: input.attemptedTabId,
    };
  }

  const restoreTabId =
    input.lastActivatedAvailableTabId !== null &&
    input.availableTabIds.includes(input.lastActivatedAvailableTabId)
      ? input.lastActivatedAvailableTabId
      : input.availableTabIds[0] ?? null;
  const shouldNotify =
    input.lastFeedbackAt === null ||
    input.now - input.lastFeedbackAt >= input.feedbackIntervalMs;
  return {
    restoreTabId,
    closeAttemptedTab: restoreTabId === null,
    shouldNotify,
    nextFeedbackAt: shouldNotify ? input.now : input.lastFeedbackAt,
    nextLastActivatedAvailableTabId: restoreTabId,
  };
}
