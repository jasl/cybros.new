# Round 1 Architecture Audit Design

## Status

- Date: 2026-04-03
- Round: 1
- Sweep order: `3 -> 2 -> 1`
- Status: approved audit baseline

## Scope

Round 1 focuses on the highest-value structural problems that are still present
after the accepted agent / execution-runtime reset:

1. code layering, module boundaries, and responsibility placement
2. schema, aggregates, and source-of-truth cleanup
3. `Core Matrix <-> Fenix` protocol, communication, and hot-path data flow

The fixed product principles from
[2026-04-03-multi-round-architecture-audit-and-reset-framework.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-03-multi-round-architecture-audit-and-reset-framework.md)
remain unchanged:

- all user-visible agent-loop progression remains owned by `Core Matrix`
- `Core Matrix` `Workflow` remains the only orchestration truth
- `Fenix` may own program behavior and execution-runtime behavior, but it does
  not become the workflow scheduler
- every completed round must still pass the same acceptance standard,
  especially the provider-backed `2048` capstone checklist

## Repository Snapshot

Current structural signals from the codebase:

- `core_matrix`
  - `app/services`: 238 files
  - `app/models`: 82 files
  - `app/controllers`: 28 files
- `agents/fenix`
  - `app/services`: 77 files
  - `app/models`: 3 files
  - `app/controllers`: 3 files

Largest active hotspots during this audit:

- `core_matrix/app/services/agent_control/handle_execution_report.rb`
- `core_matrix/app/services/provider_execution/route_tool_call.rb`
- `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- `core_matrix/app/services/provider_execution/agent_request_exchange.rb`
- `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- `agents/fenix/app/services/fenix/hooks/project_tool_result.rb`
- `agents/fenix/app/services/fenix/processes/manager.rb`

These hotspots are not just large files. They also cross multiple architecture
layers in the same object.

## Findings

### P1: execution envelope ownership is duplicated across persistence, mailbox, and runtime layers

Symptoms:

- `Turn` persists a full `execution_snapshot_payload`.
- `CreateExecutionAssignment` copies most of that snapshot into a mailbox
  payload.
- `Fenix::Runtime::MailboxWorker` copies the full mailbox item again into
  `RuntimeExecution.mailbox_item_payload`.
- `Fenix` rebuilds near-identical runtime contexts in three separate places.

Evidence:

- [core_matrix/app/services/workflows/build_execution_snapshot.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/build_execution_snapshot.rb#L13) builds the full execution envelope, including conversation projection, capability projection, provider context, runtime context, attachment manifest, and multimodal projections.
- [core_matrix/app/services/agent_control/create_execution_assignment.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_execution_assignment.rb#L31) persists a mailbox item whose payload duplicates that envelope.
- [agents/fenix/app/services/fenix/runtime/mailbox_worker.rb](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/mailbox_worker.rb#L43) persists the full mailbox item again in `RuntimeExecution`.
- [agents/fenix/app/models/runtime_execution.rb](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/models/runtime_execution.rb#L12) validates and stores full mailbox payloads plus reports, trace, and output.
- [agents/fenix/app/services/fenix/context/build_execution_context.rb](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/context/build_execution_context.rb#L12), [agents/fenix/app/services/fenix/runtime/prepare_round.rb](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/prepare_round.rb#L34), and [agents/fenix/app/services/fenix/runtime/execute_tool.rb](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_tool.rb#L51) each rebuild nearly the same context graph.

Why it matters:

- the same execution facts are serialized and copied multiple times
- hot-path changes require synchronized edits across `Core Matrix` and `Fenix`
- debugging payload drift becomes harder because there is no single owner
- `Fenix` local persistence keeps too much kernel-owned data

Recommended reset:

- define one durable kernel-owned execution envelope shape
- make mailbox items reference that envelope plus only the minimal per-request
  delta
- make `RuntimeExecution` persist only operational data needed for replay,
  cancellation, queueing, and proof, not the full mailbox payload
- introduce one shared `Fenix` payload-to-context builder reused by assignment,
  `prepare_round`, and `execute_tool`

### P1: mailbox target modeling is still transitional and leaks legacy compatibility

Symptoms:

- mailbox items carry `target_agent`, optional
  `target_agent_snapshot`, optional `target_execution_runtime`,
  `target_kind`, `target_ref`, and `runtime_plane`
- `target_ref` is only a duplicated durable identifier
- legacy `"agent"` / `"environment"` plane names are still normalized instead
  of being rejected
- routing logic still derives execution delivery from
  `agent.default_execution_runtime_id`

Evidence:

- [core_matrix/app/models/agent_control_mailbox_item.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_control_mailbox_item.rb#L33) stores three potential target relations plus `target_kind` and `target_ref`.
- [core_matrix/app/models/agent_control_mailbox_item.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_control_mailbox_item.rb#L161) validates `target_ref` against data already present in the row.
- [core_matrix/app/models/agent_control_mailbox_item.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_control_mailbox_item.rb#L191) still accepts old runtime-plane aliases.
- [core_matrix/app/services/agent_control/resolve_target_runtime.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/resolve_target_runtime.rb#L30) routes execution work through `deployment.agent.default_execution_runtime_id`.

Why it matters:

- mailbox routing is carrying both the new model and compatibility baggage
- turn-specific runtime selection is undercut by default-runtime fallback
- the externalized mailbox contract contains fields with no real behavioral
  value

Recommended reset:

- remove `target_ref`
- remove `target_kind` and derive the target mode from the populated foreign
  keys
- reject legacy runtime-plane aliases instead of silently normalizing them
- route execution work only by `target_execution_runtime_id`

### P1: the program / execution split is only half-implemented

Symptoms:

- `execution_assignment` is always sent on the `"program"` plane
- `Fenix::Runtime::ExecuteAssignment` rejects any non-program runtime plane
- execution-runtime tools are still executed through `AgentRequestExchange`

Evidence:

- [core_matrix/app/services/agent_control/create_execution_assignment.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_execution_assignment.rb#L36) always creates `"program"`-plane assignments.
- [agents/fenix/app/services/fenix/runtime/execute_assignment.rb](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb#L26) explicitly rejects anything except `"program"`.
- [core_matrix/app/services/provider_execution/route_tool_call.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/route_tool_call.rb#L33) sends `"execution_runtime"` tools through `AgentRequestExchange`.
- [core_matrix/test/services/provider_execution/route_tool_call_test.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_execution/route_tool_call_test.rb#L65) documents that this current behavior is intentional.

Why it matters:

- the codebase is carrying execution-plane concepts that are not actually first
  class in the assignment loop
- responsibility between program logic and execution-runtime tooling is still
  blurred
- protocol and schema complexity grew faster than the real product contract

Recommended round-1 decision:

- make the current contract explicit: user-visible assignment work is
  agent-plane only; execution plane exists for resource control, process
  supervision, attachment access, and close/report APIs
- remove tests and helpers that pretend execution-plane assignments are a valid
  runtime path
- if true execution-plane work items are needed later, introduce them in a
  separate round with an explicit new contract

### P1: workflow, task, and mailbox aggregates still carry redundant facts

Symptoms:

- `WorkflowRun` stores `workspace`, `conversation`, `turn`, and
  `feature_policy_snapshot`, then mostly delegates back into `turn`
- `AgentTaskRun` stores `agent`, `workflow_run`, `workflow_node`,
  `conversation`, `turn`, and its own feature policy snapshot
- both models spend significant code validating duplicated relationships

Evidence:

- [core_matrix/app/models/workflow_run.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/workflow_run.rb#L41) stores repeated ownership facts and delegates heavily into `turn.execution_snapshot`.
- [core_matrix/app/models/workflow_run.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/workflow_run.rb#L85) contains validation logic whose purpose is largely to reconcile duplicated references.
- [core_matrix/app/models/agent_task_run.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_task_run.rb#L23) stores repeated projection edges and validates them at [core_matrix/app/models/agent_task_run.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_task_run.rb#L46).

Why it matters:

- extra joins are not the real cost here; duplicated ownership facts are
  creating more callbacks, more validations, and more schema drag
- the model graph is harder to reason about because there are too many ways to
  reach the same parent facts

Recommended reset:

- make `Turn` the durable owner of execution snapshot and feature policy
- shrink `WorkflowRun` toward lifecycle, wait-state, and orchestration state
- shrink `AgentTaskRun` toward executable task state, runtime progress, and
  runtime-owned child resources

### P1: several hotspot services still mix application orchestration, domain state changes, and transport/report handling

Symptoms:

- report handling, workflow transitions, command/process reconciliation, and
  UI event broadcasting happen inside one service
- `Fenix::Runtime::ExecuteAssignment` mixes task-mode dispatch, tool
  provisioning, reporting, cancellation handling, and output finalization
- `Fenix::Hooks::ProjectToolResult` is a 400+ line static switchboard

Evidence:

- [core_matrix/app/services/agent_control/handle_execution_report.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_execution_report.rb#L25) owns freshness validation, task-state mutation, tool-invocation mutation, command-run reconciliation, workflow resume/retry logic, subagent sync, and runtime event broadcasting in one object.
- [agents/fenix/app/services/fenix/runtime/execute_assignment.rb](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb#L26) owns runtime-plane validation, skill flow dispatch, deterministic tool dispatch, reporting, and error shaping in one object.
- [agents/fenix/app/services/fenix/hooks/project_tool_result.rb](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/hooks/project_tool_result.rb#L4) hardcodes tool-by-tool projection in one large switch.

Why it matters:

- these files are now acting as permanent "service waiting rooms" instead of
  orchestration shells over smaller abstractions
- changes to tool semantics or report semantics keep touching unrelated code

Recommended reset:

- extract report handling into dedicated collaborators:
  - task lifecycle state update
  - tool-invocation reconciliation
  - command/process reconciliation
  - workflow follow-up transitions
  - runtime event broadcast
- extract `Fenix::Runtime::ExecuteAssignment` into:
  - assignment dispatcher
  - task-mode handlers
  - tool execution reporter
  - payload/context builder
- replace `ProjectToolResult` with a registry keyed by tool name or operator
  group

### P2: conversation-scoped capability preview stayed under a transitional wrapper

Symptoms:

- the conversation-scoped capability preview survived as its own wrapper after
  the turn-scoped model was accepted.
- subagent spawning depended on that transitional name for visibility
  validation.

Evidence:

- [core_matrix/app/services/runtime_capabilities/preview_for_conversation.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/runtime_capabilities/preview_for_conversation.rb) now represents the explicit preview surface.
- [core_matrix/app/services/subagent_connections/spawn.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/subagent_connections/spawn.rb#L101) is the main consumer of that preview object.

Why it matters:

- this is not a correctness bug, but it was a naming and layering holdover
  after the turn-scoped model was accepted

Recommended reset:

- keep an explicit preview capability surface object and delete the old
  conversation-composition wrapper name

## Candidate Reset List

### Must Do

1. Collapse execution-envelope ownership and remove full mailbox duplication in
   `Fenix`.
2. Simplify mailbox targeting by removing `target_ref`, removing legacy
   runtime-plane alias normalization, and routing execution work by
   `target_execution_runtime_id`.
3. Make the current agent-plane / execution-plane contract explicit and
   delete fake execution-plane assignment paths.
4. Extract the largest cross-layer service objects into smaller collaborators.

### Should Do

1. Shrink `WorkflowRun` and `AgentTaskRun` to fewer durable facts.
2. Replace conversation-scoped capability preview via fake turn construction.
3. Replace `ProjectToolResult` with a registry-based projection layer.

### Optional

1. Reduce `AgentRequestExchange` polling pressure once the payload and target
   model are simplified.
2. Revisit proof/debug persistence breadth after the runtime envelope has been
   collapsed.

### Not Now

1. Change provider-governance tables and rate-limit semantics.
2. Rework publication or app-facing transcript/export APIs.
3. Replace Action Cable transport or the manual-acceptance harness.

## Recommended Round 1 Boundary Decisions

Round 1 should treat these as explicit product-level decisions:

- `execution_assignment` is a agent-plane concept
- execution plane is for resource lifecycle and resource materialization, not
  top-level assignment orchestration
- `Turn` remains the durable execution snapshot owner
- mailbox rows are delivery objects, not shadow copies of execution snapshots
- `Fenix` runtime persistence is operational and local, not a second source of
  truth for kernel-owned payloads

## Round 1 Success Criteria

Round 1 is only considered complete when all of the following are true:

- the new mailbox / runtime contract is simpler than the current one
- no active implementation path still depends on legacy runtime-plane aliases
- `Fenix` builds one shared runtime context from payloads instead of three
  parallel copies
- the largest hotspot services are materially smaller and more single-purpose
- the same acceptance checklist still passes, including the provider-backed
  `2048` capstone
