# Chrome Extension

This context describes the Chrome-owned identities and observations used to make an individual Tab Target enforceable without treating a title or URL as identity.

## Language

**Chrome Profile**:
One Chrome profile in which the StayPane extension has its own stable local identity and Bridge Connection.
_Avoid_: Browser account, Chrome user, extension instance

**Tab Snapshot**:
The current local description of open non-Incognito tabs grouped by their Chrome window identities.
_Avoid_: Tab history, browsing log, tab cache

**Tab Activation Enforcement**:
Returning Chrome to the selected Tab Target when another tab becomes active during a Session.
_Avoid_: Tab blocking, tab closing, navigation enforcement

**Blocked Tab Activation**:
An attempt to activate a tab other than the selected Tab Target while Tab Activation Enforcement is active.
_Avoid_: Blocked website, navigation violation
