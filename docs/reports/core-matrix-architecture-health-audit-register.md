# Core Matrix Architecture Health Audit Register

> Historical audit register preserved for traceability. Entry wording and
> naming reflect the architecture review as it was originally recorded, not the
> post-reset codebase. Use
> [docs/plans/README.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/README.md)
> and
> [docs/finished-plans/README.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/README.md)
> for current execution state.

## Status Model

- `candidate`: observed signal that has not yet cleared main-thread review
- `confirmed`: verified problem with evidence and corrective direction
- `clustered`: confirmed item that belongs to a larger related finding family
- `unification-opportunity`: related findings that indicate one deeper
  non-orthogonal design
- `resolved`: previously real issue that a later round verified as addressed
- `retired`: signal that did not survive review or reflects necessary
  complexity

## Entry Index

- `AH-001` Conversation model carries too many architecture roles
- `AH-002` AgentControl::Report is becoming a multi-protocol sink
- `AH-003` ProviderExecution::ExecuteTurnStep crosses too many boundaries at once
- `AH-004` ManualResume and ManualRetry look like sibling workflows without a shared recovery abstraction
- `AH-005` Scheduler namespace mixes graph scheduling with turn mutation policy
- `AH-006` PurgeDeleted and PurgePlan form a hand-built ownership graph engine
- `AH-007` ProviderCatalog::Validate is acting like a local schema engine
- `AH-008` Test context builders are becoming a parallel architecture language
- `AH-009` Lock and freshness contracts are similar but not obviously composed
- `AH-010` Runtime snapshot shape has no single obvious owner
- `AH-011` Mailbox targeting semantics depend on payload inference
- `AH-012` Close progression is distributed across several writers
- `AH-013` Execution snapshot and aggregate-boundary ownership unification
- `AH-014` Control-plane routing and lifecycle ownership unification

## Active Entries

### AH-003
- Status: `confirmed`
- Title: ProviderExecution::ExecuteTurnStep crosses too many boundaries at once
- First seen: `2026-03-27`
- Last reviewed: `2026-03-27`
- Type: `boundary ambiguity`
- Confidence: `medium`
- Priority: `P1`
- Related files: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Related concepts: provider execution, output variants, usage events, execution profiling, stale execution fencing
- Linked rounds: `round-1`
- Recommended direction: narrow the service to orchestration and push transcript,
  usage, and profiling writes behind explicit collaborators

### AH-004
- Status: `confirmed`
- Title: ManualResume and ManualRetry duplicate the paused-recovery pipeline
- First seen: `2026-03-27`
- Last reviewed: `2026-03-27`
- Type: `contract duplication`
- Confidence: `high`
- Priority: `P1`
- Related files: `core_matrix/app/services/workflows/manual_resume.rb`, `core_matrix/app/services/workflows/manual_retry.rb`, `core_matrix/test/services/workflows/manual_resume_test.rb`, `core_matrix/test/services/workflows/manual_retry_test.rb`
- Related concepts: paused recovery, mutable workflow context, deployment switching, selector recovery
- Linked rounds: `round-1`
- Recommended direction: extract shared recovery-target preparation while
  keeping resume and retry terminal behavior separate

### AH-005
- Status: `candidate`
- Title: Scheduler namespace mixes graph scheduling with turn mutation policy
- First seen: `2026-03-27`
- Last reviewed: `2026-03-27`
- Type: `concept or naming drift`
- Confidence: `medium`
- Priority: `P2`
- Related files: `core_matrix/app/services/workflows/scheduler.rb`, `core_matrix/test/services/workflows/scheduler_test.rb`
- Related concepts: runnable selection, during-generation policy, queue follow up, expected tail guard
- Linked rounds: `round-1`
- Recommended direction: preserve graph scheduling as one owner and move
  queue/restart mutation policy behind clearer names if the drift holds

### AH-006
- Status: `candidate`
- Title: PurgeDeleted and PurgePlan form a hand-built ownership graph engine
- First seen: `2026-03-27`
- Last reviewed: `2026-03-27`
- Type: `accidental complexity`
- Confidence: `low`
- Priority: `P1`
- Related files: `core_matrix/app/services/conversations/purge_deleted.rb`, `core_matrix/app/services/conversations/purge_plan.rb`, `core_matrix/test/services/conversations/purge_deleted_test.rb`
- Related concepts: purge ownership graph, quiescence, mailbox residue, runtime rows, attachment teardown
- Linked rounds: `round-1`
- Recommended direction: keep explicit purge ownership, but express owned
  resource families more declaratively

### AH-007
- Status: `candidate`
- Title: ProviderCatalog::Validate is acting like a local schema engine
- First seen: `2026-03-27`
- Last reviewed: `2026-03-27`
- Type: `accidental complexity`
- Confidence: `medium`
- Priority: `P2`
- Related files: `core_matrix/app/services/provider_catalog/validate.rb`, `core_matrix/test/services/provider_catalog/validate_test.rb`
- Related concepts: provider catalog, model roles, request defaults, capabilities, schema validation
- Linked rounds: `round-1`
- Recommended direction: keep one validation boundary but split or declare the
  schema more explicitly

### AH-008
- Status: `candidate`
- Title: Test context builders are becoming a parallel architecture language
- First seen: `2026-03-27`
- Last reviewed: `2026-03-27`
- Type: `test-exposed structural weakness`
- Confidence: `medium`
- Priority: `P1`
- Related files: `core_matrix/test/test_helper.rb`, `core_matrix/test/services/workflows/manual_resume_test.rb`, `core_matrix/test/services/conversations/purge_deleted_test.rb`, `core_matrix/test/services/agent_control/poll_test.rb`
- Related concepts: test helper DSL, scenario builders, workflow execution contexts, agent control contexts
- Linked rounds: `round-1`
- Recommended direction: reduce overlapping context factories and align the
  dominant test setup paths more directly with production contracts

### AH-009
- Status: `candidate`
- Title: Lock and freshness contracts are similar but not obviously composed
- First seen: `2026-03-27`
- Last reviewed: `2026-03-27`
- Type: `contract duplication`
- Confidence: `medium`
- Priority: `P1`
- Related files: `core_matrix/app/services/conversations/with_mutable_state_lock.rb`, `core_matrix/app/services/workflows/with_mutable_workflow_context.rb`, `core_matrix/app/services/workflows/with_locked_workflow_context.rb`, `core_matrix/app/services/turns/with_timeline_mutation_lock.rb`, `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Related concepts: mutable state lock, workflow context lock, timeline
  mutation, stale execution, lock order
- Linked rounds: `round-1`
- Recommended direction: clarify one contract family for lock order,
  revalidation, and stale-result handling

## Resolved Or Retired Entries

### AH-002
- Status: `resolved`
- Title: AgentControl::Report is becoming a multi-protocol sink
- Decision: resolved by the Phase 2 control-plane routing and lifecycle
  ownership unification batch
- Reason: `AgentControl::Report` now stays a thin ingress shell while
  execution, close, and health report families are handled by dedicated
  services and freshness validators.

### AH-001
- Status: `resolved`
- Title: Conversation and Turn are carrying too much read-side and snapshot-facing responsibility
- Decision: resolved by Phase 2 execution-snapshot / aggregate-boundary unification
- Reason: projection helpers moved out of `Conversation` into dedicated
  read-side services and the runtime-facing snapshot surface moved behind
  `Turn#execution_snapshot`, leaving aggregate models with row ownership and
  invariants only.

### AH-010
- Status: `resolved`
- Title: Runtime snapshot shape has no single obvious owner
- Decision: resolved by explicit execution-snapshot contract introduction
- Reason: `TurnExecutionSnapshot` and
  `Workflows::BuildExecutionSnapshot` now own snapshot field names,
  serialization, and downstream reads, replacing the previous split between
  `Turn`, workflow snapshot assembly, and hash consumers.

### AH-013
- Status: `resolved`
- Title: Execution snapshot and aggregate-boundary ownership unification
- Decision: resolved by Phase 2 execution-snapshot / aggregate-boundary unification
- Reason: the unification target landed as code and docs: runtime snapshot
  ownership is explicit, conversation read-side projection logic is extracted,
  and aggregate models no longer carry the old execution-snapshot convenience
  surface.

### AH-011
- Status: `resolved`
- Title: Mailbox targeting semantics depend on payload inference
- Decision: resolved by durable mailbox routing columns and shared runtime
  resolution
- Reason: mailbox rows now persist `control_plane` and
  `target_execution_environment_id`, and poll/publish routing no longer depends
  on payload inference or JSON SQL branches.

### AH-014
- Status: `resolved`
- Title: Control-plane routing and lifecycle ownership unification
- Decision: resolved by the Phase 2 control-plane unification batch
- Reason: routing semantics are now owned by durable mailbox fields plus
  `ResolveTargetRuntime`, and lifecycle handling is split between execution,
  close, and health handler families behind the shared ingress shell.

### AH-012
- Status: `retired`
- Title: Close progression is distributed across several writers
- Decision: weakened by reverse review
- Reason: the stronger claim did not survive the behavior-doc cross-check
  because `Conversations::ReconcileCloseOperation` is already the single close
  lifecycle-state writer. The remaining concern is narrower and is now tracked
  through `AH-014` instead.
