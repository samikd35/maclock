# Native Bridge

This context describes the trusted local relationship between one Chrome Profile and the StayPane macOS application. The bridge transports validated messages and does not own Session policy.

## Language

**Native Bridge**:
The local-only messenger between the Chrome extension and StayPane that carries validated tab observations and enforcement commands.
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
