# Fenix

`fenix` is the default out-of-the-box agent program for Core Matrix.

Fenix has two jobs:

- ship as a usable general assistant product
- serve as the first technical validation program for the Core Matrix loop

## Product Definition

Fenix is a practical assistant that combines:

- general-assistant conversation behavior inspired by `openclaw`
- coding-assistant behavior inspired by Codex-style workflows
- everyday office-assistance behavior inspired by `accomplish` and `maxclaw`

Fenix may define agent-specific tools, deterministic program logic, and
composer completions such as slash commands or symbol-triggered references. It
does not need every interaction to be driven by an LLM.

## Boundary

Fenix is not:

- the kernel itself
- the home for every future product shape
- a universal agent meant to absorb all future experiments

When Core Matrix needs to validate materially different product shapes, those
should land in separate agent programs rather than forcing them into Fenix.

## Phase Role

- `Phase 2`: prove the real agent loop end to end
- `Phase 3`: become the first full Web product on top of the validated kernel
- `Phase 4`: remain one validated product while other agent programs prove the
  kernel is reusable beyond Fenix

## Phase 2 Runtime Surface

`Fenix` now exposes one machine-facing runtime execution endpoint:

- `POST /runtime/executions`

The endpoint accepts one mailbox-shaped execution assignment and returns a
deterministic report transcript for local validation:

- `execution_started`
- `execution_progress`
- `execution_complete`
- `execution_fail`

The current Phase 2 implementation keeps this surface local to `Fenix` so the
runtime pipeline can be validated before external pairing work wires the same
pipeline to `Core Matrix` mailbox delivery.

## Retained Hook Lifecycle

Phase 2 keeps a stage-shaped runtime surface instead of collapsing behavior
into one opaque callback.

Current retained hooks:

- `prepare_turn`
- `compact_context`
- `review_tool_call`
- `project_tool_result`
- `finalize_output`
- `handle_error`

The runtime executor calls them in order for successful execution and records a
trace entry for each stage. Failure paths append `handle_error` and emit
`execution_fail`.

## Estimation Helpers

`Fenix` also retains local advisory helpers:

- `estimate_tokens`
- `estimate_messages`

These are deliberately local runtime helpers rather than kernel primitives.
They support preflight budgeting and compaction decisions before any future
provider call.

## Likely-Model Hints

Assignments may carry both:

- `payload.model_context.likely_model`
- `payload.provider_execution.model_ref`

`Fenix` treats those as advisory hints. When the estimated token load exceeds
`payload.budget_hints.advisory_compaction_threshold_tokens`, `compact_context`
uses the likely-model hint to explain why compaction happened and records the
before or after message counts in the hook trace.

## Current Validation Path

The current Phase 2 runtime path is intentionally small and deterministic:

- `deterministic_tool` reviews a local calculator tool call, projects the tool
  result, and finalizes a user-facing output
- `raise_error` proves the error hook and terminal failure reporting

This preserves the runtime-stage contract needed for later mixed
code-plus-LLM execution without forcing prompt building or provider transport
back into the kernel.
