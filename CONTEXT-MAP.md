# Context Map

## Contexts

- [Product policy](./docs/contexts/product/CONTEXT.md) — defines sessions, selected targets, and the allowlist shared by every enforcement adapter.
- [macOS application](./docs/contexts/macos/CONTEXT.md) — interprets macOS windows and system interfaces for native enforcement.

Chrome-extension and native-bridge contexts will be added when those components first introduce durable language.

## Relationships

- **Product policy → macOS application**: Product policy supplies an immutable session allowlist; the macOS application observes real windows and enforces that policy.
- **macOS application → Product policy**: The macOS application reports enforcement availability and session-ending effects without adding platform objects to product policy.
