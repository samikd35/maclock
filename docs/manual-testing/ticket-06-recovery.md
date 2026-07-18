# Ticket 06 manual acceptance: Recovery

These checks exercise lifecycle behavior that cannot be proven hermetically because it depends on the macOS window server, login session, Accessibility database, and Service Management. Build with `make app`, run the packaged application, grant Accessibility permission, and record the macOS version, StayPane commit, target applications, and pass/fail result for every section.

Use short Sessions for sleep, lock, crash, permission, and expired-offline checks. Use a long enough Session for logout and restart checks. Do not use ordinary Quit for crash testing because ordinary Quit intentionally enters the early-reset flow.

## Fixed End Time through sleep and screen lock

1. Start a 30-second Session and record its expected Fixed End Time.
2. Put the Mac to sleep for longer than the remaining time, wake it, and confirm the Session completes immediately without adding the sleep duration.
3. Repeat while locking the screen instead of sleeping. Unlock after the Fixed End Time and confirm completion and Restoration.
4. Repeat with an early reset pending when sleep or lock begins. Normal completion must win if the Fixed End Time passes first.

## StayPane crash and relaunch

1. Start a Session containing both an Application Target and, in a separate run, a Window Target.
2. Confirm at least one Blocked Window was minimized by StayPane.
3. Force Quit only StayPane through Activity Monitor, leaving the target applications running.
4. Relaunch StayPane before the Fixed End Time. The menu bar and Status Panel must show the original remaining time and immutable Allowlist.
5. Confirm a surviving exact Window Target remains the same identity even if its title changed while StayPane was unavailable. A closed and reopened same-title window must remain blocked.
6. Complete or end the Session and confirm only windows StayPane changed are restored. Pre-minimized and user-closed windows must not be reopened.

## Expired while unavailable

1. Start a short Session, Force Quit StayPane, and leave the target applications running until after the Fixed End Time.
2. Relaunch StayPane. It must restore eligible windows, show the Session as Completed, and must not briefly resume enforcement.
3. Start another Session to confirm stale recovery data does not return.

## Accessibility permission loss

1. Start a Session, then disable StayPane under System Settings → Privacy & Security → Accessibility.
2. StayPane must stop all enforcement claims, restore what remains controllable, and show an Interrupted outcome in the menu bar and Status Panel.
3. Relaunch StayPane and verify that the Interrupted Session does not resume.
4. Restore Accessibility permission before starting another Session.

## Logout, restart, and Launch at Login

1. In StayPane setup, confirm Launch at Login is enabled. If macOS requires approval, use the offered Login Items settings action and approve StayPane.
2. Start a long Session, then log out. Log back in before the Fixed End Time and confirm StayPane launches and begins Recovery automatically.
3. Repeat with a Mac restart. Confirm the same Fixed End Time and Allowlist return.
4. Confirm StayPane does not reopen applications or windows closed by logout or restart. Manually launching an Application Target remains allowed; a recreated Window Target is a new blocked identity.
5. Disable Launch at Login and confirm StayPane explains that automatic Recovery after login is no longer guaranteed.
6. Repeat logout once with Launch at Login disabled. Confirm StayPane does not claim it will resume automatically; manually relaunching before the Fixed End Time still performs Recovery.

## Recovery data cleanup

1. Inspect `~/Library/Application Support/StayPane` during active and reset-pending Sessions. Local recovery files must exist and remain local.
2. Complete normally, end early, and trigger Interrupted in separate runs. After Restoration succeeds, active Session and changed-window recovery files must be removed.
3. Confirm no cloud request, application launch, or window reopening occurs during any Recovery path.

## Automated companion checks

Run `make test`. The suite covers fixed deadlines, active and reset-pending Recovery, elapsed reset confirmation, normal/early/Interrupted cleanup, expired-offline completion, file round trips, stable exact-window reconnection, and Launch at Login preference behavior using controlled clocks and local adapters.
