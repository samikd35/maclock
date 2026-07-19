# Native Bridge

This context describes the trusted local relationship between one Chrome Profile and the StayPane macOS application. The bridge transports validated messages and does not own Session policy.

## Language

**Native Bridge**:
The local-only messenger between the Chrome extension and StayPane that carries validated tab observations, optional Chrome window bounds for hover association, and enforcement commands.
_Avoid_: Server, browser backend, policy engine

**Handshake**:
The first validated exchange that confirms the protocol version, expected extension identity, and Chrome Profile before a Bridge Connection becomes usable.
_Avoid_: Login, pairing, authentication

**Bridge Connection**:
A live local channel established by a successful Handshake for one Chrome Profile.
_Avoid_: Account connection, network session, browser session

**Native Host Registration**:
The local Chrome configuration that permits only the expected unpacked extension identity to launch the Native Bridge.
_Avoid_: Extension install, account setup, server registration

**Browser Enforcement Command**:
A versioned Native Bridge command that atomically starts Chrome Target Enforcement with broad Chrome window identities and precise Tab Targets carrying their immutable Navigation Scopes.
_Avoid_: Website history, remote rule, browsing configuration

**Blocked Navigation Notice**:
A content-free Native Bridge event containing only the Chrome Profile and Tab Target identities needed to show bounded local feedback.
_Avoid_: URL report, browsing event, website telemetry

**Browser Target Closed Notice**:
A content-free Native Bridge event identifying an Available Browser Window Target or Available Tab Target that disappeared during a Session.
_Avoid_: Browser history, closed-page report, activity event
