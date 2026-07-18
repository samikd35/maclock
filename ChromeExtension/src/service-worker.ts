import {
  EXTENSION_ID,
  NATIVE_HOST_NAME,
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
  clearTabActivationEnforcement,
  loadTabActivationEnforcement,
  saveTabActivationEnforcement,
} from "./tab-activation-store.js";
import { decideTabActivation } from "./tab-policy.js";
import { collectTabSnapshots } from "./tab-snapshot.js";

const PROFILE_STORAGE_KEY = "stayPaneProfileIdentifier";
const FEEDBACK_INTERVAL_MS = 2_000;

let nativePort: chrome.runtime.Port | null = null;
let connectedProfileIdentifier: string | null = null;
let reconnectTimer: number | null = null;
let snapshotTimer: number | null = null;
let lastFeedbackAt: number | null = null;

chrome.runtime.onInstalled.addListener(() => {
  void ensureNativeConnection();
});
chrome.runtime.onStartup.addListener(() => {
  void ensureNativeConnection();
});
chrome.tabs.onCreated.addListener(() => scheduleSnapshot());
chrome.tabs.onUpdated.addListener(() => scheduleSnapshot());
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
  enforcement: TabActivationEnforcement,
): Promise<void> {
  let tab: chrome.tabs.Tab;
  try {
    tab = await chrome.tabs.get(enforcement.tabId);
  } catch {
    sendEnforcementError(enforcement.profileId, "targetMissing");
    return;
  }
  if (
    tab.incognito ||
    tab.windowId !== enforcement.windowId ||
    tab.id !== enforcement.tabId
  ) {
    sendEnforcementError(enforcement.profileId, "targetMissing");
    return;
  }

  try {
    await saveTabActivationEnforcement(enforcement);
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
    sendEnforcementError(enforcement.profileId, "activationFailed");
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
  await clearTabActivationEnforcement();
  await chrome.action.setBadgeText({ text: "" });
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

if (chrome.runtime.id !== EXTENSION_ID) {
  void stopTabActivationEnforcement();
}
