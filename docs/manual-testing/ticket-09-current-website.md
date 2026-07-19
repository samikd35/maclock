# Ticket 09 manual acceptance: Current Website

These checks cover real Chrome navigation and tab-creation behavior that the hermetic policy tests cannot prove. Use an ordinary, non-Incognito Chrome profile. Current Website is honest self-control rather than a security boundary: disabling the unpacked extension or Force Quitting StayPane remains a deliberate bypass.

## Build and update the local extension

1. Run `make app`, `make test`, and `make test-extension` from the repository root.
2. Open `.build/StayPane.app`, register the Native Host, and confirm the Chrome companion is connected.
3. In `chrome://extensions`, reload **StayPane Chrome Companion** after every rebuild. Version 0.4.0 speaks Native Bridge protocol version 4; an older loaded build cannot start the current browser-enforcement contract.
4. Pin the extension if you want to observe its brief orange `SITE` badge.

## Scope presentation and eligibility

1. Open an ordinary HTTP or HTTPS page and expand Google Chrome in StayPane's Target picker.
2. Select the row, confirm **Current Website** is the default Navigation Scope, and confirm the final review repeats that scope.
3. Confirm `chrome://`, `file://`, extension pages, and Incognito tabs are absent from the eligible Tab Target list.
4. Start a short Session and confirm the selected Tab Target remains immutable.
5. Try to start while that tab is still loading. StayPane must ask you to wait for the page to finish rather than treating an incomplete page as the Last Allowed Page.

## Allowed top-level navigation

1. From the selected page, navigate to different paths and query parameters on the same exact hostname. Each completed page must remain available and become the new Last Allowed Page.
2. Exercise an in-page fragment, an ordinary reload, and—where the site supports it—HTTP/HTTPS or port changes on that same hostname. They must remain allowed.
3. Navigate an embedded iframe to a different hostname. Subframe content must not cause the selected top-level page to be returned.

## Blocked navigation and redirects

1. Fully load an allowed page, then navigate the selected tab to a different hostname. StayPane must return the same Tab Target to the fully loaded Last Allowed Page.
2. Repeat with a subdomain, a hostname-suffix lookalike, and a browser-internal URL such as `chrome://settings`. All are outside the exact hostname rule.
3. Follow a URL that redirects from the allowed hostname to another hostname. The redirect destination must not replace the Last Allowed Page.
4. Attempt several blocked navigations rapidly. Every attempt must return, while the extension badge and StayPane notice remain rate limited.
5. Confirm the notice explains that StayPane returned the selected Tab Target to its Navigation Scope without displaying a URL, title, hostname, or browsing content.

## Links that open a new tab

1. From the Tab Target, open a same-hostname link in a new tab. Its destination must move into the original Tab Target and the new tab must close.
2. Return to a stable allowed page, then open a different-hostname link in a new tab. The new tab must close and the original Tab Target must remain unchanged.
3. Repeat both cases from links—including `noopener` links—that initially create `about:blank` before resolving. StayPane gives the blank child a brief bounded grace period to reveal its real destination; no new tab may become a Session Target or expand the immutable allowlist.
4. Activate or create an unrelated tab directly. Ticket 08 Tab Activation Enforcement must still return Chrome to the selected Tab Target.

## End, Recovery, and Fail Open

1. Complete a Session normally and repeat through the controlled early-reset flow. Navigation and tab activation must become unrestricted only after enforcement stops.
2. Relaunch StayPane while a short Session remains active. After the saved exact Tab Target is verified, Current Website must resume from the live same-hostname page and the original Fixed End Time.
3. Disable or reload the extension during enforcement. StayPane must Fail Open, mark the Session Interrupted, and stop claiming browser enforcement.

## Automated and privacy checks

1. Run `make test-extension`. Policy and adapter tests cover schemes, exact hostnames, paths, queries, fragments, ports, redirects, top-level frames, rapid blocks, Last Allowed Page, same-scope transfers, cross-scope closes, immutable tab identity, and serialized stop races.
2. Run `make test`. Swift tests cover the default Current Website scope, backward-compatible Recovery decoding, strict protocol version 4 messages, content-free Blocked Navigation notices, web-tab eligibility, and real local socket delivery.
3. Inspect extension storage and Native Bridge traffic. Active local enforcement may contain its exact Tab Target and Current Website URL, but completed Session History and exported Diagnostics must contain no tab title, URL, hostname, or domain.
