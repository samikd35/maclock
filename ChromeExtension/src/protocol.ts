import {
  requireChromeIdentifier,
  requireProfileIdentifier,
} from "./identifiers.js";

export const PROTOCOL_VERSION = 3 as const;
export const EXTENSION_ID = "hoofhoedlagpoclhkgnkmejaihaapoke";
export const NATIVE_HOST_NAME = "com.staypane.native_bridge";

export type HelloAcknowledged = {
  version: 3;
  type: "helloAck";
  profileId: string;
};

export type RequestTabs = {
  version: 3;
  type: "requestTabs";
  profileId: string;
};

export type CurrentWebsiteScopeCommand = {
  type: "currentWebsite";
  initialUrl: string;
};

export type ExactPageScopeCommand = {
  type: "exactPage";
  initialUrl: string;
};

export type NavigationScopeCommand =
  | CurrentWebsiteScopeCommand
  | ExactPageScopeCommand;

export type EnforcementTargetCommand = {
  tabId: number;
  windowId: number;
  navigationScope: NavigationScopeCommand;
};

export type BeginEnforcement = {
  version: 3;
  type: "beginEnforcement";
  profileId: string;
  targets: EnforcementTargetCommand[];
};

export type EndEnforcement = {
  version: 3;
  type: "endEnforcement";
  profileId: string;
};

export type NativeMessage =
  | HelloAcknowledged
  | RequestTabs
  | BeginEnforcement
  | EndEnforcement;

export type ExtensionTabSnapshot = {
  tabId: number;
  windowId: number;
  title: string;
  url: string;
  faviconDataUrl?: string;
  active: boolean;
  incognito: boolean;
};

export function makeHello(profileId: string) {
  requireProfileIdentifier(profileId);
  return {
    version: PROTOCOL_VERSION,
    type: "hello" as const,
    extensionId: EXTENSION_ID,
    profileId,
  };
}

export function makeTabsSnapshot(
  profileId: string,
  tabs: ExtensionTabSnapshot[],
) {
  requireProfileIdentifier(profileId);
  return {
    version: PROTOCOL_VERSION,
    type: "tabsSnapshot" as const,
    profileId,
    tabs,
  };
}

export function fitTabsToNativeMessageBudget(
  profileId: string,
  tabs: ExtensionTabSnapshot[],
  maximumBytes = 900_000,
): ExtensionTabSnapshot[] {
  requireProfileIdentifier(profileId);
  const fitted = tabs.slice(0, 10_000).map((tab) => ({ ...tab }));
  while (snapshotByteCount(profileId, fitted) > maximumBytes) {
    let faviconIndex = -1;
    for (let index = fitted.length - 1; index >= 0; index -= 1) {
      if (fitted[index]?.faviconDataUrl !== undefined) {
        faviconIndex = index;
        break;
      }
    }
    if (faviconIndex >= 0) {
      delete fitted[faviconIndex]?.faviconDataUrl;
    } else if (fitted.length > 0) {
      fitted.pop();
    } else {
      break;
    }
  }
  return fitted;
}

export function makeTabActivated(
  profileId: string,
  tabId: number,
  windowId: number,
) {
  requireProfileIdentifier(profileId);
  requireChromeIdentifier(tabId);
  requireChromeIdentifier(windowId);
  return {
    version: PROTOCOL_VERSION,
    type: "tabActivated" as const,
    profileId,
    tabId,
    windowId,
  };
}

export function makeBlockedTabActivation(
  profileId: string,
  attemptedTabId: number,
  availableTabId: number,
) {
  requireProfileIdentifier(profileId);
  requireChromeIdentifier(attemptedTabId);
  requireChromeIdentifier(availableTabId);
  return {
    version: PROTOCOL_VERSION,
    type: "blockedTabActivation" as const,
    profileId,
    attemptedTabId,
    availableTabId,
  };
}

export function makeBlockedNavigation(profileId: string, tabId: number) {
  requireProfileIdentifier(profileId);
  requireChromeIdentifier(tabId);
  return {
    version: PROTOCOL_VERSION,
    type: "blockedNavigation" as const,
    profileId,
    tabId,
  };
}

export function makeEnforcementStarted(
  profileId: string,
  tabIds: number[],
) {
  requireProfileIdentifier(profileId);
  requireUniqueChromeIdentifiers(tabIds);
  return {
    version: PROTOCOL_VERSION,
    type: "enforcementStarted" as const,
    profileId,
    tabIds,
  };
}

export function makeTabTargetClosed(profileId: string, tabId: number) {
  requireProfileIdentifier(profileId);
  requireChromeIdentifier(tabId);
  return {
    version: PROTOCOL_VERSION,
    type: "tabTargetClosed" as const,
    profileId,
    tabId,
  };
}

export function makeEnforcementError(
  profileId: string,
  code:
    | "targetMissing"
    | "targetNotReady"
    | "activationFailed"
    | "invalidCommand",
) {
  requireProfileIdentifier(profileId);
  return {
    version: PROTOCOL_VERSION,
    type: "enforcementError" as const,
    profileId,
    code,
  };
}

export function parseNativeMessage(value: unknown): NativeMessage {
  const record = requireRecord(value);
  if (record.version !== PROTOCOL_VERSION || typeof record.type !== "string") {
    throw new Error("Unsupported StayPane bridge message");
  }

  switch (record.type) {
    case "helloAck":
      requireExactKeys(record, ["version", "type", "profileId"]);
      return {
        version: PROTOCOL_VERSION,
        type: "helloAck",
        profileId: requireProfileIdentifier(record.profileId),
      };
    case "requestTabs":
      requireExactKeys(record, ["version", "type", "profileId"]);
      return {
        version: PROTOCOL_VERSION,
        type: "requestTabs",
        profileId: requireProfileIdentifier(record.profileId),
      };
    case "beginEnforcement":
      requireExactKeys(record, [
        "version",
        "type",
        "profileId",
        "targets",
      ]);
      return {
        version: PROTOCOL_VERSION,
        type: "beginEnforcement",
        profileId: requireProfileIdentifier(record.profileId),
        targets: requireEnforcementTargets(record.targets),
      };
    case "endEnforcement":
      requireExactKeys(record, ["version", "type", "profileId"]);
      return {
        version: PROTOCOL_VERSION,
        type: "endEnforcement",
        profileId: requireProfileIdentifier(record.profileId),
      };
    default:
      throw new Error("Unknown StayPane bridge message");
  }
}

function requireNavigationScope(
  value: unknown,
): NavigationScopeCommand {
  const record = requireRecord(value);
  requireExactKeys(record, ["type", "initialUrl"]);
  if (
    (record.type !== "currentWebsite" && record.type !== "exactPage") ||
    typeof record.initialUrl !== "string"
  ) {
    throw new Error("Invalid Navigation Scope");
  }
  const encoded = new TextEncoder().encode(record.initialUrl);
  let parsed: URL;
  try {
    parsed = new URL(record.initialUrl);
  } catch {
    throw new Error("Invalid Navigation Scope URL");
  }
  if (
    encoded.length === 0 ||
    encoded.length > 8_192 ||
    (parsed.protocol !== "http:" && parsed.protocol !== "https:") ||
    parsed.hostname.length === 0
  ) {
    throw new Error("Invalid Navigation Scope URL");
  }
  return {
    type: record.type,
    initialUrl: record.initialUrl,
  };
}

function requireEnforcementTargets(value: unknown): EnforcementTargetCommand[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > 128) {
    throw new Error("Invalid enforcement targets");
  }
  const targets = value.map((candidate) => {
    const record = requireRecord(candidate);
    requireExactKeys(record, ["tabId", "windowId", "navigationScope"]);
    return {
      tabId: requireChromeIdentifier(record.tabId),
      windowId: requireChromeIdentifier(record.windowId),
      navigationScope: requireNavigationScope(record.navigationScope),
    };
  });
  requireUniqueChromeIdentifiers(targets.map((target) => target.tabId));
  return targets;
}

function requireUniqueChromeIdentifiers(values: number[]): void {
  if (values.length === 0 || values.length > 128) {
    throw new Error("Invalid Chrome identifier set");
  }
  for (const value of values) {
    requireChromeIdentifier(value);
  }
  if (new Set(values).size !== values.length) {
    throw new Error("Duplicate Chrome identifier");
  }
}

function requireRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("Expected a bridge object");
  }
  return value as Record<string, unknown>;
}

function requireExactKeys(
  record: Record<string, unknown>,
  expected: string[],
): void {
  const actual = Object.keys(record).sort();
  const required = [...expected].sort();
  if (
    actual.length !== required.length ||
    actual.some((key, index) => key !== required[index])
  ) {
    throw new Error("Unexpected bridge fields");
  }
}

function snapshotByteCount(
  profileId: string,
  tabs: ExtensionTabSnapshot[],
): number {
  return new TextEncoder().encode(
    JSON.stringify(makeTabsSnapshot(profileId, tabs)),
  ).length;
}
