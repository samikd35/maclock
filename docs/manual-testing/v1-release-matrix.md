# StayPane v1 release acceptance matrix

Run this matrix on the exact commit proposed for a source-only v1 release. Automated checks are necessary but cannot substitute for macOS window-server, permission, Chrome Profile, sleep, crash, logout, or restart behavior. A release passes only when every applicable row is recorded as **Pass**; **Fail**, **Blocked**, and blank results prevent release.

## Release record

| Field | Value |
| --- | --- |
| Commit SHA | |
| Date and tester | |
| Mac model and Apple silicon chip | |
| macOS version | |
| Xcode and Swift versions | |
| Node.js and npm versions | |
| Chrome and companion versions | |
| Chrome Profiles used | |
| Displays and Spaces used | |
| Overall result: Pass / Fail / Blocked | |

Do not record application names, document titles, tab titles, URLs, domains, or other private Target content in this file. Use generic fixture labels and redacted Diagnostics only.

## Clean-source gate

1. Use a disposable macOS user account with no previous StayPane data or Native Host Registration.
2. Follow only [`../INSTALL.md`](../INSTALL.md), beginning with a fresh `git clone`.
3. Run `make verify`. Record **Pass** only if the release contract, Swift suite, Chrome-extension suite, app build, Native Bridge build, and package audit all pass.
4. Run `make setup-chrome` and confirm it prints the user-level manifest path without requiring a paid developer account.
5. Run `make run`, complete First-Run Onboarding, and confirm no Screen Recording request appears.

| Gate | Expected result | Result | Notes |
| --- | --- | --- | --- |
| Fresh clone | No ignored build output or machine-local state is required. | | |
| Automated verification | `make verify` passes with summarized, redacted output. | | |
| Native Host Registration | The manifest points to the packaged bridge, accepts only the fixed extension identity, and has owner-only permissions. | | |
| Unsigned source distribution | The locally built app is ad-hoc signed; no Developer ID, notarization, Web Store, or paid-account claim is made. | | |
| First-Run Onboarding | Accessibility, honest boundary, local-only privacy, optional Chrome setup, and Harmless Window-Control Verification work from the public guide. | | |

## Short Real Session

This is the minimum public-instructions smoke test.

1. Open one disposable fixture document in a native application and choose its exact Window Target.
2. Choose a 10-second Session, review its Allowlist, and finish the cancelable three-second countdown.
3. Confirm an unrelated fixture window is minimized while the chosen window remains usable.
4. Wait for Normal Completion without invoking Early Reset.
5. Confirm the unrelated window is restored only if StayPane minimized it, the menu bar and Status Panel show Session Complete even with notifications denied, and Session History contains only timing and Completed.
6. Relaunch StayPane and confirm the completed Session does not resume.

| Case | Expected result | Result | Notes |
| --- | --- | --- | --- |
| Short Real Session | A first-time technical user can build, configure, complete, and inspect one Session using only public documentation. | | |
| Normal Completion | Enforcement stops at the Fixed End Time, eligible windows are restored, and the Session Result is Completed. | | |

## Native application and macOS lifecycle matrix

Use the detailed procedures in [Ticket 04 window enforcement](ticket-04-window-enforcement.md), [Ticket 05 Session Presence](ticket-05-session-presence.md), and [Ticket 06 Recovery](ticket-06-recovery.md).

| Case | Expected result | Result | Notes |
| --- | --- | --- | --- |
| Early Reset | The 30-second waiting period keeps enforcement active; cancel preserves the Session, refusal keeps focusing, and confirmation yields Ended Early. | | |
| Closed Targets | Closing an exact Window Target never allows a reopened lookalike, and the Session continues when every selected Target closes. | | |
| Transient Child Interface | A sheet or modal attached to an allowed window remains usable while unrelated Independent Windows stay blocked. | | |
| Multiple Displays | The Allowlist is enforced across every connected display and only StayPane-minimized windows are restored. | | |
| Spaces | Blocked windows in other Spaces do not become available, and StayPane does not move allowed windows between Spaces. | | |
| Full Screen | An allowed full-screen window remains usable without moving or resizing; unrelated windows stay blocked and restore honestly. | | |
| Sleep and screen lock | The Fixed End Time continues; a Session ending during sleep completes and restores on wake rather than extending. | | |
| Application Crash | Relaunch before the Fixed End Time performs Recovery; unsafe Recovery uses Fail Open and Interrupted. | | |
| Mac Restart and logout | Launch at Login resumes remaining enforcement or completes an expired offline Session without reopening user-closed windows. | | |
| Accessibility Permission Loss | Revocation during enforcement triggers Fail Open, Restoration, Interrupted, and repair-required setup without trapping the user. | | |
| Restoration Failure | One failed window remains locally retryable and reported while other windows restore and the user regains control. | | |
| Notification denial | Status Panel and menu-bar completion feedback remain available without notification permission. | | |
| Keyboard, VoiceOver, contrast, and motion | The Ticket 13 matrix passes the complete setup, active, reset, History, Diagnostics, and completion flow. | | |

## Chrome Integration matrix

Install the unpacked companion in at least two ordinary Chrome Profiles and enable **Allow in Incognito**. Use the detailed procedures in [Ticket 08 Chrome setup](ticket-08-chrome-tab.md), [Ticket 09 Current Website](ticket-09-current-website.md), [Ticket 10 multiple scopes](ticket-10-multiple-tab-scopes.md), [Ticket 11 broad Chrome Targets](ticket-11-broad-chrome-targets.md), and [Ticket 12 profiles and Fail Open](ticket-12-chrome-profiles-and-fail-open.md).

| Case | Expected result | Result | Notes |
| --- | --- | --- | --- |
| Developer Mode installation | Load unpacked, Reload, Test Connection, Remove, and reinstall work using the public installation guide. | | |
| Multiple Tab Targets | Several selected tabs remain independent; closing one does not broaden another or end the Session. | | |
| Navigation Scopes | Current Website and Exact Page enforce their documented hostname/path/query boundaries, link transfer, reload, and Blocked Navigation return to the Last Allowed Page. | | |
| Broad Chrome Application Target | Every Chrome window, tab, website, and Incognito window is intentionally allowed with a visible breadth warning. | | |
| Browser Window Target | Current and future tabs in only the selected Chrome window remain available; other Chrome windows stay blocked. | | |
| Multiple Chrome Profiles | Every Required Profile is independently Ready and confirms enforcement before start or Recovery. | | |
| Incognito | Incognito tabs remain unselectable; Incognito windows are minimized for Browser Window or Tab Target enforcement. | | |
| Native Bridge Loss | Terminating the bridge or disabling a required companion triggers complete Fail Open and Interrupted; reconnect never restarts that Session. | | |
| Malformed or wrong-identity connection | The bridge rejects the caller without exposing browsing content or weakening an active Allowlist. | | |
| Chrome Restoration Failure | Failed Restoration remains locally retryable and visible without preventing Fail Open or native window Restoration. | | |

## Privacy and removal matrix

Use the [Ticket 07 privacy procedure](ticket-07-privacy.md) and inspect the built package before release.

| Case | Expected result | Result | Notes |
| --- | --- | --- | --- |
| Local-only artifacts | Session History, active Recovery, Diagnostics, and Diagnostic Export contain no prohibited Target or browsing content. | | |
| No silent network behavior | No account, server, analytics, telemetry, automatic crash upload, remote policy, background update, or automatic Diagnostics submission occurs. | | |
| Remove Chrome Integration | Removing the companion and manifest disables browser Targets while native Application Targets and Window Targets remain usable. | | |
| Manual update | `git pull --ff-only`, `make verify`, `make setup-chrome`, and companion Reload update every local component explicitly. | | |

## Final sign-off

- [ ] Every matrix row is Pass on the recorded commit.
- [ ] `git status --short` is empty after verification except for ignored build products.
- [ ] Redacted failure logs and exported Diagnostics were inspected without private content.
- [ ] The Short Real Session was completed from a fresh clone using only public instructions.
- [ ] No signed-binary, notarization, store-distribution, unsupported-browser, or tamper-proof claim was introduced.
- [ ] The release commit and exact manual results were reviewed by a second person before publishing a public v1 tag.
