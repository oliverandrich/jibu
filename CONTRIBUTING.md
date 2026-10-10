# Contributing

## Get started

Install **mise**, then:

```sh
mise trust
mise install
mix deps.get
mise run check
```

## Command reference

| Command | Purpose |
| --- | --- |
| `mise run check` | zizmor, format check, unused locks, Credo, compile, tests, docs |
| `mise run build-and-test` | Compile without warnings and run the tests |
| `mise run test` | Run the test suite |
| `mise run format` | Explicit formatting |
| `mise run credo` | Compile then strict Credo |
| `mise run docs` | Build the docs and serve them at http://127.0.0.1:8000 |
| `mise run audit` | Dependency advisories and retired Hex packages |
| `mise run beans` | List unfinished local Beans tickets |

## Checks

`mise run check` is the gate. GitHub CI runs it on the pinned toolchain from `mise.toml`.
A second leg runs `build-and-test` on the floor, Elixir 1.18 with OTP 27.
The floor leg skips style checks, because formatter and Credo releases change between versions.

Credo runs strict. ExSlop and Jump checks are registered explicitly in `.credo.exs`.
ExSlop's `BlanketRescue` covers `try` blocks only, not function-level `rescue`.
Project checks live in `credo/` and compile in dev and test only.
`Jibu.Credo.NoBeanIds` rejects Bean ids in the tree.

`mix docs --warnings-as-errors` fails on broken references in the documentation.
Audit findings run separately through `mise run audit` and a weekly workflow.

The zizmor version is pinned in `mise.toml` and in `.github/workflows/ci.yml`. Update both together.

## Tests

Every HTTP call in tests goes through `Req.Test`; no test reaches the network.
`test/docs/guides_test.exs` runs every `elixir` block of the README and the guides against a stub.
A guide example that no longer works fails the suite.
Live tests carry `@moduletag :live` and are excluded by default.
Run them with `ANTHROPIC_API_KEY` set and `mix test --only live`. They spend real money.

## Making changes

Write a focused failing test first and run `mise run check` before submitting.
Follow the TDD and Conventional Commit rules in [AGENTS.md](AGENTS.md).
Record user-visible changes in [CHANGELOG.md](CHANGELOG.md).

## Local Beans tracking

Install Beans separately. Search unfinished tickets before creating work; update
progress and finish with a Summary of Changes. Run `beans check` after changes.
`.beans/` and `.beans.yml` are ignored and not backed up by Git pushes.
