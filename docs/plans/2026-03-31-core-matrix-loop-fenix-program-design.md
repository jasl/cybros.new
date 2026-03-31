# Core Matrix Loop With Fenix Agent Program Design

## Status

- Date: 2026-03-31
- Status: implemented, verified, and accepted with the 2048 proof package
- Supersedes:
  - `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-31-fenix-provider-backed-agent-loop-design.md`
  - `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-31-fenix-provider-backed-agent-loop.md`

## Current Implementation Status

The repository now reflects the mailbox-first version of this design.

Implemented:

- `Core Matrix` owns provider transport and repeated provider rounds.
- `Core Matrix` no longer uses a synchronous direct `Fenix` HTTP client for
  `prepare_round` or `execute_program_tool`.
- `Core Matrix` creates durable `agent_program_request` mailbox items and
  waits for terminal control-plane reports through
  `ProviderExecution::ProgramMailboxExchange`.
- `Core Matrix` accepts `agent_program_completed` and `agent_program_failed`
  reports and records them against durable mailbox receipts.
- `Fenix` no longer exposes direct `/runtime/rounds/prepare` or
  `/runtime/program_tools/execute` callback endpoints.
- `Fenix` now handles both `prepare_round` and `execute_program_tool` as
  mailbox work through `Fenix::Runtime::ExecuteAgentProgramRequest`.
- `Core Matrix` now freezes loop control as `provider_execution.loop_policy`
  instead of a single `loop_settings` hash.
- Only `loop_policy.max_rounds` is active today. `parallel_tool_calls`,
  `max_parallel_tool_calls`, and `loop_detection` are reserved contract fields
  for later follow-up and do not change execution semantics yet.

Verified:

- focused Core Matrix and Fenix regression suites covering mailbox exchange,
  round preparation, execution assignment shape, and provider loop behavior
- full repository verification matrix
- end-to-end 2048 acceptance with refreshed proof artifacts

## Goal

Reframe the `Core Matrix + Fenix` architecture so the top-level agent loop runs
in `Core Matrix`, while `Fenix` remains an agent program that provides prompt
construction, skills policy, and program-owned tools.

The target end state is a complementary system:

- `Core Matrix` provides the loop kernel
- `Fenix` provides the agent-program intelligence

Both are required to complete the full agent application.

`Core Matrix` and `Fenix` should be treated as fully orthogonal components with
fully complementary responsibilities. Neither should absorb the other's core
ownership boundary.

## Architectural Position

The old March 31 direction chose a Fenix-first runtime loop. This replacement
design rejects that split.

The new position is:

- `Core Matrix` owns the top-level provider-backed round loop
- `Core Matrix` owns generic tool-calling execution and durable workflow proof
- `Core Matrix` owns generic Streamable HTTP MCP support
- `Fenix` owns prompt shaping, skills policy, and execution of
  program-specific tools

This makes `Core Matrix` the reusable execution substrate and keeps `Fenix`
focused on agent-specific cognition and environment-dependent capabilities.

## Hard Protocol Constraint

`Core Matrix` must not directly dispatch application work into an agent program
through synchronous request/response RPC.

That means:

- no `Core Matrix -> Fenix` execution HTTP callback endpoint for normal round
  preparation
- no `Core Matrix -> Fenix` execution HTTP callback endpoint for normal
  program-tool execution
- no hidden side channel that bypasses the durable control plane

The only allowed initiation path is mailbox-first control-plane delivery:

- durable mailbox item written by `Core Matrix`
- realtime websocket push as an optimization
- poll as the fallback delivery mechanism
- report messages back into `Core Matrix` as the completion path

WebSocket is therefore a delivery optimization, not the business protocol.
Mailbox state is the durable truth.

## Core Matrix Responsibilities

`Core Matrix` owns the generic loop substrate and durable orchestration:

- conversations, turns, and workflow DAG progression
- mailbox assignment and runtime control
- provider session lifecycle and transport to LLM APIs
- request credentials, routing, usage accounting, and streaming output
- repeated round execution:
  - request round preparation
  - await round-preparation report
  - call provider
  - inspect tool calls
  - execute tools
  - append tool results
  - repeat until terminal output or wait condition
- generic tool-calling support
- generic Streamable HTTP MCP support
- durable truth and publication for:
  - `ToolInvocation`
  - `CommandRun`
  - `ProcessRun`
  - workflow wait transitions
  - subagent orchestration artifacts
  - agent-program mailbox requests and reports
- audit, proof export, interrupt, retry, and governance behavior

`Core Matrix` must not understand skill internals, skill packaging, or any
agent-program-specific prompt construction policy.

## Fenix Responsibilities

`Fenix` remains an agent program, not the loop kernel.

`Fenix` owns:

- system prompt and profile-specific prompt overlays
- per-round prompt assembly policy
- skill discovery, skill selection, and skill injection strategy
- skill installation and skill repository management
- reading `SKILL.md` and skill-relative supporting files
- agent-program-specific tool exposure
- execution of program-owned tools that depend on the Fenix runtime
  environment, including:
  - workspace and filesystem helpers
  - browser tooling
  - memory helpers
  - command and process helpers that remain program-owned
  - skill-backed tools or actions

`Fenix` does not own the outer provider loop and does not directly drive the
world. It produces the "thought side" of a round and executes only the
program-owned actions that `Core Matrix` routes to it through the mailbox-first
control plane.

## Why Provider Session Belongs In Core Matrix

Provider session and transport should move into `Core Matrix` because they are
kernel infrastructure rather than agent-program behavior.

Reasons:

- provider credentials and routing are installation-level concerns
- usage accounting and latency profiling are kernel-level facts
- streaming, cancellation, retry, stale-result rejection, and durable proof
  already align with existing `Core Matrix` execution infrastructure
- future agent programs should be able to reuse the same provider loop without
  re-implementing transport stacks

This keeps provider behavior unified even when the agent-program layer changes.

## Why Skills Stay In Fenix

`Skills` must remain fully outside the `Core Matrix` kernel abstraction.

Reasons:

- skills depend on an agent-program-specific environment
- skills require filesystem access such as reading `SKILL.md`
- skills may include executable helper files or program-local conventions
- skills are optional; future agent programs may not implement them at all

Therefore:

- `Core Matrix` does not read `SKILL.md`
- `Core Matrix` does not install or activate skills
- `Core Matrix` does not model skills as a first-class kernel concept

Instead, skills affect the system only indirectly through `Fenix`:

- they shape the prompt returned for a round
- they may cause `Fenix` to expose additional program-owned tools

## Complementary Model

`Fenix` and `Core Matrix` are fully complementary.

- They are intentionally orthogonal.
- Their responsibilities are fully complementary.
- `Fenix` provides the thought.
- `Core Matrix` provides the loop, body, and durable reflexes.

Without `Core Matrix`, `Fenix` has no complete execution loop.

Without `Fenix`, `Core Matrix` has no agent-program-specific prompt shaping or
skill-aware behavior.

The product is the combination.

Orthogonal here means:

- `Core Matrix` does not absorb skill semantics, prompt policy, or program-local
  runtime conventions
- `Fenix` does not absorb provider transport, repeated loop control, generic MCP
  execution, or durable workflow orchestration

The overlap between them should be protocol only, not duplicated ownership.

## Mailbox-First Program Contract

The logical operations between `Core Matrix` and `Fenix` remain:

- `prepare_round`
- `execute_program_tool`

But they are not synchronous RPC methods. They are mailbox work families with
durable request and reply semantics.

### 1. `prepare_round`

Purpose:

- ask the agent program to prepare this round's cognition package

Request payload should include:

- turn, conversation, workflow, and mailbox identifiers
- current transcript and context imports
- budget and compaction hints
- visible environment and profile metadata
- prior tool results accumulated in the current loop
- cancellation or round-control hints as needed

Reply payload should include:

- final `messages` for the provider request
- program-owned visible tools and JSON schemas
- optional round-local policy hints

Semantics:

- `Core Matrix` creates a mailbox item for round preparation
- websocket may wake a connected runtime immediately
- polling must still be sufficient when websocket delivery is absent
- `Fenix` executes the preparation locally and reports the result back
- `Core Matrix` waits on durable report completion, not an HTTP response

### 2. `execute_program_tool`

Purpose:

- execute a program-side tool inside the Fenix runtime environment

Request payload should include:

- `tool_call_id`
- `tool_name`
- structured arguments
- conversation, turn, workflow, and runtime identifiers
- any execution metadata needed for reporting

Reply payload should include:

- structured tool result
- optional streamed progress or output chunks
- a compact durable summary suitable for proof and transcript use

Semantics:

- `Core Matrix` creates a mailbox item for program-tool execution
- `Fenix` executes the program-owned action inside its local runtime
- `Fenix` reports completion or failure back through the control plane
- `Core Matrix` still owns the surrounding tool-calling loop

## Tool Categories

The provider-visible tool surface should be the union of three categories.

### Kernel-native tools

Executed directly by `Core Matrix`.

Examples:

- workflow and wait related controls
- subagent orchestration tools
- durable interaction or policy-gate tools
- any other generic loop-owned control surface

### MCP-backed tools

Executed by `Core Matrix` through its generic Streamable HTTP MCP support.

This keeps MCP support reusable across agent programs.

### Program-owned tools

Declared by `Fenix` during round preparation and executed by `Fenix` through
the mailbox-first program-tool request/reply path.

These include tools that depend on Fenix-local runtime capabilities or
skill-aware behavior.

## Execution Model

The top-level loop belongs to `Core Matrix`.

One round should work like this:

1. `Core Matrix` begins or resumes an agent task round.
2. `Core Matrix` enqueues a `prepare_round` mailbox request.
3. `Fenix` receives that work over websocket push or poll.
4. `Fenix` executes local prompt assembly and reports round messages plus
   program-owned visible tools.
5. `Core Matrix` merges those program-owned tools with any kernel-native and
   MCP-backed tools that should be visible for the round.
6. `Core Matrix` performs the provider API request itself.
7. If the model returns terminal content:
   - `Core Matrix` persists output
   - `Core Matrix` advances the workflow
   - the loop ends
8. If the model returns tool calls:
   - `Core Matrix` routes each tool call by category
   - kernel-native tools run in `Core Matrix`
   - MCP tools run through generic MCP support
   - Fenix-owned tools are enqueued back to the agent program through the
     mailbox-first control plane
9. `Core Matrix` appends tool results to round state.
10. `Core Matrix` repeats the loop until terminal output or a wait condition.

This preserves one owner for the loop and one owner for program cognition.

## Workflow And Subagent Behavior

Subagents remain kernel-owned orchestration, not Fenix-owned loop
infrastructure.

That means:

- `Core Matrix` owns durable subagent resources and barrier/wait behavior
- `Core Matrix` owns workflow materialization and resume semantics
- `Fenix` may influence whether subagent tools are useful to expose through its
  round preparation policy
- once the model chooses a subagent tool, `Core Matrix` executes the durable
  orchestration path

This keeps subagent work visible in workflow proof without turning subagent
control into a Fenix-private mechanism.

## Compatibility

Compatibility with the earlier Fenix-first loop design is not required.

The old direction should be treated as superseded, not as a shape that the new
system must preserve.

Compatibility with any synchronous HTTP program-contract experiment is also not
required. That branch direction should be treated as a rejected intermediate
state.

## Migration Posture

This redesign is allowed to be destructive.

- do not preserve compatibility with the rejected Fenix-first loop split
- do not preserve compatibility with the rejected synchronous HTTP program
  contract
- do not add compatibility shims solely to keep transitional code alive
- prefer replacing old boundaries outright when the new boundary is clear
- if a schema or persistence model is wrong for the new design, fix it at the
  source rather than layering adapters around it

For database work during implementation:

- migration files may be rewritten in place when that produces a cleaner final
  schema for this branch
- regenerating `schema.rb` from a clean database is acceptable

The implementation should stop for discussion only when a real architectural
conflict appears. Otherwise it should proceed automatically through execution
and acceptance.

## Validation Target

The acceptance style from the earlier work remains valid and should be
preserved.

The key manual proof is still:

- a real `Core Matrix` conversation and turn flow
- a real browser-visible workload
- manual operation by the agent through the normal loop
- a finished browser-based `2048` game

This manual validation should be performed by the agent through the
`Core Matrix`-owned loop, with `Fenix` participating only through the
mailbox-first agent-program protocol.

## Success Criteria

This design succeeds when:

- `Core Matrix` owns provider transport, repeated loop control, generic tool
  routing, and durable proof
- `Fenix` owns prompt assembly, skills policy, and execution of program-owned
  tools
- `Core Matrix` never directly dispatches application work into `Fenix` through
  synchronous RPC
- mailbox state remains the durable truth for cross-app agent-program work
- websocket and poll are interchangeable delivery paths for the same mailbox
  work items
- reports from `Fenix` are sufficient for `Core Matrix` to continue the loop
  without hidden in-memory coupling
- MCP remains reusable inside `Core Matrix`
- skills remain optional and agent-program-specific inside `Fenix`
- the real browser `2048` validation completes through the final architecture

## Non-Goals

This design does not attempt to:

- make skills a kernel feature
- move prompt policy into `Core Matrix`
- make `Fenix` the owner of provider transport
- keep direct execution HTTP callbacks as a supported boundary
- collapse the mailbox control plane into a best-effort transport shortcut
