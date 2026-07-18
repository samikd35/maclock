# Product Policy

This context defines the shared language for committing to a focus interval and choosing what remains available. It is independent of any platform's window or browser APIs.

## Language

**Session**:
One non-repeating focus interval whose duration and allowlist become immutable when enforcement starts.
_Avoid_: Timer, cycle, Pomodoro

**Target**:
A user-selected application, window, or browser tab that may remain available during a Session.
_Avoid_: Exception, item

**Allowlist**:
The immutable set of Targets selected for an active Session, plus implicit essential system allowances.
_Avoid_: Whitelist, permitted apps

**Application Target**:
A broad Target representing an application and all of its current and future content.
_Avoid_: App lock, application exception

**Window Target**:
A precise Target representing one currently existing window and qualifying transient children attached to it.
_Avoid_: Window title, document target

**Exact Window Identity**:
The identity of one currently existing window. Closing it ends that identity; a reopened window with the same title has a new identity.
_Avoid_: Window title match, reopened target

**Fail Open**:
The outcome in which StayPane stops enforcement and restores what it can because it can no longer enforce the complete Allowlist reliably.
_Avoid_: Unlock error, bypass
