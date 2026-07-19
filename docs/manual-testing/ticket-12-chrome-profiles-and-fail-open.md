# Ticket 12 manual acceptance: Chrome profiles and Fail Open

These checks exercise Chrome Profile isolation, Incognito-window control, and runtime failures that hermetic tests cannot fully reproduce. StayPane is honest self-control rather than a security boundary: Force Quit and deliberately removing its extension remain user-controlled bypasses. Use short Sessions and keep an ordinary macOS window outside Chrome open so restoration is easy to observe.

## Build and profile setup

1. Run `make app`, `make test`, and `make test-extension` from the repository root.
2. Open `.build/StayPane.app` and register the Native Host.
3. In two Chrome Profiles, enable Developer mode, load the packaged **StayPane Chrome Companion** 0.5.0, and enable **Allow in Incognito** in its details.
4. Confirm StayPane lists both Chrome Profiles separately, briefly shows Synchronizing while each first snapshot arrives, then shows Ready and groups each profile's windows and eligible HTTP or HTTPS tabs beneath the correct profile.
5. Confirm no Incognito tab, `chrome://` page, extension page, or other ineligible URL appears as a selectable Tab Target.

## Preflight and profile isolation

1. Select one ordinary tab from each Ready profile, review the Session, and confirm both profile statuses remain visible.
2. Start a short Session. Confirm both profiles enforce their own selected tab; equal-looking tab titles, URLs, or numeric tab identities across profiles must not collide.
3. End the Session, disable the companion in one selected profile, and review the same draft. That profile must show Disconnected with setup guidance, retain its selected Target for repair, and prevent start. The other profile remaining Ready is not sufficient.
4. Re-enable and reload the companion. Confirm the profile returns to Ready and a newly started Session waits for both profiles' independent confirmations.
5. Turn off **Allow in Incognito** for one profile. It must show Unsupported with precise guidance, publish no selectable browser Targets, and prevent its saved Target from starting. Re-enable the capability and reload before continuing.

## Incognito behavior

1. In a Ready profile, open one ordinary window and one Incognito window. Select an ordinary Tab Target and start a short Session.
2. Restore or activate the minimized Incognito window from Chrome's Window menu. Confirm the extension minimizes it again and returns Chrome to an Available Browser Window or Tab Target. Repeat after closing every selected browser Target; the Incognito window must still be re-minimized even though the attempted tab closes. The Incognito tab must never become part of the immutable Allowlist.
3. Let the Session end normally. Confirm StayPane restores the Incognito window only when the extension minimized it; a window already minimized before start remains minimized.
4. Repeat with an ordinary Browser Window Target. The uncovered Incognito window must still be minimized.
5. Repeat with Google Chrome selected as a broad Application Target. Confirm all ordinary and Incognito Chrome windows remain available, matching the explicit broad-target warning.

## Runtime loss and Fail Open

1. Start a Session with browser Targets from both profiles plus an allowed non-Chrome macOS window. Disable or reload the companion in one required profile.
2. Confirm StayPane immediately stops claiming enforcement, ends the Session as Interrupted, asks every surviving profile to stop, and restores eligible macOS windows even if Chrome cannot finish its own cleanup.
3. Re-enable the missing companion. Confirm reconnection shows current Targets but does not restart the terminated Session or reuse its Fixed End Time.
4. Repeat by quitting one selected Chrome Profile, killing the packaged Native Bridge process, and closing the user-only bridge connection. Each loss must Fail Open rather than continue partially.
5. Repeat normal completion and controlled Early Reset afterward to confirm a fresh Session still starts and ends normally.

## Relaunch Recovery

1. Start a short two-profile Session, quit StayPane through a crash-style termination, and leave enough time before its Fixed End Time.
2. Relaunch with only one required Chrome Profile connected. StayPane must wait for the missing integration and must not claim partial Recovery.
3. Restore the second profile before the recovery deadline. Recovery must resume only after both live Target sets pass preflight and both profiles confirm enforcement.
4. Repeat without restoring the missing profile. At the deadline, StayPane must Fail Open, restore eligible macOS windows, and record Interrupted.
5. Repeat while the Session expires offline. Relaunch cleanup must complete it without restarting browser enforcement.

## Caller and schema validation

1. Run `make test`. Contract coverage rejects wrong protocol versions, unexpected extension identities, invalid profile ownership, malformed capability objects, extra fields, and spoofed messages after reconnect.
2. Run `make test-extension`. Coverage verifies the fixed extension identity, strict protocol-v5 shapes, Incognito-window minimization, restoration, and serialized connection/enforcement races.
3. Inspect Session History and exported Diagnostics after the scenarios. They must record only bounded operational outcomes and must not contain Chrome Profile names, tab titles, URLs, hostnames, or other browsing content.
