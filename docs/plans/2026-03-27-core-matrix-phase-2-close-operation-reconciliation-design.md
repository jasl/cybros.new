# Core Matrix Phase 2 Design: Close Operation Reconciliation

Use this design document before starting the follow-up batch that repairs
conversation close progression in `Phase 2 Milestone C`.

Read together with:

1. `AGENTS.md`
2. `docs/plans/README.md`
3. `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
4. `docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md`
5. `docs/plans/2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md`
6. `docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md`

## Purpose

`Task C2` and the later runtime-boundary follow-up landed the Phase 2 close
model, but the current implementation still spreads close progression across
multiple services. That leaves `ConversationCloseOperation` vulnerable to
drift whenever a blocker reaches terminal state through a path that was not
explicitly wired back into the current close refresh helpers.

The immediate trigger is the discovered `SubagentRun` gap:

- `SubagentRun` is already part of the mainline stop barrier
- terminal subagent close reports can clear the last mainline blocker
- current close progression does not always recalculate after that state change

This design repairs the broader architectural issue rather than adding a
resource-specific patch.

## Problem Statement

The current implementation has three different places that partially own close
progression:

- `Conversations::RequestClose`
- `Conversations::FinalizeDeletion`
- `AgentControl::Report`

That split causes two kinds of instability:

1. `ConversationCloseOperation` state can become stale until another service
   call happens to re-enter close orchestration.
2. Adding a new blocker or disposal-tail resource requires remembering every
   hand-written refresh path instead of extending one stable kernel contract.

That is not the Phase 2 architecture we want. `ConversationCloseOperation`
should be the durable projection of one conversation-scoped reconciliation
rule, not a side effect scattered across unrelated handlers.

## Decisions

### 1. Close Progression Is A Conversation-Scoped Reconciliation Concern

`ConversationCloseOperation` progression belongs to one conversation-scoped
kernel service.

That service is responsible for:

- loading the unfinished close operation
- computing the current close summary
- determining the next close lifecycle state
- setting `summary_payload`
- setting or clearing `completed_at`
- applying the archive-side transition from `active` to `archived`

No other service should independently decide close lifecycle state.

### 2. Introduce One Writer: `Conversations::ReconcileCloseOperation`

Phase 2 should add one explicit application service:

- `Conversations::ReconcileCloseOperation`

This service becomes the single writer for:

- `ConversationCloseOperation.lifecycle_state`
- `ConversationCloseOperation.summary_payload`
- `ConversationCloseOperation.completed_at`

It also becomes the single place that may advance an archive close from:

- `Conversation.lifecycle_state = active`
to
- `Conversation.lifecycle_state = archived`

The service must run under the conversation lock so summary reads and close
state updates stay coherent.

### 3. `CloseSummaryQuery` Remains The Summary Source Of Truth

`Conversations::CloseSummaryQuery` already defines the operator-visible shape of
close state. That query should remain the authoritative summary source for
reconciliation.

The reconciler should not duplicate its own blocker counters in private helper
queries. Instead:

- `CloseSummaryQuery` owns blocker and tail counts
- `ReconcileCloseOperation` owns lifecycle decisions derived from that summary

Future blocker families should therefore extend the query first, then reuse the
same reconciliation logic.

### 4. Reconciliation Must Be Triggered By Every Summary-Affecting State Change

The kernel must enforce this invariant:

If a state mutation can change `CloseSummaryQuery`, and the conversation still
has an unfinished `ConversationCloseOperation`, the same application-layer flow
must explicitly invoke `Conversations::ReconcileCloseOperation`.

That rule applies to both local mutation paths and mailbox-driven terminal
paths.

### 5. Trigger Coverage Is Explicit, Not Callback-Driven

This follow-up should not hide reconciliation behind model callbacks.

Phase 2 should keep reconciliation explicit in application services so the
close contract remains:

- easy to audit
- easy to extend
- transport-neutral
- compatible with the current breaking-change posture

The required trigger set is:

- `Conversations::RequestClose`
- `Conversations::RequestTurnInterrupt`
- `Conversations::FinalizeDeletion`
- `AgentControl::Report` terminal close handling

If future Phase 2 work introduces another path that can change close summary,
that path must explicitly join this trigger set.

### 6. Resource-To-Conversation Resolution Must Be General

Mailbox-driven close reporting must not special-case only resources that happen
to respond to `conversation`.

The reconciliation boundary needs one stable conversation-resolution rule:

- resources with `conversation` use it directly
- resources with `turn` may resolve through `turn.conversation`
- resources with `workflow_run` may resolve through `workflow_run.conversation`

That keeps `SubagentRun` in the same architecture as:

- `AgentTaskRun`
- `ProcessRun`
- future workflow-owned runtime resources

### 7. Archive And Delete Stay Orthogonal

The reconciler must preserve the existing product distinction:

- archive reaches `archived` once the mainline stop barrier is clear, even if
  disposal tails remain
- delete reaches `deleted` only through `FinalizeDeletion`
- delete close progression may still move among `disposing`, `degraded`, and
  `completed` after deletion finalization

The reconciler must not collapse archive and delete into one lifecycle machine.
It only centralizes the transition rules.

### 8. Future Extension Rule

Any future blocker or disposal-tail resource must follow this contract:

1. extend `CloseSummaryQuery` so the resource is represented in the durable
   summary
2. explicitly trigger `Conversations::ReconcileCloseOperation` from the path
   that mutates that resource's close-relevant state

No future work should add ad hoc close lifecycle writes outside the reconciler.

## Current Implementation Adjustments

This follow-up is expected to remove or collapse the following duplicated logic.

### `Conversations::RequestClose`

Current issue:

- it computes summary and lifecycle progression inline

Required adjustment:

- keep responsibility for creating or reusing the close operation
- keep responsibility for requesting interrupts and background close work
- remove inline lifecycle computation
- invoke `Conversations::ReconcileCloseOperation` instead

### `Conversations::FinalizeDeletion`

Current issue:

- it has its own close lifecycle decision block after setting
  `deletion_state = deleted`

Required adjustment:

- keep responsibility for mainline-barrier validation and canonical-store
  reference removal
- remove its bespoke close-state decision logic
- invoke `Conversations::ReconcileCloseOperation` after the delete product
  state is durably updated

### `Conversations::RequestTurnInterrupt`

Current issue:

- it can locally clear blockers and finalize turn/workflow cancellation
  without refreshing an unfinished close operation

Required adjustment:

- explicitly reconcile after local blocker cancellation or mainline finalization
  when the conversation is currently closing

### `AgentControl::Report`

Current issue:

- it only refreshes close progression for resources that directly expose
  `conversation`
- that misses `SubagentRun`

Required adjustment:

- replace the local close-refresh helper with one conversation-resolution path
  plus a call into `Conversations::ReconcileCloseOperation`

## Target Runtime Flow

The desired close progression flow is:

1. `RequestClose` creates or reuses one unfinished close operation.
2. `RequestClose` requests mailbox close work and local mainline fencing.
3. `ReconcileCloseOperation` writes the first summary and lifecycle state.
4. Local state changes caused by `RequestTurnInterrupt` re-enter the same
   reconciler.
5. Mailbox terminal reports for `AgentTaskRun`, `ProcessRun`, or `SubagentRun`
   re-enter the same reconciler.
6. `FinalizeDeletion` re-enters the same reconciler after the conversation is
   durably `deleted`.
7. No subsequent archive or delete API call is required merely to move the
   close operation forward.

## Acceptance Criteria

This follow-up is complete only when all of the following are true:

- `ConversationCloseOperation` has one application-layer writer
- `RequestClose`, `FinalizeDeletion`, `RequestTurnInterrupt`, and mailbox
  terminal close reports all converge on that writer
- a force archive with a `SubagentRun` as the last mainline blocker reaches
  `Conversation.lifecycle_state = archived` without a second archive request
- a delete flow with a `SubagentRun` as the last mainline blocker refreshes the
  close operation immediately after terminal close reporting
- archive with remaining detached background residue still reaches
  `disposing` or `degraded`, not a false clean completion
- no model callback is introduced for close progression
- future extension rules are documented clearly enough that adding a new blocker
  family does not require re-deriving the architecture from chat history

## Task Relationship Model

The implementation work for this design is intentionally ordered:

1. establish the single reconciler service and its tests
2. route close initiation and delete finalization into that service
3. route local mainline state changes into that service
4. route mailbox terminal close paths into that service
5. remove leftover duplicate close-state writers and re-verify documentation

That order ensures the new architecture exists before call sites are migrated,
and that all pre-existing writers can be removed without creating another
transition period or compatibility layer.

## Documentation Integrity Check

This design document was checked for completeness on `2026-03-27`.

- the task goal is explicit
- the architectural defect is explicit
- the single-writer design rule is explicit
- current implementations that must change are named directly
- trigger boundaries are explicit
- archive and delete semantics remain orthogonal
- acceptance criteria are specific enough to verify without chat-only context
- task relationships are linear and automation-safe
