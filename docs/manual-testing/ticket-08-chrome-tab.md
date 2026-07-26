# Ticket 08 manual acceptance: one Tab Target

These checks exercise Chrome APIs and native messaging that cannot be proven by the hermetic test suite. They require ordinary (non-Incognito) Chrome windows. StayPane and the companion contact no remote StayPane service.

## Build and one-time local setup

1. Run `make verify` and `make install` from the repository root.
2. Open StayPane from Applications and confirm the Native Host Registration points to the installed app.
3. Confirm **Native Host registered** appears. The generated manifest at `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.staypane.native_bridge.json` must name the packaged `StayPaneBridge` executable and allow only `chrome-extension://hoofhoedlagpoclhkgnkmejaihaapoke/`.
4. Open `chrome://extensions`, enable **Developer mode**, choose **Load unpacked**, and select `~/Applications/StayPane.app/Contents/Resources/ChromeExtension`. Confirm Chrome shows version 0.5.0 and extension ID `hoofhoedlagpoclhkgnkmejaihaapoke`, then open its details and enable **Allow in Incognito**.
5. Return to StayPane. Confirm the profile changes from **Synchronizing** to **Ready** after its current windows and tabs arrive. If Chrome was already open, reload the extension once after bridge registration.

No Apple or Google paid developer account is part of this source-build flow. Rebuilding keeps the same unpacked extension identity because the public manifest key is fixed in source.

## Discovery and selection

1. Open several ordinary tabs across at least two Chrome windows. Include one site with a favicon.
2. Refresh StayPane and expand Google Chrome.
3. Confirm a **Chrome windows and tabs** section appears beneath the macOS window rows. Tabs must be grouped by Chrome window and show title, hostname, and a favicon when Chrome provides one.
4. Confirm Incognito tabs do not appear.
5. Choose one tab, then choose a different tab. The current build keeps both explicit Tab Targets selected; an active Session must show each exact immutable Tab Target. Selecting the broad Chrome application still replaces its redundant child choices.
6. Read the visible precision note. The current build now applies Ticket 09's Current Website Navigation Scope; use the Ticket 09 manual checks for navigation behavior.

## Preflight, enforcement, and feedback

1. Select a Chrome tab, disable or reload the extension, and immediately attempt to review or start. StayPane must refuse while the bridge is disconnected or the selected tab is missing.
2. Reconnect, select an open tab, and start a short Session.
3. Activate a different tab. Chrome must return to the selected tab without closing either tab. Pin the extension to observe the brief orange return badge; StayPane also shows a bounded blocked-target notice.
4. Switch rapidly between tabs. Every disallowed activation must still return, while the visible badge/notice remains rate limited rather than flashing for every event.
5. Complete normally and repeat through the controlled early-reset flow. After enforcement stops, other tabs must remain freely selectable.
6. During an active Session, disable the extension or quit Chrome. StayPane must interrupt through Fail Open and restore eligible macOS windows rather than claiming enforcement remains active.
7. Relaunch StayPane during a short tab-restricted Session. StayPane must show **Resuming Session**, wait for the exact tab confirmation, then continue from the original fixed end time. If Chrome or the extension is unavailable, recovery must become Interrupted and restore eligible macOS windows.

## Locality and automated contracts

1. Inspect the extension service worker in `chrome://extensions`. StayPane traffic must use the native port `com.staypane.native_bridge`; the only `fetch` is Chrome's own `chrome-extension://.../_favicon/` endpoint.
2. Confirm no StayPane account, server URL, analytics request, telemetry prompt, or browsing-history store is present.
3. Run `make test`. Swift contract tests cover strict identity/schema validation, partial and oversized native frames, user-level manifest setup errors, real Unix-socket handshake/tab discovery, begin/end enforcement, preflight failure, and connection loss.
4. Run `make test-extension`. TypeScript/Node tests cover the fixed handshake, malformed and extra command rejection, immutable multi-tab restoration, Current Website and Exact Page policy, and feedback rate limiting.
