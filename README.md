# StayPane

StayPane is a source-only macOS menu-bar focus timer. You choose one or more applications or exact windows and a duration; during the session, StayPane minimizes other windows and returns focus to the most recently used allowed target without quitting anything.

StayPane targets Apple silicon running macOS 26 or newer. It uses SwiftUI, AppKit, and the macOS Accessibility API. Window discovery and hover outlines use Accessibility geometry only: Screen Recording permission is not required.

## Build and run

Install Apple's Command Line Tools, then run:

```sh
make run
```

This compiles a release executable, creates an ad-hoc-signed app at `.build/StayPane.app`, and opens it. No paid Apple Developer account is needed for a local source build.

On first use, choose **Request Access & Open Settings**, enable StayPane under **Privacy & Security → Accessibility**, and return to the menu-bar app. StayPane verifies permission before allowing a session to start.

Run the tests with:

```sh
make test
```

## Current scope

Sessions support multiple broad application targets and exact windows. A broad application target may be running or selected from an installed `.app` bundle; every current and future window and all content inside it remains available. Expanding a running application lets you choose exact current windows instead. Exact selection permits the chosen window and its attached sheets or modal dialogs while sibling, reopened, and newly created independent windows stay blocked. Browser-tab targeting belongs to a later ticket in [`tickets.md`](tickets.md).

Platform-dependent acceptance steps for multiple displays, Spaces, full-screen windows, system dialogs, and restoration are documented in [`docs/manual-testing/ticket-04-window-enforcement.md`](docs/manual-testing/ticket-04-window-enforcement.md).

During enforcement, the menu bar shows the remaining time and opens the current Status Panel. An optional native Floating Timer can move, collapse, or hide independently and remembers its position and collapsed layout. Control-Option-Command-S (`⌃⌥⌘S`) is the Open-Panel Shortcut; it is the only global shortcut and only opens the Status Panel. Notification permission is not required for in-app or brief menu-bar completion feedback. Manual Session Presence checks are documented in [`docs/manual-testing/ticket-05-session-presence.md`](docs/manual-testing/ticket-05-session-presence.md).

Active and reset-pending Sessions persist locally with a Fixed End Time. StayPane resumes unfinished enforcement after an app crash or login, completes expired offline Sessions during cleanup, and marks unsafe Recovery as Interrupted through Fail Open. Launch at Login is requested by default through macOS and can be disabled with a visible Recovery warning. Recovery never reopens applications or windows. An exact Window Target must expose a unique Accessibility identifier so StayPane can preserve its Exact Window Identity; when an application does not provide one, StayPane refuses to start and recommends its broader Application Target. Manual sleep, lock, crash, logout, restart, permission-loss, and expired-offline checks are documented in [`docs/manual-testing/ticket-06-recovery.md`](docs/manual-testing/ticket-06-recovery.md).

During an active session, **End Session Early**, ordinary Quit, and Command-Q all use the same controlled exit: enforcement stays active for a visible 30-second countdown, then a final confirmation is required. Force Quit remains a deliberate bypass outside StayPane's honest self-control boundary.
