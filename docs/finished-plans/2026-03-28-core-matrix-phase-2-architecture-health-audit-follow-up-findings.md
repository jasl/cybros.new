# Core Matrix Phase 2 Architecture Health Audit Follow-Up Findings

## Scope

- This is an architecture-health audit of the whole current `core_matrix`
  application.
- The primary review surfaces are `app/models`, `app/services`, `app/queries`,
  `app/controllers`, and `test`.
- The method is `six-boundary review + anti-pattern cross-check`.
- This work lands as a Milestone C follow-up.
- The frozen execution root shape is
  `Conversation -> Turn -> WorkflowRun -> WorkflowNode`.
- Current code volume is concentrated in `app/services` (`142` files),
  `app/models` (`59`), `test/services` (`102`), `test/models` (`55`), and
  `test/integration` (`34`).
- The heaviest service namespaces are `conversations` (`33` files),
  `agent_control` (`22`), `workflows` (`13`), `agent_deployments` (`11`), and
  `turns` (`11`).
- The six audit boundaries for this pass are conversation and lifecycle,
  workflow and execution graph, runtime control plane, runtime binding and
  deployments, provider and governance, and read side and projection.
- Recent hardening work concentrated around close reconciliation, runtime
  binding, conversation mutation safety, and lineage or provenance contracts.

## System Judgment

The current architecture is broadly healthy. The important Phase 2 boundaries
are explicit, and the system does not read like provider logic, runtime
control, and conversation lifecycle were collapsed into one undifferentiated
kernel. Most of the necessary complexity is concentrated where the product
actually needs it: conversation lifecycle, workflow execution, mailbox control,
and deployment recovery.

The drift now is subtler. The main risk is no longer missing boundaries; it is
that a few hotspot services and guard families are beginning to absorb too many
adjacent responsibilities. The architecture still feels governable, but it is
close enough to that hotspot threshold that the next cleanup batch should favor
structural consolidation over another round of narrow defect patching.

## Findings

### Provider-backed turn execution is already a cross-boundary hotspot
- Why it matters:
  `ProviderExecution::ExecuteTurnStep` already owns transport setup, provider
  request dispatch, stale-result fencing, transcript mutation, usage
  accounting, profiling, workflow-node status events, and terminal turn or
  workflow progression. That is too much responsibility for the first real
  provider path, and every new provider feature will naturally accumulate in
  the same place.
- Evidence:
  `core_matrix/app/services/provider_execution/execute_turn_step.rb`,
  `core_matrix/app/services/provider_execution/build_request_context.rb`,
  `core_matrix/app/services/provider_usage/record_event.rb`,
  `core_matrix/app/services/workflows/build_execution_snapshot.rb`, and
  `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`.
- Impact:
  Adding new wire APIs, multimodal behavior, richer failure modes, or more
  telemetry will keep coupling transport concerns to persistence and reporting
  side effects. The test seam is already broad enough that even targeted
  behavior changes require large setup scaffolding.
- Suggested direction:
  Keep one public entrypoint, but split request dispatch, response
  normalization, and terminal persistence or fact recording into narrower
  collaborators so provider breadth does not keep widening one service object.

### Workflow recovery and deployment auto-resume are becoming one control tower
- Why it matters:
  The outage and recovery path is spread across deployment predicates, pause
  snapshot helpers, drift classification, rebinding, execution snapshot
  rewrites, escalation to manual recovery, and audit logging. The behavior is
  still coherent, but too much of the recovery story now lives inside one
  orchestration surface.
- Evidence:
  `core_matrix/app/services/agent_deployments/auto_resume_workflows.rb`,
  `core_matrix/app/services/agent_deployments/mark_unavailable.rb`,
  `core_matrix/app/services/agent_deployments/unavailable_pause_state.rb`,
  `core_matrix/app/models/agent_deployment.rb`, and
  `core_matrix/test/services/agent_deployments/auto_resume_workflows_test.rb`.
- Impact:
  New drift reasons, blocker types, or rotation rules will require edits across
  planning, mutation, and audit paths at once. That increases the risk of
  resume semantics drifting away from pause semantics and keeps the recovery
  surface hard to test in smaller units.
- Suggested direction:
  Introduce an explicit recovery planner or state machine that owns pause
  snapshot semantics, drift classification, and resume versus escalate
  decisions, while keeping a small top-level service as the public orchestrator.

### Lifecycle and mutation safety still depend on a fragmented guard family
- Why it matters:
  Core Matrix now has explicit lifecycle guards, which is good, but the guard
  family is split across retained-state validation, mutable-state validation,
  mutable-state locks, workflow wrappers, timeline-mutation wrappers, work
  barrier queries, and close summaries. Callers still need to know which guard
  flavor to choose instead of having one obvious entry point per mutation
  intent.
- Evidence:
  `core_matrix/app/services/conversations/validate_mutable_state.rb`,
  `core_matrix/app/services/conversations/with_mutable_state_lock.rb`,
  `core_matrix/app/services/workflows/with_mutable_workflow_context.rb`,
  `core_matrix/app/services/turns/with_timeline_mutation_lock.rb`,
  `core_matrix/app/services/turns/validate_timeline_mutation_target.rb`,
  `core_matrix/app/services/turns/start_user_turn.rb`,
  `core_matrix/app/services/turns/queue_follow_up.rb`,
  `core_matrix/app/services/turns/start_automation_turn.rb`,
  `core_matrix/app/services/human_interactions/request.rb`,
  `core_matrix/app/queries/conversations/work_barrier_query.rb`,
  `core_matrix/app/queries/conversations/close_summary_query.rb`,
  and `core_matrix/app/services/conversations/reconcile_close_operation.rb`.
- Impact:
  Future lifecycle work can join the wrong helper, duplicate one more variant,
  or let enforcement logic and operator summary logic drift apart. The design
  is explicit, but the helper topology remains harder to read than it should
  be.
- Suggested direction:
  Collapse the guard family into a smaller set of named contracts with one
  obvious entry point per intent, and derive operator summaries from the same
  blocker model used by enforcement paths.

## Simplification / Reinforcement Opportunities

### The `Query` namespace is carrying multiple kinds of objects
- Why it matters:
  Objects named `*Query` currently range from straightforward database lookups
  to in-memory assemblers and live projection builders. That makes naming less
  informative than it should be at the exact moment the read side is getting
  more important.
- Evidence:
  `core_matrix/app/queries/workspace_variables/list_query.rb`,
  `core_matrix/app/queries/conversation_variables/resolve_query.rb`,
  `core_matrix/app/queries/conversation_transcripts/list_query.rb`, and
  `core_matrix/app/queries/publications/live_projection_query.rb`.
- Impact:
  New read paths will likely continue copying mixed patterns, and engineers
  cannot infer cost, composition style, or ownership just from the class name.
- Suggested direction:
  Split the read side into clearer categories such as raw queries, projections,
  and resolvers or assemblers, or define and enforce a naming contract that
  makes the distinction explicit.

### Runtime capability assembly still lacks one canonical contract builder
- Why it matters:
  Environment capability payloads, environment tool catalogs, deployment
  capability snapshots, effective tool catalog composition, and
  conversation-facing runtime state are all handled in adjacent places, but
  no single object clearly owns the end-to-end capability shape.
- Evidence:
  `core_matrix/app/models/execution_environment.rb`,
  `core_matrix/app/services/execution_environments/record_capabilities.rb`,
  `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`,
  `core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb`,
  `core_matrix/app/controllers/agent_api/capabilities_controller.rb`, and
  `core_matrix/app/models/agent_deployment.rb`.
- Impact:
  As the runtime surface grows, normalization order and projection semantics can
  drift even when each local payload change looks harmless.
- Suggested direction:
  Introduce one runtime-capability contract namespace that owns validation,
  merge order, and named outward projections for registration, handshake or
  refresh, and conversation use.

### High-value runtime contracts still lean heavily on raw `Hash` payloads
- Why it matters:
  The system's most important evolving contracts are often persisted as generic
  hashes with their real schema spread across readers, writers, and tests. That
  flexibility was useful during Phase 2 hardening, but it is starting to hide
  the contract boundaries that now need to stay stable.
- Evidence:
  `core_matrix/app/models/turn.rb`,
  `core_matrix/app/models/workflow_run.rb`,
  `core_matrix/app/models/execution_environment.rb`,
  `core_matrix/app/services/agent_deployments/unavailable_pause_state.rb`,
  `core_matrix/app/services/human_interactions/request.rb`,
  `core_matrix/app/services/provider_execution/build_request_context.rb`, and
  `core_matrix/test/services/provider_execution/build_request_context_test.rb`.
- Impact:
  Changing one field often requires coordinated edits across models, services,
  queries, controllers, and tests, and the safe change surface is not obvious
  from the code.
- Suggested direction:
  Keep JSON persistence, but introduce explicit builders or small contract
  objects for the highest-value payload families first: execution snapshot
  context, workflow wait or recovery state, runtime capability state, and close
  summary state.

### Provider request-setting rules are still split across multiple owners
- Why it matters:
  Supported request-default keys live in catalog validation, allowed execution
  settings live in provider request-context code, and final setting selection is
  assembled again when building the execution snapshot. The contract is still
  consistent, but its schema is not owned in one place.
- Evidence:
  `core_matrix/app/services/provider_catalog/validate.rb`,
  `core_matrix/app/services/provider_execution/build_request_context.rb`,
  `core_matrix/app/services/workflows/build_execution_snapshot.rb`, and
  `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`.
- Impact:
  Adding a new provider-facing setting or a second wire API requires edits in
  multiple files, making drift more likely than it needs to be.
- Suggested direction:
  Promote per-wire-API request-setting schema into one explicit contract object
  that both catalog validation and execution snapshot assembly consume.

## Top Structural Priorities

1. Break the two orchestration hotspots first: provider-backed turn execution
   and deployment outage recovery.
2. Collapse lifecycle and mutation safety onto one smaller canonical blocker and
   guard family.
3. Introduce explicit contract builders for the highest-value hash payloads and
   provider request-setting schema.

## Completeness Check

- The whole current `core_matrix` architecture was reviewed through the stated
  primary surfaces, with secondary docs and planning artifacts used where the
  code needed contract confirmation.
- All six boundaries were reviewed against both implementation and neighboring
  tests.
- The anti-pattern cross-check ran across lock, transaction, payload, and
  lifecycle keywords.
- Tests were used as reverse evidence before promoting any item into the final
  report.
- Every reported item includes evidence and an action direction.
- The report ends with exactly three structural priorities.
- The document was re-read once for prose flow before this checkpoint.
