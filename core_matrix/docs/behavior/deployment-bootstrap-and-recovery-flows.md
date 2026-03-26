# Deployment Bootstrap And Recovery Flows

## Purpose

Task 11.4 adds the first explicit deployment bootstrap and runtime-recovery
control surface to Core Matrix. The kernel now records system-owned bootstrap
work as durable workflow state, moves paused work through structured outage
states, supports bounded auto-resume, and requires explicit manual decisions
after runtime drift.

## Status

This document describes the current landed deployment-bootstrap and recovery
behavior.

Phase 2 keeps these recovery concepts and now runs them alongside mailbox
delivery, session presence, and durable close semantics. This document remains
the source of truth for bootstrap and recovery behavior, while the mailbox
transport and close contract live in:

Planned replacement design:

- [2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)

## Deployment Bootstrap

- `AgentDeployments::Bootstrap` materializes bootstrap as a normal automation
  conversation, turn, and workflow run instead of a hidden row update.
- bootstrap uses `Turn.origin_kind = "system_internal"` so deployment-scoped
  bootstrap work is distinguishable from schedule- or webhook-driven
  automation turns
- bootstrap turns use:
  - `source_ref_type = "AgentDeployment"`
  - `source_ref_id = <deployment public_id>`
- bootstrap creates one root workflow node:
  - `node_key = "deployment_bootstrap"`
  - `node_type = "deployment_bootstrap"`
  - `decision_source = "system"`
- the bootstrap manifest snapshot is frozen on both:
  - the turn origin payload
  - the root workflow-node metadata
- bootstrap records the audit action
  `agent_deployment.bootstrap_started`

## Deployment Rotation

- release change is modeled as deployment rotation, not in-place mutation
- a replacement `AgentDeployment` registers as `pending`
- the first healthy heartbeat on that pending deployment:
  - promotes it to `bootstrap_state = "active"`
  - supersedes any previously active deployment for the same logical
    `AgentInstallation`
- upgrade and downgrade follow the same kernel-facing rule
- the superseded deployment may still be referenced by paused turns or old
  audits, but it is no longer eligible for new scheduling
- Core Matrix does not need to dial the runtime back during cutover; the
  runtime pairs outbound and the kernel routes future work to the active
  deployment row

## Outage Wait-State Model

- `AgentDeployments::MarkUnavailable` is the control-plane service that moves
  active work into a deployment-scoped wait state.
- affected workflows are discovered by the deployment referenced on the pinned
  turn, not by a parallel pause ledger.
- transient outage behavior:
  - deployment moves to `health_status = "degraded"`
  - active workflows move to `wait_state = "waiting"`
  - `wait_reason_kind = "agent_unavailable"`
  - `wait_reason_payload["recovery_state"] = "transient_outage"`
  - `blocking_resource_type = "AgentDeployment"`
  - `blocking_resource_id = <deployment id>`
  - audit action `agent_deployment.degraded`
- prolonged outage behavior:
  - deployment moves to `health_status = "offline"`
  - `auto_resume_eligible = false`
  - active workflows remain `waiting` but move to
    `wait_reason_kind = "manual_recovery_required"`
  - `wait_reason_payload["recovery_state"] = "paused_agent_unavailable"`
  - audit action `agent_deployment.paused_agent_unavailable`
- the wait payload freezes the deployment fingerprint and capability version
  that were pinned when the workflow last ran safely
- if a workflow was already waiting on another blocker such as
  `human_interaction`, `retryable_failure`, or `policy_gate`, outage pause
  snapshots that original wait contract inside the pause payload instead of
  discarding it
- recovery restores the snapped blocker when it is still unresolved, and only
  clears to `ready` when the snapped blocker has already been satisfied while
  the workflow was paused

## Auto Resume

- `AgentDeployments::AutoResumeWorkflows` only considers workflows already
  waiting on `agent_unavailable`
- waiting workflows are discovered by logical agent identity, not only by the
  currently active deployment row
- automatic resume is allowed only when all of these remain true:
  - deployment is healthy
  - deployment is still eligible for scheduling
  - deployment is marked `auto_resume_eligible`
  - one of these recovery paths applies:
    - pinned deployment fingerprint still matches the current deployment
      fingerprint and the pinned capability snapshot version still matches the
      current active capability snapshot version
    - a rotated deployment from the same logical `AgentInstallation` preserves
      the paused capability contract and the frozen selector still resolves on
      the replacement deployment
- successful auto-resume preserves the existing turn and workflow-run IDs
- if outage pause wrapped an older blocker, successful auto-resume restores
  that blocker instead of forcing the workflow to `ready`
- when the auto-resume target is a rotated replacement deployment, the kernel:
  - re-pins the turn to the replacement deployment
  - refreshes the frozen capability snapshot binding
  - re-assembles the execution context so execution identity now references the
    replacement deployment public id
- if the deployment comes back healthy but runtime identity drifted, the kernel
  does not continue silently; it escalates the workflow to
  `manual_recovery_required` with
  `wait_reason_payload["recovery_state"] = "paused_agent_unavailable"`
- if rotation preserves logical agent identity but no longer preserves the
  capability contract, auto-resume is denied and explicit recovery is required

## Manual Recovery

### Manual Resume

- `Workflows::ManualResume` resumes the existing paused workflow path in place.
- manual resume is allowed only when:
  - the workflow is already paused in `paused_agent_unavailable`
  - the chosen deployment belongs to the same installation
  - the chosen deployment is eligible for scheduling
  - the chosen deployment belongs to the same logical `AgentInstallation`
  - the chosen deployment still preserves the paused workflow capability
    contract
  - the frozen selector, or a one-time replacement selector, can still resolve
    safely
- successful manual resume:
  - re-pins the turn to the chosen deployment
  - refreshes the frozen model-selection snapshot
  - re-assembles the execution context so the execution identity carries the
    new deployment ID
  - clears the workflow wait state only when no snapped blocker remains
  - otherwise restores the snapped blocker in place
  - records audit action `workflow.manual_resumed`

### Manual Retry

- `Workflows::ManualRetry` abandons the paused execution path and starts a new
  workflow from the last stable selected input.
- manual retry:
  - requires a paused `paused_agent_unavailable` workflow
  - requires a selected input message to replay
  - requires the chosen deployment to be eligible for scheduling
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
  - deployment default config snapshots
  - deployment model-slot configuration
- audit metadata records the temporary override when one was supplied.

## Audit Scope

- deployment bootstrap writes one audit row against the deployment subject
- transient degradation writes one deployment audit row with the affected
  workflow IDs
- paused-agent-unavailable transitions write one deployment audit row with the
  affected workflow IDs and any drift reason
- manual resume and manual retry write actor-attributed audit rows against the
  resumed or retried workflow subject

## Failure Modes

- bootstrap is rejected when the workspace does not belong to the same
  installation as the deployment
- manual resume rejects logical-agent mismatch rather than silently continuing
  on an unrelated runtime
- manual resume rejects replacement deployments that no longer preserve the
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
