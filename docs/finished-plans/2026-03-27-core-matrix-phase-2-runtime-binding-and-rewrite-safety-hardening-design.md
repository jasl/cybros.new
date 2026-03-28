# Core Matrix Phase 2 Design: Runtime Binding And Rewrite Safety Hardening

Use this design document before starting the Milestone C follow-up batch that
repairs runtime binding drift, turn-entry deployment trust, rewrite safety, and
wait-state blocker identifier consistency.

Read together with:

1. `AGENTS.md`
2. `docs/plans/README.md`
3. `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
4. `docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md`
5. `docs/plans/2026-03-26-core-matrix-phase-2-task-execution-environment-runtime-boundary-follow-up.md`
6. `docs/plans/2026-03-26-core-matrix-phase-2-execution-environment-and-agent-runtime-boundary-design.md`
7. `docs/plans/2026-03-26-core-matrix-phase-2-plan-execution-environment-runtime-boundary.md`
8. `docs/plans/2026-03-27-core-matrix-phase-2-close-operation-reconciliation-design.md`
9. `docs/plans/2026-03-27-core-matrix-phase-2-plan-close-operation-reconciliation.md`

## Purpose

Milestone C and its later follow-ups established explicit runtime pairing,
conversation close fencing, and environment ownership, but the current code
still leaves three related integrity gaps:

- paused workflow retry can start new work on a deployment outside the
  conversation's bound execution environment
- new-turn and turn-history rewrite helpers do not all share one reusable
  safety rule for deployment binding and close-fence state
- `WorkflowRun#blocking_resource_id` still mixes raw internal ids and durable
  external identifiers

This design treats those gaps as one hardening batch, not as unrelated cleanup.
The same runtime-control architecture should govern current and future entry,
retry, and rewrite paths.

## Problem Statement

The current implementation spreads safety checks across multiple entry points:

- `Conversations::SwitchAgentDeployment`
- `Workflows::ManualResume`
- `Workflows::ManualRetry`
- `Turns::StartUserTurn`
- `Turns::QueueFollowUp`
- `Turns::RetryOutput`
- `Turns::RerunOutput`

That split creates three classes of risk:

1. different runtime paths can apply different deployment-binding rules
2. future turn-entry or rewrite helpers can bypass the intended close and
   retention fences by forgetting to duplicate existing checks
3. generic wait-state logic cannot safely assume what kind of identifier
   `blocking_resource_id` contains

That is not the Milestone C architecture we want. Runtime binding and rewrite
safety should be explicit shared contracts that future work extends instead of
re-deriving locally.

## Decisions

### 1. Conversation Binding Is The Single Source Of Truth For New Turn Deployment

New turn-entry services must not trust an arbitrary caller-supplied deployment
as the durable execution target.

The conversation's bound deployment is the source of truth for:

- `Turns::StartUserTurn`
- `Turns::QueueFollowUp`
- `Turns::StartAutomationTurn`
- future same-conversation turn-entry helpers

If a flow needs a different deployment, it must explicitly rebind the
conversation first through the shared deployment-target contract.

### 2. Deployment Rebinding Uses One Shared Validator

Phase 2 should add one explicit application service:

- `Conversations::ValidateAgentDeploymentTarget`

That validator owns shared checks for:

- same installation
- same bound execution environment
- optional same logical agent continuity
- optional capability contract continuity

`Conversations::SwitchAgentDeployment`, `Workflows::ManualResume`,
`Workflows::ManualRetry`, and rotated auto-resume rebinding should all use that
service rather than carrying slightly different hand-written validation logic.

### 3. Deployment Rebinding Stays Explicit

This follow-up should not hide deployment rebinding inside model callbacks or
inside the turn-entry helpers.

The explicit runtime contract is:

1. validate candidate deployment against the conversation
2. if the flow truly wants to move execution, rebind the conversation through
   `Conversations::SwitchAgentDeployment`
3. only then create a new turn or workflow that inherits that bound deployment

That keeps pairing, recovery, and audit behavior readable and transport-neutral.

### 4. `Turn` Gets A Backstop Environment Invariant

Service-level validation is the primary defense, but `Turn` should still reject
obviously invalid runtime binding at persistence time.

`Turn` must therefore validate:

- `turn.agent_deployment.execution_environment_id ==
  turn.conversation.execution_environment_id`

This is a backstop invariant, not the primary orchestration layer.

### 5. Turn-History Rewrite Uses One Shared Safety Guard

Phase 2 should add one explicit service:

- `Turns::ValidateRewriteTarget`

That service owns the shared rewrite preconditions for:

- `Turns::RetryOutput`
- `Turns::RerunOutput`
- future rewrite helpers that can append transcript state onto an existing turn

The guard must enforce:

- conversation retained
- conversation active
- no unfinished close operation
- turn not fenced by `turn_interrupted`

Existing output-selection, tail, and fork-point checks stay in the rewrite
services, but the lifecycle and fence rules become shared.

### 6. `blocking_resource_id` Stores Durable External-Style Identifiers Only

`WorkflowRun#blocking_resource_id` should have one durable semantic contract:

- if a blocker is represented by a durable resource identifier, store that
  resource's `public_id`

The agent-unavailable path must therefore stop storing `AgentDeployment.id.to_s`
and use `AgentDeployment.public_id` instead.

Phase 2 should not preserve mixed bigint versus `public_id` semantics here.

### 7. Future Entry And Rewrite Paths Must Join The Shared Guards

Any future path that does one of the following:

- rebinds a conversation to a deployment
- starts a new turn in an existing conversation
- rewrites a turn that can append transcript artifacts

must explicitly join the corresponding shared service:

- deployment target validation
- conversation-bound turn-entry rules
- rewrite-target validation

No future path should reintroduce ad hoc copies of those checks.

## Current Implementation Adjustments

This follow-up is expected to remove or collapse the following duplicated logic.

### `Conversations::SwitchAgentDeployment`

Current issue:

- it has its own direct environment check instead of sharing the same validator
  used by recovery paths

Required adjustment:

- delegate target validation to the shared deployment validator
- remain the explicit writer that mutates `conversation.agent_deployment`

### `Workflows::ManualResume`

Current issue:

- it validates a replacement deployment inline and partially duplicates
  conversation-binding rules

Required adjustment:

- reuse the shared deployment validator for common checks
- keep its extra continuity checks explicit

### `Workflows::ManualRetry`

Current issue:

- it validates only installation and scheduling eligibility
- it can create a new turn on a deployment outside the conversation's bound
  execution environment

Required adjustment:

- validate the replacement deployment through the shared deployment contract
- explicitly rebind the conversation before creating the retried turn
- make the new turn inherit the conversation-bound deployment

### `AgentDeployments::AutoResumeWorkflows`

Current issue:

- rotated auto-resume rebinding can still target a replacement deployment
  without explicitly reusing the shared deployment-target contract

Required adjustment:

- validate rotated replacements through the shared deployment-target contract
- explicitly rebind `conversation.agent_deployment` before rewriting the turn
  runtime identity
- degrade to manual recovery instead of silently drifting across execution
  environments

### `Turns::StartUserTurn`, `Turns::QueueFollowUp`, And `Turns::StartAutomationTurn`

Current issue:

- they currently accept a deployment parameter and trust it directly

Required adjustment:

- derive the effective deployment from the conversation binding
- reject invalid persistence through the new `Turn` backstop invariant

### `Turns::RetryOutput` And `Turns::RerunOutput`

Current issue:

- they can move a turn back to `active` or create branch replay work without a
  shared lifecycle and fence guard

Required adjustment:

- call the shared rewrite-target validator before mutating transcript state
- keep their output-variant and tail logic separate from the shared lifecycle
  guard

### `AgentDeployments::UnavailablePauseState`

Current issue:

- it still writes an internal deployment id into `blocking_resource_id`

Required adjustment:

- store `deployment.public_id`
- keep snapshot and resume behavior coherent with that external-style contract

## Target Runtime Flow

The desired runtime-binding and rewrite flow is:

1. any replacement deployment is validated through one shared validator
2. any conversation rebind happens explicitly through
   `Conversations::SwitchAgentDeployment`
3. new turn-entry helpers inherit `conversation.agent_deployment` rather than
   trusting an arbitrary argument
4. `Turn` rejects cross-environment persistence if a caller still bypasses the
   shared service rules
5. rewrite helpers re-enter a shared lifecycle and fence validator before they
   append new transcript state
6. wait-state blockers carry one durable identifier semantic across all writer
   paths
7. future turn-entry, retry, or rewrite helpers extend the same shared rules
   instead of recreating them ad hoc

## Acceptance Criteria

This follow-up is complete only when all of the following are true:

- `ManualRetry` cannot create a new turn on a deployment outside the
  conversation's bound execution environment
- the successful `ManualRetry` path leaves:
  - `conversation.agent_deployment`
  - `turn.agent_deployment`
  - `execution_identity["agent_deployment_id"]`
  - `execution_identity["execution_environment_id"]`
  in one coherent runtime binding
- `SwitchAgentDeployment`, `ManualResume`, and `ManualRetry` all converge on
  one shared deployment-target validator
- `StartUserTurn` and `QueueFollowUp` no longer trust arbitrary external
  deployment input as the durable source of truth
- `Turn` rejects cross-environment deployment binding at persistence time
- `RetryOutput` and `RerunOutput` reject archived, pending-delete, closing, and
  interrupted targets through one shared validator
- `WorkflowRun#blocking_resource_id` no longer mixes bigint deployment ids with
  `public_id` identifiers
- docs explicitly state that future turn-entry and rewrite paths must reuse the
  shared safety contracts

## Task Relationship Model

The implementation work for this design is intentionally ordered:

1. establish the shared deployment-target validator and its tests
2. route recovery and conversation rebinding paths through it
3. collapse turn-entry onto the conversation-bound deployment and add the model
   backstop invariant
4. establish the shared rewrite-target validator and route rewrite helpers
   through it
5. normalize `blocking_resource_id`, update docs, and run exhaustiveness checks

That order ensures the shared rules exist before call sites are migrated and
before documentation claims future reuse requirements.

## Documentation Integrity Check

This design document was checked for completeness on `2026-03-27`.

- the follow-up goal is explicit
- the shared-rule architecture is explicit
- the current implementations that must change are named directly
- future extension requirements are explicit
- acceptance criteria are specific enough to verify without chat-only context
- task relationships are linear and automation-safe
