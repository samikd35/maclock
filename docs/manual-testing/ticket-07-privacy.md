# Ticket 07 manual acceptance: private history and diagnostics

These checks cover visible privacy behavior and local files. Build with `make app`, run the packaged application, and use short Sessions. Before testing, note any existing files under `~/Library/Application Support/StayPane` so newly created artifacts are easy to identify.

## Minimal Session History

1. Complete one Session normally, end one through the full early-reset confirmation, and produce one Interrupted result by removing Accessibility permission during enforcement.
2. Return to setup after each outcome. Session History must show start time, planned duration, actual focus time, and respectively Completed, Ended Early, or Interrupted.
3. Confirm no history row shows an application name, window title, tab title, URL, or domain.
4. Inspect `session-history.json`. Every record must have only `startedAt`, `plannedDuration`, `actualFocusTime`, and `result` as its top-level fields.
5. Create more than 100 terminal Sessions if doing an extended retention run. Only the latest 100 records may remain.

## Clear History confirmation

1. With at least one record present, choose **Clear History…**.
2. Choose **Cancel** and confirm every record remains.
3. Choose **Clear History…** again, confirm the destructive action, and verify the list becomes empty and `session-history.json` is removed.

## Recovery cleanup privacy

1. Start a Session using clearly recognizable test application and window names. Confirm `active-session.json` exists while Recovery is needed.
2. Complete the Session, end it early, and produce an Interrupted result in separate runs.
3. After each terminal outcome, confirm `active-session.json` is removed. Recovery data must not remain as a second history source.
4. Search the remaining history and diagnostics files for the recognizable application and window names. They must not appear.

## Explicit local Diagnostic Export

1. Exercise blocked-target, completion, early-reset, Interrupted, and Restoration events.
2. Confirm no export file, share sheet, network prompt, or upload appears automatically.
3. Choose **Export Diagnostics…**. Cancel the save panel and confirm no artifact is created.
4. Export to a chosen local folder. Confirm the JSON artifact is created only there and opens for inspection.
5. Read the artifact before sharing it. It must contain the inspection notice and generic events, remain bounded, and exclude application content, window or tab titles, URLs, and domains.
6. Confirm StayPane offers no analytics or telemetry setting because it performs no analytics, telemetry, automatic crash upload, or background diagnostic submission.

## Automated companion checks

Run `make test`. The suite covers all three results, exact four-field history serialization, latest-100 retention, confirmed clearing through the file store, latest-200 diagnostics retention, redaction, explicit local export, terminal Recovery cleanup, and a cross-artifact scan using deliberately sensitive app, window, tab, URL, and domain strings.
