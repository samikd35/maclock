import {
  BeginEnforcement,
  EXTENSION_ID,
  NATIVE_HOST_NAME,
  makeBlockedNavigation,
  makeBlockedTabActivation,
  makeEnforcementError,
  makeHello,
  makeTabActivated,
  makeTabActivationStarted,
  makeTabsSnapshot,
  parseNativeMessage,
} from "./protocol.js";
import { isValidProfileIdentifier } from "./identifiers.js";
import { NativeCommandQueue } from "./native-command-queue.js";
import {
  TabActivationEnforcement,
  loadTabActivationEnforcement,
} from "./tab-activation-store.js";
import { decideTabActivation } from "./tab-policy.js";
import {
  createCurrentWebsiteScope,
  isWithinCurrentWebsite,
} from "./navigation-policy.js";
import {
  CurrentWebsiteNavigationEnforcer,
  NavigationEnforcementEvent,
} from "./navigation-enforcement.js";
import { collectTabSnapshots } from "./tab-snapshot.js";

const PROFILE_STORAGE_KEY = "stayPaneProfileIdentifier";
const FEEDBACK_INTERVAL_MS = 2_000;

let nativePort: chrome.runtime.Port | null = null;
let connectedProfileIdentifier: string | null = null;
let reconnectTimer: number | null = null;
let snapshotTimer: number | null = null;
let lastFeedbackAt: number | null = null;

const navigationEnforcer = new CurrentWebsiteNavigationEnforcer({
  platform: {
    async navigateTab(tabId, url) {
      await chrome.tabs.update(tabId, { url });
    },
    async closeTab(tabId) {
      await chrome.tabs.remove(tabId);
    },
    blockedNavigation(profileId, tabId) {
      showBlockedNavigationFeedback();
      nativePort?.postMessage(makeBlockedNavigation(profileId, tabId));
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
    void handleNavigationEvent({
      type: "urlChanged",
      tabId,
      url: changeInfo.url,
    });
  }
  if (
    tab.openerTabId !== undefined &&
    (changeInfo.url !== undefined || changeInfo.status !== undefined)
  ) {
    void handleOpenedTab(tab);
  }
});
chrome.tabs.onRemoved.addListener((tabId) => {
  void handleRemovedTab(tabId);
  scheduleSnapshot();
});
chrome.tabs.onActivated.addListener((activeInfo) => {
  void handleTabActivated(activeInfo.tabId, activeInfo.windowId);
});
chrome.tabs.onAttached.addListener(() => scheduleSnapshot());
chrome.tabs.onDetached.addListener(() => scheduleSnapshot());
chrome.windows.onFocusChanged.addListener((windowId) => {
  void handleChromeWindowFocused(windowId);
});
chrome.webNavigation.onCommitted.addListener((details) => {
  void handleNavigationEvent(makeDocumentNavigationEvent("committed", details));
});
chrome.webNavigation.onCompleted.addListener((details) => {
  void handleNavigationEvent(makeDocumentNavigationEvent("completed", details));
});
chrome.webNavigation.onHistoryStateUpdated.addListener((details) => {
  void handleNavigationEvent(
    makeDocumentNavigationEvent("historyUpdated", details),
  );
});
chrome.webNavigation.onReferenceFragmentUpdated.addListener((details) => {
  void handleNavigationEvent(
    makeDocumentNavigationEvent("historyUpdated", details),
  );
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
  let tab: chrome.tabs.Tab;
  try {
    tab = await chrome.tabs.get(command.tabId);
  } catch {
    sendEnforcementError(command.profileId, "targetMissing");
    return;
  }
  if (
    tab.incognito ||
    tab.windowId !== command.windowId ||
    tab.id !== command.tabId
  ) {
    sendEnforcementError(command.profileId, "targetMissing");
    return;
  }

  try {
    const navigationScope = createCurrentWebsiteScope(
      command.navigationScope.initialUrl,
    );
    if (
      tab.url !== undefined &&
      isWithinCurrentWebsite(navigationScope, tab.url)
    ) {
      navigationScope.lastAllowedUrl = new URL(tab.url).href;
    }
    const enforcement: TabActivationEnforcement = {
      profileId: command.profileId,
      tabId: command.tabId,
      windowId: command.windowId,
      navigationScope,
    };
    await navigationEnforcer.start(enforcement);
    if (
      tab.url === undefined ||
      !isWithinCurrentWebsite(navigationScope, tab.url)
    ) {
      await chrome.tabs.update(command.tabId, {
        url: navigationScope.lastAllowedUrl,
      });
    }
    await activateAllowedTab(enforcement);
    nativePort?.postMessage(
      makeTabActivationStarted(
        enforcement.profileId,
        enforcement.tabId,
        enforcement.windowId,
      ),
    );
  } catch {
    await stopTabActivationEnforcement();
    sendEnforcementError(command.profileId, "activationFailed");
  }
}

function makeDocumentNavigationEvent(
  type: "committed" | "completed" | "historyUpdated",
  details: chrome.webNavigation.WebNavigationFramedCallbackDetails,
): NavigationEnforcementEvent {
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

async function handleOpenedTab(tab: chrome.tabs.Tab): Promise<void> {
  if (tab.id === undefined) {
    return;
  }
  await handleNavigationEvent({
    type: "openedTab",
    tabId: tab.id,
    openerTabId: tab.openerTabId,
    pendingUrl: tab.pendingUrl,
    url: tab.url,
    isComplete: tab.status === "complete",
  });
}

async function handleNavigationEvent(
  event: NavigationEnforcementEvent,
): Promise<void> {
  try {
    await navigationEnforcer.handle(event);
  } catch {
    const enforcement = await loadTabActivationEnforcement();
    await stopTabActivationEnforcement();
    if (enforcement !== null) {
      sendEnforcementError(enforcement.profileId, "activationFailed");
    }
  }
}

async function handleTabActivated(
  attemptedTabId: number,
  attemptedWindowId: number,
): Promise<void> {
  await ensureNativeConnection();
  const profileIdentifier = connectedProfileIdentifier;
  if (profileIdentifier !== null) {
    nativePort?.postMessage(
      makeTabActivated(profileIdentifier, attemptedTabId, attemptedWindowId),
    );
  }

  const enforcement = await loadTabActivationEnforcement();
  if (enforcement === null) {
    return;
  }
  const decision = decideTabActivation({
    allowedTabId: enforcement.tabId,
    attemptedTabId,
    now: Date.now(),
    lastFeedbackAt,
    feedbackIntervalMs: FEEDBACK_INTERVAL_MS,
  });
  lastFeedbackAt = decision.nextFeedbackAt;
  if (decision.restoreTabId === null) {
    return;
  }

  try {
    await activateAllowedTab(enforcement);
    if (decision.shouldNotify) {
      showBlockedFeedback();
      nativePort?.postMessage(
        makeBlockedTabActivation(
          enforcement.profileId,
          attemptedTabId,
          enforcement.tabId,
        ),
      );
    }
  } catch {
    sendEnforcementError(enforcement.profileId, "activationFailed");
  }
}

async function handleChromeWindowFocused(windowId: number): Promise<void> {
  if (windowId === chrome.windows.WINDOW_ID_NONE) {
    return;
  }
  const enforcement = await loadTabActivationEnforcement();
  if (enforcement === null || windowId === enforcement.windowId) {
    return;
  }
  const [activeTab] = await chrome.tabs.query({ active: true, windowId });
  if (activeTab?.id !== undefined) {
    await handleTabActivated(activeTab.id, windowId);
  }
}

async function activateAllowedTab(
  enforcement: TabActivationEnforcement,
): Promise<void> {
  await chrome.tabs.update(enforcement.tabId, { active: true });
  await chrome.windows.update(enforcement.windowId, { focused: true });
}

async function handleRemovedTab(tabId: number): Promise<void> {
  const enforcement = await loadTabActivationEnforcement();
  if (enforcement?.tabId === tabId) {
    sendEnforcementError(enforcement.profileId, "targetMissing");
    await stopTabActivationEnforcement();
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
  lastFeedbackAt = null;
  await navigationEnforcer.stop();
  await chrome.action.setBadgeText({ text: "" });
  await chrome.action.setTitle({ title: "StayPane Chrome Companion" });
}

function sendEnforcementError(
  profileIdentifier: string,
  code: "targetMissing" | "activationFailed" | "invalidCommand",
): void {
  nativePort?.postMessage(makeEnforcementError(profileIdentifier, code));
}

function showBlockedFeedback(): void {
  void chrome.action.setBadgeBackgroundColor({ color: "#C2410C" });
  void chrome.action.setBadgeText({ text: "↩" });
  setTimeout(() => {
    void chrome.action.setBadgeText({ text: "" });
  }, 1_200);
}

function showBlockedNavigationFeedback(): void {
  void chrome.action.setBadgeBackgroundColor({ color: "#C2410C" });
  void chrome.action.setBadgeText({ text: "SITE" });
  void chrome.action.setTitle({
    title: "StayPane returned the selected tab to its Current Website.",
  });
  setTimeout(() => {
    void chrome.action.setBadgeText({ text: "" });
    void chrome.action.setTitle({ title: "StayPane Chrome Companion" });
  }, 1_200);
}

if (chrome.runtime.id !== EXTENSION_ID) {
  void stopTabActivationEnforcement();
}
