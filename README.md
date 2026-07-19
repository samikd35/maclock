# StayPane

StayPane is a source-only macOS menu-bar focus timer. You choose one or more applications, exact windows, or individual Chrome tabs and a duration; during the session, StayPane minimizes other windows and returns focus to the allowed target without quitting anything.

StayPane targets Apple silicon running macOS 26 or newer. It uses SwiftUI, AppKit, and the macOS Accessibility API. Window discovery and hover outlines use Accessibility geometry only: Screen Recording permission is not required.

## Build and run

Install Apple's Command Line Tools and Node.js, then run:

```sh
make run
```

This compiles a release executable, creates an ad-hoc-signed app at `.build/StayPane.app`, and opens it. No paid Apple Developer account is needed for a local source build.

On first use, choose **Request Access & Open Settings**, enable StayPane under **Privacy & Security → Accessibility**, and return to the menu-bar app. StayPane verifies permission before allowing a session to start.

Run the tests with:

```sh
make test
make test-extension
```

## Current scope

Sessions support multiple broad application targets, exact windows, or multiple individual non-Incognito Chrome Tab Targets. A broad application target may be running or selected from an installed `.app` bundle; every current and future window and all content inside it remains available. Expanding a running application lets you choose exact current windows instead. Exact selection permits the chosen window and its attached sheets or modal dialogs while sibling, reopened, and newly created independent windows stay blocked. Each Chrome Tab Target independently uses Current Website (the default) or Exact Page. Current Website permits top-level HTTP and HTTPS pages on the selected hostname across paths and queries. Exact Page also requires the original path and query, while allowing fragment changes and ordinary reloads. Other navigation returns that tab to its Last Allowed Page. Same-scope links opened in a new tab transfer into their original Tab Target and close the new tab; out-of-scope new tabs close. Closing one selected tab removes only that runtime target, and unapproved, duplicated, moved, or newly activated tabs do not join the immutable allowlist.

## Optional Chrome setup

Chrome integration is entirely local and does not require a Google developer account or Chrome Web Store listing.

1. Build the packaged app and extension with `make app`, then open `.build/StayPane.app`.
2. In StayPane, choose **Register Native Host**. This Native Host Registration writes a user-level manifest that accepts only extension ID `hoofhoedlagpoclhkgnkmejaihaapoke`.
3. Open `chrome://extensions`, enable **Developer mode**, choose **Load unpacked**, and select `.build/StayPane.app/Contents/Resources/ChromeExtension` (the **Show Extension Folder** button reveals it).
4. Return to StayPane and wait for **Connected**. Expand Google Chrome to choose an eligible HTTP or HTTPS tab grouped beneath its Chrome window.

After rebuilding or pulling an update, reload the unpacked extension in `chrome://extensions`; extension version 0.3.0 speaks Native Bridge protocol version 3 and starts every selected tab atomically. The extension sends current tab metadata only through Chrome native messaging to the packaged Native Bridge, which proxies it over a user-only Unix socket to StayPane. There is no StayPane server, analytics endpoint, or remote browsing-data transport. Incognito access is disabled. The current implementation accepts one connected Chrome Profile; profile-aware hardening remains Ticket 12. Pinning the extension makes its brief, rate-limited return badge easier to see. Tab setup checks remain in [`docs/manual-testing/ticket-08-chrome-tab.md`](docs/manual-testing/ticket-08-chrome-tab.md), Current Website checks are in [`docs/manual-testing/ticket-09-current-website.md`](docs/manual-testing/ticket-09-current-website.md), and multiple-tab/Exact Page acceptance is in [`docs/manual-testing/ticket-10-multiple-tab-scopes.md`](docs/manual-testing/ticket-10-multiple-tab-scopes.md).

Platform-dependent acceptance steps for multiple displays, Spaces, full-screen windows, system dialogs, and restoration are documented in [`docs/manual-testing/ticket-04-window-enforcement.md`](docs/manual-testing/ticket-04-window-enforcement.md).

During enforcement, the menu bar shows the remaining time and opens the current Status Panel. An optional native Floating Timer can move, collapse, or hide independently and remembers its position and collapsed layout. Control-Option-Command-S (`⌃⌥⌘S`) is the Open-Panel Shortcut; it is the only global shortcut and only opens the Status Panel. Notification permission is not required for in-app or brief menu-bar completion feedback. Manual Session Presence checks are documented in [`docs/manual-testing/ticket-05-session-presence.md`](docs/manual-testing/ticket-05-session-presence.md).

Active and reset-pending Sessions persist locally with a Fixed End Time. StayPane resumes unfinished enforcement after an app crash or login, completes expired offline Sessions during cleanup, and marks unsafe Recovery as Interrupted through Fail Open. Launch at Login is requested by default through macOS and can be disabled with a visible Recovery warning. Recovery never reopens applications or windows. An exact Window Target must expose a unique Accessibility identifier so StayPane can preserve its Exact Window Identity; when an application does not provide one, StayPane refuses to start and recommends its broader Application Target. Manual sleep, lock, crash, logout, restart, permission-loss, and expired-offline checks are documented in [`docs/manual-testing/ticket-06-recovery.md`](docs/manual-testing/ticket-06-recovery.md).

Session History is local and limited to the latest 100 records. Each record contains only start time, planned duration, actual focus time, and the result Completed, Ended Early, or Interrupted; it never stores application names, window or tab titles, URLs, or domains. Diagnostics are local, bounded to 200 redacted events, and never submitted automatically. **Export Diagnostics** is an explicit local save action that opens the artifact for inspection before the user decides whether to share it. StayPane contains no analytics, telemetry, automatic crash upload, or background diagnostic submission. Manual privacy and export checks are documented in [`docs/manual-testing/ticket-07-privacy.md`](docs/manual-testing/ticket-07-privacy.md).

During an active session, **End Session Early**, ordinary Quit, and Command-Q all use the same controlled exit: enforcement stays active for a visible 30-second countdown, then a final confirmation is required. Force Quit remains a deliberate bypass outside StayPane's honest self-control boundary.
