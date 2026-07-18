# StayPane

StayPane is a source-only macOS menu-bar focus timer. You choose one or more running or installed applications and a duration; during the session, StayPane minimizes other app windows and returns focus to the most recently used allowed app without quitting anything.

Ticket 01 targets Apple silicon running macOS 26 or newer. It uses SwiftUI, AppKit, and the macOS Accessibility API. Screen Recording permission is not required.

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

Application sessions support an allowlist of multiple running applications plus closed installed applications selected from their `.app` bundles. An application target is intentionally broad: every current and future window, and all content inside the application, remains available. Exact individual-window and browser-tab targeting belong to later tickets in [`tickets.md`](tickets.md).

During an active session, **End Session Early**, ordinary Quit, and Command-Q all use the same controlled exit: enforcement stays active for a visible 30-second countdown, then a final confirmation is required. Force Quit remains a deliberate bypass outside StayPane's honest self-control boundary.
