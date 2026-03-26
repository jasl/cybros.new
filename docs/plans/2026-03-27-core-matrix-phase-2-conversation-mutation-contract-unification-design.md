# Core Matrix Phase 2 Design: Conversation Mutation Contract Unification

Use this design document before starting the Milestone C follow-up batch that
removes legacy retained-state helpers and unifies all live conversation
mutation guards behind one explicit contract family.

Read together with:

1. `AGENTS.md`
2. `docs/plans/README.md`
3. `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
4. `docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md`
5. `docs/plans/2026-03-27-core-matrix-phase-2-close-operation-reconciliation-design.md`
6. `docs/plans/2026-03-27-core-matrix-phase-2-plan-close-operation-reconciliation.md`
7. `docs/plans/2026-03-27-core-matrix-phase-2-runtime-binding-and-rewrite-safety-hardening-design.md`
8. `docs/plans/2026-03-27-core-matrix-phase-2-plan-runtime-binding-and-rewrite-safety-hardening.md`
9. `core_matrix/docs/plans/2026-03-26-core-matrix-review-audit-findings.md`

## Purpose

Milestone C now has explicit runtime pairing, close fencing, deployment
binding, and partial rewrite safety, but the latest audit refresh showed that
conversation-local mutation rules are still split across three incompatible
styles:

- direct writes with no shared lifecycle contract
- ad hoc `retained + active` checks written inline
- legacy `Conversations::RetentionGuard` calls that only protect
  `pending_delete` or `deleted`

That split already produced real defects in:

- `Turns::SteerCurrentInput`
- `Turns::EditTailInput`
- `Turns::SelectOutputVariant`
- `Conversations::RollbackToTurn`
- `Conversations::UpdateOverride`

and it leaves several adjacent mutation paths one future refactor away from the
same drift.

This follow-up treats the problem as one architectural cleanup:

- remove the old retained-state helper entirely
- replace it with explicit shared mutation contracts
- migrate every current conversation-local mutation entry point onto one of
  those contracts
- keep scanning until no adjacent mutation service remains outside the chosen
  family

## Audit Refresh Outcome

The refreshed scan covered:

- turn timeline writers
- transcript support writers
- projection overlay writers
- lineage creation writers
- selector and override writers
- conversation-local variable writers
- manual recovery entry points
- lifecycle-root services for contrast

Confirmed defects from that sweep were:

1. `Turns::SteerCurrentInput` can mutate a still-`active` turn after
   `turn_interrupted`
2. `Turns::EditTailInput`, `Turns::SelectOutputVariant`, and
   `Conversations::RollbackToTurn` bypass the shared rewrite fence
3. `Conversations::UpdateOverride` can rewrite selector and override state
   after archive or delete fencing starts

The broader sweep did not find any additional same-class mutation service
outside the final scope below. It did find several legacy `RetentionGuard`
callers that are not all broken today, but still need migration so the codebase
uses one explicit style instead of two overlapping ones.

## Problem Statement

The current implementation makes mutation legality too easy to drift:

- live conversation mutations do not all share the same
  `retained + active + not_closing` contract
- turn timeline mutations do not all share the same
  `retained + active + not_closing + not turn_interrupted` contract
- `Conversations::RetentionGuard` hides two different semantics behind one
  module:
  - “conversation row must still exist in retained state”
  - “conversation must still be mutable as a live runtime surface”
- some services lock and re-check state under the right row lock, but sibling
  services touching the same logical surface do not

That is not a maintainable Phase 2 shape. Future services should choose from a
small explicit contract family instead of rebuilding their own lifecycle guard.

## Decisions

### 1. Remove `Conversations::RetentionGuard`

This batch should delete `app/services/conversations/retention_guard.rb`.

No compatibility layer should remain. Existing callers must migrate onto one of
the new explicit contracts described below.

### 2. Introduce A Conversation `retained-only` Contract

Add:

- `Conversations::ValidateRetainedState`
- `Conversations::WithRetainedStateLock`

This contract means:

- the conversation must still be `retained`
- the service must re-check that fact from fresh locked state before writing

Use this contract only for flows that need the conversation to still exist as a
durable provenance root, but do not require the conversation to remain a live
mutable runtime surface.

Expected users:

- `Conversations::Archive`
- `Conversations::RequestClose` for archive intent validation
- `Conversations::Unarchive`
- `Publications::PublishLive`

### 3. Introduce A Conversation `live-mutation` Contract

Add:

- `Conversations::ValidateMutableState`
- `Conversations::WithMutableStateLock`

This contract means:

- `deletion_state = retained`
- `lifecycle_state = active`
- `unfinished_close_operation` is absent
- the checks run from fresh locked state before mutation

This is the default contract for any caller-driven write that changes live
conversation-local runtime state, transcript support state, or settings.

Expected users:

- `Turns::StartUserTurn`
- `Turns::QueueFollowUp`
- `Turns::StartAutomationTurn`
- `Workflows::ManualResume`
- `Workflows::ManualRetry`
- `CanonicalStores::Set`
- `CanonicalStores::DeleteKey`
- `Variables::PromoteToWorkspace`
- `HumanInteractions::Request`
- `HumanInteractions::ResolveApproval`
- `HumanInteractions::SubmitForm`
- `HumanInteractions::CompleteTask`
- `Conversations::CreateBranch`
- `Conversations::CreateThread`
- `Conversations::CreateCheckpoint`
- `Conversations::AddImport`
- `ConversationSummaries::CreateSegment`
- `Messages::UpdateVisibility`
- `Conversations::UpdateOverride`

### 4. Introduce A Turn `timeline-mutation` Contract

Add:

- `Turns::ValidateTimelineMutationTarget`
- `Turns::WithTimelineMutationLock`

This contract means:

- the owning conversation passes the `live-mutation` contract
- the target turn is reloaded under lock
- the target turn is not fenced by
  `cancellation_reason_kind = "turn_interrupted"`

This contract becomes the default for any service that mutates selected
timeline pointers or reactivates historical turn state.

Expected users:

- `Turns::SteerCurrentInput`
- `Turns::EditTailInput`
- `Turns::SelectOutputVariant`
- `Turns::RetryOutput`
- `Turns::RerunOutput`
- `Conversations::RollbackToTurn`

`Turns::ValidateRewriteTarget` should be deleted after these migrations. The
new timeline contract replaces it.

### 5. Archived Or Closing Conversations Freeze Live Mutation

This batch intentionally tightens product behavior:

- archived conversations reject live conversation-local writes
- conversations with an unfinished close operation reject live
  conversation-local writes even if the row is still `active`

That rule now applies consistently across:

- turn entry
- manual recovery
- human-interaction writes
- conversation-local variable writes and promotion
- lineage creation
- transcript support writes
- selector and override writes
- turn timeline mutation

This is a breaking behavior change by design. The codebase should prefer one
clean mutation policy over partial backward compatibility.

### 6. Timeline Mutation Must Use One Lock Order

For turn-level mutation, the standard lock order is:

1. `conversation.with_lock`
2. `turn.with_lock`
3. re-run contract validation
4. run service-specific legality checks
5. persist the mutation

No service in this family should keep its own bespoke reload and locking order.

### 7. Conversation-Level Mutation Keeps Service-Specific Business Rules Local

The shared contracts own lifecycle legality only.

These service-specific rules stay local:

- tail and fork-point checks
- selected-output ownership checks
- branch-anchor rules
- summary-range ordering
- selector candidate validation
- manual recovery deployment compatibility
- human-interaction request shape validation

This keeps the shared contracts small and future-proof instead of turning them
into mode-switch god services.

### 8. `UpdateOverride` Joins The Same Family As Other Live Settings Writes

`Conversations::UpdateOverride` currently bypasses every lifecycle fence. This
batch makes it a first-class live mutation:

- it must lock the conversation
- it must pass `ValidateMutableState`
- archived, closing, or pending-delete conversations reject override changes

That keeps selector and override state aligned with the same live runtime
surface as turn entry and later model-resolution work.

### 9. Lifecycle Roots And Internal Projection Writers Stay Outside The Family

These services are intentionally excluded because they are lifecycle roots or
system-owned projection/infrastructure writers, not caller-driven live mutation
entry points:

- `Conversations::RequestClose`
- `Conversations::RequestDeletion`
- `Conversations::RequestTurnInterrupt`
- `Conversations::FinalizeDeletion`
- `Conversations::ReconcileCloseOperation`
- `Conversations::SwitchAgentDeployment`
- `Conversations::RefreshRuntimeContract`
- `Conversations::CreateRoot`
- `Conversations::CreateAutomationRoot`
- `CanonicalStores::BootstrapForConversation`
- `CanonicalStores::CompactSnapshot`
- `ConversationEvents::Project`
- purge planning and purge execution helpers

Those services may still use smaller retained checks where appropriate, but
they must not be forced through `ValidateMutableState`.

## Migration Map

### Replace The Legacy Helper

- delete `Conversations::RetentionGuard`
- migrate every remaining include-site to:
  - `ValidateRetainedState`
  - `WithRetainedStateLock`
  - `ValidateMutableState`
  - `WithMutableStateLock`
  - `ValidateTimelineMutationTarget`
  - `WithTimelineMutationLock`

### Retained-Only Callers

- `Conversations::Archive`
- `Conversations::RequestClose`
- `Conversations::Unarchive`
- `Publications::PublishLive`

### Live-Mutation Callers

- all turn-entry services
- all human-interaction write services
- manual recovery services
- canonical-store set and delete
- variable promotion
- lineage creation
- transcript support and visibility mutation
- selector and override mutation

### Timeline-Mutation Callers

- steer current input
- edit tail input
- select output variant
- retry output
- rerun output
- rollback to turn

## Documentation And Verification Requirements

This batch must update behavior docs, not just code.

At minimum:

- `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- `core_matrix/docs/behavior/turn-rewrite-and-variant-operations.md`
- `core_matrix/docs/behavior/transcript-visibility-and-attachments.md`
- `core_matrix/docs/behavior/transcript-imports-and-summary-segments.md`
- `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- `core_matrix/docs/plans/2026-03-26-core-matrix-review-audit-findings.md`

Verification must include:

- targeted unit and integration tests for every migrated family
- neighbor regression for close, archive, delete, and interrupt flows
- final grep audit proving no service still references:
  - `Conversations::RetentionGuard`
  - `Turns::ValidateRewriteTarget`
- final grep audit proving every live mutation and timeline mutation entry
  point now uses the new shared contracts

## Resulting Invariant

After this batch lands, the codebase should have one explicit answer to
“what contract does this mutation require?”:

- retained-only
- live conversation mutation
- turn timeline mutation

No caller-driven conversation mutation should rely on ad hoc lifecycle checks,
and no future service should reintroduce the deleted legacy helper.
