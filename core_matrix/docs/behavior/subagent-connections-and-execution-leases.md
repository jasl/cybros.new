# Subagent Connections And Execution Leases

## Purpose

Current delegated execution uses conversation-first `SubagentConnection`
control while `ExecutionLease` remains the shared durable heartbeat and
holder-tracking primitive.

The landed model separates concerns cleanly:

- `Conversation` owns transcript and lineage
- `SubagentConnection` owns durable subagent control and close state
- `AgentTaskRun(kind = "subagent_step")` owns execution of delegated work
- `ExecutionLease` tracks accepted holders for leasable runtime resources

Conversation supervision reads child-task status from `SubagentConnection`
instead of scraping child workflow internals after the fact.

## Subagent Connections

- `SubagentConnection` is the durable subagent control aggregate
- every connection belongs to:
  - one installation
  - one owner conversation
  - one child conversation
- turn-scoped connections also point to one `origin_turn`
- nested connections point to `parent_subagent_connection`
- `depth` is `0` at the root of a subagent tree and otherwise must equal the
  parent depth plus one
- `profile_key` is always present and is resolved from the runtime-declared
  `profile_catalog`

## Connection Lifecycle

- `scope` is either:
  - `turn`
  - `conversation`
- `close_state` from `ClosableRuntimeResource` is the only durable owner of
  subagent close progression:
  - `open`
  - `requested`
  - `acknowledged`
  - `closed`
  - `failed`
- machine-facing `derived_close_status` remains available as a derived projection:
  - `open -> open`
  - `requested|acknowledged -> close_requested`
  - `closed|failed -> closed`
- `observed_status` records runtime-observed progress:
  - `idle`
  - `running`
  - `waiting`
  - `completed`
  - `failed`
  - `interrupted`
- `SubagentConnection#terminal_for_wait?` treats `completed`, `failed`, and
  `interrupted` as terminal for parent barrier resolution; `waiting` is
  intentionally non-terminal because the child workflow still owns live work
  even when it is paused on its own blocker
- normalized supervision summaries such as `current_focus_summary`,
  `waiting_summary`, `blocked_summary`, and `next_step_hint` are the operator
  surface consumed by conversation supervision and side chat
- close-control metadata also comes from `ClosableRuntimeResource`
- `SubagentConnections::RequestClose` writes `close_state = requested` plus close
  request metadata; terminal close reports then settle `close_state` into
  `closed` or `failed`
- quiescence checks, blocker snapshots, turn-interrupt barriers, and
  `SubagentConnections::Wait` all read that durable close model and only expose
  `derived_close_status` as a derived machine-facing projection

## Connection Boundaries

- `SubagentConnections::Spawn` creates the child conversation, the
  `SubagentConnection`, the initial child turn, and the first
  `AgentTaskRun(kind = "subagent_step")`
- `Workflows::HandleWaitTransitionRequest` is the yielding-workflow boundary
  that turns accepted `subagent_spawn` intents into those durable child
  resources
- child workflow creation now inherits the origin turn's frozen selector and
  selector source when it re-enters `Workflows::CreateForTurn`, so delegated
  work stays aligned with the parent's origin-turn `ExecutionRuntime` when one
  was selected, plus the same frozen capability contract, instead of silently
  falling back to a different selector lane
- `SubagentConnections::SendMessage` appends agent-facing messages into an
  agent-addressable child conversation
- `SubagentConnections::Wait` waits on durable connection state
- `SubagentConnections::RequestClose` creates mailbox-driven close requests

## Barrier Wait And Resume

- parallel `wait_all` stages pause the parent workflow through:
  - `wait_state = waiting`
  - `wait_reason_kind = subagent_barrier`
  - `blocking_resource_type = "SubagentBarrier"`
  - `blocking_resource_id = <intent batch barrier artifact key>`
- the parent wait payload stores only durable identifiers and barrier facts:
  - `batch_id`
  - `stage_index`
  - `barrier_artifact_key`
  - `subagent_connection_ids` as connection `public_id` values
  - yielding node `public_id` and `node_key`
- child terminal execution reports synchronize `SubagentConnection.observed_status`
  from the actual child workflow outcome:
  - `waiting` when the child workflow is paused on its own blocker
  - `completed`, `failed`, or `interrupted` once the child task is terminal
- `Workflows::ResumeAfterWaitResolution` is the only parent barrier-resolution
  boundary. It checks the current `subagent_barrier` wait payload against live
  connection state and only re-enters the parent agent once every referenced
  connection has reached a terminal wait status.

## Execution Leases

- `ExecutionLease` remains the shared explicit lease row for accepted runtime
  holders
- supported leased resources are:
  - `AgentTaskRun`
  - `ProcessRun`
  - `SubagentConnection`
- active leases track:
  - `holder_key`
  - `heartbeat_timeout_seconds`
  - `acquired_at`
  - `last_heartbeat_at`
- released leases additionally track:
  - `released_at`
  - `release_reason`

## Lease Rules

- at most one active lease may exist for a given leased resource
- model validation and a partial unique index both enforce that rule
- a lease is stale when it is still active and
  `last_heartbeat_at < heartbeat_timeout_seconds`
- `Leases::Acquire`, `Leases::Heartbeat`, and `Leases::Release` remain the
  shared service boundaries for lease lifecycle changes
- current delegated execution primarily acquires leases on `AgentTaskRun` and
  `ProcessRun`; the connection allowlist keeps the close-control and
  validation model aligned if runtimes grow into direct connection leasing
  later

## Failure Modes

- connections reject installation drift across owner conversation, child
  conversation, origin turn, and parent connection
- turn-scoped connections reject a missing `origin_turn`
- nested connections reject incorrect depth
- leases reject unsupported resource types
- leases reject installation and workflow drift away from the leased resource
- stale heartbeats do not silently restore timed-out ownership
