const STORAGE_KEY = "stayPaneTabActivationEnforcement";

export type TabActivationEnforcement = {
  profileId: string;
  tabId: number;
  windowId: number;
};

export async function saveTabActivationEnforcement(
  enforcement: TabActivationEnforcement,
): Promise<void> {
  await chrome.storage.session.set({ [STORAGE_KEY]: enforcement });
}

export async function loadTabActivationEnforcement(): Promise<
  TabActivationEnforcement | null
> {
  const stored = await chrome.storage.session.get(STORAGE_KEY);
  const candidate = stored[STORAGE_KEY];
  if (typeof candidate !== "object" || candidate === null) {
    return null;
  }
  const value = candidate as Partial<TabActivationEnforcement>;
  if (
    typeof value.profileId !== "string" ||
    new TextEncoder().encode(value.profileId).length > 128 ||
    !/^[A-Za-z0-9_-]+$/.test(value.profileId) ||
    !Number.isSafeInteger(value.tabId) ||
    (value.tabId as number) < 0 ||
    !Number.isSafeInteger(value.windowId) ||
    (value.windowId as number) < 0
  ) {
    await clearTabActivationEnforcement();
    return null;
  }
  return value as TabActivationEnforcement;
}

export async function clearTabActivationEnforcement(): Promise<void> {
  await chrome.storage.session.remove(STORAGE_KEY);
}
