# StayPane

StayPane is a source-only macOS menu-bar focus timer. You choose one or more applications, exact windows, broad Chrome windows, or individual Chrome tabs and a duration; during the session, StayPane minimizes other windows and returns focus to the allowed target without quitting anything.

StayPane is available under the [MIT License](LICENSE). Commercial and closed-source reuse is permitted, provided the copyright and license notice is preserved in copies or substantial portions of the software.

StayPane targets Apple silicon running macOS 26 or newer. It uses SwiftUI, AppKit, and the macOS Accessibility API. Window discovery and hover outlines use Accessibility geometry only: Screen Recording permission is not required.

## Build, verify, and run

On an Apple silicon Mac running macOS 26 or newer, install the Xcode 26 Command Line Tools (or full Xcode 26) and Node.js 20 or newer. From a fresh clone, run:

```sh
git clone <repository-url> StayPane
cd StayPane
make verify
make run
```

`make verify` runs the release contract, complete Swift and Chrome-extension suites, release app and Native Bridge builds, and the packaged-source audit with summarized, redacted output. `make run` creates an ad-hoc-signed local app at `.build/StayPane.app` and opens it. No paid Apple Developer account is needed for a local source build.

The complete fresh-clone, Accessibility, unsigned-source, Chrome Developer Mode, connection verification, removal, and manual update instructions are in [Install StayPane from source](docs/INSTALL.md).

On first use, StayPane opens a local onboarding checklist. It explains the honest self-control boundary and local-only privacy model, distinguishes Not Requested, Access Not Granted, Enabled but Unverified, Verified, and Revoked Accessibility Setup States, and offers a Harmless Window-Control Verification that writes a window's existing minimized value back unchanged. Choose **Open Accessibility Settings**, enable StayPane under **Privacy & Security → Accessibility**, return to the app, and run the verification. It changes no window layout or content, and StayPane never requests Screen Recording.

Chrome setup is optional for native Application Targets and Window Targets. The onboarding checklist can register and test the local Native Bridge when you want Browser Window Targets or Tab Targets; no Google developer account is required. The checklist remains available later through **Open Setup & Privacy Guide**.

Run the tests with:

```sh
make test
make test-extension
make test-release
```

The [v1 release acceptance matrix](docs/manual-testing/v1-release-matrix.md) consolidates the real macOS, Chrome, lifecycle, privacy, and Short Real Session checks that cannot be proven by hermetic automation. Future browser exploration follows [Safari first, other Chromium browsers next, and Firefox afterward](ROADMAP.md); that ordering is not a promise of support or schedule.

## Current scope

Sessions support multiple broad Application Targets, exact macOS Window Targets, broad Browser Window Targets, or multiple individual non-Incognito Tab Targets. An Application Target may be running or selected from an installed `.app` bundle; every current and future window and all content inside it remains available. Selecting Chrome as an Application Target also permits every Chrome tab and website without Navigation Scopes. A Browser Window Target permits every current and future tab and website in only that exact Chrome window; uncovered Chrome windows are minimized and restored when the Session ends. Parent selections disable redundant children until the parent is deselected. Each individual Tab Target independently uses Current Website (the default) or Exact Page. Current Website permits top-level HTTP and HTTPS pages on the selected hostname across paths and queries. Exact Page also requires the original path and query, while allowing fragment changes and ordinary reloads. Other navigation returns that tab to its Last Allowed Page. Same-scope links opened in a new tab transfer into their original Tab Target and close the new tab; out-of-scope new tabs close. Closing one selected browser target removes only that runtime target, and unapproved identities do not join the immutable allowlist.

## Optional Chrome setup

Chrome integration is entirely local and does not require a Google developer account or Chrome Web Store listing.

1. Run `make setup-chrome`. This builds the packaged app, extension, and Native Bridge and writes a user-level Native Host Registration that accepts only extension ID `hoofhoedlagpoclhkgnkmejaihaapoke`.
2. Open `.build/StayPane.app`.
3. Open `chrome://extensions`, enable **Developer mode**, choose **Load unpacked**, and select `.build/StayPane.app/Contents/Resources/ChromeExtension` (the **Show Extension Folder** button reveals it).
4. Open the extension's details and enable **Allow in Incognito**. StayPane never offers Incognito tabs as Targets, but it needs this capability to minimize Incognito windows that would otherwise bypass a precise browser Session.
5. Return to StayPane and wait for the Chrome Profile to show **Ready**. Repeat the unpacked-extension setup for every Chrome Profile whose browser Targets you want to combine, then expand Google Chrome to choose a broad Chrome window or an eligible HTTP or HTTPS tab beneath it.

After rebuilding or pulling an update, reload the unpacked extension in every configured Chrome Profile. Extension version 0.5.0 speaks Native Bridge protocol version 5. Each selected profile is independently identified, capability-checked, and confirmed before StayPane claims browser enforcement; a disconnected profile or one without Incognito-window control cannot start a browser-restricted Session. Incognito tabs remain unselectable, and Incognito windows are minimized during Browser Window or Tab Target enforcement. Selecting Chrome as an Application Target intentionally allows all Chrome content instead.

The extension sends current tab metadata and optional Chrome window bounds only through Chrome native messaging to the packaged Native Bridge, which proxies them over a user-only Unix socket to StayPane. Bounds support verified hover outlining and are not used as Target identity. There is no StayPane server, analytics endpoint, or remote browsing-data transport. Losing any required profile connection fails the entire Session open as Interrupted; reconnecting does not restart that terminated Session. Pinning the extension makes its brief, rate-limited return badge easier to see. Profile, Incognito, and failure acceptance is in [`docs/manual-testing/ticket-12-chrome-profiles-and-fail-open.md`](docs/manual-testing/ticket-12-chrome-profiles-and-fail-open.md); the Ticket 08–11 manuals retain the target and scope checks.

Platform-dependent acceptance steps for multiple displays, Spaces, full-screen windows, system dialogs, and restoration are documented in [`docs/manual-testing/ticket-04-window-enforcement.md`](docs/manual-testing/ticket-04-window-enforcement.md).

During enforcement, the menu bar shows the remaining time and opens the current Status Panel. An optional native Floating Timer can move, collapse, or hide independently and remembers its position and collapsed layout. Control-Option-Command-S (`⌃⌥⌘S`) is the Open-Panel Shortcut; it is the only global shortcut and only opens the Status Panel. Notification permission is not required for in-app or brief menu-bar completion feedback. Final review offers an optional macOS Focus reminder and opens Focus Settings without claiming automatic control. The interface uses native keyboard controls and semantic colors, announces status changes to accessibility clients, increases card contrast with the system preference, and disables numeric motion when Reduce Motion is enabled. Manual onboarding and accessibility acceptance is documented in [`docs/manual-testing/ticket-13-onboarding-and-accessibility.md`](docs/manual-testing/ticket-13-onboarding-and-accessibility.md).

Active and reset-pending Sessions persist locally with a Fixed End Time. StayPane resumes unfinished enforcement after an app crash or login, completes expired offline Sessions during cleanup, and marks unsafe Recovery as Interrupted through Fail Open. Launch at Login is requested by default through macOS and can be disabled with a visible Recovery warning. Recovery never reopens applications or windows. An exact Window Target must expose a unique Accessibility identifier so StayPane can preserve its Exact Window Identity; when an application does not provide one, StayPane refuses to start and recommends its broader Application Target. Manual sleep, lock, crash, logout, restart, permission-loss, and expired-offline checks are documented in [`docs/manual-testing/ticket-06-recovery.md`](docs/manual-testing/ticket-06-recovery.md).

Session History is local and limited to the latest 100 records. Each record contains only start time, planned duration, actual focus time, and the result Completed, Ended Early, or Interrupted; it never stores application names, window or tab titles, URLs, or domains. Diagnostics are local, bounded to 200 redacted events, and never submitted automatically. **Export Diagnostics** is an explicit local save action that opens the artifact for inspection before the user decides whether to share it. StayPane contains no analytics, telemetry, automatic crash upload, or background diagnostic submission. Manual privacy and export checks are documented in [`docs/manual-testing/ticket-07-privacy.md`](docs/manual-testing/ticket-07-privacy.md).

During an active session, **End Session Early**, ordinary Quit, and Command-Q all use the same controlled exit: enforcement stays active for a visible 30-second countdown, then a final confirmation is required. Force Quit remains a deliberate bypass outside StayPane's honest self-control boundary.
