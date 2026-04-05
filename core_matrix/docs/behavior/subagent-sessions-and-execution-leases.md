# Subagent Sessions And Execution Leases

## Purpose

Current delegated execution uses conversation-first `SubagentSession`
control while `ExecutionLease` remains the shared durable heartbeat and
holder-tracking primitive.

The landed model separates concerns cleanly:

- `Conversation` owns transcript and lineage
- `SubagentSession` owns durable subagent control and close state
- `AgentTaskRun(kind = "subagent_step")` owns execution of delegated work
- `ExecutionLease` tracks accepted holders for leasable runtime resources

Conversation supervision reads child-task status from `SubagentSession`
instead of scraping child workflow internals after the fact.

## Subagent Sessions

- `SubagentSession` is the durable subagent control aggregate
- every session belongs to:
  - one installation
  - one owner conversation
  - one child conversation
- turn-scoped sessions also point to one `origin_turn`
- nested sessions point to `parent_subagent_session`
- `depth` is `0` at the root of a subagent tree and otherwise must equal the
  parent depth plus one
- `profile_key` is always present and is resolved from the runtime-declared
  `profile_catalog`

## Session Lifecycle

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
- `SubagentSession#terminal_for_wait?` treats `completed`, `failed`, and
  `interrupted` as terminal for parent barrier resolution; `waiting` is
  intentionally non-terminal because the child workflow still owns live work
  even when it is paused on its own blocker
- normalized supervision summaries such as `current_focus_summary`,
  `waiting_summary`, `blocked_summary`, and `next_step_hint` are the operator
  surface consumed by conversation supervision and side chat
- close-control metadata also comes from `ClosableRuntimeResource`
- `SubagentSessions::RequestClose` writes `close_state = requested` plus close
  request metadata; terminal close reports then settle `close_state` into
  `closed` or `failed`
- quiescence checks, blocker snapshots, turn-interrupt barriers, and
  `SubagentSessions::Wait` all read that durable close model and only expose
  `derived_close_status` as a derived machine-facing projection

## Session Boundaries

- `SubagentSessions::Spawn` creates the child conversation, the
  `SubagentSession`, the initial child turn, and the first
  `AgentTaskRun(kind = "subagent_step")`
- `Workflows::HandleWaitTransitionRequest` is the yielding-workflow boundary
  that turns accepted `subagent_spawn` intents into those durable child
  resources
- child workflow creation now inherits the origin turn's frozen selector and
  selector source when it re-enters `Workflows::CreateForTurn`, so delegated
  work stays aligned with the parent's origin-turn `ExecutionRuntime` when one
  was selected, plus the same frozen capability contract, instead of silently
  falling back to a different selector lane
- `SubagentSessions::SendMessage` appends agent-facing messages into an
  agent-addressable child conversation
- `SubagentSessions::Wait` waits on durable session state
- `SubagentSessions::RequestClose` creates mailbox-driven close requests

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
  - `subagent_session_ids` as session `public_id` values
  - yielding node `public_id` and `node_key`
- child terminal execution reports synchronize `SubagentSession.observed_status`
  from the actual child workflow outcome:
  - `waiting` when the child workflow is paused on its own blocker
  - `completed`, `failed`, or `interrupted` once the child task is terminal
- `Workflows::ResumeAfterWaitResolution` is the only parent barrier-resolution
  boundary. It checks the current `subagent_barrier` wait payload against live
  session state and only re-enters the parent agent once every referenced
  session has reached a terminal wait status.

## Execution Leases

- `ExecutionLease` remains the shared explicit lease row for accepted runtime
  holders
- supported leased resources are:
  - `AgentTaskRun`
  - `ProcessRun`
  - `SubagentSession`
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
  `ProcessRun`; the session allowlist keeps the close-control and validation
  model aligned if runtimes grow into direct session leasing later

## Failure Modes

- sessions reject installation drift across owner conversation, child
  conversation, origin turn, and parent session
- turn-scoped sessions reject a missing `origin_turn`
- nested sessions reject incorrect depth
- leases reject unsupported resource types
- leases reject installation and workflow drift away from the leased resource
- stale heartbeats do not silently restore timed-out ownership
