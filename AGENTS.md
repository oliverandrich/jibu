# Project instructions

Read [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and checks.

## Workflow

- Implement only the requested work. Backlog items do not authorize additional
  features. Preserve existing tooling during ordinary feature work.
- Use TDD for behavior changes: write a focused test, confirm the intended failure,
  implement the smallest passing change, then refactor with tests green. Reproduce
  bugs with a regression test first. For new tests of existing behavior, verify the
  assertion with a temporary targeted fault and restore the code. Setup failures
  do not count as red. Documentation-only changes need no new tests; explain when
  a meaningful red phase cannot be demonstrated.
- Run `mise run check` after changes; format explicitly with `mise run format`.
  Run dependency audits separately with `mise run audit`. Report check results
  and any checks that could not run. Read CONTRIBUTING for project-specific gates.
- Before a requested commit, review for bugs, regressions, security issues and
  rule violations. Simplify unnecessary branches and duplication without expanding
  scope, and rerun affected checks after edits. For documentation, review wording,
  consistency and links.
- Use Conventional Commits (`type(scope): short description`) with a short body
  explaining why and what changed; omit the body for self-explanatory changes.
  Commit or push only when explicitly requested.
- Live tests spend real money. Run them only when explicitly requested.

## Work tracking

When local Beans tracking is configured:

- Search unfinished work before creating a ticket. Read the matching ticket and
  its parent/dependencies. Track progress there; do not create parallel TODO files
  or backlog comments in source. Complete one task before starting unrelated work.
- Mark work completed only after its acceptance criteria and checks pass, and add
  a `Summary of Changes`. For scrapped work, add `Reasons for Scrapping`.
- `beans list --ready` omits some unfinished work. Use `mise run beans` where
  available, or `beans list --no-status completed --no-status scrapped`.
- Keep new `.beans/` files and `.beans.yml` local and ignored. Do not force-add them,
  add ignore exceptions or remove already tracked tickets without instruction.
  Archive only when requested. Git pushes do not back up ignored tickets.
- Keep Bean IDs in Beans, not in code, tests or README. `Jibu.Credo.NoBeanIds` enforces it.
  Run `beans check` before finishing tracked work.

## Documentation structure

Keep this division:

- `README.md`: project overview, features, a short getting-started path and links.
- `CONTRIBUTING.md`: development setup, mise commands, tests and contribution workflow.
- `AGENTS.md`: authoritative instructions for coding agents and project-specific rules.
- `docs/`: library guides: usage, configuration and extension interfaces.

Do not put agent instructions or a second contributor guide under `docs/`.
Keep detailed explanations in one place and link to them. Update links when moving
content. Preserve project-specific documentation; common structure does not imply
identical application features. Other agent entry points such as `CLAUDE.md` refer
to `AGENTS.md` and do not maintain another set of rules.


## Design rules

- Request bodies are plain maps sent unchanged. Do not add parameter schemas,
  option validation or model lists. New API fields must work without a release.
- Jibu covers Anthropic's API only. Do not add other providers.
- Req is the HTTP layer. Every Req option passes through `Jibu.new/1`.
- Return `{:ok, result}` or `{:error, %Jibu.Error{}}`. Do not raise for API errors.
- Keep the raw response body available on every result struct.
- Do not send beta headers on the caller's behalf. Callers pass `betas:`.

## Tests

- Tests are `async: true`. Every HTTP call goes through `Req.Test`. No test may reach the network.
- Live tests against the real API carry `@moduletag :live` and are excluded by default.
  They run only with `ANTHROPIC_API_KEY` set and `mix test --only live`.

## Releases

Versions follow SemVer. Record every user-visible change in `CHANGELOG.md` under `Unreleased`.
Publish to Hex only when explicitly requested.
