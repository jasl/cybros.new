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

The current active batch is the substrate rebuild. It establishes the durable
roots that later phases will use for real loop execution and user-facing
surfaces.

Current authoritative project documents:

- Greenfield design: `../docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
- Phase shaping: `../docs/design/2026-03-24-core-matrix-kernel-phase-shaping-design.md`
- Platform phases and validation: `../docs/design/2026-03-25-core-matrix-platform-phases-and-validation-design.md`
- Active implementation plan: `../docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
- Next-phase loop follow-up: `../docs/future-plans/2026-03-25-core-matrix-phase-2-agent-loop-execution-follow-up.md`
- Deferred Web UI follow-up: `../docs/future-plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
- Manual validation checklist: `../docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
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

## Useful Commands

```bash
bin/rails db:version
bin/rails test
bin/rubocop app/models/application_record.rb
```

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
