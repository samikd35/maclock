export const PROTOCOL_VERSION = 1 as const;
export const EXTENSION_ID = "hoofhoedlagpoclhkgnkmejaihaapoke";
export const NATIVE_HOST_NAME = "com.staypane.native_bridge";

export type HelloAcknowledged = {
  version: 1;
  type: "helloAck";
  profileId: string;
};

export type RequestTabs = {
  version: 1;
  type: "requestTabs";
  profileId: string;
};

export type BeginEnforcement = {
  version: 1;
  type: "beginEnforcement";
  profileId: string;
  tabId: number;
  windowId: number;
};

export type EndEnforcement = {
  version: 1;
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
  requireIdentifier(tabId);
  requireIdentifier(windowId);
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
  allowedTabId: number,
) {
  requireProfileIdentifier(profileId);
  requireIdentifier(attemptedTabId);
  requireIdentifier(allowedTabId);
  return {
    version: PROTOCOL_VERSION,
    type: "blockedTabActivation" as const,
    profileId,
    attemptedTabId,
    allowedTabId,
  };
}

export function makeEnforcementError(
  profileId: string,
  code: "targetMissing" | "activationFailed" | "invalidCommand",
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
        "tabId",
        "windowId",
      ]);
      return {
        version: PROTOCOL_VERSION,
        type: "beginEnforcement",
        profileId: requireProfileIdentifier(record.profileId),
        tabId: requireIdentifier(record.tabId),
        windowId: requireIdentifier(record.windowId),
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

function requireProfileIdentifier(value: unknown): string {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    new TextEncoder().encode(value).length > 128 ||
    !/^[A-Za-z0-9_-]+$/.test(value)
  ) {
    throw new Error("Invalid Chrome profile identifier");
  }
  return value;
}

function requireIdentifier(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) < 0) {
    throw new Error("Invalid Chrome identifier");
  }
  return value as number;
}

function snapshotByteCount(
  profileId: string,
  tabs: ExtensionTabSnapshot[],
): number {
  return new TextEncoder().encode(
    JSON.stringify(makeTabsSnapshot(profileId, tabs)),
  ).length;
}
