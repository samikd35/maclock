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

**Current Website**:
The default Navigation Scope for an individual Tab Target. It permits top-level HTTP and HTTPS navigation on the selected hostname across paths, queries, ports, and fragments; a subdomain is a different hostname.
_Avoid_: Domain allowlist, same origin, URL prefix

**Last Allowed Page**:
The most recent fully completed page within Current Website. StayPane returns the selected Tab Target here after a disallowed navigation commits.
_Avoid_: Browser history, previous URL, saved page

**Blocked Navigation**:
A top-level navigation outside the selected Tab Target's Navigation Scope. It returns the selected tab to its Last Allowed Page without changing the immutable scope.
_Avoid_: Blocked website, unsafe URL, tab activation
