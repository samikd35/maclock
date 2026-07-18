# Issue tracker: Local Markdown

Specifications and tickets for StayPane are Local Markdown. The current StayPane PRD is `.scratch/staypane/PRD.md`, and its authoritative aggregate implementation queue is [`tickets.md`](../../tickets.md). New feature trackers may use the per-feature layout below when tickets are published individually.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The specification is `.scratch/<feature-slug>/PRD.md`
- Implementation tickets are `.scratch/<feature-slug>/issues/<NN>-<slug>.md`
- Ticket numbering starts at `01`
- Triage state is recorded as a `Status:` line near the top
- Comments are appended under a `## Comments` heading

## Publishing

When a skill says “publish to the issue tracker,” create the appropriate file under `.scratch/<feature-slug>/`.

## Fetching tickets

Read the referenced Markdown file. For a StayPane ticket number, read the matching numbered section in [`tickets.md`](../../tickets.md). The user will normally provide its path or ticket number.

## Future migration

The project may move to GitHub Issues when its public GitHub repository is created. Until then, Local Markdown is authoritative.
