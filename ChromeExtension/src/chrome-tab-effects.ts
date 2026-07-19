export type CandidateTabLifecyclePort = {
  removeTab(tabId: number): Promise<void>;
  tabExists(tabId: number): Promise<boolean>;
};

export async function closeTabIfPresent(
  tabId: number,
  port: CandidateTabLifecyclePort,
): Promise<void> {
  try {
    await port.removeTab(tabId);
  } catch (error) {
    if (await port.tabExists(tabId)) {
      throw error;
    }
  }
}

export function isMissingChromeTabError(error: unknown): boolean {
  return (
    error instanceof Error &&
    (/^No tab with id: \d+\.?$/.test(error.message) ||
      /^Invalid tab ID: \d+\.?$/.test(error.message))
  );
}
