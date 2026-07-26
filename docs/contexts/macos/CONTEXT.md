# macOS Application

This context translates product Targets into observable macOS windows while preserving access to essential operating-system interactions.

## Language

**Independent Window**:
A window whose availability does not depend on another window. It requires its own Window Target unless its entire application is selected.
_Avoid_: Top-level content, sibling exception

**Transient Child Interface**:
A temporary sheet, modal dialog, or utility interface attached through a parent chain to another window. It inherits availability only from a selected ancestor.
_Avoid_: Any dialog, popup exception

**Essential System Interface**:
macOS-owned authentication, permission, or critical-alert UI that remains available without becoming a user-selected Target.
_Avoid_: System target, all Apple windows

**Blocked Window**:
An observed window that is neither represented by the active Allowlist nor covered by a qualifying transient or system allowance.
_Avoid_: Closed app, forbidden process

**Restoration**:
Returning only windows minimized by StayPane to their prior non-minimized state when enforcement stops.
_Avoid_: Reopen, workspace reset

**Unconfirmed Window Mutation**:
A single write-ahead record showing that StayPane was interrupted while changing a window, before the successful change could be confirmed locally. Recovery does not reveal this uncertain window automatically; it clears the record and tells the user to restore the window manually if needed.

**Status Panel**:
The native StayPane interface that presents setup while idle and immutable Session status while enforcement is active.
_Avoid_: Popup, dashboard, setup window

**Dock and Menu-Bar Presence**:
The installed regular application remains available in the Dock and Command-Tab while running and simultaneously exposes its menu-bar item. Closing the Status Panel does not quit either presence; opening the app or clicking its Dock icon reveals the Status Panel again.
_Avoid_: Menu-bar-only app, separate Dock helper

**First-Run Onboarding**:
The locally persisted introductory checklist that explains the honest self-control boundary, local-only privacy, Accessibility setup, optional Chrome setup, notification-independent completion feedback, and the Focus Reminder before ordinary Session setup.
_Avoid_: Account setup, signup, tutorial tour

**Accessibility Setup State**:
The honest result of macOS authorization plus StayPane's verification: Not Requested, Access Not Granted, Enabled but Unverified, Verified, or Revoked after earlier verification. Only Verified permits Session start.
_Avoid_: Permission boolean, trusted mode, security status

**Harmless Window-Control Verification**:
Writing one ordinary window's existing minimized value back unchanged to verify Accessibility control without moving, resizing, closing, revealing, or capturing window content.
_Avoid_: Test Session, screen test, sample enforcement

**Chrome Setup State**:
The First-Run Onboarding summary of local Native Bridge availability, Native Host Registration, and Chrome Profile Integration States: Native Bridge Unavailable, Native Host Not Registered, Waiting for Profile Connection, Synchronizing, Connected Profile Needs Attention, or Ready. Chrome setup remains optional until the user chooses a Browser Window Target or Tab Target.
_Avoid_: Chrome permission, browser security status, extension installed boolean

**Focus Reminder**:
The optional final-review guidance that can open macOS Focus settings while stating that StayPane does not automatically toggle Focus or automate Control Center.
_Avoid_: Focus integration, automatic Do Not Disturb, notification enforcement

**Session Presence**:
The calm native status shown across the menu bar, Status Panel, and optional Floating Timer during and briefly after a Session.
_Avoid_: Native presence, timer chrome

**Floating Timer**:
An optional movable and size-adjustable native countdown that stays above work and can collapse or hide without affecting the menu-bar countdown.
_Avoid_: Overlay, webpage timer, widget

**Open-Panel Shortcut**:
The sole global shortcut, whose only effect is to reveal the Status Panel.
_Avoid_: Action shortcut, reset shortcut

**Launch at Login**:
The user-controlled macOS registration that lets StayPane begin Recovery automatically after logout or restart.
_Avoid_: Autostart, startup helper
