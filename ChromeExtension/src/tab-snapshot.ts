import {
  ExtensionTabSnapshot,
  fitTabsToNativeMessageBudget,
} from "./protocol.js";

export async function collectTabSnapshots(
  profileIdentifier: string,
): Promise<ExtensionTabSnapshot[]> {
  const tabs = await chrome.tabs.query({});
  const snapshots = await Promise.all(tabs.map(makeTabSnapshot));
  return fitTabsToNativeMessageBudget(
    profileIdentifier,
    snapshots.filter(
      (snapshot): snapshot is ExtensionTabSnapshot => snapshot !== null,
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
