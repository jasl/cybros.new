# Core Matrix

`core_matrix` is the Core Matrix product kernel.

Core Matrix is a single-installation, single-tenant agent kernel for personal,
household, and small-team use. It owns agent-loop execution, conversation and
workflow state, human-interaction primitives, runtime supervision, trigger
governance, and platform-level auditability.

Domain behavior lives in external agent programs. Core Matrix is not the
business agent itself, not an enterprise multi-tenant platform, and not the
built-in home for every memory, knowledge, or web capability.

## Current Status

The current active batch is `Agent Loop Execution`.

Milestones A through F are now landed in the current agent-loop workspace,
including the post-Milestone-C breadth and acceptance batch:

- conversation feature policy and durable stale-work safety
- workflow-owned wait, human-interaction, and subagent handoff
- durable tool governance and invocation audit
- one governed Streamable HTTP MCP path
- bundled and external `Fenix` runtime plus skill validation flows
- workflow proof export and acceptance harness coverage

The baseline operator checklist for the manual acceptance pass is:

- `../docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- `../docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md`

Current authoritative project documents:

- Greenfield design: `../docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
- Phase shaping: `../docs/design/2026-03-24-core-matrix-kernel-phase-shaping-design.md`
- Platform phases and validation: `../docs/design/2026-03-25-core-matrix-platform-phases-and-validation-design.md`
- Phase 1 implementation record: `../docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
- Multi-round audit/reset framework: `../docs/plans/2026-04-03-multi-round-architecture-audit-and-reset-framework.md`
- Active plan index: `../docs/plans/README.md`
- Deferred Web UI follow-up: `../docs/future-plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
- Manual validation checklist: `../docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- Provider-backed capstone checklist: `../docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md`
- Behavior notes for landed backend modules: `docs/behavior/`

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
- manual flows from `../docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

## Manual Validation Baseline

- Phase 1 backend manual validation was rerun on `2026-03-25` against
  `bin/dev` and the checklist at
  `../docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`.
- Acceptance runs now use the top-level harness in `../acceptance/`. Generated
  logs and artifacts are written under `../acceptance/logs/` and
  `../acceptance/artifacts/` and are intentionally not committed.
- The checklist now standardizes on a reusable
  `core_matrix_reset_backend_state` helper built on
  `ApplicationRecord.with_connection { |conn| conn.disable_referential_integrity { ... } }`.
- The reusable manual-validation harness now lives in
  `script/manual/manual_acceptance_support.rb`.
- Acceptance operator scenario scripts now live under
  `../acceptance/scenarios/*`, with shell orchestration under
  `../acceptance/bin/*`, and are intended to be run through
  `bin/rails runner ../acceptance/scenarios/...`.
- `ruby script/manual/dummy_agent_runtime.rb register` now pairs the runtime by
  stable `runtime_fingerprint`; the manual checklist currently exports that
  through `CORE_MATRIX_ENVIRONMENT_FINGERPRINT` alongside
  `CORE_MATRIX_ENROLLMENT_TOKEN`.
- Publication verification remains service-level in phase 1 because public
  publication HTTP routes have not been introduced yet.

## Useful Commands

```bash
bin/rails db:seed
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
bin/rails runner ../acceptance/scenarios/bundled_fast_terminal_validation.rb
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
- Leave `RAILS_DB_URL_BASE` unset on macOS to use bare-metal PostgreSQL over
  the default Unix socket.
- Set `RAILS_DB_URL_BASE=postgresql://postgres:postgres@127.0.0.1:5432` on
  Ubuntu when Rails runs on the host and PostgreSQL 18 runs in Docker with a
  published port.
- Containerized services still use Docker Compose environment injection. In
  `compose.yaml.sample`, explicit service `environment` values override
  same-named values coming from `env_file`.
