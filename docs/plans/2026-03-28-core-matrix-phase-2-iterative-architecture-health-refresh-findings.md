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
  `turns` (`12`), `subagent_sessions` (`7`), and `provider_execution` (`6`).
- Earlier consolidation work appears to have materially addressed the
  request-setting split, blocker-summary projection drift, and machine-facing
  runtime capability formatting by introducing `ProviderRequestSettingsSchema`,
  `ConversationBlockerSnapshot`, and `RuntimeCapabilityContract`.
- Earlier hotspot findings around provider turn execution, deployment recovery,
  and mutation-guard sprawl still look residual enough to require direct
  re-verification against current code rather than being treated as resolved.
- Newer surfaces that now require deeper review are `SubagentSession`,
  conversation-facing runtime capability composition, close and reconcile
  control, execution snapshot shaping, and the `core_matrix <-> agents/fenix`
  runtime boundary.

## System Judgment

## Confirmed Findings

### Residual Earlier Findings

### Newly Discovered Findings

## Risk Smells / Reinforcement Opportunities

### Residual Earlier Risk Smells

### Newly Discovered Risk Smells

## Top Structural Priorities

## Round Log

- Round 1 `Baseline Reconciliation`
- Coverage:
  read the iterative refresh design and implementation plan, plans index, the
  earlier architecture-health follow-up design and findings, the structural
  consolidation and repair-loop plans, and current behavior docs for
  conversation lineage, subagent sessions, execution snapshots, registration
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
  `SubagentSession`, runtime capability composition, close / reconcile,
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
  deep-read `SubagentSession`, the full `subagent_sessions` service family and
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
  `SubagentSession.close_requested` lifecycle-state candidate, and the
  `core_matrix <-> fenix` execution-context mismatch all still read as
  system-level patterns rather than isolated local mistakes.
- Candidates weakened or dropped:
  broad query-naming drift dropped below the evidence bar for this pass, while
  duplicated capability-snapshot matching logic moved toward risk-smell status
  instead of a confirmed finding.

## Completeness Check

- Baseline inventory captured.
- Prior audit reconciled against current plans and current contract docs.
- Round 1 baseline reconciliation is complete.
- Round 2 boundary review is complete.
- Round 3 boundary review is complete.
- Round 4 hotspot deep dive is complete.
- Round 5 cross-cut anti-pattern pass is complete.
- The audit still owes round-by-round code review and counter-evidence.
