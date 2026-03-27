# Core Matrix Phase 2 Architecture Health Audit Follow-Up Findings

## Scope

- This is a whole-application audit of `core_matrix`.
- The primary review surfaces are `app/models`, `app/services`, `app/queries`,
  `app/controllers`, and `test`.
- The method is `six-boundary review + anti-pattern cross-check`.
- This work lands as a Milestone C follow-up.
- The frozen execution root shape remains
  `Conversation -> Turn -> WorkflowRun -> WorkflowNode`.
- Current code volume is concentrated in `app/services` (`142` files),
  `app/models` (`59`), `test/services` (`102`), `test/models` (`55`), and
  `test/integration` (`34`).
- The heaviest service namespaces are `conversations` (`33` files),
  `agent_control` (`22`), `workflows` (`13`), `agent_deployments` (`11`), and
  `turns` (`11`).
- The six audit boundaries for this pass were conversation and lifecycle,
  workflow and execution graph, runtime control plane, runtime binding and
  deployments, provider and governance, and read side and projection.
- Recent hardening work concentrated around close reconciliation, runtime
  binding, conversation mutation safety, and lineage or provenance contracts.

## System Judgment

The current Core Matrix architecture is broadly healthy. The major ownership
lines are explicit, the Phase 2 hardening work has removed the worst category
of severe lifecycle regressions, and the system now names its runtime, close,
and lineage contracts more clearly than it did earlier in the batch.

The main architecture risk is no longer hidden severe breakage. It is rising
contract-shape complexity. Several critical boundaries still rely on large raw
`Hash` payload families, several mutation-safety helpers overlap without yet
collapsing into one obvious guard layer, and runtime capability assembly is now
fragmented enough that future breadth could create drift. None of that is an
immediate emergency, but it is exactly the kind of accidental complexity that
gets expensive if the next follow-up adds more runtime or provider surface area
before the contracts are tightened.

## Findings

### Core lifecycle and runtime contracts still depend on loosely typed `Hash` families
- Why it matters:
  The system's most important runtime and lifecycle contracts are still carried
  through raw JSON-shaped hashes whose real schema lives in scattered readers,
  writers, and tests rather than behind explicit domain objects.
- Evidence:
  `app/models/turn.rb` validates `origin_payload`,
  `resolved_config_snapshot`, `execution_snapshot_payload`, and
  `resolved_model_selection_snapshot` mostly as "must be a hash" while also
  exposing key-specific readers such as `normalized_selector` and
  `resolved_provider_handle`. `app/models/workflow_run.rb` does the same for
  `wait_reason_payload` and `resume_metadata`. `app/models/conversation_close_operation.rb`
  does the same for `summary_payload`. Runtime capability state is likewise
  split across `app/models/execution_environment.rb`,
  `app/models/capability_snapshot.rb`, and their tool catalog and capability
  payload hashes. Service code then reaches directly into these shapes in
  `app/services/provider_execution/build_request_context.rb`,
  `app/services/agent_deployments/auto_resume_workflows.rb`,
  `app/controllers/agent_api/capabilities_controller.rb`, and many turn-entry
  helpers. The tests reinforce the same contract style in
  `test/services/provider_execution/build_request_context_test.rb`,
  `test/services/provider_execution/execute_turn_step_test.rb`,
  `test/services/agent_deployments/auto_resume_workflows_test.rb`, and the
  turn-history rewrite suites.
- Impact:
  Schema changes now have to be reasoned about across models, service objects,
  controllers, and tests at once. The source of truth for a field is often the
  combination of several readers rather than one contract object, which makes
  drift and accidental compatibility layers more likely.
- Suggested direction:
  Introduce explicit contract objects or builder families for the highest-value
  payload groups first: turn execution context, workflow wait and recovery
  state, close summary state, and runtime capability payloads. Keep JSON
  persistence as the storage detail, but stop making callers depend on
  free-form hashes as the primary domain API.

### Mutation safety is still split across overlapping guard and lock helper families
- Why it matters:
  The system has done real work to centralize lifecycle checks, but callers
  still have to choose among several similar helper families whose boundaries
  are not yet obvious enough to prevent local re-implementation.
- Evidence:
  Conversation-local mutation uses `app/services/conversations/validate_mutable_state.rb`
  and `app/services/conversations/with_mutable_state_lock.rb`. Turn-history
  mutation uses `app/services/turns/validate_timeline_mutation_target.rb` and
  `app/services/turns/with_timeline_mutation_lock.rb`. Workflow mutation adds
  `app/services/workflows/with_mutable_workflow_context.rb` plus
  `app/services/workflows/with_locked_workflow_context.rb`. At the same time,
  `app/services/turns/start_user_turn.rb` and
  `app/services/turns/queue_follow_up.rb` still hand-roll
  `conversation.with_lock` plus `Conversations::ValidateMutableState.call`
  instead of joining a single obvious turn-entry guard. `app/services/conversations/rollback_to_turn.rb`
  reaches a different helper stack again. Tests such as
  `test/services/turns/validate_timeline_mutation_target_test.rb` verify one
  guard family in isolation, which confirms the helpers exist, but also shows
  how much of the contract is still spread across multiple entry points.
- Impact:
  Future callers have to decide which helper family to join, in what order, and
  whether they still need local locking or validation on top. That keeps the
  guard model understandable only to someone who already knows the current
  layering. It also increases the chance that the next mutation path bypasses a
  needed fence by choosing the wrong helper or by re-implementing the contract
  inline.
- Suggested direction:
  Collapse the current helpers into a smaller, more explicit mutation-guard
  surface organized by subject, not by historical rollout. For example,
  separate `conversation mutable`, `turn timeline mutable`, and
  `workflow mutable` guards, but make each one visibly delegate to one shared
  lifecycle contract and one clearly documented lock order. Then route turn
  entry, rollback, retry, rerun, and workflow recovery through those named
  gates instead of mixing direct locking with helper composition.

## Simplification / Reinforcement Opportunities

### Runtime capability assembly is fragmented across models, services, and controllers
- Why it matters:
  Capability-related payloads are now assembled in several adjacent places that
  represent the same runtime concept from slightly different angles.
- Evidence:
  `app/models/capability_snapshot.rb` exposes both `as_contract_payload` and
  `as_agent_plane_payload`. `app/models/execution_environment.rb` exposes
  `as_runtime_plane_payload`. `app/controllers/agent_api/capabilities_controller.rb`
  then builds a separate response shape that merges snapshot payload,
  environment-plane payload, and `effective_tool_catalog`. Conversation-facing
  runtime contract assembly lives separately in
  `app/services/runtime_capabilities/compose_for_conversation.rb` and
  `app/services/runtime_capabilities/compose_effective_tool_catalog.rb`.
  `app/controllers/agent_api/registrations_controller.rb`,
  `app/services/agent_deployments/register.rb`, and
  `app/services/agent_deployments/handshake.rb` also participate in shaping the
  same runtime-capability family. The test split between
  `test/services/runtime_capabilities/compose_for_conversation_test.rb`,
  `test/requests/agent_api/capabilities_test.rb`, and
  `test/requests/agent_api/registrations_test.rb` shows the same concept being
  verified through multiple adjacent payload surfaces.
- Impact:
  Handshake, capability refresh, registration, and conversation runtime
  contracts can drift even when each local change looks reasonable. It is also
  harder to answer which representation is canonical and which are just views.
- Suggested direction:
  Create one explicit runtime capability contract builder with named projections
  for registration, handshake or refresh, and conversation use. Keep models and
  controllers thin by delegating shape assembly to that builder family.

### Provider-backed turn execution is already concentrated in one large orchestration service
- Why it matters:
  The provider-backed path is still intentionally narrow, but the main
  orchestration object already owns too many concerns to grow comfortably.
- Evidence:
  `app/services/provider_execution/execute_turn_step.rb` is `307` lines and
  currently owns precondition validation, provider client setup, external API
  dispatch, freshness locking, transcript output creation, provider usage
  recording, profiling fact recording, turn and workflow terminal transitions,
  and workflow-node status events. `app/services/provider_execution/build_request_context.rb`
  already exists as one collaborator, which is a sign that the service is doing
  enough work to justify decomposition. The tests in
  `test/services/provider_execution/build_request_context_test.rb` and
  `test/services/provider_execution/execute_turn_step_test.rb` are still
  readable, but they also confirm that one object is coordinating most of the
  provider path.
- Impact:
  As provider breadth grows, changes to request wiring, usage accounting,
  terminal state progression, or error handling are likely to keep landing in
  the same choke point. That increases the chance that one future provider
  feature couples transport details to persistence and profiling side effects.
- Suggested direction:
  Keep one top-level entrypoint, but split collaborators for request dispatch,
  response normalization, and terminal persistence or fact recording. That would
  preserve the freshness fence while reducing the cost of adding provider
  breadth later.

## Top Structural Priorities

1. Replace the highest-value raw `Hash` contract families with explicit runtime,
   wait-state, close-summary, and execution-context contract objects.
2. Collapse the current mutable-state and timeline-mutation helper stack into a
   smaller, named guard layer with one clear lock and validation model.
3. Unify runtime capability contract assembly so registration, handshake,
   capability refresh, and conversation runtime composition project from one
   canonical shape.

## Completeness Check

- The whole current `core_matrix` application was covered through the planned
  six-boundary model.
- Conversation and lifecycle, workflow and execution graph, runtime control
  plane, runtime binding and deployments, provider and governance, and read side
  and projection were all reviewed against both implementation and behavior
  docs.
- The anti-pattern cross-check was run with focused searches over lock usage,
  transactions, payload families, lifecycle terms, and large production files.
- Tests were used as reverse evidence, especially
  `test/services/turns/validate_timeline_mutation_target_test.rb`,
  `test/services/provider_execution/build_request_context_test.rb`,
  `test/services/provider_execution/execute_turn_step_test.rb`,
  `test/services/agent_deployments/auto_resume_workflows_test.rb`,
  `test/services/runtime_capabilities/compose_for_conversation_test.rb`,
  `test/requests/agent_api/capabilities_test.rb`, and
  `test/requests/agent_api/registrations_test.rb`.
- Candidate-only signals that were not promoted included "the `Conversation`
  model is large" by itself and "the `AgentAPI::BaseController` is centralized"
  by itself, because neither point cleared the evidence bar without leaning on
  taste-based judgment.
- Every promoted item includes evidence and a concrete action direction.
- The report ends with exactly three structural priorities.
- The prose was re-read once for flow before this draft was finalized.
