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

**Tab Target**:
A precise Target representing one currently existing, non-Incognito browser tab within one Browser Profile. Its identity, not its title or URL, determines which tab remains available.
_Avoid_: Website target, tab title, browser exception

**Exact Window Identity**:
The identity of one currently existing window. Closing it ends that identity; a reopened window with the same title has a new identity.
_Avoid_: Window title match, reopened target

**Fail Open**:
The outcome in which StayPane stops enforcement and restores what it can because it can no longer enforce the complete Allowlist reliably.
_Avoid_: Unlock error, bypass

**Fixed End Time**:
The promised wall-clock end of an active Session, which does not move when StayPane, the screen, or the Mac is temporarily unavailable.
_Avoid_: Remaining duration, paused timer

**Recovery**:
Continuing an unfinished Session from its immutable Allowlist and Fixed End Time after StayPane becomes available again.
_Avoid_: Restart session, reopen session

**Interrupted**:
A terminal Session outcome produced when StayPane must Fail Open because complete enforcement or safe Recovery is no longer trustworthy.
_Avoid_: Failed, canceled, completed

**Session History**:
The bounded, local list of terminal Sessions containing only start time, planned duration, actual focus time, and Session Result.
_Avoid_: Activity log, tracking log, target history

**Session Result**:
The terminal classification of one Session: Completed, Ended Early, or Interrupted.
_Avoid_: Success flag, status code

**Diagnostics**:
A bounded, redacted local sequence of generic operational events used to troubleshoot StayPane without recording Target or browsing content.
_Avoid_: Analytics, telemetry, activity log

**Diagnostic Export**:
A local troubleshooting artifact created only by an explicit user action and opened for inspection before the user decides whether to share it.
_Avoid_: Crash upload, diagnostic submission, support report
