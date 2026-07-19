# Ticket 10 manual acceptance: multiple tab scopes

These checks cover real Chrome window and tab lifecycle behavior that cannot be proven by the hermetic policy tests alone. Use one ordinary, non-Incognito Chrome profile. StayPane is honest self-control rather than a security boundary: disabling the unpacked extension or Force Quitting StayPane remains a deliberate bypass.

## Build and setup

1. Run `make app`, `make test`, and `make test-extension` from the repository root.
2. Open `.build/StayPane.app`, register the Native Host, and confirm the Chrome companion is connected.
3. Reload **StayPane Chrome Companion** in `chrome://extensions`. Confirm it reports version 0.5.0, then enable **Allow in Incognito** so the profile is Ready.
4. Open at least two eligible HTTP or HTTPS tabs in different Chrome windows.

## Multiple selection and review

1. Expand Google Chrome in StayPane and select two or more individual tabs from different window groups.
2. Set one tab to **Current Website** and another to **Exact Page**.
3. Confirm every selected row retains its own scope when Chrome publishes refreshed titles, URLs, or window positions.
4. Review the Session. Confirm every tab and its scope are listed separately and that no scope can be edited after the countdown finishes.
5. Close or move one selected tab during the three-second countdown. Start must either use its current exact identity and window or explain that the target disappeared; it must not acknowledge a partial normal start.

## Independent navigation scopes

1. In the Current Website tab, navigate across paths and query parameters on the same hostname. Confirm completed pages become that tab's Last Allowed Page.
2. In the Exact Page tab, use in-page anchor links and ordinary reload. Both must remain allowed.
3. Change only the Exact Page query, including query order, or its path. Confirm that tab returns to its own Last Allowed Page while the Current Website tab remains unchanged.
4. Navigate either tab to another hostname or a special URL such as `chrome://settings`. Confirm only the attempted tab is restored.
5. Open same-scope and out-of-scope links into new tabs from each selected tab. Confirm each decision uses the source tab's own scope and never transfers into the other selected tab.

## Tab identities and windows

1. Activate each selected tab in turn, then activate an unapproved tab. Chrome must return to the most recently active selected tab.
2. Duplicate a selected tab and try to activate the duplicate. The duplicate must not join the allowlist, even though its URL matches.
3. Drag a selected tab into another Chrome window. Its exact tab identity must remain allowed and its navigation scope must remain unchanged.
4. Drag an unapproved tab into a window containing a selected tab and activate it. Window membership must not approve it.
5. Close one selected tab. Confirm the Session continues, the closed identity is removed, and the remaining tabs keep their original independent policies.
6. Close every selected tab, then create or activate another Chrome tab. It must not become an Available Tab Target; the Session's Fixed End Time and controlled Early Reset flow remain available from StayPane.
7. Relaunch StayPane after closing one of several selected tabs. Recovery should atomically resume the selected tabs that still exist without recreating the closed identity.

## Races, ending, and privacy

1. While an out-of-scope navigation is returning, rapidly activate an unapproved tab, move a selected tab, and close another selected tab. Repeat in a different order. No disallowed tab may remain active and no event may add a target.
2. Complete a Session normally, then repeat through End Session Early. Chrome navigation and activation must become unrestricted only after enforcement stops.
3. Disable or reload the extension during enforcement. StayPane must Fail Open, mark the Session Interrupted, and stop claiming browser enforcement.
4. Inspect completed Session History and exported Diagnostics. They must not contain tab titles, URLs, hostnames, paths, queries, or scope values derived from browsing content.

## Automated coverage

- `make test-extension` covers mixed scopes across windows, one initial Available Tab Target per selected Chrome window, hostname/path/query matching, ignored fragments, reloads, source-specific new-tab handling, duplicated and attached unapproved identities, selected-tab movement and closure, confirmation/closure ordering, replacement identities, notice rate limiting, and serialized event races.
- `make test` covers multi-selection, independent scope persistence, atomic protocol messages, exact confirmation sets, closure notices, native runtime shrinkage, partial Recovery after closure, and immutable active Session configuration.
