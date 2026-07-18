# Domain docs

StayPane uses a multi-context documentation layout.

## Before exploring

1. Read `CONTEXT-MAP.md` at the repository root when it exists.
2. Follow it to every context relevant to the task.
3. Read system-wide decisions under `docs/adr/`.
4. Read context-specific ADRs referenced by the relevant context.

If a document does not exist yet, proceed without treating its absence as an error. Domain documents and ADRs are created as vocabulary and architectural decisions become durable.

## Planned contexts

- Product — shared session, target, enforcement, completion, and recovery language
- macOS application — menu-bar UI, timer, Accessibility integration, and window enforcement
- Chrome extension — tab selection, navigation scopes, and browser enforcement
- Native bridge — local communication between the Mac application and browser extension

`CONTEXT-MAP.md` will become authoritative for the eventual filesystem locations of these contexts.

## Vocabulary

Use the exact domain terms defined by the relevant context. Avoid inventing synonyms for established concepts.

If a necessary concept is missing, record it through domain modeling rather than silently introducing competing language.

## Architectural decisions

Surface any conflict with an existing ADR explicitly. Do not silently override a recorded decision.
