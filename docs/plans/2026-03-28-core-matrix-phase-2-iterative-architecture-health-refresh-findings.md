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

## Completeness Check

- Baseline inventory captured.
- Prior audit reconciled against current plans and current contract docs.
- Round 1 baseline reconciliation is complete.
- The audit still owes round-by-round code review and counter-evidence.
