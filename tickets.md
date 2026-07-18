# Tickets: StayPane v1

These tickets build the source-only StayPane v1 described in the [product specification](.scratch/staypane/PRD.md).

Work the **frontier**: any ticket whose blockers are all complete. Tickets 2, 3, and 5 form the first parallel frontier after Ticket 1.

## 01 — Run a complete application-only focus session

**Status:** completed

**What to build:** Deliver the first complete StayPane experience on a supported Mac. A user launches the menu-bar app, grants and verifies Accessibility permission, selects one running application, chooses a valid duration, reviews the session, starts after a cancelable countdown, remains confined to the selected application, and regains their prior windows when the timer completes.

**Blocked by:** None — can start immediately.

- [x] A source build launches as a native menu-bar application on Apple silicon with macOS 26 or newer.
- [x] First use explains Accessibility permission, opens the relevant System Settings area, and verifies that control works before enabling Start.
- [x] The duration defaults to 30 minutes, accepts 10 seconds through 24 hours, remembers the last value, and can reset to 30 minutes.
- [x] The picker lists running applications with recognizable names and icons and requires one selection.
- [x] A final review shows the selected application and duration, followed by a cancelable three-second countdown.
- [x] Starting creates an immutable active session through the Session Engine and minimizes disallowed application windows without quitting their processes.
- [x] Activating a blocked application returns focus to the last allowed target and produces rate-limited explanatory feedback.
- [x] Timer completion stops enforcement and restores only windows changed by StayPane.
- [x] A denied or missing Accessibility permission prevents the session from starting without trapping the user.
- [x] Session Engine tests prove the idle, configuring, ready, starting, enforcing, and completed path using simulated time and fake enforcement ports.

## 02 — Make application sessions safe to end early

**Status:** completed

**What to build:** Let a user deliberately abandon an active application-only session without creating an instant distraction bypass. The same controlled exit applies from the visible action, Command-Q, and ordinary Quit.

**Blocked by:** 01 — Run a complete application-only focus session.

- [x] End Session Early remains available from StayPane throughout enforcement.
- [x] Requesting an early reset starts a visible 30-second countdown while target enforcement remains active.
- [x] The reset countdown can be canceled and returns to the unchanged active session.
- [x] Finishing the countdown requires a final confirmation before access is restored.
- [x] Confirming stops enforcement, restores eligible windows, and produces an Ended Early outcome distinct from Completed.
- [x] Command-Q and ordinary Quit use the same early-reset flow during an active session.
- [x] No pause, duration-edit, or target-edit control exists after the session starts.
- [x] The interface explains that Force Quit is a deliberate bypass outside StayPane's honest self-control boundary.
- [x] Tests cover reset request, cancellation, countdown completion, confirmation refusal, confirmation acceptance, and race conditions at normal timer completion.

## 03 — Support multiple and closed application targets

**Status:** ready-for-agent

**What to build:** Expand application-only sessions from one running app to a practical allowlist of multiple running or installed applications, while making the breadth of application-level access explicit.

**Blocked by:** 01 — Run a complete application-only focus session.

- [ ] A user can select multiple running applications before starting.
- [ ] A user can add a closed installed application to the allowlist.
- [ ] Selecting an application allows all of its existing windows.
- [ ] New windows from an allowed application remain allowed during the session.
- [ ] Launching a closed application-level target during the session allows its windows.
- [ ] An application-level selection visibly warns that all current and future content inside the application is permitted.
- [ ] Targets that disappear before the start countdown finishes are revalidated and explained rather than silently ignored.
- [ ] The final review accurately represents every broad target.
- [ ] Policy tests cover multiple allowed applications, delayed application launch, target disappearance, and activation order.

## 04 — Enforce individual window targets precisely

**Status:** ready-for-agent

**What to build:** Let users expand applications and allow exact windows while keeping sibling and future independent windows blocked. Preserve the real desktop state across completion and early reset.

**Blocked by:** 03 — Support multiple and closed application targets.

- [ ] Running application rows expand to show their current windows by title.
- [ ] Hovering a window entry outlines the real window without taking a screenshot or requesting Screen Recording permission.
- [ ] Selecting an application disables redundant child-window controls; deselecting it restores precise window choices.
- [ ] An individually selected window remains allowed while sibling and newly created independent windows from the same application are blocked.
- [ ] Closing an individually selected window removes its availability; reopening creates a new blocked window.
- [ ] Closing every user-selected target leaves the session running with StayPane still accessible.
- [ ] Essential macOS authentication, permission, and critical-alert UI remains accessible.
- [ ] Temporary sheets and modal dialogs belonging to an allowed window work without allowing unrelated independent windows.
- [ ] Enforcement and documented manual checks cover multiple displays, Spaces, and allowed full-screen windows.
- [ ] StayPane does not move, resize, or intentionally change the display or Space of allowed windows.
- [ ] Restoration affects only windows StayPane minimized; pre-minimized windows stay minimized and user-closed windows are not reopened.
- [ ] A restoration failure for one window is reported without preventing other windows from restoring or the session from unlocking.

## 05 — Deliver the menu-bar and floating-timer experience

**Status:** ready-for-agent

**What to build:** Give an active session a calm, persistent Mac-native presence that remains reachable without competing with the user's work.

**Blocked by:** 01 — Run a complete application-only focus session.

- [ ] The menu bar shows the remaining time while a session is active.
- [ ] Clicking the menu-bar item opens setup when idle and session status when active.
- [ ] The active panel shows remaining time, allowed targets, enforcement status, and End Session Early without permitting edits.
- [ ] An optional native floating timer stays above work without being injected into webpages.
- [ ] The floating timer can move, collapse into a compact pill, and hide completely while the menu-bar timer remains.
- [ ] Floating timer position and collapsed state persist locally between launches.
- [ ] A non-destructive global shortcut opens the StayPane panel.
- [ ] No global shortcut starts, resets, or quits a session.
- [ ] The UI remains usable when notification permission is denied.

## 06 — Recover sessions across sleep, crashes, and restarts

**Status:** ready-for-agent

**What to build:** Make application and window sessions reliable across ordinary Mac lifecycle events while always failing open when enforcement is no longer trustworthy.

**Blocked by:** 02 — Make application sessions safe to end early; 04 — Enforce individual window targets precisely.

- [ ] A session uses a fixed end time and continues while the Mac sleeps or the screen is locked.
- [ ] In-process timing uses simulated/continuous time in tests and is not based on repeated real sleeps.
- [ ] The immutable session configuration, end time, enforcement state, and necessary restoration state persist locally while active.
- [ ] Relaunching StayPane before the end time resumes enforcement for the remaining duration.
- [ ] Logging out or restarting the Mac resumes an unfinished session after login when recovery is available.
- [ ] Launch at Login is enabled by default, can be disabled, and explains the resulting recovery limitation.
- [ ] If the session expired while StayPane was unavailable, the next launch restores eligible windows and records completion rather than resuming.
- [ ] Losing Accessibility permission stops all enforcement claims, restores what remains controllable, and produces an Interrupted outcome.
- [ ] Recovery never reopens applications or windows the user closed.
- [ ] Persistence and Session Engine tests cover every meaningful active and reset-pending recovery state.
- [ ] Manual acceptance covers sleep, screen lock, application crash, logout, restart, login-item behavior, and expired offline sessions.

## 07 — Record private history and export redacted diagnostics

**Status:** ready-for-agent

**What to build:** Give users a truthful, minimal view of past sessions and an explicit troubleshooting path without collecting or uploading sensitive activity.

**Blocked by:** 06 — Recover sessions across sleep, crashes, and restarts.

- [ ] Completed history records start time, planned duration, actual focus time, and result only.
- [ ] Results distinguish Completed, Ended Early, and Interrupted.
- [ ] History never stores application names, window titles, tab titles, URLs, or domains.
- [ ] Only the latest 100 session records are retained.
- [ ] Clear History requires confirmation and removes all retained records.
- [ ] Diagnostic logs are bounded and redact application content, window titles, tab titles, URLs, and domains.
- [ ] StayPane performs no analytics, telemetry, automatic crash upload, or background diagnostic submission.
- [ ] Export Diagnostics creates a local artifact only after an explicit action and lets the user inspect it before sharing.
- [ ] Privacy tests scan history, recovery cleanup, logs, and exports for prohibited fields.

## 08 — Connect one Chrome tab through the native bridge

**Status:** ready-for-agent

**What to build:** Establish the narrowest complete browser slice: an unpacked Chrome extension connects locally to StayPane, exposes tabs to the picker, and keeps one selected tab active during a session.

**Blocked by:** 04 — Enforce individual window targets precisely.

- [ ] The Manifest V3 extension builds from source and loads through Chrome Developer Mode without a Google developer account.
- [ ] A local setup action registers the native messaging bridge for the expected unpacked extension identity.
- [ ] The extension and bridge complete a validated handshake and expose connected/disconnected state to the Mac app.
- [ ] The target picker shows open Chrome tabs beneath their Chrome windows with title, hostname, and favicon when available.
- [ ] A user can select one tab as an immutable session target.
- [ ] A tab-restricted session refuses to start when the extension or bridge preflight fails.
- [ ] Activating another tab during the session returns Chrome to the selected tab and produces rate-limited feedback.
- [ ] Native messages are schema-validated and rejected when the caller identity or content is invalid.
- [ ] The extension and bridge contact no remote StayPane service and transmit browsing data only across the local connection.
- [ ] Automated contract tests cover handshake, tab discovery, activation enforcement, malformed messages, and connection setup errors.

## 09 — Constrain an allowed Chrome tab to its website

**Status:** ready-for-agent

**What to build:** Close the navigation loophole by keeping an individually selected tab on its chosen website and handling links that attempt to create additional tabs.

**Blocked by:** 08 — Connect one Chrome tab through the native bridge.

- [ ] Current Website is available as the default scope for an individual tab target.
- [ ] HTTP and HTTPS top-level navigation on the selected hostname is allowed across paths and query parameters.
- [ ] Navigation to a different hostname is blocked and the tab returns to its last allowed page.
- [ ] A same-scope link that opens a new tab is transferred into the original allowed tab and the new tab closes.
- [ ] An out-of-scope new tab closes while the original allowed tab remains unchanged.
- [ ] New tabs are never added to the immutable allowlist automatically.
- [ ] A small, rate-limited notice explains blocked navigation without repeatedly distracting the user.
- [ ] Tests cover schemes, hostnames, paths, redirects, rapid navigation, same-scope links, and cross-scope new tabs.

## 10 — Support exact-page scopes and multiple Chrome tabs

**Status:** ready-for-agent

**What to build:** Let a focused browser workflow include several explicitly chosen tabs, each with its own strict website or page rule.

**Blocked by:** 09 — Constrain an allowed Chrome tab to its website.

- [ ] A user can select multiple individual Chrome tabs before starting.
- [ ] Each selected tab independently chooses Current Website or Exact Page.
- [ ] Exact Page matches the original hostname, path, and query parameters while ignoring URL fragments.
- [ ] An ordinary reload of an allowed tab remains permitted.
- [ ] Duplicated, detached, newly created, or newly activated unapproved tabs remain blocked.
- [ ] Closing one selected tab removes it without ending the session or broadening another tab's policy.
- [ ] Browser policies remain immutable for the entire session.
- [ ] Concurrent tab and navigation events resolve deterministically without leaving a disallowed tab active.
- [ ] Tests cover multiple windows, mixed scopes, reloads, fragments, query changes, duplication, detachment, closure, and event races.

## 11 — Support broad Chrome application and window targets

**Status:** ready-for-agent

**What to build:** Complete Chrome's application/window/tab hierarchy so users can intentionally trade precision for a broader browser workflow.

**Blocked by:** 08 — Connect one Chrome tab through the native bridge.

- [ ] Selecting the Chrome application allows every current and future Chrome window, tab, and website.
- [ ] Selecting one Chrome window allows every current and future tab inside that window.
- [ ] Chrome application selection disables redundant Chrome window and tab controls.
- [ ] Chrome window selection disables redundant tab controls beneath that window.
- [ ] Deselecting a broad parent restores the ability to choose precise children.
- [ ] Broad Chrome targets show a clear warning that they permit more distraction paths and do not apply page scopes.
- [ ] Chrome windows not covered by a window-level target remain blocked.
- [ ] Broad-target behavior survives tab creation, tab movement, window activation, and normal session completion.
- [ ] Policy tests cover every parent-child combination and transition available before start.

## 12 — Harden Chrome profiles, Incognito, and connection failures

**Status:** ready-for-agent

**What to build:** Make browser enforcement honest across Chrome profiles and runtime failures, refusing unsupported states before start and failing open when a verified connection disappears.

**Blocked by:** 06 — Recover sessions across sleep, crashes, and restarts; 10 — Support exact-page scopes and multiple Chrome tabs; 11 — Support broad Chrome application and window targets.

- [ ] Every selected Chrome profile must have an independently verified extension connection before a tab-restricted session starts.
- [ ] Picker state makes connected, disconnected, and unsupported Chrome profiles understandable.
- [ ] Incognito tabs cannot be selected in v1.
- [ ] Incognito windows are minimized during a tab-restricted session unless the whole Chrome application is allowed.
- [ ] Losing the extension, profile connection, or native bridge during enforcement stops all enforcement claims and produces Interrupted.
- [ ] Fail-open behavior restores eligible macOS windows and leaves the user in control even if Chrome cleanup is incomplete.
- [ ] Reconnection after interruption does not silently restart a terminated session.
- [ ] Recovery refuses to resume a tab-restricted session until every required browser integration passes preflight.
- [ ] Bridge inputs remain caller-restricted and schema-validated throughout disconnect and reconnect races.
- [ ] Automated and manual tests cover multiple profiles, missing extensions, Incognito, extension disablement, bridge termination, malformed traffic, and relaunch recovery.

## 13 — Complete first-run onboarding and accessible interaction

**Status:** ready-for-agent

**What to build:** Turn the assembled capabilities into a coherent first-run and daily experience that clearly explains permissions, privacy, notification limitations, browser setup, and the honest self-control boundary.

**Blocked by:** 05 — Deliver the menu-bar and floating-timer experience; 07 — Record private history and export redacted diagnostics; 12 — Harden Chrome profiles, Incognito, and connection failures.

- [ ] First-run onboarding explains StayPane's honest boundary and local-only privacy model in plain language.
- [ ] Accessibility setup handles not-determined, denied, granted, and later-revoked states.
- [ ] Chrome setup is optional for application/window sessions and required only for tab-restricted sessions.
- [ ] The onboarding checklist can install/test the bridge connection and run a harmless window-enforcement verification.
- [ ] Final session review can remind users to enable macOS Focus and open the relevant settings without claiming automatic control.
- [ ] Notification denial leaves clear in-app and menu-bar completion feedback.
- [ ] Every flow is keyboard navigable and exposes meaningful VoiceOver labels, grouping, focus order, and status announcements.
- [ ] Dark mode, increased contrast, and Reduce Motion are respected.
- [ ] No onboarding or picker behavior requests Screen Recording permission.
- [ ] User-facing v1 copy is clear English and consistently uses the specification's domain terms.
- [ ] Accessibility and UI tests cover onboarding, setup failure, final review, active state, reset, history, diagnostics, and completion.

## 14 — Verify the source-only v1 release from a fresh clone

**Status:** ready-for-agent

**What to build:** Package the repository as a trustworthy open-source v1 that another technical Mac user can clone, understand, build, install, verify, and update without paid developer accounts.

**Blocked by:** 13 — Complete first-run onboarding and accessible interaction.

- [ ] The repository carries the MIT license and clearly explains that commercial and closed-source reuse is permitted with the license notice preserved.
- [ ] Multi-context domain documentation maps product, Mac application, Chrome extension, and native bridge vocabulary and architectural decisions.
- [ ] Build instructions start from a fresh clone on a supported Mac and identify all required tools.
- [ ] One documented setup command builds or installs the local native bridge registration without requiring an Apple or Google paid developer account.
- [ ] Chrome Developer Mode installation, reload, bridge verification, removal, and update steps are documented.
- [ ] The documentation explains unsigned source distribution, Accessibility permission, the honest bypass boundary, local-only privacy, and unsupported environments.
- [ ] Automated checks build and test the Mac app, Session Engine, extension, and bridge with redacted test output.
- [ ] The complete test suite passes from a clean checkout.
- [ ] A manual acceptance matrix passes normal completion, early reset, closed targets, transient dialogs, multi-display, Spaces, full screen, sleep, crash, restart, permission loss, bridge loss, multiple Chrome tabs, scopes, profiles, Incognito, and restoration failures.
- [ ] A short real session completes successfully after following only the public installation documentation.
- [ ] The roadmap documents Safari first, other Chromium browsers next, and Firefox afterward without promising them in v1.
- [ ] No release artifact includes automatic telemetry, background update checks, signed-binary claims, or private macOS APIs.
