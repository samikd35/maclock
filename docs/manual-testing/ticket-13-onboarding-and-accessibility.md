# Ticket 13 manual acceptance: onboarding and accessible interaction

These checks cover real macOS permission prompts, System Settings links, keyboard focus, VoiceOver announcements, and visual preferences that hermetic tests cannot prove. Use a disposable macOS user account or a source build whose onboarding defaults can be reset safely. StayPane must never request Screen Recording during any step.

## First-run boundary and privacy

1. Launch StayPane without completed onboarding. Confirm the Status Panel opens the First-Run Onboarding checklist before ordinary Session setup.
2. Read the honest-boundary card. It must state that StayPane is a self-control tool rather than tamper-proof security and name Force Quit, administrator changes, source modification, permission revocation, and companion disablement as deliberate bypasses.
3. Confirm the same card explains Fail Open and says Session state, minimal History, redacted Diagnostics, and optional browser messages remain local. It must not claim an account, cloud service, analytics, telemetry, automatic crash upload, or background update checks.
4. Relaunch before completing the checklist. Onboarding must still appear. Complete Accessibility verification, choose **Continue to Session Setup**, relaunch, and confirm ordinary setup appears. Use **Setup & Help** to revisit the instructions.

## Accessibility permission states and harmless verification

1. Before requesting permission, confirm the checklist says **Not Requested** and explains why Accessibility is needed.
2. Choose **Open Accessibility Settings**. Confirm macOS opens **Privacy & Security → Accessibility**, not Screen Recording. Decline or leave access disabled, return to StayPane, and confirm **Access Not Granted** with retry guidance.
3. Enable StayPane while no ordinary settable application window is open. If verification cannot find a safe window, confirm **Enabled but Unverified** is shown without claiming protection works.
4. Open a normal application window and choose **Run Harmless Window-Control Verification**. Confirm the state becomes **Verified** and no window moves, resizes, closes, changes minimized state, or exposes captured content.
5. Complete onboarding, then revoke Accessibility. Within the normal refresh interval, setup must show **Revoked** and prevent review/start. If revocation occurs during enforcement, the Session must Fail Open, restore what remains controllable, and become Interrupted.
6. Grant access again and choose **Check Again** or rerun the harmless test. A new Session must remain unavailable until verification succeeds.

## Optional Chrome setup and failures

1. Leave Chrome unconfigured. Confirm onboarding can finish after Accessibility verification and that native Application Target and Window Target Sessions remain available.
2. Confirm onboarding says the companion is required for Browser Window Targets or Tab Targets, not for native Targets.
3. Choose **Register Native Host**. A missing packaged bridge or unwritable registration must produce an understandable local error and leave the checklist incomplete only for optional Chrome setup.
4. Build the app, register the host, load StayPane Chrome Companion 0.5.0 with Developer Mode → Load unpacked, and enable **Allow in Incognito**.
5. Choose **Test Connection**. Observe Waiting, Synchronizing, Unsupported, and Ready guidance as applicable. Ready must verify the extension identity, Native Bridge, and browser capability locally without a Google account.
6. Disable the companion and confirm native Sessions remain configurable while Browser Window Targets and Tab Targets cannot pass their existing preflight.

## Final review, Focus, and notification denial

1. Configure a Session and open final review. Confirm it presents duration, every Target, broad-target warnings, Navigation Scopes when applicable, profile integration state, Floating Timer, Launch at Login, and completion feedback.
2. Confirm final review says Status Panel and menu-bar completion feedback remain available when notifications are denied.
3. Confirm the macOS Focus reminder is explicitly optional and says StayPane cannot reliably toggle Focus or automate Control Center.
4. Choose **Open Focus Settings**. Confirm the correct System Settings area opens, or StayPane gives a plain fallback path without claiming Focus was enabled.
5. Deny or disable notification permission if StayPane appears in notification settings. Complete a short Session and confirm the Status Panel shows **Session Complete** while the menu-bar title briefly says **Session Complete**.

## Keyboard, VoiceOver, and focus order

1. Enable Full Keyboard Access as needed, then operate onboarding without a pointer. Tab through the honest-boundary card, Accessibility actions, optional Chrome actions, and Continue in visual order. Return activates the primary Continue/Start action only when enabled; Escape activates Back or countdown cancellation where offered.
2. Continue through Session setup, target hierarchy, final review, cancelable start countdown, active Status Panel, Early Reset waiting period, final confirmation, completion, Session History clearing, and Diagnostics export. Every action must remain keyboard reachable with a visible focus indicator.
3. Enable VoiceOver and repeat the flow. Confirm headings, card/group labels, Target controls, profile states, countdown values, remaining time, History privacy label, redacted Diagnostics action, and destructive confirmations have meaningful names and values.
4. Confirm VoiceOver announces notices and meaningful screen-state changes: onboarding, setup, review, countdown, active enforcement, both Early Reset stages, Completed, Ended Early, and Interrupted. Repeated timer ticks must not flood announcements.
5. Confirm icon-only controls such as Refresh, Floating Timer collapse, and hide expose action names rather than symbol descriptions.

## Appearance and motion

1. Repeat onboarding, setup, review, active, reset, History, Diagnostics, and completion in Light and Dark appearances. Text and icons must remain legible and no card may depend on a hard-coded light background.
2. Enable **Increase contrast**. Confirm informational, warning, setup, review, History, and notice cards gain stronger separation while retaining their text and symbol cues.
3. Enable **Differentiate without color**. Verified, optional, in-progress, warning, and failure states must remain distinguishable by text and symbols rather than color alone.
4. Enable **Reduce motion**. Start and reset short Sessions. Countdown numbers must update without animated numeric transitions; no workflow or status information may disappear.
5. Inspect **Privacy & Security** throughout the complete flow. StayPane may appear under Accessibility and optionally Notifications, but it must never request or instruct the user to grant Screen Recording.

## Automated companion checks

- `make test` covers durable first-run progress, all Accessibility Setup States, optional and failed Chrome setup states, notification-independent terminal Session Presence, accessible presentation for onboarding through completion, privacy-specific History and Diagnostics labels, and Reduce Motion policy.
- `make test-extension` retains browser-policy coverage; Ticket 13 adds no new remote service, browser permission, or screen-capture behavior.
- `make app` verifies the onboarding and accessibility presentation compile into the source-built app and packaged Native Bridge flow.
