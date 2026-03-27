# Core Matrix Architecture Health Audit Register

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

### AH-001
- Status: `clustered`
- Title: Conversation model carries too many architecture roles
- First seen: `2026-03-27`
- Last reviewed: `2026-03-27`
- Type: `responsibility drift`
- Confidence: `medium`
- Priority: `P1`
- Related files: `core_matrix/app/models/conversation.rb`, `core_matrix/test/models/conversation_test.rb`
- Related concepts: transcript projection, historical anchors, visibility overlays, runtime contract
- Linked rounds: `round-1`
- Recommended direction: separate projection and lineage-calculation helpers
  from row-level conversation invariants

### AH-002
- Status: `clustered`
- Title: AgentControl::Report is becoming a multi-protocol sink
- First seen: `2026-03-27`
- Last reviewed: `2026-03-27`
- Type: `responsibility drift`
- Confidence: `medium`
- Priority: `P1`
- Related files: `core_matrix/app/services/agent_control/report.rb`
- Related concepts: mailbox control, execution reports, close reports, leases, idempotency receipts
- Linked rounds: `round-1`
- Recommended direction: keep one intake boundary but split method-specific
  report handlers from the shared receipt shell

### AH-003
- Status: `clustered`
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
- Title: ManualResume and ManualRetry look like sibling workflows without a shared recovery abstraction
- First seen: `2026-03-27`
- Last reviewed: `2026-03-27`
- Type: `contract duplication`
- Confidence: `medium`
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
- Confidence: `medium`
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

### AH-010
- Status: `clustered`
- Title: Runtime snapshot shape has no single obvious owner
- First seen: `2026-03-27`
- Last reviewed: `2026-03-27`
- Type: `boundary ambiguity`
- Confidence: `medium`
- Priority: `P1`
- Related files: `core_matrix/app/models/turn.rb`, `core_matrix/app/services/workflows/context_assembler.rb`, `core_matrix/app/services/provider_execution/build_request_context.rb`, `core_matrix/test/services/workflows/context_assembler_test.rb`
- Related concepts: resolved config snapshot, execution context, model context,
  provider execution, runtime attachment manifest
- Linked rounds: `round-1`
- Recommended direction: make the runtime snapshot a clearer first-class
  projection or contract owner

### AH-011
- Status: `clustered`
- Title: Mailbox targeting semantics depend on payload inference
- First seen: `2026-03-27`
- Last reviewed: `2026-03-27`
- Type: `boundary ambiguity`
- Confidence: `medium`
- Priority: `P2`
- Related files: `core_matrix/app/models/agent_control_mailbox_item.rb`, `core_matrix/app/services/agent_control/resolve_target_runtime.rb`, `core_matrix/app/services/agent_control/create_resource_close_request.rb`
- Related concepts: mailbox items, runtime plane, target resolution, resource
  close requests, environment plane
- Linked rounds: `round-1`
- Recommended direction: move runtime-plane and durable-target semantics into a
  stricter write-time contract

### AH-013
- Status: `unification-opportunity`
- Title: Execution snapshot and aggregate-boundary ownership unification
- First seen: `2026-03-27`
- Last reviewed: `2026-03-27`
- Type: `unification-opportunity`
- Confidence: `high`
- Priority: `P1`
- Related files: `core_matrix/app/models/conversation.rb`, `core_matrix/app/models/turn.rb`, `core_matrix/app/services/workflows/context_assembler.rb`, `core_matrix/app/services/provider_execution/build_request_context.rb`, `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Related concepts: aggregate invariants, execution snapshot, snapshot readers,
  provider execution, runtime attachment manifest
- Linked rounds: `round-1`
- Recommended direction: define one explicit execution-snapshot contract owner
  and shrink aggregate-model helper surfaces to true row invariants

### AH-014
- Status: `unification-opportunity`
- Title: Control-plane routing and lifecycle ownership unification
- First seen: `2026-03-27`
- Last reviewed: `2026-03-27`
- Type: `unification-opportunity`
- Confidence: `high`
- Priority: `P1`
- Related files: `core_matrix/app/services/agent_control/report.rb`, `core_matrix/app/models/agent_control_mailbox_item.rb`, `core_matrix/app/services/agent_control/poll.rb`
- Related concepts: mailbox targeting, runtime plane, report-family dispatch,
  stale reports, lifecycle ownership
- Linked rounds: `round-1`
- Recommended direction: keep one ingress shell, but centralize routing and
  target semantics into one shared control-plane contract family

## Resolved Or Retired Entries

### AH-012
- Status: `retired`
- Title: Close progression is distributed across several writers
- Decision: weakened by reverse review
- Reason: the stronger claim did not survive the behavior-doc cross-check
  because `Conversations::ReconcileCloseOperation` is already the single close
  lifecycle-state writer. The remaining concern is narrower and is now tracked
  through `AH-014` instead.
