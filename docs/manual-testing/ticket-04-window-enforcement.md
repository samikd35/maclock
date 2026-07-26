# Ticket 04 manual acceptance: window enforcement

These checks exercise macOS WindowServer behavior that the hermetic policy suite cannot reproduce. Run them on a supported Mac after `make install`, with Accessibility access granted to the installed StayPane app. A 60-second session is long enough for most cases. Do not use documents with unsaved work for restoration tests.

Record the macOS version, StayPane commit, applications used, display arrangement, and pass/fail result for each row. These steps are the acceptance procedure; they are not marked as executed by the automated suite.

## Exact-window behavior

1. Open two independent windows in the same application and give them recognizable titles.
2. Expand the application's row in StayPane. Confirm both titles appear and hovering each entry outlines that real window without a Screen Recording prompt.
3. Select one window. Confirm selecting the whole application clears and disables its child choices; deselecting the application makes the window choices available again.
4. Start a session with only one exact window selected.
5. Activate its sibling, then create and activate a new independent window. Each blocked window should minimize and focus should return to the selected window.
6. Open a sheet attached to the selected window, such as Save As. It should remain usable. A sheet or modal attached to a blocked sibling must not make that sibling accessible.
7. Close the selected window. The session must continue and StayPane must remain accessible. Reopen a window with the same title; it is a new window and must be blocked.
8. Repeat with every selected exact window closed. The timer must continue until normal completion or the controlled early-reset flow finishes.

## Displays, Spaces, and full screen

| Scenario | Procedure | Expected result |
| --- | --- | --- |
| Multiple displays | Place the allowed window and blocked siblings across every connected display, note the allowed window's frame, then start a session. | Blocked windows on every display minimize. The allowed window stays on its original display with the same position and size. |
| Spaces | Put allowed and blocked windows on different Spaces, start a session, and switch between Spaces. | A blocked window does not become usable by changing Spaces. The allowed window remains in its original Space; StayPane does not move it. |
| Allowed full screen | Put the exact allowed window into native full screen before starting. Attempt to activate a blocked sibling and return to the full-screen Space. | The allowed window stays full screen and usable. StayPane neither exits full screen nor moves it to another Space or display. |
| System UI | During enforcement, trigger a normal macOS permission or authentication prompt from an allowed workflow. | Authentication, permission, and critical system UI remains usable. Dismissing it returns to the allowed workflow. |

## Restoration

Set up three blocked windows before starting: one visible, one already minimized, and one that you will close during enforcement.

Run the setup once through normal timer completion and once through the 30-second early-reset confirmation. In both cases:

- the visible window minimized by StayPane is restored;
- the pre-minimized window remains minimized;
- the user-closed window is not reopened;
- allowed-window position, size, display, and Space are unchanged;
- all blocking ends even if one window cannot be restored, and StayPane reports any pending restoration instead of holding the session locked.

The isolated restoration-failure path is also covered without touching desktop windows by `swift test --filter failedRestorationsRemainTrackedUntilARetrySucceeds`.

## Automated companion checks

Run `make test`. The suite covers target hierarchy, exact versus new window identity, transient-child policy, the session continuing after all exact targets close, pre-minimized and closed-window restoration, and isolated restoration failures.

For an opt-in check of the real Accessibility discovery/minimize/restore/raise adapter against a window created by the test itself, grant Accessibility access to the test host and run:

```sh
STAYPANE_RUN_AX_INTEGRATION_TESTS=1 swift test --filter systemAccessibilityAdapterControlsAFixtureWindowWhenOptedIn
```

The ordinary test suite never moves or minimizes unrelated desktop windows.
