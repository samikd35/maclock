# Context Map

## Contexts

- [Product policy](./docs/contexts/product/CONTEXT.md) — defines sessions, selected targets, and the allowlist shared by every enforcement adapter.
- [macOS application](./docs/contexts/macos/CONTEXT.md) — interprets macOS windows and system interfaces for native enforcement.
- [Chrome extension](./docs/contexts/chrome/CONTEXT.md) — observes Chrome profiles, windows, and tabs and performs Chrome Target Enforcement.
- [Native bridge](./docs/contexts/native-bridge/CONTEXT.md) — carries validated local messages between the Chrome extension and macOS application.

## Relationships

- **Product policy → macOS application**: Product policy supplies an immutable session allowlist; the macOS application observes real windows and enforces that policy.
- **macOS application → Product policy**: The macOS application reports enforcement availability and session-ending effects without adding platform objects to product policy.
- **Product policy → Chrome extension**: Product policy supplies immutable Browser Window Targets and Tab Targets; the Chrome extension enforces their breadth and browser identities.
- **Chrome extension ↔ Native bridge**: Each Chrome Profile establishes a validated Bridge Connection and exchanges Tab Snapshots and enforcement commands locally.
- **Native bridge ↔ macOS application**: The Native Bridge transports messages only; the macOS application owns Session state and browser-policy decisions.
