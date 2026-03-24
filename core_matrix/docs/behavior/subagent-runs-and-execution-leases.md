# Subagent Runs And Execution Leases

## Purpose

Task 10.4 adds the remaining workflow-owned runtime resources in Milestone 3:
`SubagentRun` for lightweight coordination and `ExecutionLease` for explicit
heartbeat ownership.

This task does not add a second orchestration aggregate, machine-facing APIs,
or recovery-time policy decisions. It establishes:

- workflow-owned subagent coordination rows
- explicit runtime-resource lease ownership
- heartbeat freshness and explicit release semantics

## Subagent Runs

- `SubagentRun` is a workflow-owned runtime resource.
- Every row belongs to one installation, workflow run, and workflow node.
- v1 keeps the coordination contract lightweight and first-class through these
  fields:
  - `parent_subagent_run_id`
  - `depth`
  - `batch_key`
  - `coordination_key`
  - `requested_role_or_slot`
  - `terminal_summary_artifact_id`
- `requested_role_or_slot` is required so the fan-out record states which role
  or slot the runtime work was asked to fill.
- `terminal_summary_artifact_id` is optional, but when present it must point to
  a workflow artifact inside the same workflow run.

## Parentage And Depth

- Root subagent runs use `depth = 0`.
- Child subagent runs point back to a parent row through
  `parent_subagent_run_id`.
- Child depth must equal parent depth plus one.
- Parentage may not cross workflow-run boundaries.
- This keeps nested coordination explicit without creating a separate
  `SwarmRun` or `SwarmPlan` aggregate.

## Lifecycle

- `SubagentRun` lifecycle states in v1 are:
  - `running`
  - `completed`
  - `failed`
  - `canceled`
- `started_at` is required for every row and defaults on create.
- Terminal states require `finished_at`.
- Running rows reject `finished_at`.
- Task 10.4 only introduces spawn-time creation; terminal-state transitions are
  still left to follow-up runtime orchestration work.

## Spawn Boundary

- `Subagents::Spawn` is the application-service boundary for subagent fan-out.
- The service derives installation and workflow ownership from the provided
  `WorkflowNode`.
- The service derives child depth from the optional parent run rather than
  trusting callers to hand-roll nested depth.
- The service does not create a second orchestration record. Fan-out remains
  expressed as more workflow-owned runtime rows under the same workflow graph.

## Execution Leases

- `ExecutionLease` is the explicit lease row for one workflow-bound runtime
  resource.
- Every lease belongs to one installation, workflow run, and workflow node.
- Every lease also points to one supported polymorphic runtime resource:
  - `ProcessRun`
  - `SubagentRun`
- Active leases track:
  - `holder_key`
  - `heartbeat_timeout_seconds`
  - `acquired_at`
  - `last_heartbeat_at`
- Released leases additionally track:
  - `released_at`
  - `release_reason`

## Lease Uniqueness And Freshness

- At most one active lease may exist for a given leased resource.
- The model enforces this in two places:
  - a custom validation for readable model-level failures
  - a partial unique index on active leases for database enforcement
- A lease is considered stale when it is still active and
  `last_heartbeat_at` is older than `heartbeat_timeout_seconds`.
- Staleness is a runtime-ownership rule, not a separate lifecycle enum.

## Lease Services

- `Leases::Acquire` is the lease-acquisition boundary.
- Acquire creates a new active lease for a supported runtime resource.
- If the resource already has an active lease and that lease is stale, acquire
  expires the stale row with `release_reason = heartbeat_timeout` before
  granting the replacement lease.
- If the resource already has a fresh active lease, acquire rejects the new
  claim.
- `Leases::Heartbeat` is the heartbeat boundary.
- Heartbeat only succeeds for the current holder of an active lease.
- If the lease is already stale when a heartbeat arrives, the service records
  `release_reason = heartbeat_timeout` and raises a stale-lease error instead
  of silently reviving ownership.
- `Leases::Release` is the explicit release boundary.
- Release only succeeds for the current holder of an active lease and records
  the caller-provided release reason.

## Failure Modes

- subagent runs reject workflow-run or installation drift
- child subagent runs reject parentage that crosses workflow runs
- subagent runs reject non-hash metadata
- active leases reject unsupported leased-resource types
- active leases reject workflow drift away from the leased resource
- active leases reject zero or negative heartbeat timeouts
- release metadata must be paired: `released_at` and `release_reason`
- lease acquire rejects a fresh competing active lease
- heartbeat and release reject holder mismatch
- stale heartbeat does not silently restore a timed-out lease

## Rails Findings

- Local Rails validation guidance mattered here again: model-level uniqueness
  validation is not enough on its own, so active-lease exclusivity is enforced
  with both a partial unique index and a readable model validation.
- No external reference implementation was treated as authoritative for this
  task; the landed contract is defined by the local design, tests, and
  behavior doc.
