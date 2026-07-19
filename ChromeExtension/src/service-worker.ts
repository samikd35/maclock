import {
  BeginEnforcement,
  EXTENSION_ID,
  NATIVE_HOST_NAME,
  makeBlockedNavigation,
  makeBlockedTabActivation,
  makeBrowserWindowTargetClosed,
  makeEnforcementError,
  makeHello,
  makeTabActivated,
  makeEnforcementStarted,
  makeTabTargetClosed,
  makeTabsSnapshot,
  parseNativeMessage,
} from "./protocol.js";
import { isValidProfileIdentifier } from "./identifiers.js";
import { NativeCommandQueue } from "./native-command-queue.js";
import {
  closeTabIfPresent,
  isMissingChromeTabError,
} from "./chrome-tab-effects.js";
import {
  ChromeTargetEnforcement,
} from "./chrome-target-enforcement-store.js";
import {
  canStartNavigationEnforcement,
  createStartingNavigationScope,
  isWithinNavigationScope,
} from "./navigation-policy.js";
import {
  ChromeTargetEnforcementCoordinator,
  ChromeTargetEnforcementEvent,
} from "./chrome-target-enforcement.js";
import {
  RestorableChromeWindowState,
  chooseInitialAvailableTabsByWindow,
  chooseWindowsToMinimizeAtStart,
  findInitiallyMinimizedWindowIds,
} from "./tab-policy.js";
import { collectTabSnapshots } from "./tab-snapshot.js";

const PROFILE_STORAGE_KEY = "stayPaneProfileIdentifier";
const FEEDBACK_INTERVAL_MS = 2_000;
const OPENED_TAB_GRACE_MS = 2_000;

let nativePort: chrome.runtime.Port | null = null;
let connectedProfileIdentifier: string | null = null;
let reconnectTimer: number | null = null;
let snapshotTimer: number | null = null;
let restorationFailureReported = false;
const openedTabGraceTimers = new Map<number, number>();

const targetEnforcementCoordinator = new ChromeTargetEnforcementCoordinator({
  platform: {
    async navigateTab(tabId, url) {
      return performExistingTabEffect(async () => {
        await chrome.tabs.update(tabId, { url });
      });
    },
    async closeTab(tabId) {
      await closeTabIfPresent(tabId, {
        removeTab: async (candidateTabId) => chrome.tabs.remove(candidateTabId),
        tabExists: async (candidateTabId) =>
          performExistingTabEffect(async () => {
            await chrome.tabs.get(candidateTabId);
          }),
      });
    },
    async activateTab(tabId) {
      return activateTabAndWindow(tabId);
    },
    async activateWindow(windowId) {
      return activateChromeWindow(windowId);
    },
    async captureWindowState(windowId) {
      return captureChromeWindowState(windowId);
    },
    async minimizeWindow(windowId) {
      try {
        await chrome.windows.update(windowId, { state: "minimized" });
        return "minimized";
      } catch (error) {
        if (isMissingChromeWindowError(error)) {
          return "missing";
        }
        throw error;
      }
    },
    async restoreWindow(windowId, state) {
      try {
        await chrome.windows.update(windowId, { state });
        return "restored";
      } catch (error) {
        if (isMissingChromeWindowError(error)) {
          return "missing";
        }
        throw error;
      }
    },
    blockedNavigation(profileId, tabId) {
      showBlockedNavigationFeedback();
      nativePort?.postMessage(makeBlockedNavigation(profileId, tabId));
    },
    blockedTabActivation(profileId, attemptedTabId, availableTabId) {
      showBlockedFeedback(availableTabId === null);
      if (availableTabId !== null) {
        nativePort?.postMessage(
          makeBlockedTabActivation(profileId, attemptedTabId, availableTabId),
        );
      }
    },
    tabTargetClosed(profileId, tabId) {
      nativePort?.postMessage(makeTabTargetClosed(profileId, tabId));
    },
    browserWindowTargetClosed(profileId, windowId) {
      nativePort?.postMessage(
        makeBrowserWindowTargetClosed(profileId, windowId),
      );
    },
    restorationFailed() {
      restorationFailureReported = true;
    },
  },
  feedbackIntervalMs: FEEDBACK_INTERVAL_MS,
});

chrome.runtime.onInstalled.addListener(() => {
  void ensureNativeConnection();
});
chrome.runtime.onStartup.addListener(() => {
  void ensureNativeConnection();
});
chrome.tabs.onCreated.addListener((tab) => {
  scheduleSnapshot();
  void handleOpenedTab(tab);
});
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  scheduleSnapshot();
  if (changeInfo.url !== undefined) {
    void handleChromeTargetEnforcementEvent({
      type: "urlChanged",
      tabId,
      url: changeInfo.url,
    });
  }
  if (changeInfo.url !== undefined || changeInfo.status !== undefined) {
    void handleOpenedTab(tab, changeInfo.url);
  }
});
chrome.tabs.onRemoved.addListener((tabId) => {
  cancelOpenedTabGracePeriod(tabId);
  void handleChromeTargetEnforcementEvent({ type: "removed", tabId });
  scheduleSnapshot();
});
chrome.tabs.onActivated.addListener((activeInfo) => {
  void handleTabActivated(activeInfo.tabId, activeInfo.windowId);
  scheduleSnapshot();
});
chrome.tabs.onAttached.addListener((tabId, attachInfo) => {
  void handleAttachedTab(tabId, attachInfo.newWindowId);
  scheduleSnapshot();
});
chrome.tabs.onDetached.addListener(() => scheduleSnapshot());
chrome.tabs.onReplaced.addListener((addedTabId, removedTabId) => {
  void handleChromeTargetEnforcementEvent({
    type: "replaced",
    addedTabId,
    removedTabId,
  });
  scheduleSnapshot();
});
chrome.windows.onFocusChanged.addListener((windowId) => {
  void handleChromeWindowFocused(windowId);
});
chrome.windows.onBoundsChanged.addListener(() => scheduleSnapshot());
chrome.windows.onRemoved.addListener((windowId) => {
  void handleChromeTargetEnforcementEvent({ type: "windowRemoved", windowId });
  scheduleSnapshot();
});
chrome.webNavigation.onCommitted.addListener((details) => {
  void handleChromeTargetEnforcementEvent(
    makeDocumentNavigationEvent("committed", details),
  );
});
chrome.webNavigation.onCompleted.addListener((details) => {
  void handleChromeTargetEnforcementEvent(
    makeDocumentNavigationEvent("completed", details),
  );
});
chrome.webNavigation.onHistoryStateUpdated.addListener((details) => {
  void handleChromeTargetEnforcementEvent(
    makeDocumentNavigationEvent("historyUpdated", details),
  );
});
chrome.webNavigation.onReferenceFragmentUpdated.addListener((details) => {
  void handleChromeTargetEnforcementEvent(
    makeDocumentNavigationEvent("historyUpdated", details),
  );
});
chrome.webNavigation.onCreatedNavigationTarget.addListener((details) => {
  void handleOpenedTabObservation({
    tabId: details.tabId,
    sourceTabId: details.sourceTabId,
    pendingUrl: details.url,
    url: undefined,
  });
});

void bootstrapExtension();

async function bootstrapExtension(): Promise<void> {
  restorationFailureReported = false;
  await targetEnforcementCoordinator.retryPendingRestoration();
  if (restorationFailureReported) {
    await showRestorationFailureFeedback();
  }
  await ensureNativeConnection();
}

async function ensureNativeConnection(): Promise<void> {
  if (nativePort !== null) {
    return;
  }
  const profileIdentifier = await loadProfileIdentifier();
  try {
    const incognitoWindowControl = await chrome.extension
      .isAllowedIncognitoAccess();
    const port = chrome.runtime.connectNative(NATIVE_HOST_NAME);
    nativePort = port;
    connectedProfileIdentifier = null;
    const commandQueue = new NativeCommandQueue(
      async () => handleNativePortUnavailable(port),
    );
    port.onMessage.addListener((message: unknown) => {
      commandQueue.enqueue(async () => {
        await handleNativeMessage(port, profileIdentifier, message);
      });
    });
    port.onDisconnect.addListener(() => {
      void chrome.runtime.lastError;
      commandQueue.enqueue(
        async () => handleNativePortUnavailable(port),
      );
    });
    port.postMessage(makeHello(profileIdentifier, {
      incognitoWindowControl,
    }));
  } catch {
    nativePort = null;
    connectedProfileIdentifier = null;
    await stopChromeTargetEnforcement();
    scheduleReconnect();
  }
}

async function handleNativePortUnavailable(
  port: chrome.runtime.Port,
): Promise<void> {
  const wasCurrentConnection = nativePort === port;
  if (wasCurrentConnection) {
    nativePort = null;
    connectedProfileIdentifier = null;
  }
  port.disconnect();
  if (!wasCurrentConnection) {
    return;
  }
  try {
    await stopChromeTargetEnforcement();
  } finally {
    scheduleReconnect();
  }
}

function scheduleReconnect(): void {
  if (reconnectTimer !== null) {
    return;
  }
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    void ensureNativeConnection();
  }, 2_000);
}

async function handleNativeMessage(
  port: chrome.runtime.Port,
  expectedProfileIdentifier: string,
  rawMessage: unknown,
): Promise<void> {
  const message = parseNativeMessage(rawMessage);
  if (message.profileId !== expectedProfileIdentifier) {
    throw new Error("Chrome profile mismatch");
  }
  if (message.type === "helloAck") {
    connectedProfileIdentifier = message.profileId;
    return;
  }
  if (connectedProfileIdentifier !== message.profileId) {
    throw new Error("Command received before handshake");
  }

  switch (message.type) {
    case "requestTabs":
      await publishTabs();
      break;
    case "beginEnforcement":
      await beginEnforcement(message);
      break;
    case "endEnforcement":
      await stopChromeTargetEnforcement();
      break;
  }
}

async function beginEnforcement(
  command: BeginEnforcement,
): Promise<void> {
  if (!(await chrome.extension.isAllowedIncognitoAccess())) {
    sendEnforcementError(command.profileId, "invalidCommand");
    return;
  }
  const windowCommands = command.targets.filter(
    (target): target is Extract<
      BeginEnforcement["targets"][number],
      { type: "window" }
    > => target.type === "window",
  );
  const tabCommands = command.targets.filter(
    (target): target is Extract<
      BeginEnforcement["targets"][number],
      { type: "tab" }
    > => target.type === "tab",
  );
  let resolvedWindows: Array<{
    commandTarget: (typeof windowCommands)[number];
    window: chrome.windows.Window;
  }>;
  let resolvedTabs: Array<{
    commandTarget: (typeof tabCommands)[number];
    tab: chrome.tabs.Tab;
  }>;
  try {
    [resolvedWindows, resolvedTabs] = await Promise.all([
      Promise.all(
        windowCommands.map(async (commandTarget) => ({
          commandTarget,
          window: await chrome.windows.get(commandTarget.windowId),
        })),
      ),
      Promise.all(
        tabCommands.map(async (commandTarget) => ({
        commandTarget,
        tab: await chrome.tabs.get(commandTarget.tabId),
        })),
      ),
    ]);
  } catch {
    sendEnforcementError(command.profileId, "targetMissing");
    return;
  }
  if (
    resolvedWindows.some(({ commandTarget, window }) =>
      window.incognito || window.id !== commandTarget.windowId) ||
    resolvedTabs.some(({ commandTarget, tab }) => {
    return (
      tab.incognito ||
      tab.windowId !== commandTarget.windowId ||
      tab.id !== commandTarget.tabId
    );
    })
  ) {
    sendEnforcementError(command.profileId, "targetMissing");
    return;
  }

  try {
    const startingTargets = resolvedTabs.map(({ commandTarget, tab }) => ({
      commandTarget,
      tab,
      startingScope: {
        type: commandTarget.navigationScope.type,
        initialUrl: commandTarget.navigationScope.initialUrl,
        liveUrl: tab.url,
        liveDocumentIsComplete: tab.status === "complete",
      },
    }));
    if (startingTargets.some(
      ({ startingScope }) => !canStartNavigationEnforcement(startingScope),
    )) {
      sendEnforcementError(command.profileId, "targetNotReady");
      return;
    }
    const preparedTargets = startingTargets.map((startingTarget) => ({
      ...startingTarget,
      availableTarget: {
        tabId: startingTarget.commandTarget.tabId,
        windowId: startingTarget.commandTarget.windowId,
        navigationScope: createStartingNavigationScope(
          startingTarget.startingScope,
        ),
      },
    }));
    const focusedWindowTarget = resolvedWindows.find(
      ({ window }) => window.focused,
    );
    const activeTabTarget = preparedTargets.find(({ tab }) => tab.active);
    const coveredWindowIds = [
      ...resolvedWindows.map(({ commandTarget }) => commandTarget.windowId),
      ...preparedTargets.map(({ availableTarget }) => availableTarget.windowId),
    ];
    const windowStatesAtStart = (await chrome.windows.getAll()).flatMap(
      (window) => {
        const state = restorableChromeWindowState(window.state);
        return window.id === undefined || state === null
          ? []
          : [{
              windowId: window.id,
              state,
              incognito: window.incognito,
            }];
      },
    );
    const windowsToMinimize = chooseWindowsToMinimizeAtStart(
      windowStatesAtStart,
      coveredWindowIds,
    );
    const initialTarget = focusedWindowTarget !== undefined
      ? {
          type: "window" as const,
          windowId: focusedWindowTarget.commandTarget.windowId,
        }
      : activeTabTarget !== undefined
        ? {
            type: "tab" as const,
            tabId: activeTabTarget.availableTarget.tabId,
          }
        : resolvedWindows[0] !== undefined
          ? {
              type: "window" as const,
              windowId: resolvedWindows[0].commandTarget.windowId,
            }
          : preparedTargets[0] !== undefined
            ? {
                type: "tab" as const,
                tabId: preparedTargets[0].availableTarget.tabId,
              }
            : null;
    const enforcement: ChromeTargetEnforcement = {
      state: "active",
      profileId: command.profileId,
      allowedWindowIds: resolvedWindows.map(
        ({ commandTarget }) => commandTarget.windowId,
      ),
      initiallyMinimizedWindowIds: findInitiallyMinimizedWindowIds(
        windowStatesAtStart,
      ),
      minimizedWindows: windowsToMinimize,
      availableTargets: preparedTargets.map(
        ({ availableTarget }) => availableTarget,
      ),
      lastActivatedTarget: initialTarget,
    };
    await targetEnforcementCoordinator.start(enforcement, async () => {
      for (const window of windowsToMinimize) {
        await chrome.windows.update(window.windowId, { state: "minimized" });
      }
      for (const { tab, availableTarget } of preparedTargets) {
        const liveURL = tab.url;
        if (
          liveURL === undefined ||
          !isWithinNavigationScope(
            availableTarget.navigationScope,
            liveURL,
          )
        ) {
          await chrome.tabs.update(availableTarget.tabId, {
            url: availableTarget.navigationScope.lastAllowedUrl,
          });
        }
      }
      const initialTabsByWindow = chooseInitialAvailableTabsByWindow(
        preparedTargets.map(({ tab, availableTarget }) => ({
          tabId: availableTarget.tabId,
          windowId: availableTarget.windowId,
          isActive: tab.active,
        })),
      );
      for (const tabId of initialTabsByWindow) {
        await chrome.tabs.update(tabId, { active: true });
      }
      const initialTarget = enforcement.lastActivatedTarget;
      if (initialTarget === null) {
        throw new Error("Atomic enforcement requires at least one target");
      }
      const didActivate = initialTarget.type === "window"
        ? (await activateChromeWindow(initialTarget.windowId)) !== null
        : await activateTabAndWindow(initialTarget.tabId);
      if (!didActivate) {
        throw new Error(
          "Initial browser target disappeared during activation",
        );
      }
      nativePort?.postMessage(
        makeEnforcementStarted(
          enforcement.profileId,
          enforcement.allowedWindowIds,
          enforcement.availableTargets.map((target) => target.tabId),
        ),
      );
    });
  } catch {
    await stopChromeTargetEnforcement();
    sendEnforcementError(command.profileId, "activationFailed");
  }
}

function makeDocumentNavigationEvent(
  type: "committed" | "completed" | "historyUpdated",
  details: chrome.webNavigation.WebNavigationFramedCallbackDetails,
): ChromeTargetEnforcementEvent {
  return {
    type,
    tabId: details.tabId,
    frameId: details.frameId,
    documentId:
      details.documentId ??
      `legacy:${details.processId}:${details.frameId}:${details.url}`,
    url: details.url,
  };
}

async function handleOpenedTab(
  tab: chrome.tabs.Tab,
  observedUrl?: string,
): Promise<void> {
  if (tab.id === undefined) {
    return;
  }
  await handleOpenedTabObservation({
    tabId: tab.id,
    windowId: tab.windowId,
    sourceTabId: tab.openerTabId,
    pendingUrl: observedUrl ?? tab.pendingUrl,
    url: tab.url,
  });
}

async function handleOpenedTabObservation(
  observation: Omit<
    Extract<ChromeTargetEnforcementEvent, { type: "openedTab" }>,
    "type"
  >,
): Promise<void> {
  const candidateUrl = observation.pendingUrl ?? observation.url;
  if (
    candidateUrl === undefined ||
    candidateUrl === "" ||
    candidateUrl === "about:blank"
  ) {
    scheduleOpenedTabGracePeriod(observation.tabId);
  } else {
    cancelOpenedTabGracePeriod(observation.tabId);
  }
  await handleChromeTargetEnforcementEvent({
    type: "openedTab",
    ...observation,
  });
}

function scheduleOpenedTabGracePeriod(tabId: number): void {
  cancelOpenedTabGracePeriod(tabId);
  openedTabGraceTimers.set(
    tabId,
    setTimeout(() => {
      openedTabGraceTimers.delete(tabId);
      void handleChromeTargetEnforcementEvent({
        type: "openedTabGraceExpired",
        tabId,
      });
    }, OPENED_TAB_GRACE_MS),
  );
}

function cancelOpenedTabGracePeriod(tabId: number): void {
  const timer = openedTabGraceTimers.get(tabId);
  if (timer !== undefined) {
    clearTimeout(timer);
    openedTabGraceTimers.delete(tabId);
  }
}

function clearOpenedTabGracePeriods(): void {
  for (const timer of openedTabGraceTimers.values()) {
    clearTimeout(timer);
  }
  openedTabGraceTimers.clear();
}

async function handleChromeTargetEnforcementEvent(
  event: ChromeTargetEnforcementEvent,
): Promise<void> {
  try {
    await targetEnforcementCoordinator.handle(event);
  } catch {
    await failOpenAfterNavigationFailure();
  }
}

async function failOpenAfterNavigationFailure(): Promise<void> {
  const failedPort = nativePort;
  const failedProfileIdentifier = connectedProfileIdentifier;
  try {
    try {
      await stopChromeTargetEnforcement();
    } catch {
      // The bridge disconnect below is the authoritative Fail Open signal.
    }
    if (failedPort !== null && failedProfileIdentifier !== null) {
      try {
        failedPort.postMessage(
          makeEnforcementError(failedProfileIdentifier, "activationFailed"),
        );
      } catch {
        // Disconnect still reports enforcement loss to StayPane.
      }
    }
  } finally {
    if (nativePort === failedPort) {
      nativePort = null;
      connectedProfileIdentifier = null;
    }
    try {
      failedPort?.disconnect();
    } finally {
      scheduleReconnect();
    }
  }
}

async function handleTabActivated(
  attemptedTabId: number,
  attemptedWindowId: number,
): Promise<void> {
  await handleChromeTargetEnforcementEvent({
    type: "activated",
    tabId: attemptedTabId,
    windowId: attemptedWindowId,
  });
  await ensureNativeConnection();
  const profileIdentifier = connectedProfileIdentifier;
  if (profileIdentifier !== null) {
    nativePort?.postMessage(
      makeTabActivated(profileIdentifier, attemptedTabId, attemptedWindowId),
    );
  }
}

async function handleAttachedTab(
  tabId: number,
  windowId: number,
): Promise<void> {
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  await handleChromeTargetEnforcementEvent({
    type: "attached",
    tabId,
    windowId,
    ...(tab?.url === undefined ? {} : { url: tab.url }),
    isActive: tab?.active === true,
  });
}

async function handleChromeWindowFocused(windowId: number): Promise<void> {
  if (windowId === chrome.windows.WINDOW_ID_NONE) {
    return;
  }
  const [activeTab] = await chrome.tabs.query({ active: true, windowId });
  if (activeTab?.id !== undefined) {
    await handleTabActivated(activeTab.id, windowId);
  }
}

async function activateTabAndWindow(tabId: number): Promise<boolean> {
  return performExistingTabEffect(async () => {
    const tab = await chrome.tabs.get(tabId);
    await chrome.tabs.update(tabId, { active: true });
    await chrome.windows.update(tab.windowId, { focused: true });
  });
}

async function activateChromeWindow(windowId: number): Promise<number | null> {
  try {
    const [activeTab] = await chrome.tabs.query({ active: true, windowId });
    await chrome.windows.update(windowId, { focused: true });
    return activeTab?.id ?? null;
  } catch {
    return null;
  }
}

async function captureChromeWindowState(
  windowId: number,
): Promise<RestorableChromeWindowState | null> {
  try {
    const state = restorableChromeWindowState(
      (await chrome.windows.get(windowId)).state,
    );
    return state === "minimized" ? null : state;
  } catch {
    return null;
  }
}

function restorableChromeWindowState(
  state: unknown,
): RestorableChromeWindowState | "minimized" | null {
  switch (state) {
    case "normal":
    case "maximized":
    case "fullscreen":
    case "minimized":
      return state;
    default:
      return null;
  }
}

function isMissingChromeWindowError(error: unknown): boolean {
  return error instanceof Error &&
    /No window with id/i.test(error.message);
}

async function performExistingTabEffect(
  effect: () => Promise<void>,
): Promise<boolean> {
  try {
    await effect();
    return true;
  } catch (error) {
    if (isMissingChromeTabError(error)) {
      return false;
    }
    throw error;
  }
}

function scheduleSnapshot(): void {
  if (snapshotTimer !== null) {
    clearTimeout(snapshotTimer);
  }
  snapshotTimer = setTimeout(() => {
    snapshotTimer = null;
    void publishTabs();
  }, 150);
}

async function publishTabs(): Promise<void> {
  const profileIdentifier = connectedProfileIdentifier;
  if (nativePort === null || profileIdentifier === null) {
    return;
  }
  nativePort.postMessage(
    makeTabsSnapshot(
      profileIdentifier,
      await collectTabSnapshots(profileIdentifier),
    ),
  );
}

async function loadProfileIdentifier(): Promise<string> {
  const stored = await chrome.storage.local.get(PROFILE_STORAGE_KEY);
  const existing = stored[PROFILE_STORAGE_KEY];
  if (
    isValidProfileIdentifier(existing)
  ) {
    return existing;
  }
  const created = `profile_${crypto.randomUUID().replaceAll("-", "_")}`;
  await chrome.storage.local.set({ [PROFILE_STORAGE_KEY]: created });
  return created;
}

async function stopChromeTargetEnforcement(): Promise<void> {
  clearOpenedTabGracePeriods();
  restorationFailureReported = false;
  await targetEnforcementCoordinator.stop();
  if (restorationFailureReported) {
    await showRestorationFailureFeedback();
    return;
  }
  await chrome.action.setBadgeText({ text: "" });
  await chrome.action.setTitle({ title: "StayPane Chrome Companion" });
}

async function showRestorationFailureFeedback(): Promise<void> {
  await chrome.action.setBadgeBackgroundColor({ color: "#B91C1C" });
  await chrome.action.setBadgeText({ text: "!" });
  await chrome.action.setTitle({
    title: "StayPane could not restore one or more Chrome windows. It retained their local Restoration state and will retry.",
  });
}

function sendEnforcementError(
  profileIdentifier: string,
  code:
    | "targetMissing"
    | "targetNotReady"
    | "activationFailed"
    | "invalidCommand",
): void {
  nativePort?.postMessage(makeEnforcementError(profileIdentifier, code));
}

function showBlockedFeedback(noTargetsRemain = false): void {
  void chrome.action.setBadgeBackgroundColor({ color: "#C2410C" });
  void chrome.action.setBadgeText({ text: "↩" });
  if (noTargetsRemain) {
    void chrome.action.setTitle({
      title: "StayPane rejected the Blocked Tab Activation because no Available Browser Window Targets or Available Tab Targets remain.",
    });
  }
  setTimeout(() => {
    void chrome.action.setBadgeText({ text: "" });
    void chrome.action.setTitle({ title: "StayPane Chrome Companion" });
  }, 1_200);
}

function showBlockedNavigationFeedback(): void {
  void chrome.action.setBadgeBackgroundColor({ color: "#C2410C" });
  void chrome.action.setBadgeText({ text: "SITE" });
  void chrome.action.setTitle({
    title: "StayPane returned the Tab Target to its Navigation Scope.",
  });
  setTimeout(() => {
    void chrome.action.setBadgeText({ text: "" });
    void chrome.action.setTitle({ title: "StayPane Chrome Companion" });
  }, 1_200);
}

if (chrome.runtime.id !== EXTENSION_ID) {
  void stopChromeTargetEnforcement();
}
