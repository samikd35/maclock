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

**Status Panel**:
The native StayPane interface that presents setup while idle and immutable Session status while enforcement is active.
_Avoid_: Popup, dashboard, setup window

**Session Presence**:
The calm native status shown across the menu bar, Status Panel, and optional Floating Timer during and briefly after a Session.
_Avoid_: Native presence, timer chrome

**Floating Timer**:
An optional movable native countdown that stays above work and can collapse or hide without affecting the menu-bar countdown.
_Avoid_: Overlay, webpage timer, widget

**Open-Panel Shortcut**:
The sole global shortcut, whose only effect is to reveal the Status Panel.
_Avoid_: Action shortcut, reset shortcut
