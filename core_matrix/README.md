# Core Matrix

`core_matrix` is the Core Matrix product kernel.

Core Matrix is a single-installation, single-tenant agent kernel for personal,
household, and small-team use. It owns agent-loop execution, conversation and
workflow state, human-interaction primitives, runtime supervision, trigger
governance, and platform-level auditability.

Domain behavior lives in external agents. Core Matrix is not the
business agent itself, not an enterprise multi-tenant platform, and not the
built-in home for every memory, knowledge, or web capability.

## Current Status

The current kernel baseline includes the full agent-loop execution stack plus
the April 2026 supervision/runtime rebuild:

- conversation feature policy and durable stale-work safety
- workflow-owned wait, human-interaction, and subagent handoff
- durable tool governance and invocation audit
- one governed Streamable HTTP MCP path
- bundled and external `Fenix` runtime plus skill validation flows
- workflow proof export and acceptance harness coverage
- turn-todo-backed supervision and canonical supervision feeds
- canonical turn runtime event streams for app/review surfaces
- plan-first supervision fallbacks plus replayable supervision evaluation dumps

The baseline product acceptance path now lives in the top-level harness:

- `../acceptance/README.md`
- `../acceptance/bin/run_active_suite.sh`

Current authoritative project documents:

- Phase shaping: `../docs/design/2026-03-24-core-matrix-kernel-phase-shaping-design.md`
- Platform phases and validation: `../docs/design/2026-03-25-core-matrix-platform-phases-and-validation-design.md`
- Phase 1 implementation record: `../docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
- Multi-round audit/reset framework: `../docs/plans/2026-04-03-multi-round-architecture-audit-and-reset-framework.md`
- Runtime/supervision closeout record: `../docs/finished-plans/2026-04-07-fenix-runtime-supervision-ui-implementation.md`
- Plan-first supervision closeout record: `../docs/finished-plans/2026-04-07-plan-first-supervision-rebuild.md`
- Active plan index: `../docs/plans/README.md`
- App-facing UI contract: `../docs/finished-plans/2026-04-06-fenix-app-ui-contract.md`
- Deferred Web UI follow-up: `../docs/future-plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
- Acceptance harness and active suite: `../acceptance/README.md`
- Archived pre-reset docs: `../docs/archived/README.md`
- Product/operator docs: `docs/`
- Legacy implementation archive:
  `../docs/archived-plans/core_matrix-docs-legacy-2026-04-17/`

## What Core Matrix Owns

- agent-loop execution and workflow progression
- conversation, turn, and runtime-resource state
- human-interaction primitives
- capability governance and execution supervision
- feature gating and recovery behavior
- audit, profiling, and platform-level observability

## What Core Matrix Does Not Own Yet

- built-in long-term memory or knowledge subsystems
- the final implementation of every generic tool
- IM, PWA, and desktop surfaces
- extension and plugin packaging

## Validation Rule

Loop-related work is not complete with automated tests alone. When a phase
claims real loop behavior, validation must include:

- unit and integration coverage
- `bin/dev`
- a real LLM API
- the current active acceptance suite from `../acceptance/README.md`

Changes that touch conversation/turn/workflow bootstrap, runtime event streams,
or app-facing roundtrip behavior must satisfy an even stricter gate before they
are considered done:

- the full local `core_matrix` verification suite
- `ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash ../acceptance/bin/run_active_suite.sh`
- inspection of the produced acceptance artifacts
- inspection of the resulting database records so state shapes, anchors, and
  transitions are confirmed against the business contract rather than inferred
  only from exit codes

When a branch intentionally uses destructive schema refactors and rewrites
original migrations in place, the standard rebuild flow from the
`core_matrix` root is:

- `rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset`

## Acceptance Baseline

- Acceptance runs use the top-level harness in `../acceptance/`.
- The canonical gate is `bash ../acceptance/bin/run_active_suite.sh`.
- Generated logs and artifacts are written under `../acceptance/logs/` and
  `../acceptance/artifacts/` and are intentionally not committed.
- The reusable harness lives in `../acceptance/lib/manual_support.rb`.
- Ruby scenario entrypoints live under `../acceptance/scenarios/*`, with shell
  orchestration under `../acceptance/bin/*`.
- Historical pre-reset checklists and bundled-runtime closeout documents were
  moved to `../docs/archived/`.

## Useful Commands

```bash
bin/rails db:seed
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash ../acceptance/bin/run_active_suite.sh
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
../acceptance/bin/run_active_suite.sh
bin/rails runner ../acceptance/scenarios/provider_backed_turn_validation.rb
bundle exec ruby script/manual/workflow_proof_export.rb export ...
```

## Seed Baseline

- `db/seeds.rb` is backend-safe and idempotent.
- Seeds validate the provider catalog on every run.
- Seeds do not create demo users, conversations, or UI-facing sample data.
- When an installation already exists, seeds may reconcile the optional bundled
  runtime through the existing bundled bootstrap service path.

## Environment Notes

- Host-side Rails commands load local `.env*` files via `dotenv-rails`,
  including bare-metal production boots.
- Docker and Compose deployment paths default to `RAILS_ENV=production`.
- Leave `RAILS_DB_URL_BASE` unset on macOS to use bare-metal PostgreSQL over
  the default Unix socket.
- Set `RAILS_DB_URL_BASE=postgresql://postgres:postgres@127.0.0.1:5432` on
  Ubuntu when Rails runs on the host and PostgreSQL 18 runs in Docker with a
  published port.
- Set `CORE_MATRIX_PUBLIC_BASE_URL` to the externally reachable origin that
  operators, browsers, and webhook providers should use for generated links.
- Keep `CORE_MATRIX_PUBLIC_BASE_URL` distinct from the internal
  container-to-container control-plane URL used by `fenix` or `nexus`.
- For home or office deployments without a public IP, use the deployment modes
  documented in
  [docs/INSTALL.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/INSTALL.md).
- Containerized services still use Docker Compose environment injection. In
  `compose.yaml.sample`, explicit service `environment` values override
  same-named values coming from `env_file`.

## License

`core_matrix` is licensed under the O'Saasy License Agreement. See
[LICENSE.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/LICENSE.md).

This project includes separately licensed vendored code under
[vendor/simple_inference](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference).
That vendored gem remains licensed under the MIT License, as stated in
[LICENSE.txt](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/LICENSE.txt).
