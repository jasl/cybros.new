# Core Matrix Phase 2 Iterative Architecture Health Refresh Findings

## Scope

- This is a whole-system audit of the current `core_matrix`.
- The method is `mixed refresh + iterative scanning`.
- The work reconciles earlier audit conclusions against current code.
- The work is a Phase 2 mid-flight cleanup audit where destructive follow-up is
  acceptable.
- The frozen execution root shape is
  `Conversation -> Turn -> WorkflowRun -> WorkflowNode`.
- Current code volume is concentrated in `app/services` (`155` files),
  `app/models` (`65`), `test/services` (`112`), `test/models` (`61`),
  `test/integration` (`33`), and `app/queries` (`24`).
- The heaviest current service namespaces are `conversations` (`33` files),
  `agent_control` (`22`), `agent_deployments` (`13`), `workflows` (`13`),
  `turns` (`12`), `subagent_connections` (`7`), and `provider_execution` (`6`).
- Earlier consolidation work appears to have materially addressed the
  request-setting split, blocker-summary projection drift, and machine-facing
  runtime capability formatting by introducing `ProviderRequestSettingsSchema`,
  `ConversationBlockerSnapshot`, and `RuntimeCapabilityContract`.
- Earlier hotspot findings around provider turn execution, deployment recovery,
  and mutation-guard sprawl still look residual enough to require direct
  re-verification against current code rather than being treated as resolved.
- Newer surfaces that now require deeper review are `SubagentConnection`,
  conversation-facing runtime capability composition, close and reconcile
  control, execution snapshot shaping, and the `core_matrix <-> agents/fenix`
  runtime boundary.

## System Judgment

The current `core_matrix` shape is still governable, but the architecture is no
longer drifting around the original Milestone C hotspots that dominated the
earlier audit. Provider request-setting ownership, blocker-summary projection,
and machine-facing capability formatting are materially more coherent than they
were in the earlier follow-up.

The current pressure is concentrated in the newest delegation and runtime
contract surfaces. The system is now most exposed where recovery, runtime
capability preservation, subagent close control, and the `core_matrix <-> fenix`
boundary overlap. Those are exactly the seams where another round of feature
work would harden accidental complexity into durable protocol shape.

## Confirmed Findings

### Residual Earlier Findings

#### Deployment recovery still has duplicate rebinding authority

- Priority: `Act Now`
- Why it matters: recovery planning, capability validation, selector
  re-resolution, deployment switching, and execution-snapshot rewrites are
  still spread across separate services instead of one obvious recovery
  contract.
- Evidence:
  `core_matrix/app/services/agent_deployments/build_recovery_plan.rb`,
  `core_matrix/app/services/agent_deployments/apply_recovery_plan.rb`,
  `core_matrix/app/services/workflows/manual_resume.rb`, and
  `core_matrix/app/services/conversations/validate_agent_deployment_target.rb`.
- Structural impact: the same recovery semantics now have multiple edit sites,
  so runtime-drift fixes can land in one path and silently miss the others.
  The newer capability-preservation gap is a direct symptom of that split.
- Action direction: centralize recovery compatibility checks, selector
  re-resolution, deployment rebinding, and snapshot rebuilds behind one shared
  recovery contract that both auto-resume and manual recovery use.

### Newly Discovered Findings

#### Capability-preservation checks are narrower than the runtime contract they claim to protect

- Priority: `Act Now`
- Why it matters: recovery and manual rebinding currently treat
  "capability contract preserved" as method-name and tool-name continuity, but
  the actual runtime contract also includes profile catalog, config schema,
  override schema, and default config.
- Evidence:
  `core_matrix/app/models/agent_deployment.rb`,
  `core_matrix/app/services/agent_deployments/build_recovery_plan.rb`,
  `core_matrix/app/services/conversations/validate_agent_deployment_target.rb`,
  `core_matrix/app/models/runtime_capability_contract.rb`, and
  `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`.
- Structural impact: a rotated or manually selected deployment can be treated
  as compatible even when conversation-visible tool visibility, profile
  semantics, or override rules have drifted. That makes recovery continuity
  look safer than it is.
- Action direction: replace the current method/tool-name check with one shared
  capability-compatibility comparison over the full runtime capability contract,
  or an explicit reduced contract object that names every field recovery is
  allowed to preserve.

#### `SubagentConnection` close progression is split across two state machines, and one of them has a dead middle state

- Priority: `Act Now`
- Why it matters: the documented and modeled `SubagentConnection` lifecycle says
  `open -> close_requested -> closed`, but the close-request path mutates only
  `close_state`, while terminal close reports jump `lifecycle_state` straight
  from `open` to `closed`.
- Evidence:
  `core_matrix/app/models/subagent_connection.rb`,
  `core_matrix/app/services/subagent_connections/request_close.rb`,
  `core_matrix/app/services/agent_control/create_resource_close_request.rb`,
  `core_matrix/app/services/agent_control/apply_close_outcome.rb`, and
  `core_matrix/docs/behavior/subagent-connections-and-execution-leases.md`.
- Structural impact: session lifecycle is no longer the obvious durable owner
  of session close progression. Queries and guards compensate by mixing
  `lifecycle_state`, `close_state`, and `last_known_status`, which makes
  `SubagentConnection` harder to reason about than the rest of the closable
  runtime surface.
- Action direction: pick one canonical close-progression state model. Either
  make `lifecycle_state` advance through `close_requested` for real, or delete
  that lifecycle state and standardize all session-close readers on
  `ClosableRuntimeResource`.

#### The `core_matrix <-> fenix` execution-context contract drops real model hints on the floor

- Priority: `Good Mid-Phase Cleanup`
- Why it matters: Core Matrix freezes model identity in the execution snapshot,
  but the Fenix runtime reads advisory model hints from fields that Core Matrix
  does not actually send on real assignments.
- Evidence:
  `core_matrix/app/services/workflows/build_execution_snapshot.rb`,
  `core_matrix/app/services/workflows/create_for_turn.rb`,
  `core_matrix/app/services/agent_control/create_execution_assignment.rb`,
  `agents/fenix/app/services/fenix/context/build_execution_context.rb`,
  `agents/fenix/app/services/fenix/hooks/prepare_turn.rb`, and
  `agents/fenix/README.md`.
- Structural impact: compaction and any future model-sensitive runtime
  heuristics cannot trust the actual cross-project execution payload. The
  boundary currently looks richer in docs and local tests than it is in real
  end-to-end traffic.
- Action direction: align the boundary on one model-hint field family and add
  a cross-project contract test that exercises real Core Matrix assignment
  payloads against the Fenix execution-context builder.

## Risk Smells / Reinforcement Opportunities

### Residual Earlier Risk Smells

#### Mutable-state and quiescence enforcement still require callers to know too many wrapper families

- Priority: `Watch Closely`
- Why it matters: blocker facts are now centralized, but the mutation and
  quiescence entrypoints are still split across conversation, workflow, and
  timeline-specific wrappers with slightly different lock and rejection
  surfaces.
- Evidence:
  `core_matrix/app/services/conversations/with_mutable_state_lock.rb`,
  `core_matrix/app/services/workflows/with_mutable_workflow_context.rb`,
  `core_matrix/app/services/turns/with_timeline_mutation_lock.rb`,
  `core_matrix/app/services/turns/validate_timeline_mutation_target.rb`, and
  `core_matrix/app/services/conversations/work_quiescence_guard.rb`.
- Structural impact: new callers still need to choose among several guard
  families instead of one obvious contract per mutation intent. That is better
  than the old state, but it still invites local reinvention.
- Action direction: keep consolidating on blocker-snapshot-driven guards and
  shrink the number of public wrapper entrypoints before the next lifecycle
  batch adds more variants.

### Newly Discovered Risk Smells

#### Capability-snapshot reuse rules are duplicated across registration paths

- Priority: `Watch Closely`
- Why it matters: the equality rules for reusing an existing capability
  snapshot now live in more than one place.
- Evidence:
  `core_matrix/app/services/agent_deployments/handshake.rb` and
  `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`.
- Structural impact: the next runtime capability field addition will require
  parallel edits across both paths or snapshot reuse semantics will drift.
- Action direction: extract one shared capability-snapshot matcher so machine
  registration and bundled runtime bootstrap reuse the same comparison rules.

#### Fenix currently treats `allowed_tool_names` as trace data, not as an execution-time constraint

- Priority: `Watch Closely`
- Why it matters: Core Matrix already computes and freezes visible tool names
  per conversation and subagent profile, but the Fenix runtime does not
  currently consult that list when reviewing or choosing tools.
- Evidence:
  `core_matrix/app/services/workflows/build_execution_snapshot.rb`,
  `agents/fenix/app/services/fenix/hooks/prepare_turn.rb`,
  `agents/fenix/app/services/fenix/hooks/review_tool_call.rb`, and
  `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`.
- Structural impact: the boundary contract is only partially self-enforcing.
  It is safe today because the deterministic runtime path still happens to stay
  inside the currently allowed tool families, but that safety is accidental.
- Action direction: either make Fenix consume `allowed_tool_names` as a real
  policy input, or narrow the boundary so Core Matrix no longer advertises that
  contract as execution-relevant.

## Top Structural Priorities

1. Unify runtime capability preservation and reuse rules so recovery, manual
   rebinding, handshake, and bundled runtime bootstrap all compare the same
   contract surface.
2. Collapse `SubagentConnection` close progression onto one canonical state model
   and remove the split authority between session lifecycle and close-state
   metadata.
3. Repair the `core_matrix <-> fenix` execution-context contract and lock it
   down with cross-project contract tests for model hints and visible-tool
   semantics.

## Round Log

- Round 1 `Baseline Reconciliation`
- Coverage:
  read the iterative refresh design and implementation plan, plans index, the
  earlier architecture-health follow-up design and findings, the structural
  consolidation and repair-loop plans, and current behavior docs for
  conversation lineage, subagent connections, execution snapshots, registration
  handshake, and runtime resource APIs.
- Current-shape baseline:
  captured `app` / `test` directory inventory, top-level file counts, and the
  heaviest service namespaces in current `core_matrix`.
- Earlier work that appears materially resolved in current code:
  centralized provider request-setting contract, blocker snapshot projection,
  and shared runtime capability contract formatting.
- Earlier work that still looks residual and must be re-verified:
  provider execution orchestration, deployment recovery authority, and mutation
  guard-family readability.
- Newer hotspot surfaces queued for deeper review:
  `SubagentConnection`, runtime capability composition, close / reconcile,
  execution snapshot coherence, and the `core_matrix <-> agents/fenix`
  contract.
- New high-confidence candidates this round:
  none promoted yet; Round 1 is a baseline and hypothesis-freezing pass.
- Round 2 `Boundary Review: conversation, workflow, control`
- Coverage:
  reviewed `Conversation`, close-request / turn-interrupt / close-reconcile
  services, workflow mutation-context and manual-resume paths, workflow
  scheduler and wait-state docs, and control-plane report / close-outcome
  handlers plus the corresponding conversation, workflow, and agent-control
  tests.
- Round result:
  no newly discovered high-confidence finding promoted from this boundary pass,
  but the residual guard-family and close-control orchestration concerns stayed
  live and moved forward for hotspot review.
- Earlier findings rejected as no longer current in this round:
  blocker-summary drift is no longer a standalone issue because
  `WorkBarrierQuery` and `CloseSummaryQuery` are both thin projections over
  `ConversationBlockerSnapshot`.
- Round 3 `Boundary Review: runtime binding, provider, read side`
- Coverage:
  reviewed `ExecutionEnvironment`, `AgentDeployment`, environment capability
  recording, deployment registration / handshake / recovery services, runtime
  capability composition services, execution-snapshot shaping, provider
  catalog and request-context contracts, read-side query objects, and
  machine-facing capability request tests.
- Round result:
  this round produced a new high-confidence candidate around recovery-time
  capability compatibility checks being narrower than the runtime capability
  contract they are meant to preserve.
- Earlier residual concerns that now look materially resolved:
  provider request-setting validation and request-context shaping are now
  separated cleanly enough from provider execution to drop them as a
  standalone runtime-boundary finding.
- Round 4 `Hotspot Deep Dive`
- Coverage:
  deep-read `SubagentConnection`, the full `subagent_connections` service family and
  tests, runtime capability composition and execution-snapshot shaping,
  close-reconcile and resource-close request services, plus the neighboring
  `agents/fenix` runtime manifest, execution-context builder, prepare-turn
  hook, and assignment executor.
- Candidate movement:
  this round added `2` new high-confidence candidates and carried forward the
  residual recovery-breadth concern for counter-evidence.
- Neighboring-surface expansion:
  expanded from the requested `fenix` boundary files into `fenix` execution
  hooks because the boundary mismatch only became concrete when the runtime
  consumer path was read end to end.
- Round 5 `Cross-Cut Anti-Pattern Pass`
- Search patterns used:
  cross-cut scans over lock / transaction families, blocker and close-control
  contracts, raw payload and snapshot families, `profile_catalog` /
  `tool_catalog` usage, and query / projection naming.
- Candidates strengthened:
  the shallow capability-compatibility candidate, the dead
  `SubagentConnection.close_requested` lifecycle-state candidate, and the
  `core_matrix <-> fenix` execution-context mismatch all still read as
  system-level patterns rather than isolated local mistakes.
- Candidates weakened or dropped:
  broad query-naming drift dropped below the evidence bar for this pass, while
  duplicated capability-snapshot matching logic moved toward risk-smell status
  instead of a confirmed finding.
- Counter-evidence result:
  `4` confirmed findings survived promotion; `5` candidate findings were
  dropped or downgraded by counter-evidence. Round 5 itself did not add any new
  high-confidence finding.
- Round 6 `Contract Adjacency Re-Verification`
- Coverage:
  re-read capability-snapshot reuse in runtime handshake and bundled-runtime
  bootstrap, traced the real Core Matrix execution-assignment assembly path,
  and compared it against Fenix runtime-flow tests, execution test helpers,
  and the external pairing manifest.
- Round result:
  no newly discovered high-confidence finding was promoted from this pass.
  The duplicated capability-snapshot matcher still reads as a reinforcement
  smell, and the `allowed_tool_names` enforcement gap still reads as a boundary
  smell rather than an observed runtime break.
- Counter-evidence and strengthening:
  this pass confirmed that Core Matrix locally tests the frozen assignment
  payload shape, while Fenix runtime tests still rely on a helper payload that
  injects `model_context.likely_model` and `provider_execution.model_ref`.
  That strengthened the existing `core_matrix <-> fenix` model-hint finding
  without creating an additional independent finding.

## Completeness Check

- Baseline inventory captured.
- Prior audit reconciled against current plans and current contract docs.
- Round 1 baseline reconciliation is complete.
- Round 2 boundary review is complete.
- Round 3 boundary review is complete.
- Round 4 hotspot deep dive is complete.
- Round 5 cross-cut anti-pattern pass is complete.
- Round 6 contract adjacency re-verification is complete.
- Counter-evidence has been applied to every promoted item.
- The mandatory five rounds are complete.
- Rounds 5 and 6 produced no new high-confidence findings.
- The iterative stop condition is satisfied.
