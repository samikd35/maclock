# StayPane v1 Product Specification

Status: ready-for-agent

## Problem Statement

Mac users who intentionally begin a focus session can still switch to distracting applications, windows, browser tabs, and websites before the timer ends. Ordinary Pomodoro timers measure time but do not keep the user's working environment constrained to the applications and content chosen at the start. Existing blockers often operate only at the application or website level, which leaves loopholes inside multi-window applications and browsers.

The user needs an honest self-control tool: strong enough to make casual distraction inconvenient, transparent about the ways a determined administrator can bypass it, and safe enough to restore control whenever enforcement fails. The tool must remain local, understandable, open source, and usable without paid Apple or Google developer accounts when built from source.

## Solution

StayPane is a free, MIT-licensed, source-distributed macOS focus timer. Before starting a session, the user chooses a duration and an immutable allowlist of entire applications, individual windows, and—through a companion Chrome extension—individual browser tabs. StayPane minimizes disallowed windows, rejects later attempts to activate them, and returns focus to the last allowed target until the timer completes.

Chrome targets support three levels of breadth: the entire Chrome application, an entire Chrome window, or selected tabs. Selected tabs are constrained to either their current website or exact page. A local native bridge connects the Chrome extension to the Mac application; no server or account is involved.

StayPane is an honest commitment device, not a security boundary. A normal early exit requires a 30-second enforced countdown and final confirmation, while Force Quit, extension removal, permission revocation, or administrator intervention remain deliberate bypasses. Any unexpected loss of enforcement fails open instead of trapping the user.

The v1 experience is a menu-bar application with a setup window, an optional floating countdown, permission onboarding, minimal local session history, crash and restart recovery, and precise restoration of windows changed by StayPane.

## User Stories

1. As a Mac user, I want to understand that StayPane is a self-control tool rather than tamper-proof security, so that I know what protection it does and does not provide.
2. As a Mac user, I want to build StayPane from its public source code, so that I can use it without paying for a signed binary.
3. As a first-time user, I want StayPane to explain why Accessibility permission is required, so that I can make an informed choice.
4. As a first-time user, I want a button that opens the correct macOS permission settings, so that onboarding is straightforward.
5. As a first-time user, I want StayPane to verify that Accessibility permission works, so that I do not begin a session with false protection.
6. As a Chrome user, I want guided instructions for loading the companion extension locally, so that I can enable tab enforcement without a Chrome Web Store account.
7. As a Chrome user, I want StayPane to verify its extension and native bridge connection, so that tab enforcement is known to work before a session.
8. As a first-time user, I want a harmless window-control test, so that I can verify enforcement without risking my work.
9. As a privacy-conscious user, I want onboarding to explain that StayPane is local-only, so that I understand how its powerful permissions are used.
10. As a focus user, I want new sessions to default to 30 minutes, so that a useful focus duration is immediately available.
11. As a focus user, I want to choose a duration between 10 seconds and 24 hours, so that I can run quick tests or long focus blocks.
12. As a returning user, I want StayPane to remember my last duration, so that repeated setup is faster.
13. As a returning user, I want to reset the duration to the 30-minute default, so that remembered settings are reversible.
14. As a focus user, I want to see currently running applications in the target picker, so that I can choose what remains accessible.
15. As a focus user, I want to expand an application to see its open windows, so that I can allow only the window I need.
16. As a focus user, I want to add a closed installed application, so that its future windows may be allowed at the application level.
17. As a focus user, I want application icons and window titles in the picker, so that targets are recognizable.
18. As a focus user, I want a hovered picker entry to outline its real window, so that windows with similar titles can be distinguished.
19. As a privacy-conscious user, I want the picker to work without screenshots or thumbnails, so that StayPane does not require Screen Recording permission.
20. As a focus user, I want to select an entire application, so that every window it owns is allowed.
21. As a focus user, I want to select one individual window, so that other windows from the same application remain blocked.
22. As a focus user, I want the picker hierarchy to be application, window, and browser tab, so that broader selections clearly contain narrower ones.
23. As a focus user, I want selecting a parent to disable redundant child choices, so that the final allowlist is unambiguous.
24. As a focus user, I want warnings when I make broad selections, so that I understand the additional distraction paths being allowed.
25. As a focus user, I want StayPane to require at least one allowed target, so that an empty selection is not mistaken for an intentional block-everything mode.
26. As a Chrome user, I want open Chrome tabs listed beneath their windows, so that I can select browser content precisely.
27. As a Chrome user, I want to select multiple individual tabs, so that a focused workflow can span several necessary pages.
28. As a Chrome user, I want each selected tab to have its own navigation scope, so that different work pages can use appropriate restrictions.
29. As a Chrome user, I want a Current Website scope, so that I can navigate within the selected hostname without reaching unrelated sites.
30. As a Chrome user, I want an Exact Page scope, so that I can remain on one specific article, document, or video.
31. As a Chrome user, I want the Current Website scope to permit HTTP and HTTPS navigation on the same hostname, so that normal site navigation continues.
32. As a Chrome user, I want Exact Page matching to include hostname, path, and query parameters while ignoring fragments, so that meaningful page changes are blocked without breaking in-page anchors.
33. As a Chrome user, I want navigation outside the selected scope blocked, so that an allowed tab cannot be reused to visit a distracting site.
34. As a Chrome user, I want a same-scope link that opens a new tab moved into the original allowed tab, so that the workflow continues without expanding the allowlist.
35. As a Chrome user, I want an out-of-scope new tab closed while the original tab stays unchanged, so that distracting links do not interrupt my work.
36. As a Chrome user, I want newly created or duplicated unapproved tabs blocked, so that tab creation cannot bypass a session.
37. As a Chrome user, I want ordinary reloads of an allowed tab to keep working, so that page refreshes do not break the session.
38. As a Chrome user with multiple profiles, I want each selected profile verified independently, so that only profiles with a connected extension can participate.
39. As a Chrome user, I want StayPane to refuse Incognito tab selection in v1, so that unsupported enforcement is never presented as reliable.
40. As a Chrome user, I want Incognito windows minimized during a tab-restricted session, so that they do not provide a casual bypass.
41. As a Chrome user, I want StayPane to refuse a tab-restricted session when the extension is unavailable, so that enforcement never begins in a knowingly incomplete state.
42. As a focus user, I want a final review of duration, targets, browser scopes, and notification guidance, so that I can catch mistakes before starting.
43. As a focus user, I want a cancelable three-second start countdown, so that enforcement does not begin abruptly.
44. As a focus user, I want the allowlist and duration to become immutable when the session starts, so that I cannot casually negotiate with myself later.
45. As a focus user, I want no pause control during an active session, so that pausing cannot become a distraction loophole.
46. As a focus user, I want blocked windows minimized at session start, so that they are neither accessible nor visually distracting.
47. As a focus user, I want StayPane to remember which windows it minimized, so that it can later restore only its own changes.
48. As a focus user, I want attempts to activate a blocked window rejected, so that I remain in the chosen environment.
49. As a focus user, I want focus returned to the last allowed window after a blocked attempt, so that I can continue working immediately.
50. As a focus user, I want a quiet notice explaining what was blocked and how much time remains, so that the behavior is understandable.
51. As a focus user, I want repeated block notices rate-limited, so that StayPane does not become a distraction itself.
52. As a focus user, I want blocked applications left running rather than quit, so that unsaved state and background work are preserved.
53. As a multi-display user, I want enforcement applied across every connected display, so that another monitor is not a loophole.
54. As a Spaces user, I want enforcement applied across macOS Spaces, so that switching desktops does not reveal blocked windows.
55. As a full-screen user, I want an allowed full-screen window to remain usable, so that focused full-screen workflows work normally.
56. As a focus user, I want StayPane to leave allowed windows in their existing positions, sizes, displays, and Spaces, so that starting a session does not rearrange my workspace.
57. As a focus user, I want essential macOS authentication, permission, and critical-alert interfaces always available, so that StayPane never blocks required system interaction.
58. As a focus user, I want temporary sheets and modal dialogs attached to an allowed window permitted, so that saving, opening, and confirming actions continue to work.
59. As a focus user, I want unrelated independent windows from a partially allowed application blocked, so that transient-dialog support does not broaden access.
60. As a focus user, I want an individually allowed window that I close to remain closed and unavailable, so that reopening it does not silently create a new allowed target.
61. As a focus user, I want newly created windows from an application-level target allowed, so that broad application selection behaves consistently.
62. As a focus user, I want newly created windows from a window-level target blocked, so that precise selection remains precise.
63. As a focus user, I want the timer to continue if every selected target closes, so that closing work does not complete the session early.
64. As a focus user, I want StayPane itself always accessible, so that I can inspect the session or request an emergency reset.
65. As a focus user, I accept that content inside allowed non-browser applications is unrestricted, so that StayPane does not pretend to understand every application's internal interface.
66. As a focus user, I want the remaining time visible in the menu bar, so that progress is available without opening a window.
67. As a focus user, I want an optional floating timer, so that the countdown can remain visible over my work.
68. As a focus user, I want to move the floating timer, so that it does not cover important content.
69. As a focus user, I want to collapse the floating timer into a small pill, so that it remains present but unobtrusive.
70. As a focus user, I want to hide the floating timer while retaining the menu-bar countdown, so that visible timer pressure is optional.
71. As a returning user, I want the floating timer to remember its position and collapsed state, so that it fits my workspace consistently.
72. As a focus user, I want a shortcut that opens the StayPane panel, so that session status is easy to reach.
73. As a focus user, I do not want global start, reset, or quit shortcuts, so that destructive actions cannot happen accidentally.
74. As a focus user, I want an optional reminder to enable macOS Focus before starting, so that notifications from blocked apps can be silenced.
75. As a focus user, I want a button that opens macOS Focus settings, so that notification configuration is convenient.
76. As a focus user, I want StayPane to be honest that it cannot reliably toggle macOS Focus automatically, so that notification protection is not overstated.
77. As a focus user, I want End Session Early available throughout a session, so that I always retain control of my Mac.
78. As a focus user, I want the early-reset action to begin a 30-second countdown, so that abandoning focus requires a deliberate pause.
79. As a focus user, I want enforcement to remain active during the reset countdown, so that the countdown does not become free browsing time.
80. As a focus user, I want to cancel a pending reset, so that a momentary impulse does not end the session.
81. As a focus user, I want a final confirmation after the reset countdown, so that ending the session remains intentional.
82. As a focus user, I want an early reset recorded as ended early, so that history distinguishes it from success.
83. As a focus user, I want Command-Q and ordinary Quit to use the early-reset flow, so that normal quitting is not an instant bypass.
84. As a focus user, I accept that Force Quit remains a deliberate bypass, so that StayPane does not make false tamper-resistance claims.
85. As a focus user, I want normal timer completion to end enforcement immediately, so that access returns at the promised time.
86. As a focus user, I want only windows StayPane minimized restored, so that my earlier workspace choices are preserved.
87. As a focus user, I want windows already minimized before the session to remain minimized afterward, so that StayPane does not reveal them unexpectedly.
88. As a focus user, I do not want StayPane to reopen applications or windows I closed during the session, so that user actions are respected.
89. As a focus user, I want restoration failures isolated and reported, so that one problematic window does not prevent everything else from unlocking.
90. As a focus user, I want a completion notification, gentle sound, and brief completed state, so that I know the focus block ended.
91. As a focus user, I do not want a break or another focus session started automatically, so that v1 remains a one-session tool.
92. As a focus user, I want the timer to continue while the Mac sleeps or the screen is locked, so that the promised end time remains fixed.
93. As a focus user, I want an active session restored after an accidental StayPane crash, so that focus protection is reliable.
94. As a focus user, I want an unfinished session resumed after logout or restart when time remains, so that restarting does not accidentally cancel it.
95. As a focus user, I want StayPane to launch at login by default, so that restart recovery can happen automatically.
96. As a focus user, I want a warning if I disable Launch at Login, so that I understand the recovery limitation.
97. As a focus user, I want a session that expired while StayPane was unavailable completed and its windows restored at the next launch, so that stale enforcement state is cleaned up.
98. As a focus user, I want StayPane to fail open if Accessibility permission disappears, so that broken enforcement cannot trap me.
99. As a Chrome user, I want StayPane to fail open if the extension or native bridge disconnects during a tab-restricted session, so that partial enforcement is never misrepresented.
100. As a focus user, I want system failures recorded as Interrupted rather than Completed or Ended Early, so that history remains truthful.
101. As a privacy-conscious user, I want active recovery state stored only on my Mac, so that sessions do not require a server.
102. As a privacy-conscious user, I want window titles, tab titles, URLs, and domains excluded from completed history, so that sensitive work is not retained.
103. As a focus user, I want history to show start time, planned duration, actual focus time, and result, so that I can review basic focus activity.
104. As a focus user, I want only the latest 100 sessions retained, so that history remains bounded.
105. As a focus user, I want to clear all history with confirmation, so that I control retained activity data.
106. As a privacy-conscious user, I want diagnostic logs to redact window titles and URLs, so that troubleshooting does not expose content.
107. As a privacy-conscious user, I want no automatic crash reporting or telemetry, so that StayPane never sends data silently.
108. As a contributor, I want users to export and inspect diagnostics explicitly, so that support remains possible without background collection.
109. As a keyboard user, I want every setup and session action keyboard-accessible, so that I can operate StayPane without a pointer.
110. As a VoiceOver user, I want meaningful labels, grouping, and status announcements, so that the interface is understandable nonvisually.
111. As a user with visual preferences, I want StayPane to respect dark mode and increased contrast, so that it matches my system.
112. As a user sensitive to animation, I want StayPane to respect Reduce Motion, so that countdown and blocking feedback remain comfortable.
113. As an English-speaking early adopter, I want clear English copy, so that the v1 workflow is understandable even before localization exists.
114. As an open-source user, I want a documented Xcode build and setup command, so that the Mac app and native bridge can be installed consistently.
115. As an open-source Chrome user, I want documented Developer Mode installation, so that the extension can be loaded without payment.
116. As an open-source user, I want updates to be explicit through Git and rebuilding, so that StayPane performs no hidden network checks.
117. As a contributor, I want the repository licensed under MIT, so that reuse and contribution terms are simple and permissive.
118. As a contributor, I want one repository for the Mac app, extension, and bridge, so that cross-component changes remain coordinated.
119. As a contributor, I want separate product, Mac app, Chrome extension, and bridge domain contexts, so that specialized language stays clear.
120. As a maintainer, I want browser enforcement behind an adapter boundary, so that Safari, other Chromium browsers, and Firefox can be added later without rewriting the Session Engine.

## Implementation Decisions

- The public product name is **StayPane**. The working tagline is “Stay with what you chose.”
- StayPane is an honest self-control tool. It does not claim to resist Force Quit, administrator actions, source modification, uninstalling, permission revocation, or disabling the browser extension.
- The v1 license is MIT. Source code, build instructions, and manual installation instructions are the distribution product; v1 does not include signed or notarized binaries.
- The officially supported v1 platform is Apple-silicon hardware on macOS 26 or newer. The implementation should avoid needless restrictions that prevent future older-macOS or Intel contributions.
- The repository is a monorepo with four domain contexts: shared product policy, macOS application and window enforcement, Chrome extension and tab enforcement, and the native messaging bridge.
- The Mac application uses Swift 6. SwiftUI provides ordinary interface screens; AppKit and the macOS Accessibility APIs provide menu-bar, window, and cross-application behavior.
- The Chrome extension uses TypeScript and Chrome Manifest V3. A small local native-messaging bridge connects it to the Mac application.
- No cloud service, user account, remote configuration, analytics, telemetry, or automatic update check exists in v1.
- The central behavioral module is the **Session Engine**. It owns session policy and state transitions without depending directly on SwiftUI, Accessibility objects, Chrome APIs, wall-clock APIs, or persistence implementations.
- The Session Engine receives commands and external events, exposes observable session state, and requests effects through ports. Relevant events include configuration, start countdown, blocked-target activation, sleep/wake, clock progress, completion, reset request/cancellation/confirmation, permission loss, extension loss, crash recovery, and login recovery.
- The Session Engine requests effects for target enforcement, focus restoration, browser policy, persistence, history, and user notices. Adapters perform those effects and report success or failure.
- Principal session states are idle, configuring, ready, starting, enforcing, reset-pending, completed, ended-early, and interrupted. Terminal states include a reason and enough timing data for history.
- A session is one non-repeating focus interval. There is no pause, target editing, duration editing, automatic break, or automatic repeat after starting.
- The default duration is 30 minutes. Valid custom durations range from 10 seconds through 24 hours. The last duration is remembered, and the user can reset it to 30 minutes.
- A session must include at least one user-selected target. StayPane itself and essential macOS interfaces are implicit system allowances rather than user targets.
- The target hierarchy is application, window, then browser tab. Selecting a parent allows everything underneath it and disables redundant child selection.
- Application-level targets may reference running or closed installed applications. Individual windows and tabs must exist when selected.
- Application targets allow all current and future windows from that application. Window targets allow only the selected window plus qualifying transient child UI. Newly created independent windows remain blocked.
- An individually selected window that closes is no longer available. A reopened window is a new blocked window. If every selected target closes, the session continues with StayPane accessible.
- The picker shows application icons, window titles, Chrome tab titles, hostnames, and favicons. Hovering an entry outlines the real window. No screenshot or thumbnail collection is used, and Screen Recording permission is not requested.
- Before starting, the user sees a final summary of duration, targets, browser scopes, broad-selection warnings, integration state, and the macOS Focus reminder. A cancelable three-second countdown follows confirmation.
- The allowlist and duration become immutable when the start countdown completes.
- On session start, StayPane records existing window state and minimizes disallowed windows. It must distinguish windows already minimized from windows it minimized.
- A blocked activation causes the target to be minimized when possible and focus to return to the last allowed target. StayPane does not quit the owning application.
- Block feedback is quiet and rate-limited. It identifies the blocked application or window when safe and shows remaining session time.
- Enforcement covers all connected displays and macOS Spaces. StayPane does not intentionally move, resize, or change the Space of an allowed window.
- Essential macOS authentication prompts, permission prompts, and critical alerts remain accessible. Temporary sheets, modal dialogs, and utility UI attached to an allowed window may be temporarily allowed; unrelated independent windows remain blocked.
- Content inside an allowed non-browser application or window is unrestricted. StayPane documents this as an honest limitation rather than attempting unreliable universal control of internal app UI.
- Chrome offers three target breadths. Selecting the application permits all Chrome windows, tabs, and sites. Selecting a Chrome window permits all current and future tabs in that window. Selecting individual tabs enables per-tab navigation scopes.
- Multiple individual Chrome tabs may be selected. Each tab independently uses Current Website or Exact Page scope.
- Current Website permits top-level HTTP or HTTPS navigation on the selected hostname, across paths and query parameters, but not other hostnames.
- Exact Page requires the original hostname, path, and query parameters. URL fragments are ignored so in-page anchors remain usable.
- When an allowed link attempts to open a new tab, an in-scope destination is moved into the original allowed tab and the new tab is closed. An out-of-scope new tab is closed and the original tab remains unchanged.
- Reloading an allowed tab is permitted. Duplicated, detached, newly created, or newly activated unapproved tabs are blocked unless a broader Chrome window or application target permits them.
- The extension must be installed and connected for every selected Chrome profile. A session containing tab-level targets cannot start if any selected profile fails preflight.
- Incognito tab targeting is unsupported in v1. Incognito windows are treated as blocked during a tab-restricted session unless the whole Chrome application is allowed.
- If the extension, native bridge, or required Accessibility permission becomes unavailable during enforcement, StayPane fails open. It stops claiming enforcement, restores what it can, marks the session Interrupted, explains the failure, and requires repair before another session.
- The native bridge communicates locally only. Its registration must restrict callers to the expected extension identity and validate every message crossing the browser/native boundary.
- The Chrome extension requests only permissions required for tab identity, navigation observation, local policy state, and native messaging. It does not send browsing data to a remote service.
- The active timer is defined by a fixed end time and continues through sleep, screen lock, logout, application termination, and restart. In-process timing should use a continuous monotonic clock; persisted recovery uses the stored end time and remaining session data.
- Active session recovery data includes the immutable configuration, end time, enforcement status, and enough window identity/state to resume or restore. Sensitive recovery data is local and removed when no longer necessary.
- StayPane launches at login by default. Disabling Launch at Login is allowed, but the UI explains that automatic restart recovery is no longer guaranteed.
- On relaunch, StayPane resumes a still-active session. If the end time passed while StayPane was unavailable, it restores remaining windows and completes the session rather than restarting enforcement.
- Ordinary Quit and Command-Q invoke the early-reset flow during an active session. Force Quit remains outside the honest enforcement boundary.
- End Session Early starts a 30-second countdown while enforcement remains active. The countdown can be canceled. When it finishes, a final confirmation ends enforcement and records Ended Early.
- Normal completion stops enforcement immediately, restores eligible windows, records Completed, shows a macOS notification, plays a gentle sound when allowed, and briefly displays Session Complete.
- Restoration applies only to windows StayPane minimized. Windows already minimized remain minimized; windows closed by the user are not reopened. A failure restoring one window does not block restoration of others.
- Window state restoration preserves position, size, display, and Space by avoiding changes to those properties. Where macOS prevents exact restoration, StayPane reports the limitation without blocking unlock.
- The primary interface is a menu-bar application. The setup and active-session panel is reachable from the menu bar and a non-destructive global open-panel shortcut. There are no global start, reset, or quit shortcuts.
- The remaining time appears in the menu bar while active. An optional native floating timer is movable, collapsible, hideable, and remembers position and collapsed state. It is not injected into webpages.
- macOS Focus integration is reminder-based in v1. StayPane may open Focus settings and explain notification behavior but does not automate Control Center or use private APIs.
- First-run onboarding covers the honest boundary, local-only privacy, Accessibility permission, optional Chrome setup, connection verification, and a harmless enforcement test.
- Notification permission is optional. If denied, in-app and menu-bar completion feedback remains available.
- Completed session history contains start time, planned duration, actual focus time, and one of Completed, Ended Early, or Interrupted. It never contains application names, window titles, tab titles, URLs, or domains.
- History retains the latest 100 sessions and supports confirmed full deletion.
- Diagnostic logs are bounded and redact window titles, tab titles, URLs, and domains. There is no automatic crash reporting. Users explicitly export and inspect diagnostics before sharing.
- The v1 interface is English-only but supports keyboard navigation, VoiceOver labels and announcements, dark mode, increased contrast, and Reduce Motion.
- Source installation includes a documented Xcode build and one setup command for local native-bridge registration. Chrome extension installation uses Developer Mode and Load Unpacked. Updates are manual Git pulls, rebuilds, and extension reloads.
- The project uses Local Markdown for its initial specification and tickets. All implementation tickets are built as test-driven vertical slices and reviewed against this specification before completion.
- The browser integration is behind an adapter boundary. The roadmap order is Safari, other Chromium browsers, then Firefox; app-specific internal-content integrations are demand-driven and not assumed to be universal.

## Testing Decisions

- Good tests assert externally observable policy: session state, requested effects, persisted recovery, history outcomes, and user-visible notices. They do not assert private method calls, internal collection types, SwiftUI view structure, or incidental timing implementation.
- The highest behavioral seam is the Session Engine. Most acceptance behavior is exercised through its public commands/events and observable state using a simulated continuous clock and in-memory ports.
- Session Engine tests cover every state transition, invalid command, timer boundary, cancellation race, failure path, sleep/wake path, recovery path, and terminal history result.
- Table-driven policy tests cover the application/window/tab hierarchy, parent-child redundancy, new-window behavior, closed-target behavior, transient-dialog decisions, and broad Chrome selection behavior.
- Timer tests use controlled time rather than real sleeping. They cover the 10-second minimum, 24-hour maximum, exact completion boundary, reset countdown, sleep counting, wall-clock recovery, and clock-change resilience.
- Persistence tests save and reload active sessions at each meaningful state. They verify that sensitive recovery data is removed after completion and that expired sessions restore rather than resume.
- Restoration tests verify that only StayPane-minimized windows are restored, pre-minimized windows remain minimized, closed windows are ignored, and one restoration failure does not stop the rest.
- The macOS enforcement adapter receives integration tests against controlled fixture applications and windows. Tests verify discovery, identity, minimize, restore, activate, focus observation, transient-dialog classification, and permission failure without touching unrelated user windows.
- Multi-display, Spaces, full-screen, sleep, logout, login-item, and real system-dialog behavior receive documented manual acceptance tests because they depend on macOS window-server behavior that is unsuitable for hermetic unit tests.
- The Chrome extension receives automated tests for tab activation, creation, duplication, detachment, reload, Current Website matching, Exact Page matching, new-tab redirection, profile identity, Incognito rejection, and notice rate limiting.
- The native bridge receives contract tests for handshake, extension identity, message schema validation, malformed messages, connection loss, reconnection, and local-only transport.
- Cross-component integration tests run the Session Engine, bridge protocol, and extension policy against fakes at each platform edge. A small real-Chrome manual suite validates unpacked installation and native messaging.
- Onboarding tests cover denied, granted, revoked, and stale permissions; missing and connected extensions; failed bridge setup; and successful harmless enforcement verification.
- UI tests cover target hierarchy presentation, broad-selection warnings, final review, countdown cancellation, active panel status, early-reset flow, history clearing, accessibility labels, and reduced-motion behavior.
- Privacy tests verify that history, diagnostics, persistence after completion, and exported logs contain none of the prohibited content fields.
- Installation smoke tests start from a fresh clone on a supported Mac, build the app and bridge, register native messaging, load the unpacked extension, grant Accessibility permission, and complete a short real session.
- A release candidate must pass the automated suite plus a manual end-to-end matrix covering normal completion, early reset, app crash, Mac restart, permission loss, extension loss, multiple displays, Spaces, full screen, and restoration failures.
- This is a greenfield repository, so there is no existing test prior art. The first vertical slice establishes the test harness and conventions that later tickets must reuse.

## Out of Scope

- Tamper-proof, parental-control, enterprise-compliance, security-boundary, or administrator-resistant behavior.
- Automatic Pomodoro breaks, repeating cycles, schedules, streaks, productivity scores, charts, or saved session templates.
- Pause, duration edits, allowlist edits, or temporary target exceptions during an active session.
- A block-everything mode with no user-selected targets.
- Website blocklists independent of selected Chrome tabs.
- Deep control of content inside allowed non-browser applications, including Slack channels, Discord chats, Terminal commands, VS Code editors or terminals, Spotify content, and Finder tabs.
- Safari, Firefox, Edge, Brave, Arc, Vivaldi, or other browser integrations in v1.
- Incognito tab targeting.
- Automatic control of macOS Focus or Notification Center through private APIs, UI scripting, or unsupported mechanisms.
- Window thumbnails, screenshots, Screen Recording permission, or recording screen content.
- Cloud sync, accounts, servers, remote policy, analytics, telemetry, automatic crash upload, or background update checks.
- Signed and notarized public binaries, Mac App Store distribution, Chrome Web Store distribution, or paid developer accounts.
- iPhone, iPad, Windows, Linux, Android, or web versions.
- Official support for Intel Macs or macOS versions earlier than 26 in v1.
- Localization beyond English in v1.
- Reopening windows or applications that the user closed during a session.
- Guaranteeing exact restoration when macOS or the target application no longer exposes the original window.

## Further Notes

- The product directory may still use its earlier local folder name during planning; public-facing product language and future repository naming should use StayPane.
- StayPane should consistently use the terms **session**, **target**, **allowlist**, **application target**, **window target**, **tab target**, **navigation scope**, **enforcement**, **early reset**, **completed**, **ended early**, **interrupted**, and **fail open**. The future domain contexts should define these terms precisely and reject drifting synonyms.
- Window-level enforcement depends on the macOS Accessibility API and the quality of accessibility information exposed by each target application. Unsupported or inconsistent applications must fail honestly rather than receive special undocumented behavior.
- Chrome tab enforcement depends on the Tabs API and Native Messaging. The manual setup must establish a stable extension identity or safely register the actual unpacked identity before the bridge is considered connected.
- A future signed release would require Apple Developer Program membership, Developer ID signing, and notarization, but none of these are prerequisites for the source-only v1.
- Before broader public branding, StayPane should receive a formal repository, domain, application-name, and trademark review. The current name was selected after a preliminary conflict screen, not a legal clearance.
- Relevant platform references include Apple’s Accessibility API documentation, Chrome’s Tabs API documentation, and Chrome’s Native Messaging documentation.
