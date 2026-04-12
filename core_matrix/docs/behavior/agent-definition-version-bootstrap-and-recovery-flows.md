# Agent Definition Version Bootstrap And Recovery Flows

## Purpose

Task 11.4 adds the first explicit agent-definition-version bootstrap and
runtime-recovery control surface to Core Matrix. The kernel now records
system-owned bootstrap work as durable workflow state, moves paused work
through structured outage states, supports bounded auto-resume, and requires
explicit manual decisions after runtime drift.

## Status

This document describes the current landed agent-definition-version bootstrap
and recovery behavior.

This document is the source of truth for bootstrap and recovery behavior.
Mailbox delivery, session presence, and durable close semantics run alongside
these recovery flows.

Related design note:

- [2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)

## Agent Definition Version Bootstrap

- `AgentDefinitionVersions::Bootstrap` materializes bootstrap as a normal automation
  conversation, turn, and workflow run instead of a hidden row update.
- bootstrap uses `Turn.origin_kind = "system_internal"` so
  agent-definition-version-scoped bootstrap work is distinguishable from
  schedule- or webhook-driven
  automation turns
- bootstrap turns use:
  - `source_ref_type = "AgentDefinitionVersion"`
  - `source_ref_id = <agent definition version public_id>`
- bootstrap creates one root workflow node:
  - `node_key = "agent_definition_version_bootstrap"`
  - `node_type = "agent_definition_version_bootstrap"`
  - `decision_source = "system"`
- the bootstrap manifest snapshot is frozen on both:
  - the turn origin payload
  - the root workflow-node metadata
- bootstrap records the audit action
  `agent_definition_version.bootstrap_started`

## Agent Definition Version Rotation

- release change is modeled as agent definition version rotation, not in-place mutation
- a replacement `AgentDefinitionVersion` registers as `pending`
- the first healthy heartbeat on that pending agent definition version:
  - promotes it to `bootstrap_state = "active"`
  - supersedes any previously active agent definition version for the same logical
    `Agent`
- upgrade and downgrade follow the same kernel-facing rule
- the superseded agent definition version may still be referenced by paused turns or old
  audits, but it is no longer eligible for new scheduling
- Core Matrix does not need to dial the runtime back during cutover; the
  runtime pairs outbound and the kernel routes future work to the active
  agent definition version row

## Outage Wait-State Model

- `AgentDefinitionVersions::MarkUnavailable` is the control-plane service that moves
  active work into an agent-definition-version-scoped wait state.
- affected workflows are discovered by the agent definition version referenced on the pinned
  turn, not by a parallel pause ledger.
- transient outage behavior:
  - agent definition version moves to `health_status = "degraded"`
  - active workflows move to `wait_state = "waiting"`
  - `wait_reason_kind = "agent_unavailable"`
  - `wait_reason_payload["recovery_state"] = "transient_outage"`
  - `blocking_resource_type = "AgentDefinitionVersion"`
  - `blocking_resource_id = <agent definition version public_id>`
  - audit action `agent_definition_version.degraded`
- prolonged outage behavior:
  - agent definition version moves to `health_status = "offline"`
  - `auto_resume_eligible = false`
  - active workflows remain `waiting` but move to
    `wait_reason_kind = "manual_recovery_required"`
  - `wait_reason_payload["recovery_state"] = "paused_agent_unavailable"`
  - audit action `agent_definition_version.paused_agent_unavailable`
- the wait payload freezes the agent definition version fingerprint and capability version
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

- `AgentDefinitionVersions::AutoResumeWorkflows` only considers workflows already
  waiting on `agent_unavailable`
- waiting workflows are discovered by logical agent identity, not only by the
  currently active agent definition version row
- automatic resume is allowed only when all of these remain true:
  - agent definition version is healthy
  - agent definition version is still eligible for scheduling
  - agent definition version is marked `auto_resume_eligible`
  - one of these recovery paths applies:
    - pinned agent definition version fingerprint still matches the current
      agent definition version fingerprint and runtime identity still matches
    - a rotated agent definition version from the same logical `Agent` preserves
      the paused capability contract and the frozen selector still resolves on
      the replacement agent definition version
- successful auto-resume preserves the existing turn and workflow-run IDs
- if outage pause wrapped an older blocker, successful auto-resume restores
  that blocker instead of forcing the workflow to `ready`
- `ExecutionIdentityRecovery::BuildPlan` now owns drift classification and
  recovery planning and returns one explicit action:
  - `resume`
  - `resume_with_rebind`
  - `manual_recovery_required`
- `ExecutionIdentityRecovery::ResolveTarget` is the one paused-work
  target-resolution contract for:
  - scheduling and auto-resume eligibility checks
  - same-installation and same execution-environment checks for paused work
  - same logical-agent enforcement for paused resumptions
  - paused capability-contract compatibility
  - selector re-resolution on the candidate agent definition version
- `ExecutionIdentityRecovery::ApplyPlan` is now a thin orchestrator over the
  planned recovery target and restored wait-state writes
- `ExecutionIdentityRecovery::RebindTurn` is the one paused-turn mutation owner for:
  - rewriting `turn.agent_definition_version`
  - rewriting `turn.pinned_agent_definition_fingerprint`
  - replacing the frozen model-selection snapshot
  - rebuilding the turn execution snapshot
- when the auto-resume target is a rotated replacement agent definition version, the kernel:
  - re-pins the turn to the replacement agent definition version
  - refreshes the frozen agent-definition-version binding
  - re-assembles the execution context so execution identity now references the
    replacement agent definition version public id
- if the agent definition version comes back healthy but runtime identity drifted, the kernel
  does not continue silently; it escalates the workflow to
  `manual_recovery_required` with
  `wait_reason_payload["recovery_state"] = "paused_agent_unavailable"`
- if rotation preserves logical agent identity but no longer preserves the
  capability contract, auto-resume is denied and explicit recovery is required

## Manual Recovery

### Manual Resume

- `Workflows::ManualResume` resumes the existing paused workflow path in place.
- manual resume reuses `ExecutionIdentityRecovery::ResolveTarget` and
  `ExecutionIdentityRecovery::RebindTurn`; it does not keep a second paused-work
  compatibility or rebinding path
- manual resume is allowed only when:
  - the workflow is already paused in `paused_agent_unavailable`
  - the chosen agent definition version belongs to the same installation
  - the chosen agent definition version is eligible for scheduling
  - the chosen agent definition version belongs to the same logical `Agent`
  - the chosen agent definition version still preserves the paused workflow capability
    contract
  - the frozen selector, or a one-time replacement selector, can still resolve
    safely
- successful manual resume:
  - re-pins the turn to the chosen agent definition version
  - refreshes the frozen model-selection snapshot
  - re-assembles the execution context so the execution identity carries the
    new agent definition version ID
  - clears the workflow wait state only when no snapped blocker remains
  - otherwise restores the snapped blocker in place
  - records audit action `workflow.manual_resumed`

### Manual Retry

- `Workflows::ManualRetry` abandons the paused execution path and starts a new
  workflow from the last stable selected input.
- manual retry reuses `ExecutionIdentityRecovery::ResolveTarget` for
  paused-work target validation, but it does not call `RebindTurn` because it
  starts a fresh turn instead of mutating the paused one
- manual retry:
  - requires a paused `paused_agent_unavailable` workflow
  - requires a selected input message to replay
  - requires the chosen agent definition version to be eligible for scheduling
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
  - agent definition version default config snapshots
  - agent definition version model-slot configuration
- audit metadata records the temporary override when one was supplied.

## Audit Scope

- agent definition version bootstrap writes one audit row against the agent definition version subject
- transient degradation writes one audit row against the affected agent
  definition version with the workflow IDs
- paused-agent-unavailable transitions write one audit row against the affected
  agent definition version with the workflow IDs and any drift reason
- manual resume and manual retry write actor-attributed audit rows against the
  resumed or retried workflow subject

## Failure Modes

- bootstrap is rejected when the workspace does not belong to the same
  installation as the agent definition version
- live conversation agent-definition-version switching keeps its own
  installation and execution-environment validation path and does not carry
  paused-work logical-agent or capability-contract continuity checks
- manual resume rejects logical-agent mismatch rather than silently continuing
  on an unrelated runtime
- manual resume rejects replacement agent definition versions that no longer preserve the
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
