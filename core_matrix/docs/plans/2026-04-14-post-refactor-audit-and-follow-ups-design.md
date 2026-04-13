# Post-Refactor Audit And Follow-Ups Design

## Goal

Capture one coherent post-refactor audit for the current `core_matrix` branch:

1. record the real benefits already achieved by the `Conversation` / `Turn` /
   workflow bootstrap slimming work
2. identify the remaining correctness risks introduced or exposed by the new
   state boundaries
3. rank the next worthwhile simplification, lazy-materialization, schema
   slimming, and redundancy-hardening opportunities

This branch allows destructive refactors, in-place migration rewrites, and full
database rebuilds. Compatibility with pre-launch schema is not a constraint.

## Context

The branch has already completed a large structural pass:

- `Workspace` and `Conversation` became clearer boundary resources
- `ConversationCapabilityPolicy` was collapsed into `Conversation`
- root lineage substrate became lazy
- `ConversationExecutionEpoch` creation moved to first real execution entry
- app-facing manual user turn entry now records accepted-turn truth
  synchronously and materializes workflow substrate later
- hot payloads were split out of several wide rows

This design does **not** supersede the earlier implementation plans. It is a
follow-up audit and prioritization layer on top of:

- `docs/plans/2026-04-13-core-matrix-data-structure-optimization-design.md`
- `docs/plans/2026-04-13-conversation-bootstrap-phase-two-design.md`

This document now serves two purposes:

- preserve the original audit findings that shaped the follow-up work
- record which items were implemented, closed, deferred, or judged not worth a
  standalone pass

Unless explicitly marked otherwise, the `Findings` section below should be read
as the original audit record, while the later `Status Summary` and `Closeout
Decisions` sections describe the current branch state.

## What Looks Good

### `Conversation` and `Message` are directionally correct

The most important boundary resources now have the right shape:

- `Conversation` owns execution continuity, capability booleans, latest anchors,
  and app-facing current-state pointers
- `Turn` owns workflow bootstrap state and accepted-turn truth
- `Message` remains intentionally lean and transcript-centric

The audit did **not** find a new structural regression in `Message` itself.
`Message` still has the correct provenance rules and should stay narrow. Adding
`user_id`, `workspace_id`, or `agent_id` directly to `messages` is still not
recommended.

### The branch achieved real request-path weight reduction

The current branch already has test-backed reductions in the hottest
conversation-entry paths:

- `Conversations::CreateRoot`
  - budgeted at `<= 13` SQL
- `Workbench::CreateConversationFromAgent`
  - budgeted at `<= 52` SQL
- `POST /app_api/conversations`
  - budgeted at `<= 62` SQL
- `Workbench::SendMessage`
  - budgeted at `<= 40` SQL
- `POST /app_api/conversations/:id/messages`
  - budgeted at `<= 50` SQL

The most important qualitative win is also real:

- synchronous acceptance no longer allocates `WorkflowRun`, `WorkflowNode`, or
  initial task substrate
- the app-facing API now acknowledges accepted work before full workflow
  substrate exists

### The current denormalization strategy is mostly working

The following current-state and read-side redundancies still look justified:

- `conversations.latest_turn_id`
- `conversations.latest_active_turn_id`
- `conversations.latest_message_id`
- `conversations.latest_active_workflow_run_id`
- `conversations.last_activity_at`
- `conversations.current_execution_epoch_id`
- `conversations.current_execution_runtime_id`

The current read-model denormalization also still looks right:

- `ConversationSupervisionState`
- `ConversationSupervisionFeedEntry`

Those rows are serving real board/feed use cases and should remain explicitly
denormalized.

## Original Audit Findings

### 1. Bootstrap failure can still be misread as healthy runtime state

This is the highest-priority remaining correctness issue.

`Turns::MaterializeWorkflowBootstrap` can create a `WorkflowRun`, then fail
later during dispatch or execution handoff. In that case:

- the `Turn` is marked `workflow_bootstrap_state = "failed"`
- but the already-created `WorkflowRun` remains present

The current supervision read path only treats bootstrap projection as
authoritative while the turn has **no** workflow run. Once `turn.workflow_run`
exists, supervision can fall back to workflow-backed state and present the turn
as queued or active instead of failed.

**Why this matters**

- user-facing state becomes dishonest
- failed acceptance can look like live runtime activity
- recovery and debugging flows lose a reliable state contract

**Design direction**

The `Turn` bootstrap state machine must remain authoritative until workflow
materialization reaches a fully healthy handoff point. A partially created
`WorkflowRun` must not outrank a bootstrap failure.

There are only two clean end states:

1. make bootstrap failure terminal for the substrate as well
2. or preserve a strict “bootstrap failed” projection branch even when
   `workflow_run` exists

The second option is safer if we want retry/recovery to reuse substrate, but it
must be explicit in every supervision/read-side branch.

### 2. Durable backlog recovery is not fully wired

The branch now treats `pending` bootstrap as durable backlog, but the recovery
loop is not fully closed unless the maintenance scheduler actually runs it.

There is already:

- `Turns::RecoverWorkflowBootstrapBacklog`
- `Turns::RecoverWorkflowBootstrapBacklogJob`

But this only closes the hanging-state problem if the job is actually scheduled
in recurring maintenance.

**Why this matters**

If `perform_later` fails after accepted-turn truth is committed, the system must
eventually recover that backlog without manual intervention. Otherwise `pending`
becomes a hanging terminal state in practice.

**Design direction**

Treat `pending` as a first-class durable queue and wire the recovery job into
the maintenance cadence explicitly. This is not optional.

### 3. Some critical state shape is only partially schema-enforced

The branch improved state modeling, and some of the most important shape
contracts are already in schema, but the job is not finished yet.

Notably:

- `Conversation.current_execution_epoch_id` and
  `Conversation.execution_continuity_state` **do** have a DB-level existence
  contract, but `Conversation.current_execution_runtime_id` still does not have
  a DB-level alignment check against the current epoch runtime
- `Turn.workflow_bootstrap_*` shape and transition rules are heavily tested, but
  are not yet locked down with equivalent DB checks

**Why this matters**

This branch explicitly embraces destructive refactors and structural truth in
schema. If these contracts are important enough to drive read-side behavior,
they are important enough to survive:

- `update_columns`
- data repair scripts
- direct SQL
- future write paths that accidentally bypass validations

**Design direction**

Continue the “state shape is structural truth” policy:

- keep the existing continuity/epoch presence contract on `conversations`
- harden runtime/epoch cache alignment on `conversations`
- harden `workflow_bootstrap_*` contract in schema where feasible
- keep model validation as the second line, not the only line

### 4. Some new redundancy is not yet fully consumed

The branch correctly added and maintains turn/message anchors, but some read
paths still fall back to scanning base tables.

The clearest example is supervision feed selection, which still scans `turns`
when anchors are absent.

This is not a correctness bug, but it means the branch has not yet fully cashed
in the benefit of its new redundant columns.

**Design direction**

Before adding new redundancy, finish consuming the current redundancy in
remaining read paths.

## Recommended Follow-Ups

The next worthwhile work falls into four buckets.

### Bucket A: Correctness hardening

These should go before any new broad optimization pass.

#### A1. Make bootstrap failure authoritative even if substrate exists

Priority: `P1`

This is the first fix to land.

Possible approaches:

- preserve bootstrap-failed projection as long as the turn bootstrap state is
  `failed`, regardless of `workflow_run` presence
- or cancel/terminalize the partial `WorkflowRun` in the same failure path

Recommendation:

- keep substrate reuse available if desired, but make supervision/read-side
  always prefer bootstrap failure over workflow presence until a real successful
  handoff occurs

#### A2. Wire backlog recovery into recurring maintenance

Priority: `P1`

The branch already has the right job. It now needs to become part of the actual
maintenance loop.

#### A3. Move remaining critical state contracts into schema

Priority: `P2`

Specifically:

- `conversations.current_execution_epoch_id` /
  `conversations.current_execution_runtime_id`
- `turns.workflow_bootstrap_state`
- `turns.workflow_bootstrap_payload`
- `turns.workflow_bootstrap_failure_payload`
- timestamp pairing rules around bootstrap lifecycle

### Bucket B: Further lazy/deferred work

These are the best remaining candidates for the same optimization style.

#### B1. `ConversationDiagnosticsSnapshot` / `TurnDiagnosticsSnapshot`

Priority: `P2`

These are recomputed summary surfaces over persisted facts, not boundary truth.
They are strong deferred-recompute candidates.

Recommendation:

- keep writes truthful and small
- recompute diagnostics asynchronously
- make debug/diagnostics surfaces explicitly stale-tolerant

#### B2. `ConversationSupervisionState` / `ConversationSupervisionFeedEntry`

Priority: `P2`

This is a larger product tradeoff. The current feed and todo-plan controllers
still force synchronous supervision state refresh before reading.

Recommendation:

- do this only if we are willing to make board/feed semantics explicitly
  projection-first and slightly stale by contract

#### B3. `Conversations::Metadata::BootstrapTitle`

Priority: `P3`

This is not boundary truth. It is a good low-risk cleanup candidate for moving
out of the accepted-turn transaction path.

### Bucket C: Model and table slimming

These are the best structural simplification targets still left.

#### C1. Collapse `WorkspacePolicy` into `Workspace`

Priority: `P2`

`WorkspacePolicy` is a one-row companion with no real independent lifecycle.
Its main payload, `disabled_capabilities`, can live directly on `workspaces`.

Recommendation:

- inline `disabled_capabilities`
- delete `workspace_policies`
- keep capability projection logic, but make `Workspace` the single owner

#### C2. Collapse export request duplicates

Priority: `P2`

`ConversationExportRequest` and `ConversationDebugExportRequest` appear to be
the same workflow with different intent.

Recommendation:

- merge into a single request table with a `kind`
- collapse create/execute service trees accordingly

#### C3. Re-evaluate `LineageStoreReference` polymorphism

Priority: `P3`

At this point, all real call sites use `Conversation` ownership, and
`LineageStore` itself is already explicit about `owner_conversation_id`. The
remaining polymorphism now mostly lives in:

- `LineageStoreReference.owner`
- `LineageStores::QuerySupport`
- purge/delete helpers that still filter on `owner_type = "Conversation"`

This means the abstraction is probably no longer buying us anything. The
separate `Conversation#root_lineage_store` alias also appears unused.

Recommendation:

- if lineage gets another structural pass, flatten `LineageStoreReference` to
  explicit `conversation_id`
- delete the unused `Conversation#root_lineage_store` alias at the same time
- do **not** prioritize this as a standalone hot-path optimization; it is now
  a low-leverage cleanup, not a mainline performance blocker

#### C4. Re-evaluate supervision session side tables

Priority: `P3`

`ConversationSupervisionMessage` and `ConversationSupervisionSnapshot` may now
be heavier than necessary relative to `ConversationSupervisionSession`.

After the refactor, the surviving shape looks more justified than it first
appeared:

- `ConversationSupervisionSession` is accepted boundary truth
- `ConversationSupervisionSnapshot` is a point-in-time audit/context capture
- `ConversationSupervisionMessage` is the actual side-chat transcript

These rows also still participate in:

- app-facing supervision APIs
- embedded supervision responder flows
- data retention pruning
- purge/delete cleanup

Recommendation:

- keep the current table split unless the supervision product surface itself is
  reduced
- if we revisit this later, target payload slimming inside snapshot/message
  rows rather than collapsing the tables
- treat this as effectively closed for the current branch unless a product
  decision removes the need for supervision transcript/audit history

### Bucket D: Redundancy follow-ups

These are not new lazy candidates; they are “the denormalization is good but
not yet complete” items.

#### D1. Add direct `workflow_run_id` to `ProcessRun`

Priority: `P2`

`ProcessRun` still derives `workflow_run` through `workflow_node`, which is too
indirect for runtime/debug hot paths.

Recommendation:

- add `workflow_run_id`
- align it structurally with `workflow_node_id`
- simplify runtime events, blocker aggregation, and debug export reads

#### D2. Consider lightweight conversation-state redundancy for open human interactions

Priority: `P3`

`HumanInteractionRequest` already has owner/context, but open inbox reads still
re-enter `Conversation` lifecycle state.

The current read paths suggest this is **not** yet a worthwhile denormalization
target:

- `HumanInteractions::OpenForUserQuery` still needs `Conversation` for access
  control and active-retained filtering
- blocker and close-safety reads already aggregate directly from
  `HumanInteractionRequest` keyed by `conversation_id`

So an extra conversation-state cache on the request would not remove the most
important join, and it would introduce another piece of state to maintain.

Recommendation:

- only if inbox becomes hot
- otherwise keep current shape
- treat this as a profiling-gated follow-up, not an active design gap

#### D3. Finish consuming current anchors before adding new ones

Priority: `P3`

The branch already maintains:

- latest turn
- latest active turn
- latest message
- latest active workflow run

Recommendation:

- keep preferring existing anchors over new columns
- note that the hottest app-facing reads are now already anchor-first
- limit further work here to opportunistic cleanup of remaining full-refresh
  paths such as creation/import/repair helpers
- do **not** add new redundancy until a specific read path demonstrates that
  current anchors are insufficient

## What Should Not Be “Lazy”

The audit still strongly recommends **against** using deferred creation for
boundary truth itself:

- `Conversation`
- `Turn`
- `Message`
- `Workspace`
- `Agent`
- `ExecutionRuntime`
- `ConversationControlRequest`
- `ConversationCapabilityGrant`
- `ConversationCloseOperation`
- `ConversationSupervisionSession`

These must exist synchronously once their corresponding business fact is
accepted.

Execution substrate needs a more precise rule:

- `WorkflowRun`
- `WorkflowNode`
- `AgentTaskRun`
- `ProcessRun`
- `ConversationExecutionEpoch`

These should **not** be treated as synchronous acceptance requirements for
app-facing entry if the product contract already allows accepted work to exist
before substrate materialization.

But once execution crosses a real materialization boundary, these rows become
substrate truth and should not be softened into best-effort cache state.

In other words:

- they may be **deferred until the correct execution boundary**
- they should **not** be fabricated eagerly just to acknowledge accepted work
- and once materialized, they should still be treated as first-class execution
  truth

## Current Minimality Assessment

### Already close to the right shape

- `Conversation`
- `Workspace`
- `Message`
- `ConversationSupervisionState`
- `ConversationSupervisionFeedEntry`
- hot/cold detail splits such as:
  - `ConversationDetail`
  - `WorkflowRunWaitDetail`
  - `HumanInteractionRequestDetail`

### Still likely over-factored or under-denormalized

- `WorkspacePolicy`
- `ConversationExportRequest` / `ConversationDebugExportRequest`
- `ProcessRun` without direct `workflow_run_id`

### Low-priority cleanup, not active branch drivers

- `LineageStoreReference` polymorphism
- unused `Conversation#root_lineage_store` alias
- remaining generic full-anchor refresh helpers in non-hot paths

## Recommended Order

From a global and long-term perspective, the next work should be ordered like
this:

1. make bootstrap failure authoritative in supervision and read-side
2. wire backlog recovery into recurring maintenance
3. move remaining critical state-shape contracts into schema
4. add `workflow_run_id` to `process_runs`
5. collapse `WorkspacePolicy` into `Workspace`
6. collapse export request duplicates
7. defer diagnostics recomputation
8. optionally make supervision projections more explicitly async/stale-tolerant
9. only then consider low-leverage cleanup such as lineage reference
   flattening or leftover anchor-refresh consolidation

## Closeout Decisions For Remaining Tail Items

The remaining unresolved items from this audit should be treated as follows:

- `C3` is a valid simplification target, but not a worthwhile standalone pass
  unless we are already changing lineage internals again
- `C4` should be considered closed for now; current supervision session /
  snapshot / message separation still maps to real product and retention
  semantics
- `D2` should stay deferred until profiling proves inbox/open-human-interaction
  reads are hot enough to justify new redundancy
- `D3` is mostly complete on hot app-facing reads; further work should stay
  opportunistic and should not justify new anchor columns by itself

### D3 quick-scan conclusion

A final spot check of the current branch suggests the remaining non-anchor-first
paths are now mostly:

- generic repair/import helpers such as `Conversations::RefreshLatestAnchors`
  from root creation or bundle rehydration
- richer internal supervision/runtime builders that still compute detailed
  evidence by scanning turns or workflow runs
- ordering/sequence helpers for write paths rather than app-facing read paths

The hottest app-facing reads that previously justified this item are already in
better shape:

- feed reads now prefer persisted anchors and persisted feed entries
- todo-plan reads now prefer persisted supervision state
- conversation runtime targeting already consumes current anchor pointers first

So `D3` should now be treated as functionally complete for the optimization
goal of this branch. Remaining work is cleanup-only.

## Status Summary

### Implemented

- `A1` bootstrap failure made authoritative in supervision/read-side
- `A2` backlog recovery wired into recurring maintenance on an explicit
  `every 5 minutes` cadence
- `A3` remaining critical execution/bootstrap state shape hardened in schema
- `B1` diagnostics moved to deferred recompute
- `B2` feed / todo-plan moved to projection-first stale-tolerant reads
- `B3` title bootstrap moved to placeholder plus async upgrade
- `C1` `WorkspacePolicy` collapsed into `Workspace`
- `C2` export request duplicates collapsed
- `D1` direct `workflow_run_id` added to `ProcessRun`

### Closed

- `C4` supervision session side-table factoring

### Deferred / Conditional

- `C3` lineage reference flattening, only if lineage internals are reopened
- `D2` human-interaction redundancy, only if inbox/open-request reads become hot
- `D3` remaining anchor cleanup, opportunistic only

## Acceptance Criteria For The Next Follow-Up

Any next iteration based on this document should explicitly verify:

- no bootstrap failure can present as healthy queued/running state
- no accepted turn can remain permanently stuck in `pending` because maintenance
  recovery is absent
- critical state shape is enforced in schema, not only model validation
- any new lazy/deferred surface records a measured before/after reduction in:
  - SQL count
  - synchronously created rows
  - request-path runtime work
- any proposed model collapse removes real duplication without weakening
  boundary truth or audit semantics
