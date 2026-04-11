# Agent Snapshot Bootstrap And Recovery Flows

## Purpose

Task 11.4 adds the first explicit agent snapshot bootstrap and runtime-recovery
control surface to Core Matrix. The kernel now records system-owned bootstrap
work as durable workflow state, moves paused work through structured outage
states, supports bounded auto-resume, and requires explicit manual decisions
after runtime drift.

## Status

This document describes the current landed agent snapshot bootstrap and recovery
behavior.

This document is the source of truth for bootstrap and recovery behavior.
Mailbox delivery, session presence, and durable close semantics run alongside
these recovery flows.

Related design note:

- [2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)

## Agent Snapshot Bootstrap

- `AgentSnapshots::Bootstrap` materializes bootstrap as a normal automation
  conversation, turn, and workflow run instead of a hidden row update.
- bootstrap uses `Turn.origin_kind = "system_internal"` so agent-snapshot-scoped
  bootstrap work is distinguishable from schedule- or webhook-driven
  automation turns
- bootstrap turns use:
  - `source_ref_type = "AgentSnapshot"`
  - `source_ref_id = <agent snapshot public_id>`
- bootstrap creates one root workflow node:
  - `node_key = "agent_snapshot_bootstrap"`
  - `node_type = "agent_snapshot_bootstrap"`
  - `decision_source = "system"`
- the bootstrap manifest snapshot is frozen on both:
  - the turn origin payload
  - the root workflow-node metadata
- bootstrap records the audit action
  `agent_snapshot.bootstrap_started`

## Agent Snapshot Rotation

- release change is modeled as agent snapshot rotation, not in-place mutation
- a replacement `AgentSnapshot` registers as `pending`
- the first healthy heartbeat on that pending agent snapshot:
  - promotes it to `bootstrap_state = "active"`
  - supersedes any previously active agent snapshot for the same logical
    `Agent`
- upgrade and downgrade follow the same kernel-facing rule
- the superseded agent snapshot may still be referenced by paused turns or old
  audits, but it is no longer eligible for new scheduling
- Core Matrix does not need to dial the runtime back during cutover; the
  runtime pairs outbound and the kernel routes future work to the active
  agent snapshot row

## Outage Wait-State Model

- `AgentSnapshots::MarkUnavailable` is the control-plane service that moves
  active work into an agent-snapshot-scoped wait state.
- affected workflows are discovered by the agent snapshot referenced on the pinned
  turn, not by a parallel pause ledger.
- transient outage behavior:
  - agent snapshot moves to `health_status = "degraded"`
  - active workflows move to `wait_state = "waiting"`
  - `wait_reason_kind = "agent_unavailable"`
  - `wait_reason_payload["recovery_state"] = "transient_outage"`
  - `blocking_resource_type = "AgentSnapshot"`
  - `blocking_resource_id = <agent snapshot public_id>`
  - audit action `agent_snapshot.degraded`
- prolonged outage behavior:
  - agent snapshot moves to `health_status = "offline"`
  - `auto_resume_eligible = false`
  - active workflows remain `waiting` but move to
    `wait_reason_kind = "manual_recovery_required"`
  - `wait_reason_payload["recovery_state"] = "paused_agent_unavailable"`
  - audit action `agent_snapshot.paused_agent_unavailable`
- the wait payload freezes the agent snapshot fingerprint and capability version
  that were pinned when the workflow last ran safely
- if a workflow was already waiting on another blocker such as
  `human_interaction`, `retryable_failure`, or `policy_gate`, outage pause
  snapshots that original wait contract inside the pause payload instead of
  discarding it
- `WorkflowWaitSnapshot` is the explicit contract object for that nested pause
  payload and owns both restore attributes and blocker-resolution checks
- recovery restores the snapped blocker when it is still unresolved, and only
  clears to `ready` when the snapped blocker has already been satisfied while
  the workflow was paused

## Auto Resume

- `AgentSnapshots::AutoResumeWorkflows` only considers workflows already
  waiting on `agent_unavailable`
- waiting workflows are discovered by logical agent identity, not only by the
  currently active agent snapshot row
- automatic resume is allowed only when all of these remain true:
  - agent snapshot is healthy
  - agent snapshot is still eligible for scheduling
  - agent snapshot is marked `auto_resume_eligible`
  - one of these recovery paths applies:
    - pinned agent snapshot fingerprint still matches the current agent snapshot
      fingerprint and the pinned capability snapshot version still matches the
      current active capability snapshot version
    - a rotated agent snapshot from the same logical `Agent` preserves
      the paused capability contract and the frozen selector still resolves on
      the replacement agent snapshot
- successful auto-resume preserves the existing turn and workflow-run IDs
- if outage pause wrapped an older blocker, successful auto-resume restores
  that blocker instead of forcing the workflow to `ready`
- `AgentSnapshots::BuildRecoveryPlan` now owns drift classification and
  recovery planning and returns one explicit action:
  - `resume`
  - `resume_with_rebind`
  - `manual_recovery_required`
- `AgentSnapshots::ResolveRecoveryTarget` is the one paused-work
  target-resolution contract for:
  - scheduling and auto-resume eligibility checks
  - same-installation and same execution-environment checks for paused work
  - same logical-agent enforcement for paused resumptions
  - paused capability-contract compatibility
  - selector re-resolution on the candidate agent snapshot
- `AgentSnapshots::ApplyRecoveryPlan` is now a thin orchestrator over the
  planned recovery target and restored wait-state writes
- `AgentSnapshots::RebindTurn` is the one paused-turn mutation owner for:
  - rewriting `turn.agent_snapshot`
  - rewriting `turn.pinned_agent_snapshot_fingerprint`
  - replacing the frozen model-selection snapshot
  - rebuilding the turn execution snapshot
- when the auto-resume target is a rotated replacement agent snapshot, the kernel:
  - re-pins the turn to the replacement agent snapshot
  - refreshes the frozen agent-snapshot binding
  - re-assembles the execution context so execution identity now references the
    replacement agent snapshot public id
- if the agent snapshot comes back healthy but runtime identity drifted, the kernel
  does not continue silently; it escalates the workflow to
  `manual_recovery_required` with
  `wait_reason_payload["recovery_state"] = "paused_agent_unavailable"`
- if rotation preserves logical agent identity but no longer preserves the
  capability contract, auto-resume is denied and explicit recovery is required

## Manual Recovery

### Manual Resume

- `Workflows::ManualResume` resumes the existing paused workflow path in place.
- manual resume reuses `AgentSnapshots::ResolveRecoveryTarget` and
  `AgentSnapshots::RebindTurn`; it does not keep a second paused-work
  compatibility or rebinding path
- manual resume is allowed only when:
  - the workflow is already paused in `paused_agent_unavailable`
  - the chosen agent snapshot belongs to the same installation
  - the chosen agent snapshot is eligible for scheduling
  - the chosen agent snapshot belongs to the same logical `Agent`
  - the chosen agent snapshot still preserves the paused workflow capability
    contract
  - the frozen selector, or a one-time replacement selector, can still resolve
    safely
- successful manual resume:
  - re-pins the turn to the chosen agent snapshot
  - refreshes the frozen model-selection snapshot
  - re-assembles the execution context so the execution identity carries the
    new agent snapshot ID
  - clears the workflow wait state only when no snapped blocker remains
  - otherwise restores the snapped blocker in place
  - records audit action `workflow.manual_resumed`

### Manual Retry

- `Workflows::ManualRetry` abandons the paused execution path and starts a new
  workflow from the last stable selected input.
- manual retry reuses `AgentSnapshots::ResolveRecoveryTarget` for
  paused-work target validation, but it does not call `RebindTurn` because it
  starts a fresh turn instead of mutating the paused one
- manual retry:
  - requires a paused `paused_agent_unavailable` workflow
  - requires a selected input message to replay
  - requires the chosen agent snapshot to be eligible for scheduling
- successful manual retry:
  - marks the paused workflow run `canceled`
  - marks the paused turn `canceled`
  - starts a fresh turn with the same selected input content
  - starts a fresh workflow run using the original root node contract
  - records audit action `workflow.manual_retried`

## Recovery-Time Selector Overrides

- `manual_resume` and `manual_retry` may accept a one-time selector override.
- the override is resolved through the normal selector pipeline with
  `selector_source = "manual_recovery"`.
- the override is frozen onto the resumed or retried turn snapshot only.
- the override does not mutate:
  - conversation interactive selector state
  - agent snapshot default config snapshots
  - agent snapshot model-slot configuration
- audit metadata records the temporary override when one was supplied.

## Audit Scope

- agent snapshot bootstrap writes one audit row against the agent snapshot subject
- transient degradation writes one audit row against the affected agent
  snapshot with the workflow IDs
- paused-agent-unavailable transitions write one audit row against the affected
  agent snapshot with the workflow IDs and any drift reason
- manual resume and manual retry write actor-attributed audit rows against the
  resumed or retried workflow subject

## Failure Modes

- bootstrap is rejected when the workspace does not belong to the same
  installation as the agent snapshot
- `Conversations::ValidateAgentSnapshotTarget` remains the generic live
  conversation agent snapshot switch validator and does not carry paused-work
  logical-agent or capability-contract continuity checks
- manual resume rejects logical-agent mismatch rather than silently continuing
  on an unrelated runtime
- manual resume rejects replacement agent snapshots that no longer preserve the
  pinned capability contract
- manual resume rejects selector drift when the frozen execution selector can no
  longer be resolved safely
- manual retry rejects paused workflows that have no stable selected input to
  replay

## Retained Implementation Notes

- no new pause table was introduced for this task; recovery composes the
  existing `WorkflowRun.wait_*` fields plus audit rows
- `Workflows::CreateForTurn` now accepts an explicit selector source and
  selector override so recovery-time retries can reuse the normal model
  resolution and context assembly path instead of forking a parallel creation
  flow
