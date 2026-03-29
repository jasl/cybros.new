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
- `SubagentSessions::SendMessage` appends agent-facing messages into an
  agent-addressable child conversation
- `SubagentSessions::Wait` waits on durable session state
- `SubagentSessions::RequestClose` creates mailbox-driven close requests

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
