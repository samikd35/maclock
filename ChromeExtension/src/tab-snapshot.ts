import {
  ExtensionTabSnapshot,
  fitTabsToNativeMessageBudget,
} from "./protocol.js";

export type FaviconResponse = {
  ok: boolean;
  bytes: Uint8Array;
};

export type TabSnapshotPort = {
  queryTabs(): Promise<chrome.tabs.Tab[]>;
  queryWindows(): Promise<chrome.windows.Window[]>;
  loadFavicon(pageURL: string): Promise<FaviconResponse>;
};

const chromeTabSnapshotPort: TabSnapshotPort = {
  queryTabs: async () => chrome.tabs.query({}),
  queryWindows: async () => chrome.windows.getAll(),
  loadFavicon: async (pageURL) => {
    const faviconURL = new URL(chrome.runtime.getURL("/_favicon/"));
    faviconURL.searchParams.set("pageUrl", pageURL);
    faviconURL.searchParams.set("size", "32");
    const response = await fetch(faviconURL);
    return {
      ok: response.ok,
      bytes: new Uint8Array(await response.arrayBuffer()),
    };
  },
};

export async function collectTabSnapshots(
  profileIdentifier: string,
  port: TabSnapshotPort = chromeTabSnapshotPort,
): Promise<ExtensionTabSnapshot[]> {
  const tabs = await port.queryTabs();
  const windowBoundsByIdentifier = new Map(
    (await port.queryWindows()).flatMap((window) => {
      const bounds = validatedWindowBounds(window);
      return window.id === undefined || bounds === null
        ? []
        : [[window.id, bounds] as const];
    }),
  );
  const snapshots = await Promise.all(
    tabs.map((tab) => makeTabSnapshot(
      tab,
      windowBoundsByIdentifier.get(tab.windowId),
      port,
    )),
  );
  return fitTabsToNativeMessageBudget(
    profileIdentifier,
    snapshots.filter(
      (snapshot): snapshot is ExtensionTabSnapshot => snapshot !== null,
    ),
  );
}

async function makeTabSnapshot(
  tab: chrome.tabs.Tab,
  windowBounds: {
    left: number;
    top: number;
    width: number;
    height: number;
  } | undefined,
  port: TabSnapshotPort,
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
  const faviconDataUrl = await loadFaviconDataURL(tab.url, port);
  return {
    tabId: tab.id,
    windowId: tab.windowId,
    title,
    url,
    ...(faviconDataUrl === null ? {} : { faviconDataUrl }),
    ...(windowBounds === undefined ? {} : { windowBounds }),
    active: tab.active,
    incognito: tab.incognito,
  };
}

function validatedWindowBounds(
  window: chrome.windows.Window,
): {
  left: number;
  top: number;
  width: number;
  height: number;
} | null {
  const values = [window.left, window.top, window.width, window.height];
  if (
    values.some((value) => !Number.isSafeInteger(value)) ||
    window.left === undefined ||
    window.top === undefined ||
    window.width === undefined ||
    window.height === undefined ||
    Math.abs(window.left) > 1_000_000 ||
    Math.abs(window.top) > 1_000_000 ||
    window.width < 1 ||
    window.width > 1_000_000 ||
    window.height < 1 ||
    window.height > 1_000_000
  ) {
    return null;
  }
  return {
    left: window.left,
    top: window.top,
    width: window.width,
    height: window.height,
  };
}

async function loadFaviconDataURL(
  pageURL: string,
  port: TabSnapshotPort,
): Promise<string | null> {
  try {
    const response = await port.loadFavicon(pageURL);
    const bytes = response.bytes;
    const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    if (
      !response.ok ||
      bytes.length > 48_000 ||
      pngSignature.some((byte, index) => bytes[index] !== byte)
    ) {
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
