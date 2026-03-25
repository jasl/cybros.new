# Core Matrix Phase 2 Milestone B: Provider Execution Foundation

Part of `Core Matrix Phase 2: Agent Loop Execution`.

## Purpose

Land the first real LLM execution path before external runtime pairing and
mailbox-driven agent control broaden the loop.

Milestone B should prove that `Core Matrix` can:

- resolve one real provider-qualified model path
- execute one provider-backed `turn_step`
- persist authoritative usage and execution facts
- pass resolved catalog-backed provider execution settings into the real API
  request path

This milestone should use `simple_inference` as the provider substrate and
`httpx` as the network client inside that substrate.

Validation baseline for this milestone:

- use the Phase 1 mock LLM path for fast iteration
- use `OPENROUTER_API_KEY` from `.env` plus `db:seed` to materialize one real
  provider credential for focused real-provider verification
- keep provider execution rooted in the existing turn and workflow snapshot
  chain rather than introducing a second provider-owned execution ledger

## Included Tasks

### Task B1

- [2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md)

## Exit Criteria

- one mock-provider path and one real-provider path execute through
  `simple_inference`
- provider-backed execution persists authoritative usage and correlation data
- resolved sampling settings from the LLM catalog are carried into the real API
  request path, including:
  - `temperature`
  - `top_p`
  - `top_k`
  - `min_p`
  - `presence_penalty`
  - `repetition_penalty`
- mock and real OpenRouter validation paths are both exercised for the first
  provider-backed turn path
- likely-model hints and advisory compaction thresholds remain distinct from
  provider-facing execution settings

## Non-Goals

- mailbox delivery to external agent runtimes
- turn interrupt and conversation close
- external `Fenix` pairing
- MCP breadth
