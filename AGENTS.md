# Engineering Principles

- Follow the Pareto principle: prioritize the small set of changes that delivers most of the benefit.
- Avoid implementing the remaining 80% when it adds complexity without proportionate value.
- Prefer the simplest secure design that meets the current requirement. Add infrastructure only when a concrete need justifies it.

## Agent skills

### Issue tracker

Issues and specs live as markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context domain documentation uses root `CONTEXT.md` and `docs/adr/`. See `docs/agents/domain.md`.
