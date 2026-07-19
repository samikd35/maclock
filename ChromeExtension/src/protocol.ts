import {
  requireChromeIdentifier,
  requireProfileIdentifier,
} from "./identifiers.js";

export const PROTOCOL_VERSION = 5 as const;
export const EXTENSION_ID = "hoofhoedlagpoclhkgnkmejaihaapoke";
export const NATIVE_HOST_NAME = "com.staypane.native_bridge";

export type HelloAcknowledged = {
  version: 5;
  type: "helloAck";
  profileId: string;
};

export type RequestTabs = {
  version: 5;
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

export type EnforcementWindowTargetCommand = {
  type: "window";
  windowId: number;
};

export type EnforcementTabTargetCommand = {
  type: "tab";
  tabId: number;
  windowId: number;
  navigationScope: NavigationScopeCommand;
};

export type EnforcementTargetCommand =
  | EnforcementWindowTargetCommand
  | EnforcementTabTargetCommand;

export type BeginEnforcement = {
  version: 5;
  type: "beginEnforcement";
  profileId: string;
  targets: EnforcementTargetCommand[];
};

export type EndEnforcement = {
  version: 5;
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
  windowBounds?: ExtensionWindowBounds;
  active: boolean;
  incognito: boolean;
};

export type ExtensionWindowBounds = {
  left: number;
  top: number;
  width: number;
  height: number;
};

export type ExtensionProfileCapabilities = {
  incognitoWindowControl: boolean;
};

export function makeHello(
  profileId: string,
  capabilities: ExtensionProfileCapabilities,
) {
  requireProfileIdentifier(profileId);
  return {
    version: PROTOCOL_VERSION,
    type: "hello" as const,
    extensionId: EXTENSION_ID,
    profileId,
    capabilities,
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
  windowIds: number[],
  tabIds: number[],
) {
  requireProfileIdentifier(profileId);
  requireUniqueChromeIdentifiers(windowIds, true);
  requireUniqueChromeIdentifiers(tabIds, true);
  if (windowIds.length + tabIds.length === 0) {
    throw new Error("Enforcement confirmation requires a target");
  }
  return {
    version: PROTOCOL_VERSION,
    type: "enforcementStarted" as const,
    profileId,
    windowIds,
    tabIds,
  };
}

export function makeBrowserWindowTargetClosed(
  profileId: string,
  windowId: number,
) {
  requireProfileIdentifier(profileId);
  requireChromeIdentifier(windowId);
  return {
    version: PROTOCOL_VERSION,
    type: "browserWindowTargetClosed" as const,
    profileId,
    windowId,
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
  const targets = value.map((candidate): EnforcementTargetCommand => {
    const record = requireRecord(candidate);
    if (record.type === "window") {
      requireExactKeys(record, ["type", "windowId"]);
      return {
        type: "window",
        windowId: requireChromeIdentifier(record.windowId),
      };
    }
    if (record.type === "tab") {
      requireExactKeys(record, [
        "type",
        "tabId",
        "windowId",
        "navigationScope",
      ]);
      return {
        type: "tab",
        tabId: requireChromeIdentifier(record.tabId),
        windowId: requireChromeIdentifier(record.windowId),
        navigationScope: requireNavigationScope(record.navigationScope),
      };
    }
    throw new Error("Invalid enforcement target type");
  });
  const windowIds = targets
    .filter((target): target is EnforcementWindowTargetCommand =>
      target.type === "window")
    .map((target) => target.windowId);
  const tabTargets = targets.filter(
    (target): target is EnforcementTabTargetCommand => target.type === "tab",
  );
  requireUniqueChromeIdentifiers(windowIds, true);
  requireUniqueChromeIdentifiers(
    tabTargets.map((target) => target.tabId),
    true,
  );
  if (tabTargets.some((target) => windowIds.includes(target.windowId))) {
    throw new Error("Redundant browser enforcement target");
  }
  return targets;
}

function requireUniqueChromeIdentifiers(
  values: number[],
  allowsEmpty = false,
): void {
  if ((!allowsEmpty && values.length === 0) || values.length > 128) {
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
