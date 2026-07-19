import {
  isValidChromeIdentifier,
  isValidProfileIdentifier,
} from "./identifiers.js";
import {
  NavigationScope,
  isValidNavigationScope,
} from "./navigation-policy.js";
import {
  ChromeTargetReference,
  MinimizedChromeWindow,
  RestorableChromeWindowState,
} from "./tab-policy.js";

const STORAGE_KEY = "stayPaneChromeTargetEnforcement";

export type AvailableTabTarget = {
  tabId: number;
  windowId: number;
  navigationScope: NavigationScope;
};

export type ChromeTargetEnforcement = {
  state: "active";
  profileId: string;
  allowedWindowIds: number[];
  initiallyMinimizedWindowIds: number[];
  minimizedWindows: MinimizedChromeWindow[];
  availableTargets: AvailableTabTarget[];
  lastActivatedTarget: ChromeTargetReference | null;
};

export type PendingChromeWindowRestoration = {
  state: "restorationPending";
  profileId: string;
  initiallyMinimizedWindowIds: number[];
  minimizedWindows: MinimizedChromeWindow[];
};

export type StoredChromeTargetState =
  | ChromeTargetEnforcement
  | PendingChromeWindowRestoration;

export type ChromeTargetStateStorePort = {
  get(key: string): Promise<Record<string, unknown>>;
  set(items: Record<string, unknown>): Promise<void>;
  remove(key: string): Promise<void>;
};

const chromeSessionStore: ChromeTargetStateStorePort = {
  get: async (key) => chrome.storage.session.get(key),
  set: async (items) => chrome.storage.session.set(items),
  remove: async (key) => chrome.storage.session.remove(key),
};

export async function saveStoredChromeTargetState(
  state: StoredChromeTargetState,
  store: ChromeTargetStateStorePort = chromeSessionStore,
): Promise<void> {
  await store.set({ [STORAGE_KEY]: state });
}

export async function loadStoredChromeTargetState(
  store: ChromeTargetStateStorePort = chromeSessionStore,
): Promise<StoredChromeTargetState | null> {
  const stored = await store.get(STORAGE_KEY);
  const candidate = stored[STORAGE_KEY];
  if (typeof candidate !== "object" || candidate === null) {
    return null;
  }
  if (!isValidStoredChromeTargetState(candidate)) {
    await clearStoredChromeTargetState(store);
    return null;
  }
  return candidate;
}

export async function clearStoredChromeTargetState(
  store: ChromeTargetStateStorePort = chromeSessionStore,
): Promise<void> {
  await store.remove(STORAGE_KEY);
}

function isValidStoredChromeTargetState(
  value: object,
): value is StoredChromeTargetState {
  const candidate = value as Record<string, unknown>;
  if (candidate.state === "restorationPending") {
    return Object.keys(candidate).sort().join(",") ===
        "initiallyMinimizedWindowIds,minimizedWindows,profileId,state" &&
      hasValidRestorationState(candidate);
  }
  if (
    Object.keys(candidate).sort().join(",") !==
      "allowedWindowIds,availableTargets,initiallyMinimizedWindowIds,lastActivatedTarget,minimizedWindows,profileId,state" ||
    candidate.state !== "active" ||
    !hasValidRestorationState(candidate) ||
    !Array.isArray(candidate.allowedWindowIds) ||
    candidate.allowedWindowIds.length > 128 ||
    !Array.isArray(candidate.availableTargets) ||
    candidate.availableTargets.length > 128 ||
    !isValidLastActivatedTarget(candidate.lastActivatedTarget)
  ) {
    return false;
  }
  const allowedWindowIds = candidate.allowedWindowIds;
  if (
    allowedWindowIds.some((value) => !isValidChromeIdentifier(value)) ||
    new Set(allowedWindowIds).size !== allowedWindowIds.length
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
  const lastTarget = candidate.lastActivatedTarget;
  const lastTargetIsAvailable = lastTarget === null ||
    (lastTarget.type === "window"
      ? allowedWindowIds.includes(lastTarget.windowId)
      : seenTabIdentifiers.has(lastTarget.tabId));
  return lastTargetIsAvailable;
}

function hasValidRestorationState(candidate: Record<string, unknown>): boolean {
  if (
    !isValidProfileIdentifier(candidate.profileId) ||
    !Array.isArray(candidate.initiallyMinimizedWindowIds) ||
    candidate.initiallyMinimizedWindowIds.length > 128 ||
    !Array.isArray(candidate.minimizedWindows) ||
    candidate.minimizedWindows.length > 128
  ) {
    return false;
  }
  const initiallyMinimizedWindowIds = candidate.initiallyMinimizedWindowIds;
  const minimizedWindows = candidate.minimizedWindows;
  return initiallyMinimizedWindowIds.every(isValidChromeIdentifier) &&
    new Set(initiallyMinimizedWindowIds).size ===
      initiallyMinimizedWindowIds.length &&
    minimizedWindows.every(isValidMinimizedWindow) &&
    new Set(minimizedWindows.map((window) => window.windowId)).size ===
      minimizedWindows.length;
}

function isValidMinimizedWindow(
  value: unknown,
): value is MinimizedChromeWindow {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }
  const candidate = value as Record<string, unknown>;
  return Object.keys(candidate).sort().join(",") ===
      "previousState,windowId" &&
    isValidChromeIdentifier(candidate.windowId) &&
    isRestorableChromeWindowState(candidate.previousState);
}

function isRestorableChromeWindowState(
  value: unknown,
): value is RestorableChromeWindowState {
  return value === "normal" || value === "maximized" || value === "fullscreen";
}

function isValidLastActivatedTarget(
  value: unknown,
): value is ChromeTargetReference | null {
  if (value === null) {
    return true;
  }
  if (typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const candidate = value as Record<string, unknown>;
  if (candidate.type === "window") {
    return Object.keys(candidate).sort().join(",") === "type,windowId" &&
      isValidChromeIdentifier(candidate.windowId);
  }
  if (candidate.type === "tab") {
    return Object.keys(candidate).sort().join(",") === "tabId,type" &&
      isValidChromeIdentifier(candidate.tabId);
  }
  return false;
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
