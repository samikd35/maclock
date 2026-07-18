import {
  EXTENSION_ID,
  NATIVE_HOST_NAME,
  ExtensionTabSnapshot,
  fitTabsToNativeMessageBudget,
  makeBlockedTabActivation,
  makeEnforcementError,
  makeHello,
  makeTabActivated,
  makeTabsSnapshot,
  parseNativeMessage,
} from "./protocol.js";
import { decideTabActivation } from "./tab-policy.js";

const PROFILE_STORAGE_KEY = "stayPaneProfileIdentifier";
const ENFORCEMENT_STORAGE_KEY = "stayPaneTabEnforcement";
const FEEDBACK_INTERVAL_MS = 2_000;

type Enforcement = {
  profileId: string;
  tabId: number;
  windowId: number;
};

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
    port.onMessage.addListener((message: unknown) => {
      void handleNativeMessage(port, profileIdentifier, message);
    });
    port.onDisconnect.addListener(() => {
      void chrome.runtime.lastError;
      if (nativePort === port) {
        nativePort = null;
        connectedProfileIdentifier = null;
        void clearEnforcement();
        scheduleReconnect();
      }
    });
    port.postMessage(makeHello(profileIdentifier));
  } catch {
    nativePort = null;
    connectedProfileIdentifier = null;
    await clearEnforcement();
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
  try {
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
        await clearEnforcement();
        break;
    }
  } catch {
    port.disconnect();
  }
}

async function beginEnforcement(enforcement: Enforcement): Promise<void> {
  try {
    const tab = await chrome.tabs.get(enforcement.tabId);
    if (
      tab.incognito ||
      tab.windowId !== enforcement.windowId ||
      tab.id !== enforcement.tabId
    ) {
      sendEnforcementError(enforcement.profileId, "targetMissing");
      return;
    }
    await chrome.storage.session.set({
      [ENFORCEMENT_STORAGE_KEY]: enforcement,
    });
    await activateAllowedTab(enforcement);
  } catch {
    sendEnforcementError(enforcement.profileId, "targetMissing");
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

  const enforcement = await loadEnforcement();
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
  const enforcement = await loadEnforcement();
  if (enforcement === null || windowId === enforcement.windowId) {
    return;
  }
  const [activeTab] = await chrome.tabs.query({ active: true, windowId });
  if (activeTab?.id !== undefined) {
    await handleTabActivated(activeTab.id, windowId);
  }
}

async function activateAllowedTab(enforcement: Enforcement): Promise<void> {
  await chrome.tabs.update(enforcement.tabId, { active: true });
  await chrome.windows.update(enforcement.windowId, { focused: true });
}

async function handleRemovedTab(tabId: number): Promise<void> {
  const enforcement = await loadEnforcement();
  if (enforcement?.tabId === tabId) {
    sendEnforcementError(enforcement.profileId, "targetMissing");
    await clearEnforcement();
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
  const tabs = await chrome.tabs.query({});
  const snapshots = await Promise.all(tabs.map(makeTabSnapshot));
  const eligibleTabs = snapshots.filter(
    (snapshot): snapshot is ExtensionTabSnapshot => snapshot !== null,
  );
  nativePort.postMessage(
    makeTabsSnapshot(
      profileIdentifier,
      fitTabsToNativeMessageBudget(profileIdentifier, eligibleTabs),
    ),
  );
}

async function makeTabSnapshot(
  tab: chrome.tabs.Tab,
): Promise<ExtensionTabSnapshot | null> {
  if (
    tab.id === undefined ||
    tab.id < 0 ||
    tab.windowId < 0 ||
    tab.url === undefined ||
    tab.url.length === 0
  ) {
    return null;
  }
  const title = boundedUtf8(tab.title ?? tab.url, 2_048);
  const url = boundedUtf8(tab.url, 8_192);
  const faviconDataUrl = await loadFaviconDataURL(tab.url);
  return {
    tabId: tab.id,
    windowId: tab.windowId,
    title,
    url,
    ...(faviconDataUrl === null ? {} : { faviconDataUrl }),
    active: tab.active,
    incognito: tab.incognito,
  };
}

async function loadFaviconDataURL(pageURL: string): Promise<string | null> {
  try {
    const faviconURL = new URL(chrome.runtime.getURL("/_favicon/"));
    faviconURL.searchParams.set("pageUrl", pageURL);
    faviconURL.searchParams.set("size", "32");
    const response = await fetch(faviconURL);
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (!response.ok || bytes.length === 0 || bytes.length > 48_000) {
      return null;
    }
    let binary = "";
    for (let offset = 0; offset < bytes.length; offset += 8_192) {
      binary += String.fromCharCode(...bytes.subarray(offset, offset + 8_192));
    }
    const value = `data:image/png;base64,${btoa(binary)}`;
    return new TextEncoder().encode(value).length <= 65_536 ? value : null;
  } catch {
    return null;
  }
}

async function loadProfileIdentifier(): Promise<string> {
  const stored = await chrome.storage.local.get(PROFILE_STORAGE_KEY);
  const existing = stored[PROFILE_STORAGE_KEY];
  if (
    typeof existing === "string" &&
    new TextEncoder().encode(existing).length <= 128 &&
    /^[A-Za-z0-9_-]+$/.test(existing)
  ) {
    return existing;
  }
  const created = `profile_${crypto.randomUUID().replaceAll("-", "_")}`;
  await chrome.storage.local.set({ [PROFILE_STORAGE_KEY]: created });
  return created;
}

async function loadEnforcement(): Promise<Enforcement | null> {
  const stored = await chrome.storage.session.get(ENFORCEMENT_STORAGE_KEY);
  const candidate = stored[ENFORCEMENT_STORAGE_KEY];
  if (typeof candidate !== "object" || candidate === null) {
    return null;
  }
  const value = candidate as Partial<Enforcement>;
  if (
    typeof value.profileId !== "string" ||
    new TextEncoder().encode(value.profileId).length > 128 ||
    !/^[A-Za-z0-9_-]+$/.test(value.profileId) ||
    !Number.isSafeInteger(value.tabId) ||
    (value.tabId as number) < 0 ||
    !Number.isSafeInteger(value.windowId) ||
    (value.windowId as number) < 0
  ) {
    await clearEnforcement();
    return null;
  }
  return value as Enforcement;
}

async function clearEnforcement(): Promise<void> {
  lastFeedbackAt = null;
  await chrome.storage.session.remove(ENFORCEMENT_STORAGE_KEY);
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

function boundedUtf8(value: string, maximumBytes: number): string {
  if (new TextEncoder().encode(value).length <= maximumBytes) {
    return value;
  }
  let result = value;
  while (
    result.length > 1 &&
    new TextEncoder().encode(result).length > maximumBytes
  ) {
    result = result.slice(0, Math.floor(result.length * 0.9));
  }
  return result.length === 0 ? "Untitled" : result;
}

if (chrome.runtime.id !== EXTENSION_ID) {
  void clearEnforcement();
}
