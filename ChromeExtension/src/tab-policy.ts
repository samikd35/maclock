export type TabActivationInput = {
  allowedTabId: number;
  attemptedTabId: number;
  now: number;
  lastFeedbackAt: number | null;
  feedbackIntervalMs: number;
};

export type TabActivationDecision = {
  restoreTabId: number | null;
  shouldNotify: boolean;
  nextFeedbackAt: number | null;
};

export function decideTabActivation(
  input: TabActivationInput,
): TabActivationDecision {
  if (input.attemptedTabId === input.allowedTabId) {
    return {
      restoreTabId: null,
      shouldNotify: false,
      nextFeedbackAt: input.lastFeedbackAt,
    };
  }

  const shouldNotify =
    input.lastFeedbackAt === null ||
    input.now - input.lastFeedbackAt >= input.feedbackIntervalMs;
  return {
    restoreTabId: input.allowedTabId,
    shouldNotify,
    nextFeedbackAt: shouldNotify ? input.now : input.lastFeedbackAt,
  };
}
