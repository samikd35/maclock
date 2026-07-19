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
Keeping Chrome activation within the Available Tab Targets and returning from an unapproved tab to the most recently activated Available Tab Target during a Session.
_Avoid_: Tab blocking, tab closing, navigation enforcement

**Blocked Tab Activation**:
An attempt to activate a tab that is not one of the Available Tab Targets while Tab Activation Enforcement is active.
_Avoid_: Blocked website, navigation violation

**Current Website**:
The default Navigation Scope for an individual Tab Target. It permits top-level HTTP and HTTPS navigation on the selected hostname across paths, queries, ports, and fragments; a subdomain is a different hostname.
_Avoid_: Domain allowlist, same origin, URL prefix

**Exact Page**:
A Navigation Scope that permits top-level HTTP and HTTPS navigation only when hostname, path, and query exactly match the selected page. URL fragments are ignored, so in-page anchors and ordinary reloads remain available.
_Avoid_: Exact URL, frozen page, URL prefix

**Available Tab Target**:
A selected Tab Target whose exact Chrome tab identity still exists. Closing one Tab Target removes it from the runtime available set without changing the immutable Session configuration or any other Navigation Scope.
When no Available Tab Targets remain, a newly activated unapproved tab closes instead of becoming a target; the Session and its Fixed End Time continue unchanged.
_Avoid_: Active tab, current tab, edited allowlist

**Last Allowed Page**:
The most recent fully completed page within a Tab Target's Navigation Scope. StayPane returns that exact Tab Target here after a disallowed navigation commits.
_Avoid_: Browser history, previous URL, saved page

**Blocked Navigation**:
A top-level navigation outside the selected Tab Target's Navigation Scope. It returns that Tab Target to its Last Allowed Page without changing the immutable Navigation Scope.
_Avoid_: Blocked website, unsafe URL, tab activation
