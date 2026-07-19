export type ChromeTargetReference =
  | { type: "window"; windowId: number }
  | { type: "tab"; tabId: number };

export type RestorableChromeWindowState =
  | "normal"
  | "maximized"
  | "fullscreen";

export type ChromeWindowAtStart = {
  windowId: number;
  state: RestorableChromeWindowState | "minimized";
};

export type MinimizedChromeWindow = {
  windowId: number;
  previousState: RestorableChromeWindowState;
};

export type ChromeActivationInput = {
  allowedWindowIds: number[];
  availableTabIds: number[];
  attemptedTabId: number;
  attemptedWindowId: number | undefined;
  lastActivatedTarget: ChromeTargetReference | null;
  now: number;
  lastFeedbackAt: number | null;
  feedbackIntervalMs: number;
};

export type ChromeActivationDecision = {
  restoreTarget: ChromeTargetReference | null;
  closeAttemptedTab: boolean;
  shouldNotify: boolean;
  nextFeedbackAt: number | null;
  nextLastActivatedTarget: ChromeTargetReference | null;
};

export type AvailableTabAtStart = {
  tabId: number;
  windowId: number;
  isActive: boolean;
};

export function chooseWindowsToMinimizeAtStart(
  windows: ChromeWindowAtStart[],
  coveredWindowIds: number[],
): MinimizedChromeWindow[] {
  const covered = new Set(coveredWindowIds);
  return windows.flatMap((window) =>
    covered.has(window.windowId) || window.state === "minimized"
      ? []
      : [{
          windowId: window.windowId,
          previousState: window.state,
        }]
  );
}

export function findInitiallyMinimizedWindowIds(
  windows: ChromeWindowAtStart[],
): number[] {
  return windows
    .filter((window) => window.state === "minimized")
    .map((window) => window.windowId);
}

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

export function decideChromeActivation(
  input: ChromeActivationInput,
): ChromeActivationDecision {
  if (
    input.attemptedWindowId !== undefined &&
    input.allowedWindowIds.includes(input.attemptedWindowId)
  ) {
    return {
      restoreTarget: null,
      closeAttemptedTab: false,
      shouldNotify: false,
      nextFeedbackAt: input.lastFeedbackAt,
      nextLastActivatedTarget: {
        type: "window",
        windowId: input.attemptedWindowId,
      },
    };
  }
  if (input.availableTabIds.includes(input.attemptedTabId)) {
    return {
      restoreTarget: null,
      closeAttemptedTab: false,
      shouldNotify: false,
      nextFeedbackAt: input.lastFeedbackAt,
      nextLastActivatedTarget: {
        type: "tab",
        tabId: input.attemptedTabId,
      },
    };
  }

  const restoreTarget = isAvailableReference(
    input.lastActivatedTarget,
    input.allowedWindowIds,
    input.availableTabIds,
  )
    ? input.lastActivatedTarget
    : input.allowedWindowIds[0] !== undefined
      ? { type: "window" as const, windowId: input.allowedWindowIds[0] }
      : input.availableTabIds[0] !== undefined
        ? { type: "tab" as const, tabId: input.availableTabIds[0] }
        : null;
  const shouldNotify =
    input.lastFeedbackAt === null ||
    input.now - input.lastFeedbackAt >= input.feedbackIntervalMs;
  return {
    restoreTarget,
    closeAttemptedTab: restoreTarget === null,
    shouldNotify,
    nextFeedbackAt: shouldNotify ? input.now : input.lastFeedbackAt,
    nextLastActivatedTarget: restoreTarget,
  };
}

function isAvailableReference(
  reference: ChromeTargetReference | null,
  allowedWindowIds: number[],
  availableTabIds: number[],
): reference is ChromeTargetReference {
  if (reference === null) {
    return false;
  }
  return reference.type === "window"
    ? allowedWindowIds.includes(reference.windowId)
    : availableTabIds.includes(reference.tabId);
}
