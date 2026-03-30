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

`Fenix` now exposes one stable machine-facing pairing endpoint:

- `GET /runtime/manifest`

`GET /runtime/manifest` publishes the registration metadata needed for external
pairing:

- protocol version
- SDK version
- protocol methods
- tool catalog
- `profile_catalog`
- `agent_plane`
- `environment_plane`
- `effective_tool_catalog`
- config schema snapshots
- default config snapshot

The manifest now declares runtime-owned profile and subagent defaults:

- `default_config_snapshot.interactive.profile` is fixed to `main` for root
  interactive conversations in this batch
- `default_config_snapshot.subagents.enabled`
- `default_config_snapshot.subagents.allow_nested`
- `default_config_snapshot.subagents.max_depth`
- `conversation_override_schema_snapshot` exposes only `subagents.*`

The current pairing contract models `Fenix` as one process serving both:

- `AgentRuntime`
- `ExecutionEnvironmentRuntime`

That dual role is explicit in the manifest even though Phase 2 still ships it
as one bundled runtime.

Normal execution and close control do not use a runtime callback endpoint.
`Core Matrix` is the orchestration truth and delivers mailbox items through the
control plane:

- realtime push over `/cable`
- `POST /agent_api/control/poll` fallback delivery
- `POST /agent_api/control/report` for incremental reports back into the kernel

The manifest therefore exists for registration and capability advertisement,
not for direct execution dispatch. The runtime still keeps deterministic local
execution logic, but product execution now rides the mailbox-first control
plane shared by bundled and external pairing.

Long-lived environment resources also require a persistent mailbox worker.
`Fenix` ships:

- `bin/rails runtime:control_loop_once`
  - one-shot realtime-or-poll worker used for targeted checks and short-lived
    mailbox execution
- `bin/rails runtime:control_loop_forever`
  - persistent websocket-first worker that retains local `ProcessRun` handles
    across mailbox iterations so later close requests can settle gracefully

Detached long-lived services therefore follow this contract:

- `process_exec` first asks Core Matrix to create one `ProcessRun`
- `Fenix` launches the local process only after that durable resource exists
- the persistent control worker reports `process_started`, `process_output`,
  `process_exited`, and `resource_close_*` over the control plane

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

Assignments primarily carry model hints through:

- `payload.model_context.model_ref`
- `payload.model_context.api_model`

`Fenix` also accepts older compatibility fallbacks such as
`payload.model_context.likely_model` or `payload.provider_execution.model_ref`.
When the estimated token load exceeds
`payload.budget_hints.advisory_hints.recommended_compaction_threshold`,
`compact_context`
uses the resolved model hint to explain why compaction happened and records the
before or after message counts in the hook trace.

## Current Validation Path

The current Phase 2 runtime path is intentionally small and deterministic:

- `deterministic_tool` reviews a local calculator tool call, projects the tool
  result, and finalizes a user-facing output
- `raise_error` proves the error hook and terminal failure reporting

This preserves the runtime-stage contract needed for later mixed
code-plus-LLM execution without forcing prompt building or provider transport
back into the kernel.

Prompt building, prompt-template choice, and profile-specific tool semantics
remain inside `Fenix`. Core Matrix computes and freezes the
conversation-visible tool set into `agent_context.allowed_tool_names`, and
`Fenix::Hooks::ReviewToolCall` treats that frozen set as a real execution-time
constraint rather than trace-only metadata.

## Phase 2 Skill Surface

`Fenix` now keeps the Phase 2 skill boundary inside the agent program rather
than pushing skills into `Core Matrix`.

Skill roots are separated intentionally:

- `skills/.system/<name>/` for reserved built-in `Fenix` skills
- `skills/.curated/<name>/` for bundled curated catalog entries
- `skills/<name>/` for live installed third-party skills

The current minimal skill surface is:

- `skills_catalog_list`
- `skills_load`
- `skills_read_file`
- `skills_install`

That surface is sufficient to:

- discover reserved system skills and bundled curated entries
- load one active system or installed skill body on demand
- read additional files relative to an active skill root
- stage and promote a third-party skill into the live root

Phase 2 keeps two explicit rules:

- `.system` skill names are reserved and may not be overridden
- installs become effective on the next top-level turn, not mid-turn

The built-in `deploy-agent` system skill exists to prove that `Fenix` can use
its own skill mechanism for an operational workflow, not just passive
instruction storage.

## Phase 2 Acceptance Runtime Layout

The retained manual-acceptance layout uses two local `Fenix` processes:

- `AGENT_FENIX_PORT=3101 bin/dev`
  - default bundled/external runtime validation
  - bundled mailbox execution
  - external pairing
  - deployment rotation
  - spawns `runtime:control_loop_forever` for long-lived `ProcessRun`
    validation when the operator script needs one persistent mailbox worker
- `AGENT_FENIX_PORT=3102 ... bin/dev`
  - dedicated skills-validation runtime
  - `FENIX_LIVE_SKILLS_ROOT=/tmp/phase2-fenix-live-skills`
  - `FENIX_STAGING_SKILLS_ROOT=/tmp/phase2-fenix-staging`
  - `FENIX_BACKUP_SKILLS_ROOT=/tmp/phase2-fenix-backups`

The dedicated `3102` runtime keeps live, staging, and backup skill writes out
of the repo tree so the Phase 2 skill catalog stays reproducible. The manual
acceptance scripts intentionally clear those `/tmp/phase2-fenix-*` roots before
scenarios `12` and `13`.

## Deployment Rotation

Phase 2 treats release change as deployment rotation:

- boot a new `Fenix` release as a new deployment
- expose the same manifest and mailbox control contract
- register it with Core Matrix
- cut future work over once the new deployment reaches healthy runtime
  participation

There is no in-place self-updater in Phase 2. Upgrade and downgrade are the
same kernel-facing operation.
