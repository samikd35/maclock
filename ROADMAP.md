# StayPane roadmap

StayPane v1 is a source-only release for Apple silicon Macs running macOS 26 or newer. Its only browser companion is the locally loaded Chrome extension described in the installation guide.

Future browser work will be evaluated in this order:

1. **Safari first** — investigate a Safari Web Extension plus a native adapter while preserving StayPane's local-only privacy model, exact Target semantics, and Fail Open behavior.
2. **Other Chromium browsers next** — evaluate Edge, Brave, Vivaldi, and similar browsers only after their unpacked-extension identity, Native Bridge registration, profile behavior, and Incognito boundary can be tested honestly.
3. **Firefox afterward** — investigate Firefox only after the Safari and Chromium adapter boundaries are understood and the same preflight, Recovery, and privacy guarantees can be maintained.

This ordering is not a promise of support, schedule, or compatibility. An integration becomes supported only after its public installation instructions, adapter tests, failure behavior, and manual acceptance matrix exist. Until then, Safari, other Chromium browsers, and Firefox remain outside v1.

Deep control inside allowed non-browser applications—such as Slack channels, Terminal commands, editor tabs, Finder tabs, or media content—is demand-driven. StayPane will not claim universal internal-content enforcement where an application does not expose a reliable, privacy-preserving boundary.
