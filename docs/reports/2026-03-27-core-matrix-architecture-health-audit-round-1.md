# Core Matrix Architecture Health Audit Round 1

> Historical report preserved as the Round 1 diagnosis that led to the April
> 2026 reset batches. This document intentionally preserves the terminology and
> implementation context of that date. For the current code state, use
> [docs/plans/README.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/README.md),
> [docs/finished-plans/README.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/README.md),
> and the active acceptance harness at
> [acceptance/README.md](/Users/jasl/Workspaces/Ruby/cybros/acceptance/README.md).

## Scope For This Round

- product: `core_matrix`
- frozen execution root shape:
  `Conversation -> Turn -> WorkflowRun -> WorkflowNode`
- phase context: Milestone A through C has landed, including recent hardening
  around close progression, conversation mutation contracts, runtime binding,
  rewrite safety, lineage, and provenance
- audit emphasis: architecture health and structural coherence, not only defect
  discovery
- primary review surfaces:
  - `core_matrix/app/models`
  - `core_matrix/app/services`
  - `core_matrix/app/queries`
  - `core_matrix/app/controllers`
  - `core_matrix/test`
- secondary review surfaces when needed for confirmation or rejection:
  - `core_matrix/config`
  - `core_matrix/db`
  - `docs/archived-plans/core_matrix-docs-legacy-2026-04-17/behavior`
  - root `docs/plans` artifacts for current phase intent
- fixed broad-scan viewpoints:
  - layering
  - contracts
  - complexity
  - test reverse view

## Executive Summary

- Overall judgment: the current `core_matrix` architecture is still coherent
  enough to extend, but several important boundaries are getting sticky after
  repeated Phase 2 hardening. The strongest signals are not raw correctness
  defects. They are ownership and orthogonality problems at aggregate,
  execution-snapshot, and control-plane seams.
- The three most important problem families from this round are:
  - aggregate models and execution snapshots are blurring together
  - control-plane mailbox and report handling are accumulating too many roles
  - paused recovery behavior is duplicated across sibling workflows
- The strongest healthy patterns worth preserving are:
  - controller and query layers remain comparatively thin
  - close lifecycle state is still funneled through an explicit reconciler
  - public-id discipline at machine-facing and snapshot-facing boundaries is
    consistently treated as a real contract
- Several candidates were weakened, not strengthened, by the reverse pass:
  - the purge ownership graph is intentionally explicit and fail-closed
  - the close reconciler really is the single lifecycle-state writer, even
    though several services feed facts into it
  - the split between selector persistence and selector resolution is deliberate
- The best next step is not a random cleanup pass. It is targeted
  simplification around two unification opportunities:
  - execution snapshot and aggregate-boundary ownership
  - control-plane routing and lifecycle ownership
- Recovery and scheduler observations in this round are based on the current
  workspace state, which already contains in-flight uncommitted edits in that
  area. Re-run those judgments after that change set lands.

## Implementation Update

- A later Phase 2 execution-snapshot / aggregate-boundary unification batch
  has now landed in `core_matrix`.
- The batch introduced `TurnExecutionSnapshot` and
  `Workflows::BuildExecutionSnapshot` as the explicit runtime snapshot contract
  family, replacing the previous split across `Turn`, workflow snapshot
  assembly, and downstream hash readers.
- Conversation transcript, context, and historical-anchor projection logic now
  lives in dedicated read-side services under
  `core_matrix/app/services/conversations/`.
- That implementation resolves the execution-snapshot ownership family tracked
  through `AH-001`, `AH-010`, and `AH-013`.
- A later Phase 2 control-plane routing and lifecycle ownership unification
  batch has also landed in `core_matrix`.
- The batch moved mailbox routing semantics into durable mailbox columns,
  routed `Poll` and `PublishPending` through the shared
  `ResolveTargetRuntime` contract, and split `AgentControl::Report` into a
  thin ingress shell plus execution / close / health handler families.
- That implementation resolves the control-plane ownership family tracked
  through `AH-002`, `AH-011`, and `AH-014`.
- The Round 1 observations remain useful as the historical diagnosis that led
  to the batch, but their current status should now be read through the audit
  register rather than as still-open findings.

## Confirmed Findings

### Conversation and Turn are carrying too much read-side and snapshot-facing responsibility
- Priority: `P1`
- Confidence: `high`
- Implementation update: resolved later by the Phase 2 execution-snapshot /
  aggregate-boundary unification batch, which extracted conversation
  projection logic into dedicated services and reduced `Turn` to row-owned
  state plus the single `execution_snapshot` reader.
- Why it matters: `Conversation` and `Turn` are both genuine aggregates, but
  they also act as projection engines and snapshot facades. That makes it
  harder to tell which rules are durable domain invariants and which are
  read-side or execution-snapshot conveniences.
- Evidence:
  - `core_matrix/app/models/conversation.rb`
  - `core_matrix/app/models/turn.rb`
  - `docs/archived-plans/core_matrix-docs-legacy-2026-04-17/behavior/workflow-context-assembly-and-execution-snapshot.md`
  - `docs/archived-plans/core_matrix-docs-legacy-2026-04-17/behavior/turn-entry-and-selector-state.md`
- Counterpoint: the behavior docs do intentionally bless an explicit workflow
  snapshot assembly boundary and a limited `Turn` read surface, so some
  exposure is expected.
- Related concepts: transcript projection, historical anchors, execution
  context, provider execution, runtime attachment manifest
- Local fix: extract transcript-projection and snapshot-access helpers into
  narrower collaborators without changing row ownership.
- Systemic fix: formalize two distinct contracts:
  - one conversation/turn aggregate contract for persistent invariants
  - one execution snapshot contract for read-side and runtime-facing payloads

### AgentControl control-plane intake is too centralized and still partly convention-driven
- Priority: `P1`
- Confidence: `high`
- Implementation update: resolved later by the Phase 2 control-plane routing
  and lifecycle ownership unification batch, which moved routing semantics into
  durable mailbox fields and split the report family handling behind a thin
  ingress shell.
- Why it mattered at audit time: `AgentControl::Report` acted as a large
  ingress shell for execution events, close events, retry gating, and
  follow-up reconciliation, while mailbox targeting still depended partly on
  payload conventions. That made control-plane growth depend on one
  increasingly broad intake boundary.
- Evidence:
  - `core_matrix/app/services/agent_control/report.rb`
  - `core_matrix/app/models/agent_control_mailbox_item.rb`
  - `core_matrix/app/services/agent_control/poll.rb`
  - `core_matrix/test/services/agent_control/report_test.rb`
- Counterpoint: one ingress endpoint for duplicate/stale handling is a good
  idea and should not be discarded.
- Related concepts: mailbox targeting, control planes, stale reports, leases,
  close requests
- Local fix: split method families behind dedicated report handlers and replace
  payload-based control-plane inference with stricter declared semantics.
- Systemic fix: define one control-plane routing contract that owns:
  - control-plane intent
  - durable target reference semantics
  - report-family dispatch
  so the ingress boundary stays thin while routing and lifecycle rules stop
  drifting by convention.

### ManualResume and ManualRetry duplicate the paused-recovery pipeline
- Priority: `P1`
- Confidence: `high`
- Why it matters: the docs intentionally model manual resume and manual retry
  as separate recovery boundaries, but the implementation duplicates most of the
  preparation steps before diverging late. That is a classic drift hazard.
- Evidence:
  - `core_matrix/app/services/workflows/manual_resume.rb`
  - `core_matrix/app/services/workflows/manual_retry.rb`
  - `core_matrix/test/services/workflows/manual_resume_test.rb`
  - `core_matrix/test/services/workflows/manual_retry_test.rb`
  - `docs/archived-plans/core_matrix-docs-legacy-2026-04-17/behavior/agent-definition-version-bootstrap-and-recovery-flows.md`
- Counterpoint: the final side effects are materially different, so these
  should not be collapsed into one opaque service.
- Related concepts: paused recovery, mutable workflow context, deployment
  switching, selector recovery, audit logging
- Local fix: extract shared recovery-target validation, deployment-switch
  preparation, and selector-resolution steps into a common helper or service.
- Systemic fix: define a paused-recovery pipeline with strategy-specific end
  transitions so resume and retry share legality and binding rules but keep
  different terminal behavior.

### ProviderExecution::ExecuteTurnStep is still a too-broad orchestration boundary
- Priority: `P1`
- Confidence: `medium`
- Why it matters: one service currently owns provider I/O, stale-execution
  fencing, output creation, usage accounting, profiling writes, and workflow
  terminalization. Even if the transaction boundary is right, the responsibility
  surface is too wide.
- Evidence:
  - `core_matrix/app/services/provider_execution/execute_turn_step.rb`
  - `core_matrix/app/services/provider_execution/build_request_context.rb`
  - `docs/archived-plans/core_matrix-docs-legacy-2026-04-17/behavior/workflow-context-assembly-and-execution-snapshot.md`
- Counterpoint: the write path is deliberately transactional and fail-closed, so
  some orchestration density is justified.
- Related concepts: provider request context, output variants, usage events,
  execution profiling, stale result rejection
- Local fix: push transcript, usage, and profiling persistence into dedicated
  collaborators invoked inside the same transaction boundary.
- Systemic fix: treat provider execution as a pipeline with:
  - request preparation
  - provider call
  - fresh-state revalidation
  - result persistence
  as explicit stages, instead of one growable service object.

### Unification Opportunity: Execution snapshot and aggregate-boundary ownership
- Implementation update: this target shape has now landed. `TurnExecutionSnapshot`
  owns snapshot field names and readers, `Workflows::BuildExecutionSnapshot`
  owns persisted snapshot assembly, and the aggregate helper surfaces on
  `Conversation` and `Turn` were reduced accordingly.
- Historical shape at audit time: execution-related structure was split across
  `Conversation`, `Turn`, workflow snapshot assembly,
  `ProviderExecution::BuildRequestContext`, and downstream consumers.
- Why it is not orthogonal: the codebase has aggregate roots, snapshot
  assemblers, and convenience read helpers, but the ownership line between them
  is only partly explicit. That invites more fields and more helper methods to
  land in whichever object is nearest.
- Target shape: one explicit execution-snapshot contract owns snapshot field
  names, serialization, and read helpers, while aggregate models keep only true
  row invariants and identity relationships.
- Single owner / source of truth: the execution-snapshot contract, not `Turn`
  convenience methods spread across the model plus assembler plus executor.
- What should be merged / deleted / demoted:
  - merge snapshot-shape knowledge into one contract family
  - demote convenience hash accessors on the model when they are only read-side
    adapters
  - keep selector persistence and aggregate invariants on the rows
- Migration path:
  1. introduce an explicit snapshot object or module for field access
  2. move assembler and request-context consumers onto that object
  3. shrink `Turn` and `Conversation` helper surfaces afterward
- Risk if left as-is: Phase 2 follow-up work will keep widening model helpers
  and service touch points around snapshot evolution.

### Unification Opportunity: Control-plane routing and lifecycle ownership
- Implementation update: this target shape has now landed. Mailbox routing
  semantics live on durable mailbox fields, `ResolveTargetRuntime` is shared by
  poll and publish paths, and `AgentControl::Report` now delegates lifecycle
  families to dedicated handlers and freshness validators.
- Current shape: ingress report handling, mailbox targeting, control-plane
  semantics, and close follow-up behavior are spread across model validation,
  polling selection, and report dispatch.
- Why it is not orthogonal: one logical control-plane contract is currently
  split between durable row semantics, ingress dispatch, and payload
  conventions. That makes it too easy for routing and lifecycle rules to drift.
- Target shape: a single routing contract defines target semantics and
  report-family dispatch, while the ingress controller stays responsible only
  for idempotency/staleness and method-family fan-out.
- Single owner / source of truth: a control-plane routing contract shared by
  mailbox writers, pollers, and report handlers.
- What should be merged / deleted / demoted:
  - merge control-plane and durable-target interpretation into one rule family
  - demote payload-shape inference to a legacy compatibility detail, then
    remove it
  - keep report handlers separate by family once routing is explicit
- Migration path:
  1. make mailbox target semantics explicit at write time
  2. route poll and report handling through the same declared targeting rules
  3. split `AgentControl::Report` by message family behind the shared shell
- Risk if left as-is: every new control-plane method will increase the change
  surface of the ingress boundary and make environment-plane growth more brittle.

## Candidate Signals

This section preserves the Round 1 broad-scan discovery pool. Promotion,
clustering, and retirement status live in the cumulative register.

### Candidate: Conversation model is carrying too many architecture roles
- Category: `layering`
- Why suspicious: `Conversation` is not only a persistence model. It also acts
  as transcript projection engine, lineage walker, visibility overlay resolver,
  historical anchor validator, and runtime-contract access point.
- Evidence: `core_matrix/app/models/conversation.rb`; `core_matrix/test/models/conversation_test.rb`
- Possible impact: More phase work will keep accreting rules onto one model,
  making it harder to see which invariants are domain-level, projection-level,
  or workflow/runtime-level.
- Counterpoint: Conversation is a genuine aggregate root, so some cross-cutting
  invariants do belong there.
- Suggested direction: Separate projection and lineage-calculation helpers from
  row-level validation and identity concerns, while keeping the aggregate root
  authoritative for true conversation invariants.
- Related concepts: transcript projection, historical anchors, visibility
  overlays, runtime contract, lineage provenance

### Candidate: AgentControl::Report is becoming a multi-protocol sink
- Category: `layering`
- Why suspicious: One service handles idempotent receipt creation, stale-report
  detection, execution lifecycle updates, lease heartbeats, close acknowledgments,
  close terminalization, and mailbox poll responses.
- Evidence: `core_matrix/app/services/agent_control/report.rb`
- Possible impact: New control-plane events will tend to land in the same file,
  increasing change surface and making one report path harder to reason about in
  isolation.
- Counterpoint: There is value in one intake boundary for agent control
  reports, especially for duplicate and stale handling.
- Suggested direction: Keep one intake boundary, but split per-method report
  handlers behind a shared receipt/staleness shell.
- Related concepts: mailbox control, execution reports, close reports,
  idempotency receipts, leases

### Candidate: ProviderExecution::ExecuteTurnStep crosses too many boundaries at once
- Category: `contracts`
- Why suspicious: The service performs provider I/O, stale-state validation,
  transcript output writing, usage accounting, execution profiling, and
  lifecycle terminalization in one class.
- Evidence: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Possible impact: Provider execution becomes the place where unrelated policy
  changes accumulate, making it hard to evolve request transport, transcript
  semantics, and telemetry independently.
- Counterpoint: The write path is transaction-sensitive, so some coordination
  is unavoidable.
- Suggested direction: Keep one transaction boundary, but narrow the service to
  orchestration and delegate transcript, usage, and profiling writes to smaller
  collaborators with explicit contracts.
- Related concepts: provider execution, output variants, usage events,
  execution profiling, stale execution fencing

### Candidate: ManualResume and ManualRetry look like sibling workflows without a shared recovery abstraction
- Category: `contracts`
- Why suspicious: Both services validate paused recovery state, enter the same
  mutable workflow context, switch deployment context, and then diverge late
  into either resume or retry behavior.
- Evidence: `core_matrix/app/services/workflows/manual_resume.rb`; `core_matrix/app/services/workflows/manual_retry.rb`; `core_matrix/test/services/workflows/manual_resume_test.rb`; `core_matrix/test/services/workflows/manual_retry_test.rb`
- Possible impact: Recovery behavior may keep drifting into two near-parallel
  implementations with slightly different safety checks or audit metadata.
- Counterpoint: Resume and retry do end in materially different state
  transitions, so they should not be collapsed into one opaque method.
- Suggested direction: Extract a shared recovery-target and deployment-switch
  preparation layer, then keep resume-specific and retry-specific transitions
  separate.
- Related concepts: paused recovery, mutable workflow context, deployment
  switching, selector recovery, audit logging

### Candidate: Scheduler namespace mixes graph scheduling with turn mutation policy
- Category: `layering`
- Why suspicious: `Workflows::Scheduler` holds runnable-node selection,
  during-generation queue/restart policy, and expected-tail guard behavior in
  one namespace with nested classes.
- Evidence: `core_matrix/app/services/workflows/scheduler.rb`; `core_matrix/test/services/workflows/scheduler_test.rb`
- Possible impact: More policy will gather under the broad "scheduler" name
  even when it is really queue mutation or turn-entry policy, not graph
  scheduling.
- Counterpoint: The nested-class split keeps the current file somewhat
  organized, and these behaviors do all influence workflow progress.
- Suggested direction: Preserve graph scheduling as one owner, but consider
  moving queue/restart and expected-tail invalidation into names that describe
  mutation policy rather than scheduling.
- Related concepts: runnable selection, during-generation policy, queue follow
  up, expected tail guard, wait-state release

### Candidate: PurgeDeleted and PurgePlan form a hand-built ownership graph engine
- Category: `complexity`
- Why suspicious: Purge is implemented as a long explicit ownership collector
  and deletion graph that knows about publication rows, agent-control rows,
  runtime rows, transcript rows, attachments, and structural rows.
- Evidence: `core_matrix/app/services/conversations/purge_deleted.rb`; `core_matrix/app/services/conversations/purge_plan.rb`; `core_matrix/test/services/conversations/purge_deleted_test.rb`
- Possible impact: Every new owned resource type may require edits in several
  purge methods and tests, increasing the odds of silent drift between
  ownership rules and teardown rules.
- Counterpoint: Fail-closed explicit deletion can be safer than broad
  association cascades in a kernel that owns durable lineage and runtime state.
- Suggested direction: Keep explicit purge ownership, but model owned-resource
  families more declaratively so new resources extend a registry instead of a
  growing bespoke collector.
- Related concepts: purge ownership graph, quiescence, mailbox residue,
  runtime rows, attachment teardown

### Candidate: ProviderCatalog::Validate is acting like a local schema engine
- Category: `complexity`
- Why suspicious: The validator contains format rules, type rules, defaulting
  behavior, enum-like constraints, and nested shape validation for provider,
  model, role, capability, and request-default payloads in one monolithic
  service.
- Evidence: `core_matrix/app/services/provider_catalog/validate.rb`; `core_matrix/test/services/provider_catalog/validate_test.rb`
- Possible impact: Catalog evolution may require editing one large validator
  that behaves like an internal framework, which raises maintenance cost and
  obscures the catalog contract.
- Counterpoint: A provider catalog is inherently schema-heavy, and one strict
  validation boundary is valuable.
- Suggested direction: Split the validator by provider/model/role sections or
  move the schema description into a more declarative structure while keeping
  one entrypoint.
- Related concepts: provider catalog, model roles, request defaults,
  capabilities, schema validation

### Candidate: Test context builders are becoming a parallel architecture language
- Category: `test-reverse-view`
- Why suspicious: Many service and integration tests depend on large helper
  families like `create_workspace_context!`, `build_human_interaction_context!`,
  `build_agent_control_context!`, `prepare_workflow_execution_setup!`, and
  scenario builders to express ordinary behavior.
- Evidence: `core_matrix/test/test_helper.rb`; `core_matrix/test/services/workflows/manual_resume_test.rb`; `core_matrix/test/services/conversations/purge_deleted_test.rb`; `core_matrix/test/services/agent_control/poll_test.rb`
- Possible impact: Tests may remain expressive only for contributors who know
  the helper DSL, while production boundaries grow harder to exercise directly
  and reason about locally.
- Counterpoint: Shared context builders do reduce repeated fixture boilerplate
  in a domain with legitimately rich setup.
- Suggested direction: Keep a few canonical scenario builders, but reduce the
  number of overlapping context factories and make the dominant setup paths
  map more directly to production contracts.
- Related concepts: test helper DSL, scenario builders, workflow execution
  contexts, agent control contexts, fixture choreography

### Candidate: Lock and freshness contracts are similar but not obviously composed
- Category: `contracts`
- Why suspicious: `Conversations::WithMutableStateLock`,
  `Workflows::WithMutableWorkflowContext`, `Workflows::WithLockedWorkflowContext`,
  `Turns::WithTimelineMutationLock`, and
  `ProviderExecution::ExecuteTurnStep#with_fresh_execution_state_lock` all
  implement related lock-and-revalidate patterns with slightly different shapes
  and ownership boundaries.
- Evidence: `core_matrix/app/services/conversations/with_mutable_state_lock.rb`; `core_matrix/app/services/workflows/with_mutable_workflow_context.rb`; `core_matrix/app/services/workflows/with_locked_workflow_context.rb`; `core_matrix/app/services/turns/with_timeline_mutation_lock.rb`; `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Possible impact: the system can end up with several near-parallel freshness
  contracts that stay conceptually aligned only by convention, not by one clear
  composition model.
- Counterpoint: each path does need different locked records and different
  staleness checks, so one shared helper might be too blunt.
- Suggested direction: treat these as one contract family and clarify which
  pieces are shared primitives versus specialized wrappers, especially around
  lock order and stale-result rejection.
- Related concepts: mutable state lock, workflow context lock, timeline
  mutation, stale execution, lock order

### Candidate: Runtime snapshot shape has no single obvious owner
- Category: `complexity`
- Implementation update: resolved later by introducing
  `TurnExecutionSnapshot` and `Workflows::BuildExecutionSnapshot` as the
  single runtime snapshot contract family.
- Why suspicious: `Turn` exposed many readers over nested snapshot hashes while
  workflow snapshot assembly lived in a separate builder layer and other
  services depended on pieces of it. The snapshot looked important enough to be
  a first-class concept, but it was split across a row, assembly code, and
  downstream hash consumers.
- Evidence: `core_matrix/app/models/turn.rb`; `core_matrix/app/services/workflows/build_execution_snapshot.rb`; `core_matrix/app/services/provider_execution/build_request_context.rb`; `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Possible impact: snapshot-shape changes may fan out across helpers and tests,
  and it becomes hard to tell whether a field is part of a durable contract or
  just an incidental hash entry.
- Counterpoint: for a Rails app, persisting and reading structured hashes
  directly can be a pragmatic way to move quickly without adding more classes.
- Suggested direction: make runtime snapshot shape more explicit, either with a
  dedicated projection object or at least a narrower serialization boundary that
  owns field names and invariants.
- Related concepts: resolved config snapshot, execution context, model context,
  provider execution, runtime attachment manifest

### Candidate: Mailbox targeting semantics depend on payload inference
- Category: `contracts`
- Why suspicious at audit time: `AgentControlMailboxItem` partly read
  control-plane and target meaning from explicit fields and partly inferred
  them from payload conventions such as `resource_type == "ProcessRun"`.
- Evidence: `core_matrix/app/models/agent_control_mailbox_item.rb`; `core_matrix/app/services/agent_control/resolve_target_runtime.rb`; `core_matrix/app/services/agent_control/create_resource_close_request.rb`
- Possible impact: as environment-plane work grows, mailbox routing can become
  increasingly convention-driven instead of contract-driven, which makes the
  protocol harder to extend safely.
- Counterpoint: the current inference rule is small and may simply reflect a
  still-narrow protocol surface.
- Suggested direction: push control-plane and target semantics into an explicit
  write-time contract so the model validates declared intent instead of
  reconstructing it from payload shape.
- Related concepts: mailbox items, control plane, target resolution, resource
  close requests, environment plane

### Candidate: Close progression is distributed across several writers
- Category: `contracts`
- Why suspicious: close initiation, turn interruption, background resource
  close requests, summary reconciliation, and final purge readiness are spread
  across several services that together define one lifecycle family.
- Evidence: `core_matrix/app/services/conversations/request_close.rb`; `core_matrix/app/services/conversations/reconcile_close_operation.rb`; `core_matrix/app/services/conversations/request_turn_interrupt.rb`; `core_matrix/app/services/conversations/purge_deleted.rb`; `core_matrix/app/services/conversations/purge_plan.rb`
- Possible impact: the close/dispose model may remain correct but difficult to
  reason about because there is no single obvious owner for progression
  semantics across request, quiesce, reconcile, and purge phases.
- Counterpoint: these phases are genuinely distinct, and collapsing them into
  one service would likely be worse.
- Suggested direction: keep the phases separate, but clarify one conversation
  lifecycle contract that defines which service owns which transition and which
  facts are merely derived.
- Related concepts: close operation, quiescence, resource close requests, purge,
  lifecycle ownership

## Healthy Patterns Worth Preserving

- `AgentAPI` controllers are still comparatively thin. They mostly authenticate,
  locate durable resources by `public_id`, and delegate real work into services.
- Query objects remain clearer than the service layer overall. For example,
  `Conversations::CloseSummaryQuery` is doing read-side aggregation rather than
  mutating lifecycle.
- The close model already has one strong idea worth preserving:
  `Conversations::ReconcileCloseOperation` is the single lifecycle-state writer
  for close progression even though many services feed facts into it.
- The purge graph is intentionally explicit and fail-closed. That may be heavy,
  but it is safer than broad cascading deletes in a kernel with lineage and
  runtime residue.
- Machine-facing and snapshot-facing paths consistently prefer `public_id`
  instead of internal relational ids.

## Simplification / Reinforcement Backlog

- Simplify:
  - extract a paused-recovery preparation layer shared by manual resume and
    manual retry
  - break `AgentControl::Report` into family-specific handlers behind one shell
  - narrow provider execution orchestration by stage, not by one larger method
- Reinforce:
  - define one execution-snapshot contract owner
  - define one control-plane routing contract owner
  - make mailbox targeting semantics explicit at write time
- Observe before acting:
  - scheduler namespace drift versus intentional grouping
  - provider-catalog validator size versus justified schema complexity
  - test-helper DSL growth and whether it can be reduced without losing clarity

## Suggested Focus For The Next Round

- Re-run the broad scan after any cleanup touching execution snapshots, mailbox
  routing, or paused recovery.
- Add a dedicated round focused only on query/model ownership boundaries so
  service-heavy review bias does not dominate the long-term audit.
- Re-check whether the purge graph still feels like justified explicitness or is
  starting to become an extension tax for every new runtime-owned row.
- Track whether candidate items AH-005, AH-007, AH-008, and AH-009 strengthen,
  weaken, or collapse into the two current unification opportunities.

## Completeness Check

- Completed this round:
  - durable register created
  - round report created
  - broad scan candidates collected across layering, contracts, complexity, and
    test reverse view
  - main-thread review completed against hotspot code, tests, and behavior docs
  - confirmed findings and unification opportunities written with corrective
    direction
- Still candidate-only after reverse review:
  - scheduler namespace drift
  - provider catalog validator complexity
  - lock/freshness contract family composition
  - test-helper DSL overlap
- Weakened by reverse review:
  - purge explicitness is partly deliberate and currently defensible
  - close progression already has an explicit reconciler, so the stronger claim
    is about routing and surrounding ownership, not lack of any single writer
- Remaining blind spots:
  - no dedicated browser/UI layer review
  - no second round yet focused only on query purity and read-side ownership
  - recovery and scheduler surfaces are currently under active local
    modification, so those judgments should be treated as current-workspace
    observations rather than a frozen baseline
