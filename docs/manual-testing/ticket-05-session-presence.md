# Ticket 05 manual acceptance: Session Presence

These checks validate Dock, menu-bar, panel, floating-window, shortcut, full-screen, and notification-denial behavior that cannot be proven by the pure presentation tests. Install with `make install` and record the macOS version, StayPane commit, and pass/fail result for each section.

## Menu bar and Status Panel

1. With no active Session, click StayPane in the menu bar. The Status Panel must show setup controls.
2. Start a short Session. The menu-bar title must change to the remaining focus time and update as time passes.
3. Click the menu-bar item again. The Status Panel must show remaining time, selected Targets, active enforcement, Floating Timer controls, and End Session Early. Duration and Target editing must not be available.
4. Request an early reset. The menu bar must continue to include the focus time, and the Status Panel must keep showing the enforced reset flow.

## Floating Timer

1. Start a Session with the Floating Timer preference visible. Confirm the native Floating Timer appears above ordinary application windows without any browser extension or webpage injection.
2. Drag it by the visible handle to another position and, when available, another display. It must remain movable and must not activate blocked content.
3. Drag any edge or corner to resize continuously. The Floating Timer and countdown must remain proportional, stay completely on a connected display, and continue counting down. In Settings, verify the size slider and **Reset to Medium** provide keyboard and VoiceOver alternatives.
4. Collapse it into the compact pill, then expand it. The countdown must remain visible and movable in both layouts.
5. Hide it from either the Floating Timer or Status Panel. The menu-bar countdown must remain visible and the Status Panel must offer Show Floating Timer.
6. Show it, move it, resize it, and collapse it. Complete or end the Session, quit while idle, relaunch, and start another short Session. Its saved position, size, and collapsed state must be restored. A Floating Timer hidden during the prior launch defaults to visible again.
7. Repeat with an allowed application in native full screen. The Floating Timer must remain available as auxiliary native UI without exiting full screen.
8. Navigate the active Status Panel and Settings with the keyboard and VoiceOver. The size slider, Reset to Medium, Collapse/Expand, Hide/Show, and Move to Top Right must provide non-drag alternatives for every Floating Timer control.

## Global Open-Panel Shortcut

1. Close the standalone Status Panel and switch to another application.
2. Press Control-Option-Command-S (`⌃⌥⌘S`). StayPane must activate and show the Status Panel for the current state.
3. During an active Session, press the shortcut and verify it only opens the Status Panel. It must not start, reset, end, or quit a Session.
4. If another application already owns the shortcut, StayPane must report the conflict while the menu-bar panel remains usable.

## Notification denial

1. Deny or disable StayPane notification permission if it appears in System Settings.
2. Repeat setup, active status, Floating Timer controls, normal completion, and the early-reset flow.
3. Every in-app and menu-bar interaction must remain usable. StayPane does not require notification permission for Ticket 05.
4. Complete a short Session and verify the menu-bar title briefly says Session Complete while the Status Panel shows its completion state.

## Automated companion checks

Run `make test`. The tests cover menu-bar presence for active, reset-pending, and terminal states; persisted Floating Timer position, size, and collapsed layout; session-local hiding; and the single-purpose Open-Panel Shortcut definition.
