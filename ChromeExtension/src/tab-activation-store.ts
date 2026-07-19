import {
  isValidChromeIdentifier,
  isValidProfileIdentifier,
} from "./identifiers.js";
import {
  NavigationScope,
  isValidNavigationScope,
} from "./navigation-policy.js";

const STORAGE_KEY = "stayPaneTabActivationEnforcement";

export type AvailableTabTarget = {
  tabId: number;
  windowId: number;
  navigationScope: NavigationScope;
};

export type TabActivationEnforcement = {
  profileId: string;
  availableTargets: AvailableTabTarget[];
  lastActivatedAvailableTabId: number | null;
};

export type TabActivationStorePort = {
  get(key: string): Promise<Record<string, unknown>>;
  set(items: Record<string, unknown>): Promise<void>;
  remove(key: string): Promise<void>;
};

const chromeSessionStore: TabActivationStorePort = {
  get: async (key) => chrome.storage.session.get(key),
  set: async (items) => chrome.storage.session.set(items),
  remove: async (key) => chrome.storage.session.remove(key),
};

export async function saveTabActivationEnforcement(
  enforcement: TabActivationEnforcement,
  store: TabActivationStorePort = chromeSessionStore,
): Promise<void> {
  await store.set({ [STORAGE_KEY]: enforcement });
}

export async function loadTabActivationEnforcement(
  store: TabActivationStorePort = chromeSessionStore,
): Promise<TabActivationEnforcement | null> {
  const stored = await store.get(STORAGE_KEY);
  const candidate = stored[STORAGE_KEY];
  if (typeof candidate !== "object" || candidate === null) {
    return null;
  }
  if (!isValidTabActivationEnforcement(candidate)) {
    await clearTabActivationEnforcement(store);
    return null;
  }
  return candidate;
}

export async function clearTabActivationEnforcement(
  store: TabActivationStorePort = chromeSessionStore,
): Promise<void> {
  await store.remove(STORAGE_KEY);
}

function isValidTabActivationEnforcement(
  value: object,
): value is TabActivationEnforcement {
  const candidate = value as Record<string, unknown>;
  if (
    Object.keys(candidate).sort().join(",") !==
      "availableTargets,lastActivatedAvailableTabId,profileId" ||
    !isValidProfileIdentifier(candidate.profileId) ||
    !Array.isArray(candidate.availableTargets) ||
    candidate.availableTargets.length > 128 ||
    !(
      candidate.lastActivatedAvailableTabId === null ||
      isValidChromeIdentifier(candidate.lastActivatedAvailableTabId)
    )
  ) {
    return false;
  }
  const seenTabIdentifiers = new Set<number>();
  for (const target of candidate.availableTargets) {
    if (!isValidAvailableTabTarget(target)) {
      return false;
    }
    if (seenTabIdentifiers.has(target.tabId)) {
      return false;
    }
    seenTabIdentifiers.add(target.tabId);
  }
  return (
    candidate.lastActivatedAvailableTabId === null ||
    seenTabIdentifiers.has(candidate.lastActivatedAvailableTabId)
  );
}

function isValidAvailableTabTarget(
  value: unknown,
): value is AvailableTabTarget {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }
  const candidate = value as Record<string, unknown>;
  return (
    Object.keys(candidate).sort().join(",") ===
      "navigationScope,tabId,windowId" &&
    isValidChromeIdentifier(candidate.tabId) &&
    isValidChromeIdentifier(candidate.windowId) &&
    isValidNavigationScope(candidate.navigationScope)
  );
}
