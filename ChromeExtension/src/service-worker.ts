import {
  BeginEnforcement,
  EXTENSION_ID,
  NATIVE_HOST_NAME,
  makeBlockedNavigation,
  makeBlockedTabActivation,
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
  TabActivationEnforcement,
} from "./tab-activation-store.js";
import {
  canStartNavigationEnforcement,
  createStartingNavigationScope,
  isWithinNavigationScope,
} from "./navigation-policy.js";
import {
  ChromeTabEnforcementCoordinator,
  ChromeTabEnforcementEvent,
} from "./navigation-enforcement.js";
import { chooseInitialAvailableTabsByWindow } from "./tab-policy.js";
import { collectTabSnapshots } from "./tab-snapshot.js";

const PROFILE_STORAGE_KEY = "stayPaneProfileIdentifier";
const FEEDBACK_INTERVAL_MS = 2_000;
const OPENED_TAB_GRACE_MS = 2_000;

let nativePort: chrome.runtime.Port | null = null;
let connectedProfileIdentifier: string | null = null;
let reconnectTimer: number | null = null;
let snapshotTimer: number | null = null;
const openedTabGraceTimers = new Map<number, number>();

const tabEnforcementCoordinator = new ChromeTabEnforcementCoordinator({
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
    void handleChromeTabEnforcementEvent({
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
  void handleChromeTabEnforcementEvent({ type: "removed", tabId });
  scheduleSnapshot();
});
chrome.tabs.onActivated.addListener((activeInfo) => {
  void handleTabActivated(activeInfo.tabId, activeInfo.windowId);
});
chrome.tabs.onAttached.addListener((tabId, attachInfo) => {
  void handleChromeTabEnforcementEvent({
    type: "attached",
    tabId,
    windowId: attachInfo.newWindowId,
  });
  scheduleSnapshot();
});
chrome.tabs.onDetached.addListener(() => scheduleSnapshot());
chrome.tabs.onReplaced.addListener((addedTabId, removedTabId) => {
  void handleChromeTabEnforcementEvent({
    type: "replaced",
    addedTabId,
    removedTabId,
  });
  scheduleSnapshot();
});
chrome.windows.onFocusChanged.addListener((windowId) => {
  void handleChromeWindowFocused(windowId);
});
chrome.webNavigation.onCommitted.addListener((details) => {
  void handleChromeTabEnforcementEvent(
    makeDocumentNavigationEvent("committed", details),
  );
});
chrome.webNavigation.onCompleted.addListener((details) => {
  void handleChromeTabEnforcementEvent(
    makeDocumentNavigationEvent("completed", details),
  );
});
chrome.webNavigation.onHistoryStateUpdated.addListener((details) => {
  void handleChromeTabEnforcementEvent(
    makeDocumentNavigationEvent("historyUpdated", details),
  );
});
chrome.webNavigation.onReferenceFragmentUpdated.addListener((details) => {
  void handleChromeTabEnforcementEvent(
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

void ensureNativeConnection();

async function ensureNativeConnection(): Promise<void> {
  if (nativePort !== null) {
    return;
  }
  const profileIdentifier = await loadProfileIdentifier();
  try {
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
    port.postMessage(makeHello(profileIdentifier));
  } catch {
    nativePort = null;
    connectedProfileIdentifier = null;
    await stopTabActivationEnforcement();
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
    await stopTabActivationEnforcement();
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
      await stopTabActivationEnforcement();
      break;
  }
}

async function beginEnforcement(
  command: BeginEnforcement,
): Promise<void> {
  let resolvedTargets: Array<{
    commandTarget: BeginEnforcement["targets"][number];
    tab: chrome.tabs.Tab;
  }>;
  try {
    resolvedTargets = await Promise.all(
      command.targets.map(async (commandTarget) => ({
        commandTarget,
        tab: await chrome.tabs.get(commandTarget.tabId),
      })),
    );
  } catch {
    sendEnforcementError(command.profileId, "targetMissing");
    return;
  }
  if (resolvedTargets.some(({ commandTarget, tab }) => {
    return (
      tab.incognito ||
      tab.windowId !== commandTarget.windowId ||
      tab.id !== commandTarget.tabId
    );
  })) {
    sendEnforcementError(command.profileId, "targetMissing");
    return;
  }

  try {
    const startingTargets = resolvedTargets.map(({ commandTarget, tab }) => ({
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
    const enforcement: TabActivationEnforcement = {
      profileId: command.profileId,
      availableTargets: preparedTargets.map(
        ({ availableTarget }) => availableTarget,
      ),
      lastActivatedAvailableTabId:
        preparedTargets.find(({ tab }) => tab.active)?.availableTarget.tabId ??
        preparedTargets[0]!.availableTarget.tabId,
    };
    await tabEnforcementCoordinator.start(enforcement, async () => {
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
      const initialAvailableTabId = enforcement.lastActivatedAvailableTabId;
      if (initialAvailableTabId === null) {
        throw new Error("Atomic enforcement requires at least one target");
      }
      if (!(await activateTabAndWindow(initialAvailableTabId))) {
        throw new Error(
          "Initial Available Tab Target disappeared during activation",
        );
      }
      nativePort?.postMessage(
        makeEnforcementStarted(
          enforcement.profileId,
          enforcement.availableTargets.map((target) => target.tabId),
        ),
      );
    });
  } catch {
    await stopTabActivationEnforcement();
    sendEnforcementError(command.profileId, "activationFailed");
  }
}

function makeDocumentNavigationEvent(
  type: "committed" | "completed" | "historyUpdated",
  details: chrome.webNavigation.WebNavigationFramedCallbackDetails,
): ChromeTabEnforcementEvent {
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
    sourceTabId: tab.openerTabId,
    pendingUrl: observedUrl ?? tab.pendingUrl,
    url: tab.url,
  });
}

async function handleOpenedTabObservation(
  observation: Omit<
    Extract<ChromeTabEnforcementEvent, { type: "openedTab" }>,
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
  await handleChromeTabEnforcementEvent({
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
      void handleChromeTabEnforcementEvent({
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

async function handleChromeTabEnforcementEvent(
  event: ChromeTabEnforcementEvent,
): Promise<void> {
  try {
    await tabEnforcementCoordinator.handle(event);
  } catch {
    await failOpenAfterNavigationFailure();
  }
}

async function failOpenAfterNavigationFailure(): Promise<void> {
  const failedPort = nativePort;
  const failedProfileIdentifier = connectedProfileIdentifier;
  try {
    try {
      clearOpenedTabGracePeriods();
      await tabEnforcementCoordinator.stop();
      await chrome.action.setBadgeText({ text: "" });
      await chrome.action.setTitle({ title: "StayPane Chrome Companion" });
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
  await handleChromeTabEnforcementEvent({
    type: "activated",
    tabId: attemptedTabId,
  });
  await ensureNativeConnection();
  const profileIdentifier = connectedProfileIdentifier;
  if (profileIdentifier !== null) {
    nativePort?.postMessage(
      makeTabActivated(profileIdentifier, attemptedTabId, attemptedWindowId),
    );
  }
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

async function stopTabActivationEnforcement(): Promise<void> {
  clearOpenedTabGracePeriods();
  await tabEnforcementCoordinator.stop();
  await chrome.action.setBadgeText({ text: "" });
  await chrome.action.setTitle({ title: "StayPane Chrome Companion" });
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
      title: "StayPane rejected the Blocked Tab Activation because no Available Tab Targets remain.",
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
  void stopTabActivationEnforcement();
}
