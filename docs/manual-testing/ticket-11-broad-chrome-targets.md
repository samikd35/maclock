# Ticket 11 manual acceptance: broad Chrome targets

These checks cover real Chrome window focus, tab creation, and tab movement. Use one ordinary non-Incognito Chrome profile with StayPane Chrome Companion 0.4.0 loaded and connected.

## Hierarchy and warnings

1. Open at least two Chrome windows with two tabs in each, then expand Google Chrome in StayPane.
2. Select Chrome as an Application Target. Confirm every Chrome window and tab control is disabled and the warning says all current and future Chrome windows, tabs, and websites are allowed without Navigation Scopes.
3. Deselect the application. Confirm Chrome window and tab controls become selectable again.
4. Select one Browser Window Target. Confirm only its child tab controls are disabled and the warning says every current and future tab and website in that window is allowed without Navigation Scopes.
5. Deselect the Chrome window. Confirm its individual tabs can be selected again.
6. Select one broad Chrome window and one individual tab in the other window. Confirm the review shows both breadths and shows a Navigation Scope only for the Tab Target.
7. Give two Chrome windows the same active-tab title, then hover each Browser Window Target and verify StayPane outlines the correct real Chrome window using its observed frame rather than its title.
8. Before starting, close a selected Chrome window. Confirm its Browser Window Target disappears from the draft instead of remaining as an invisible stale selection.

## Enforcement

1. Start a short Session with one Browser Window Target. Navigate existing tabs in that window to unrelated websites and create additional tabs; all must remain available.
2. Activate the other Chrome window. StayPane must minimize it, return Chrome to the selected window, and show only rate-limited feedback.
3. Create a new tab in the selected window. It must remain available without being added to the immutable allowlist.
4. Drag a tab from the selected window to the unselected window while it is active. StayPane must return to the selected window.
5. Drag a tab from the unselected window into the selected window. It must become available because of the window identity, without becoming a Tab Target.
6. In a mixed broad-window and precise-tab Session, move the precise tab into the broad window, navigate outside its original scope, then move it back out. Its original Navigation Scope must immediately apply again.
7. Open or focus an additional Chrome window created after Session start. It must be minimized unless Chrome was selected as an Application Target.
8. Start with an uncovered Chrome window already minimized, restore it during the Session, and confirm StayPane re-minimizes it. At completion, it must remain minimized because StayPane did not create its original minimized state.

## Completion and closure

1. Let the Session complete normally. Confirm Chrome enforcement stops and StayPane restores only macOS and Chrome windows it minimized; windows already minimized before the Session stay minimized.
2. Repeat with Chrome selected as an Application Target. Confirm all existing and newly created Chrome windows, tabs, and websites remain available throughout the Session.
3. Close a selected Chrome window during a mixed Session. Confirm the Session and Fixed End Time continue with the remaining Targets and no sibling policy broadens.
4. If Chrome refuses one Restoration during a diagnostic run, confirm the extension shows a persistent error badge and retains the local Restoration entry for a later retry while other windows still restore.

## Automated coverage

- `make test` covers the application/window/tab selection hierarchy, parent-child redundancy, bridge protocol v4, mixed target preflight, closure notices, and Session Engine coordination.
- `make test-extension` covers new tabs and arbitrary websites inside a broad window, uncovered-window minimization and restoration, movement across the selected-window boundary, precise-scope reapplication, runtime closure, mixed-target storage, and serialized lifecycle events.
