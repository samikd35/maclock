import {
  isValidChromeIdentifier,
  isValidProfileIdentifier,
} from "./identifiers.js";

const STORAGE_KEY = "stayPaneTabActivationEnforcement";

export type TabActivationEnforcement = {
  profileId: string;
  tabId: number;
  windowId: number;
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
  const value = candidate as Partial<TabActivationEnforcement>;
  if (
    !isValidProfileIdentifier(value.profileId) ||
    !isValidChromeIdentifier(value.tabId) ||
    !isValidChromeIdentifier(value.windowId)
  ) {
    await clearTabActivationEnforcement(store);
    return null;
  }
  return value as TabActivationEnforcement;
}

export async function clearTabActivationEnforcement(
  store: TabActivationStorePort = chromeSessionStore,
): Promise<void> {
  await store.remove(STORAGE_KEY);
}
