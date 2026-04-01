# Agent Program Runtime Contract Design

## Status

Approved design for the next contract reset between `core_matrix` and external
agent runtimes such as `agents/fenix`.

This document is intentionally destructive-first:

- compatibility is not required
- legacy payload shapes do not need adapters
- historical test fixtures may be deleted and replaced
- database reset is acceptable when schema correction is cleaner than migration

This note does not replace the earlier kernel and platform documents. It
specializes them around one narrower question:

- what belongs to the Core Matrix runtime kernel
- what belongs to an agent program
- what the versioned request and report envelopes between them should look like

## Purpose

Core Matrix is converging on the right architectural boundary:

- the kernel should remain the minimal durable runtime substrate
- business execution behavior should live in pluggable agent programs

Externally, the product may continue to use the word `agent` because users
already understand it. Internally, the boundary should be modeled as
`agent program`, `agent profile`, and `runtime contract`.

This lets the platform support more than one product shape without turning the
kernel into a Fenix-shaped business runtime.

## Executive Summary

Core Matrix should own:

- durable conversation, turn, and workflow state
- runtime resource lifecycle for tool invocations, command runs, and process
  runs
- mailbox delivery, wait and resume semantics, and workflow re-entry
- capability visibility, governance, and audit
- transcript and context projection
- final persistence authority for all kernel-owned resources

Agent programs should own:

- prompt assembly
- context compaction policy
- memory policy and memory extraction
- profile behavior
- domain-specific tool shaping
- subagent or specialist strategy
- output shaping and summary generation

The contract between the two should be reset around four surfaces:

1. assignment execution
2. provider round preparation
3. program-owned tool execution
4. runtime execution reporting

## Relationship To Existing Design

This document narrows and updates the earlier protocol guidance in
`docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md`.

The earlier note correctly separated protocol methods, tool names, and
transport details. The next step is to normalize the payload envelopes
themselves and stop treating `agent_context` as a bag for unrelated concerns.

Use the following existing code as the current baseline being corrected:

- `core_matrix/app/services/agent_control/create_execution_assignment.rb`
- `core_matrix/app/services/provider_execution/prepare_program_round.rb`
- `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- `core_matrix/app/services/agent_control/handle_execution_report.rb`
- `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- `agents/fenix/app/services/fenix/context/build_execution_context.rb`
- `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- `agents/fenix/app/services/fenix/runtime/prepare_round.rb`
- `agents/fenix/app/services/fenix/runtime/execute_program_tool.rb`
- `agents/fenix/app/services/fenix/runtime/execute_agent_program_request.rb`

## Naming And Concept Model

### External Naming

User-facing product language may continue to say `agent`.

Examples:

- agent
- subagent
- agent deployment
- agent conversation

This is a product concern, not a kernel-domain concern.

### Internal Naming

Inside the architecture and the protocol, prefer:

- `AgentProgram`
- `AgentProfile`
- `AgentTaskRun`
- `SubagentSession`
- `ExecutionEnvironment`
- `RuntimeCapabilityContract`

The point is not to rename every persisted model immediately. The point is to
make the boundary explicit:

- an `agent installation` identifies a logical product integration
- a concrete runtime process is an `agent program deployment`
- a profile expresses a behavior and capability mask inside that program

## Kernel Responsibilities

Core Matrix must remain generic and durable.

It should own:

- execution snapshots and context projection
- workflow orchestration and re-entry
- mailbox delivery and report freshness checks
- governance over visible tools and profiles
- persisted resource truth for:
  - `ToolInvocation`
  - `CommandRun`
  - `ProcessRun`
  - `SubagentSession`
  - `ConversationSummarySegment`
  - workflow wait states and retry state
- audit, telemetry, and publication surfaces

Core Matrix must not own:

- prompt wording
- few-shot examples
- memory taxonomies
- summarization heuristics
- agent persona
- tool phrasing or display summaries
- context compaction strategy
- profile-specific task strategy

## Agent Program Responsibilities

An agent program is the business execution runtime that consumes kernel
projections and emits execution intent and reports.

It should own:

- prompt section assembly
- prompt cache boundaries
- context shaping before provider calls
- profile-specific behavior
- memory reads, writes, extraction, and consolidation policy
- program-owned tool implementations
- subagent or specialist orchestration strategy
- short and long summaries for progress and outcome

An agent program must not:

- treat local files as the source of truth for kernel-owned runtime resources
- persist durable workflow state outside kernel contracts
- mutate kernel-owned resources except through explicit protocol methods
- assume it can reinterpret history from current config

## Design Principles

1. The kernel sends projections, not raw internal models.
2. The agent program returns intent and reports, not direct truth mutation.
3. Payloads should be shaped around responsibilities, not implementation
   convenience.
4. `task_payload` describes the requested job only.
5. provider metadata and capability metadata must not be smuggled through
   `task_payload`.
6. every envelope carries `protocol_version`.
7. every envelope should be safe to fixture and compare in contract tests.
8. summary production should be a first-class output, not an afterthought.
9. compatibility is intentionally out of scope during this reset.

## Turn Control Semantics

Turn lifecycle and turn control must remain separate concerns.

Lifecycle answers whether work is active, paused, interrupted, or complete.
Control answers what the operator is asking the active work to do next.

The kernel should therefore model these separately:

- lifecycle examples:
  - `running`
  - `pause_requested`
  - `paused_turn`
  - `interrupted`
  - `completed`
- control actions:
  - `steer`
  - `pause`
  - `resume`
  - `retry`
  - `stop`

`steer` is not a lifecycle state. It is an input mutation or follow-up control
channel for an active or resumable turn.

The intended behavior is:

- running work before the first transcript side-effect boundary may accept
  in-place steering
- running work after a side-effect boundary may queue follow-up work instead of
  rewriting the current turn
- paused work may accept steering as resume guidance because the turn remains
  active and resumable; this bypasses during-generation queue or restart
  policy because the operator is updating the same resumable turn rather than
  redirecting still-running work
- pause is only valid when the kernel still has a resumable mainline execution
  attempt to re-enter; otherwise the request should be rejected rather than
  persisting a paused state that cannot later resume
- interrupted work must not accept in-place steering; it requires a new turn
- external or agent-facing steering requests should bind to the intended active
  turn by `public_id` so the kernel can reject stale or misrouted control
  input instead of applying it to the wrong turn

This is the same boundary Core Matrix should preserve regardless of which
agent program is plugged into the kernel.

## Contract Structure

The next contract should stop scattering top-level fields and instead use a
small set of named sections.

The canonical envelope sections are:

- `protocol_version`
- `request_kind`
- `task`
- `conversation_projection`
- `capability_projection`
- `provider_context`
- `runtime_context`
- `task_payload`

Not every request kind needs every section, but the section names should stay
stable.

## Canonical Envelope

```json
{
  "protocol_version": "agent-program/2026-04-01",
  "request_kind": "execution_assignment",
  "task": {
    "agent_task_run_id": "atr_...",
    "workflow_run_id": "wr_...",
    "workflow_node_id": "wn_...",
    "conversation_id": "conv_...",
    "turn_id": "turn_...",
    "kind": "turn_step"
  },
  "conversation_projection": {
    "messages": [],
    "context_imports": [],
    "prior_tool_results": [],
    "projection_fingerprint": "sha256:..."
  },
  "capability_projection": {
    "tool_surface": [],
    "profile_key": "main",
    "is_subagent": false,
    "subagent_session_id": null,
    "parent_subagent_session_id": null,
    "subagent_depth": 0,
    "owner_conversation_id": null,
    "subagent_policy": {}
  },
  "provider_context": {
    "budget_hints": {},
    "provider_execution": {},
    "model_context": {}
  },
  "runtime_context": {
    "runtime_plane": "agent",
    "logical_work_id": "workflow-node:...",
    "attempt_no": 1,
    "deployment_public_id": "dep_..."
  },
  "task_payload": {}
}
```

## Envelope Sections

### `task`

`task` identifies the durable kernel work item being executed.

It should contain:

- `agent_task_run_id`
- `workflow_run_id`
- `workflow_node_id`
- `conversation_id`
- `turn_id`
- `kind`

It should not contain provider configuration, prompt state, or profile policy.

### `conversation_projection`

`conversation_projection` is the kernel-owned read model for the current work.

It should contain:

- `messages`
- `context_imports`
- `prior_tool_results`
- `projection_fingerprint`

`messages` replaces the current split naming between `context_messages` and
`transcript`.

`context_imports` remains the place for summary imports and other explicit
projection additions.

`prior_tool_results` remains the provider-loop continuation bridge.

### `capability_projection`

`capability_projection` replaces the current overloaded `agent_context`.

It should contain:

- `tool_surface`
- `profile_key`
- `is_subagent`
- `subagent_session_id`
- `parent_subagent_session_id`
- `subagent_depth`
- `owner_conversation_id`
- `subagent_policy`

`tool_surface` is the visible program-facing tool catalog for the current work.
It replaces ad hoc use of `allowed_tool_names` plus a separately returned
`program_tools`.

The agent program can derive allowlists from `tool_surface`; the kernel should
stop sending both a list and a catalog when one catalog is enough.

### `provider_context`

`provider_context` carries model and loop settings needed for provider-backed
round work.

It should contain:

- `budget_hints`
- `provider_execution`
- `model_context`

For deterministic task execution that does not call a model, this section may be
present but ignored.

### `runtime_context`

`runtime_context` contains mail and runtime metadata that does not belong in the
business task.

It should contain:

- `runtime_plane`
- `logical_work_id`
- `attempt_no`
- `deployment_public_id`

If later needed, this is also the correct place for:

- `mailbox_item_id`
- `protocol_message_id`
- short-lived runtime diagnostics

### `task_payload`

`task_payload` must describe only the requested job.

Examples:

- the deterministic tool to execute in a non-model task
- skill task arguments
- a requested profile-local mode
- explicit user-specified arguments that are part of the work

It must not contain:

- visible tool names
- provider model details
- runtime identifiers already present elsewhere
- projection data copied out of `conversation_projection`

## Request Kinds

The next contract should normalize three request kinds.

### 1. `execution_assignment`

This is the kernel-to-program request for direct mailbox execution.

Use it for:

- deterministic tasks
- subagent work
- skill management tasks
- program-owned execution outside provider turn loops

Required sections:

- `protocol_version`
- `request_kind`
- `task`
- `conversation_projection`
- `capability_projection`
- `provider_context`
- `runtime_context`
- `task_payload`

### 2. `prepare_round`

This is the kernel-to-program request for provider-loop message preparation.

Use it when the kernel is about to call the provider and needs:

- final messages
- visible tool surface
- compacted context
- optional trace diagnostics

Required sections:

- `protocol_version`
- `request_kind`
- `task`
- `conversation_projection`
- `capability_projection`
- `provider_context`
- `runtime_context`

`task_payload` is usually unnecessary for this request kind.

### 3. `execute_program_tool`

This is the kernel-to-program request for executing a program-owned tool after
the provider selected it.

Required sections:

- `protocol_version`
- `request_kind`
- `task`
- `capability_projection`
- `provider_context`
- `runtime_context`
- `program_tool_call`
- `runtime_resource_refs`

Suggested shape:

```json
{
  "protocol_version": "agent-program/2026-04-01",
  "request_kind": "execute_program_tool",
  "task": {},
  "capability_projection": {},
  "provider_context": {},
  "runtime_context": {},
  "program_tool_call": {
    "call_id": "call_123",
    "tool_name": "workspace_tree",
    "arguments": {}
  },
  "runtime_resource_refs": {
    "tool_invocation": {},
    "command_run": null,
    "process_run": null
  }
}
```

This is cleaner than flattening `tool_call`, `tool_invocation`, `command_run`,
and `process_run` beside unrelated context fields.

## Response Shapes

Responses should also become sectioned and explicit.

### `prepare_round` Response

```json
{
  "status": "ok",
  "messages": [],
  "tool_surface": [],
  "summary_artifacts": [],
  "trace": []
}
```

Rules:

- `messages` is the fully prepared provider input transcript
- `tool_surface` is the visible program-owned tool catalog for this round
- `summary_artifacts` is optional but allowed
- `trace` is non-durable diagnostic detail

### `execute_program_tool` Response

```json
{
  "status": "ok",
  "program_tool_call": {},
  "result": {},
  "output_chunks": [],
  "summary_artifacts": [],
  "trace": []
}
```

Rules:

- `result` is the canonical tool result payload
- `output_chunks` carries streamable output when relevant
- `summary_artifacts` is where concise labels and summaries belong
- the kernel should not depend on `trace` for correctness

### Failure Response

```json
{
  "status": "failed",
  "failure": {
    "classification": "semantic",
    "code": "tool_not_allowed",
    "message": "workspace_write is not visible for this profile",
    "retryable": false
  },
  "summary_artifacts": [],
  "trace": []
}
```

## Summary Artifacts

`summary_artifacts` should become the one normalized place for agent-produced
human-readable summaries.

Suggested shape:

```json
{
  "kind": "tool_batch",
  "label": "Ran focused auth tests",
  "text": "Executed auth-related tests and captured the first failing case in signup validation.",
  "source": "agent_program",
  "metadata": {}
}
```

Supported initial kinds:

- `tool_batch`
- `subagent`
- `conversation`
- `memory_candidate`

Rules:

- `label` should be short and timeline-friendly
- `text` may be longer but must remain bounded
- the kernel may choose to persist, ignore, or project these artifacts
- the agent program may emit them in progress or terminal reports

## Runtime Events And Reports

The stable durable report methods should remain:

- `execution_started`
- `execution_progress`
- `execution_complete`
- `execution_fail`

These report names are already good enough. The problem is their payload shape,
not their verb.

### `execution_started`

Suggested payload:

```json
{
  "protocol_version": "agent-program/2026-04-01",
  "method_id": "execution_started",
  "task": {},
  "runtime_context": {},
  "expected_duration_seconds": 30
}
```

### `execution_progress`

Suggested payload:

```json
{
  "protocol_version": "agent-program/2026-04-01",
  "method_id": "execution_progress",
  "task": {},
  "runtime_context": {},
  "runtime_events": [],
  "summary_artifacts": []
}
```

`runtime_events` is the new normalized place for resource lifecycle events such
as:

- tool invocation started
- tool invocation output
- command output forwarded
- subagent stage change

This is cleaner than mixing `tool_invocation`, `tool_invocation_output`, and
other future event kinds inside one loose `progress_payload`.

### `execution_complete`

Suggested payload:

```json
{
  "protocol_version": "agent-program/2026-04-01",
  "method_id": "execution_complete",
  "task": {},
  "runtime_context": {},
  "output": {},
  "runtime_events": [],
  "summary_artifacts": []
}
```

### `execution_fail`

Suggested payload:

```json
{
  "protocol_version": "agent-program/2026-04-01",
  "method_id": "execution_fail",
  "task": {},
  "runtime_context": {},
  "failure": {
    "failure_kind": "runtime_error",
    "last_error_summary": "execution canceled by close request",
    "retryable": false
  },
  "runtime_events": [],
  "summary_artifacts": []
}
```

## Runtime Events

The kernel should treat `runtime_events` as typed facts that may update durable
resource state.

Suggested event kinds:

- `tool_invocation_started`
- `tool_invocation_completed`
- `tool_invocation_failed`
- `tool_invocation_output`
- `command_run_started`
- `command_run_completed`
- `command_run_failed`
- `process_run_started`
- `process_run_state_changed`
- `subagent_state_changed`

Rules:

- every event kind should have a clear owner and reducer in the kernel
- event payloads should be typed by `event_kind`
- terminal durable truth remains kernel-owned even when derived from program
  reports

## Context Projection Reset

The current execution snapshot is useful but overpacked. The next reset should
re-map it into the new envelope sections instead of passing it through almost
unchanged.

The main changes are:

- `context_messages` becomes `conversation_projection.messages`
- `agent_context` is removed in favor of `capability_projection` and
  `runtime_context`
- `allowed_tool_names` is removed once `tool_surface` is present
- `program_tools` is renamed to `tool_surface`

This change should be made in one pass across:

- `Workflows::BuildExecutionSnapshot`
- `AgentControl::CreateExecutionAssignment`
- `ProviderExecution::PrepareProgramRound`
- `Fenix::Context::BuildExecutionContext`
- `Fenix::Runtime::PrepareRound`
- `Fenix::Runtime::ExecuteAssignment`
- `Fenix::Runtime::ExecuteProgramTool`

## Tool Surface Reset

The current split between:

- capability snapshot tool catalog
- agent-context allowlist
- prepare-round returned `program_tools`

is redundant.

The next design should make one rule true:

- the kernel decides the visible `tool_surface`
- the agent program consumes that `tool_surface`
- the same `tool_surface` is returned to the provider round if needed

This removes the need to keep a list and a catalog in sync.

## Fenix Implications

For `agents/fenix`, this design implies:

- `BuildExecutionContext` should become a section-aware envelope reader
- prompt assembly should consume `capability_projection.profile_key` instead of
  digging through `agent_context`
- tool review should validate against `tool_surface`
- operator snapshot should remain local and program-owned
- prompt, memory, and compaction remain entirely on the Fenix side

This keeps Fenix as a strong reference program without making it the kernel's
business-logic home.

## Core Matrix Implications

For `core_matrix`, this design implies:

- contract responsibility gets clearer
- execution snapshot naming becomes more coherent
- report reducers can move from ad hoc payload parsing to typed runtime events
- conversation and subagent read models can later consume `summary_artifacts`
  without special Fenix branches

Most importantly, the kernel becomes easier to extend to new agent programs
because it stops assuming a Fenix-shaped context payload.

## Migration And Reset Strategy

This design should be implemented as a destructive reset.

Rules:

- do not add compatibility shims
- do not keep old and new payload shapes in parallel
- replace existing contract fixtures instead of supporting both
- delete obsolete tests and rebuild them around the new envelopes
- reset the database if schema correction is simpler than migration

Recommended order:

1. rewrite the shared envelope fixtures and contract tests
2. rewrite `core_matrix` request builders
3. rewrite `agents/fenix` context readers and response builders
4. rewrite report handling around typed runtime events and summary artifacts
5. delete dead payload parsing and old fixture names

## Acceptance Criteria

This design is considered landed when:

- all kernel-to-program requests use the sectioned envelope
- `agent_context` no longer exists in the public runtime contract
- `tool_surface` is the only visible tool catalog for the current work
- progress and terminal reports support `summary_artifacts`
- progress and terminal reports use typed `runtime_events`
- old payload fixtures and compatibility tests are deleted
- a fresh database and fresh fixtures are sufficient to run the test suite

## Non-Goals

This design does not attempt to define:

- a long-term public plugin marketplace
- cross-version compatibility guarantees
- final end-user wording for `specialist`
- every future runtime event kind
- every future summary artifact persistence rule

Those concerns can follow once the kernel-program boundary is reset and stable.
