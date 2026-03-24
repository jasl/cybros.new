# Core Matrix Kernel Greenfield Implementation Plan

> **Execution Note:** Work phase-by-phase and execution-unit-by-execution-unit, applying the shared phase-gate audits after every task or subtask before continuing. Treat an execution unit as complete only after its tests pass, two design-conformance review passes pass cleanly, and the most relevant reference implementations have been checked for behavioral sanity.

**Goal:** Rebuild `core_matrix` from a clean backend baseline that matches the approved kernel design, including the preserved conversation runtime capabilities, automated coverage, and real-environment manual validation rules.

**Architecture:** Implement the kernel from the ownership roots downward: installation and identity first, then agent registry and user bindings, then provider catalog and governance, then conversation and workflow runtime, then machine-facing protocol boundaries and publication. Keep the phase backend-first and model-first, but allow minimal machine-facing request endpoints when they are required to exercise agent enrollment, registration, heartbeat, health, and recovery in a real environment. Human-facing UI remains deferred to the follow-up document.

**Tech Stack:** Rails 8.2, PostgreSQL, Active Storage, Minitest, ActionDispatch integration and request tests, bcrypt `has_secure_password`, RuboCop, Brakeman, Bundler Audit, Bun for existing frontend tooling only, `bin/dev` for manual environment validation.

---

## Source Documents

Read these before each phase:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md`
4. `docs/future-plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Do not use the deleted 2026-03-23 plan documents as implementation truth.

Each execution-unit document narrows this source set. During implementation, load only the active execution-unit document and the companion documents it names.

## Documentation Alignment Rule

During implementation, keep code, tests, and plan documents aligned in the same checkpoint:

- if an execution unit reveals a local task-document mistake, omission, stale file list, stale test command, or similar non-architectural documentation bug, fix the relevant document before continuing the task
- if the issue changes approved architecture, product semantics, or business logic in a material way and cannot be resolved from the existing design, stop and escalate for discussion before continuing
- do not leave known doc-code mismatches behind for a later cleanup pass

## Behavior Documentation Rule

During implementation, maintain module-level behavior documents as a durable factual source alongside plans and code:

- write or update behavior docs for every implemented module or cohesive subsystem under the owning product docs tree, such as `core_matrix/docs/behavior/...` or `agents/fenix/docs/behavior/...`
- behavior docs should describe observable behavior, invariants, inputs and outputs, side effects, lifecycle or state transitions, failure modes, and integration boundaries
- treat behavior docs as factual review inputs, not as optional polish or a later documentation pass
- an execution unit is not complete until the active task document, the behavior doc, the code, and the tests all agree

## Reference Benchmarks

Use these reference projects as non-authoritative comparison points during implementation and validation:

- `references/original/references/openclaw`
- `references/original/references/codex`
- `references/original/references/bub`
- `references/original/references/Risuai`
- `references/original/references/OpenAlice`
- `references/original/references/accomplish`
- `references/original/references/OpenManus`
- `references/original/references/paperclip`

Reference projects are for behavior, ergonomics, and failure-mode cross-checks only. They do not override the canonical design or task scope in this plan.

The topical design notes `docs/design/2026-03-24-core-matrix-model-role-resolution-design.md` and `docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md` may be used as rationale, but the phase indexes and task documents below are the canonical execution order.

## Implementation Guardrails

- Build root aggregates before conversation and workflow runtime tables.
- Keep only `personal` and `global` resource scopes.
- Keep `Identity` and `User` separate.
- Keep `AgentInstallation` and `AgentDeployment` separate.
- Keep `Workspace` private and `Publication` read-only.
- Preserve the required conversation runtime baseline: attachments, imports, summary segments, visibility overlays, queued turns, steer-before-side-effect, variant pointers, workflow event streams, leases, timeouts, background-service control, archive lifecycle, automation conversation purpose, turn-origin metadata, conversation events, human-interaction requests, and canonical variables.
- Keep the provider catalog config-backed. Do not build provider-model tables in SQL.
- Fully reuse already-landed infrastructure when implementing later phases. If an existing abstraction is close but insufficient, refactor or extend it instead of building a parallel wheel.
- Maintain orthogonality and consistency across naming, ownership boundaries, state models, protocols, and documentation.
- Route audited installation and runtime mutations through explicit services rather than ad hoc model saves.
- Require both unit tests and integration tests for every major flow.
- Allow minimal machine-facing controllers and request tests only where needed for M2M runtime validation, canonical transcript access, canonical variable access, or human-interaction intent submission.
- Do not implement human-facing UI in this phase.
- Keep the manual validation checklist updated as work lands.
- Finish with a real `bin/dev` validation pass, not just automated tests.
- For every execution unit, inspect the most relevant reference benchmark slices before implementation and again before final verification.
- For every execution unit, perform at least two full review passes against the active task document plus the greenfield design; if any gap is found, fix it, rerun the relevant tests, and repeat until both passes are clean.
- For every execution unit, update the relevant behavior docs in the owning product docs tree and include them in the self-review loop.
- At the end of every phase, review the landed code against Ruby and Rails best practices: layered boundaries, service and query placement, Active Record associations and validations, callback restraint, naming consistency, and test clarity.
- Commit after each finished task or subtask.

## Phase Gates

At the end of each task or subtask, perform these audits before continuing:

1. Missing-fields audit: check for missing columns, indexes, associations, validations, enums, snapshots, and foreign keys.
2. Boundary audit: verify the task did not collapse `Identity` versus `User`, `AgentInstallation` versus `AgentDeployment`, `Workspace` versus `Publication`, or agent intent versus kernel side effects.
3. Coverage audit: verify the task includes unit tests, at least one integration or request test when a real flow exists, and boundary or extreme-case assertions where applicable.
4. Checklist audit: if the task introduced or changed a manually testable flow, update `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md` inside the same task once that flow is independently reproducible; if it is not independently reproducible yet, carry the checklist delta into the first later verification subtask that makes the full flow reproducible.
5. Reference audit: compare the implemented behavior against the most relevant reference benchmarks; follow this plan when intentional differences exist and record the difference in the task review notes.
6. Design-conformance audit: review the implementation against the active execution-unit document and the greenfield design twice, fixing every mismatch before continuing.
7. Behavior-doc audit: update the owning product behavior docs and verify they match the task document, the code, and the tests.
8. Rails-quality audit: check that the implementation still uses thin controllers, explicit services and queries, clear model responsibilities, and Rails-native patterns instead of ad hoc framework invention.

If any audit fails, fix it inside the same task before moving on.

## Phase Index Documents

Use the phase files as ordering indexes:

1. `docs/plans/2026-03-24-core-matrix-kernel-phase-1-foundations.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-phase-2-governance-and-accounting.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-phase-3-conversation-and-runtime.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-4-protocol-publication-and-verification.md`

## Task Group Documents

Some larger tasks are split into subtasks so implementation can load less context at one time and keep tighter acceptance boundaries.

Use these task-group files as grouping indexes, not as the detailed execution bodies:

- `docs/plans/2026-03-24-core-matrix-task-05-provider-catalog-and-governance.md`
- `docs/plans/2026-03-24-core-matrix-task-06-usage-accounting-and-profiling.md`
- `docs/plans/2026-03-24-core-matrix-task-04-bindings-workspaces-and-default-agent.md`
- `docs/plans/2026-03-24-core-matrix-task-07-conversation-and-turn-foundations.md`
- `docs/plans/2026-03-24-core-matrix-task-08-transcript-support-models.md`
- `docs/plans/2026-03-24-core-matrix-task-09-workflow-core-and-scheduling.md`
- `docs/plans/2026-03-24-core-matrix-task-10-runtime-resources-and-lease-control.md`
- `docs/plans/2026-03-24-core-matrix-task-11-agent-protocol-and-recovery.md`
- `docs/plans/2026-03-24-core-matrix-task-12-publication-and-final-verification.md`

## Execution Unit Documents

Execute the task and subtask documents in this exact order:

1. `docs/plans/2026-03-24-core-matrix-task-01-shell-baseline.md`
2. `docs/plans/2026-03-24-core-matrix-task-02-installation-identity-and-audit.md`
3. `docs/plans/2026-03-24-core-matrix-task-03-agent-registry-and-connectivity.md`
4. `docs/plans/2026-03-24-core-matrix-task-04-1-bindings-and-workspaces.md`
5. `docs/plans/2026-03-24-core-matrix-task-04-2-bundled-default-agent-bootstrap.md`
6. `docs/plans/2026-03-24-core-matrix-task-05-1-provider-catalog-config.md`
7. `docs/plans/2026-03-24-core-matrix-task-05-2-provider-governance-models.md`
8. `docs/plans/2026-03-24-core-matrix-task-06-1-usage-events-and-rollups.md`
9. `docs/plans/2026-03-24-core-matrix-task-06-2-execution-profiling-facts.md`
10. `docs/plans/2026-03-24-core-matrix-task-07-1-conversation-structure.md`
11. `docs/plans/2026-03-24-core-matrix-task-07-2-turn-entry-and-override-state.md`
12. `docs/plans/2026-03-24-core-matrix-task-07-3-rewrite-and-variant-operations.md`
13. `docs/plans/2026-03-24-core-matrix-task-08-1-visibility-and-attachments.md`
14. `docs/plans/2026-03-24-core-matrix-task-08-2-imports-and-summary-segments.md`
15. `docs/plans/2026-03-24-core-matrix-task-09-1-workflow-graph-foundations.md`
16. `docs/plans/2026-03-24-core-matrix-task-09-2-scheduler-and-wait-states.md`
17. `docs/plans/2026-03-24-core-matrix-task-09-3-model-selector-resolution.md`
18. `docs/plans/2026-03-24-core-matrix-task-09-4-context-assembly-and-execution-snapshot.md`
19. `docs/plans/2026-03-24-core-matrix-task-10-1-artifacts-events-and-process-runs.md`
20. `docs/plans/2026-03-24-core-matrix-task-10-2-human-interactions-and-conversation-events.md`
21. `docs/plans/2026-03-24-core-matrix-task-10-3-canonical-variables.md`
22. `docs/plans/2026-03-24-core-matrix-task-10-4-subagents-and-leases.md`
23. `docs/plans/2026-03-24-core-matrix-task-11-1-registration-and-capability-handshake.md`
24. `docs/plans/2026-03-24-core-matrix-task-11-2-runtime-resource-apis.md`
25. `docs/plans/2026-03-24-core-matrix-task-11-3-deployment-credential-lifecycle.md`
26. `docs/plans/2026-03-24-core-matrix-task-11-4-bootstrap-and-recovery.md`
27. `docs/plans/2026-03-24-core-matrix-task-12-1-publication-model-and-live-projection.md`
28. `docs/plans/2026-03-24-core-matrix-task-12-2-read-side-queries-and-seed-baseline.md`
29. `docs/plans/2026-03-24-core-matrix-task-12-3-verification-and-manual-validation.md`

## Phase Summary

- **Phase 1**: Tasks 01-03 plus Task 04.1-04.2. Build shell, identity, agent registry, bindings, private workspaces, and bundled default-agent bootstrap.
- **Phase 2**: Tasks 05.1-06.2. Build provider catalog, governance, role-based model selection catalog, usage accounting, and profiling facts.
- **Phase 3**: Tasks 07.1-10.4. Build conversation kinds and purposes, archive lifecycle, transcript controls, interactive selector state, automation turn-origin semantics, workflow scheduling, resolved model snapshots, conversation events, human-interaction resources, canonical variables, and runtime resources.
- **Phase 4**: Tasks 11.1-11.4 plus Tasks 12.1-12.3. Build machine-facing protocol boundaries, recovery-time selector overrides, transcript and variable APIs, publication, seeds, and the final automated plus manual verification pass.

## Cross-Cutting Topic Placement

Treat model-role resolution as one cross-cutting topic that lands in these exact places:

- **Phase 2 / Task 5**: define and validate the config-backed role catalog, provider-qualified candidate lists, and governance prerequisites.
- **Phase 3 / Task 7**: persist the conversation interactive selector in `auto | explicit candidate` form and freeze resolved model-selection snapshots on turns.
- **Phase 3 / Task 9**: implement selector normalization, role-local fallback, execution-time entitlement reservation, and resolved-model snapshotting.
- **Phase 4 / Task 11**: expose the related machine-facing protocol surfaces and allow one-time selector overrides during explicit manual recovery without mutating durable config.

Treat automation-trigger support as one split-scope topic that lands in these exact places:

- **Phase 3 / Task 7**: define `automation` conversation purpose, read-only automation root-conversation semantics, and structured turn-origin fields for manual and future trigger-based execution.
- **Phase 3 / Task 9**: ensure workflow creation and context assembly can run from automation-origin turns that do not start with a transcript-bearing user message.
- **Follow-up only**: do not implement `AutomationTrigger`, schedule parsing, recurring trigger execution, webhook ingress, or trigger management surfaces in this backend kernel batch.

Treat agent protocol and tool-surface consistency as one cross-cutting topic that lands in these exact places:

- **Design baseline**: `docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md` defines naming rules, capability-snapshot structure, future invocation-envelope semantics, and the `kernel_primitive | agent_observation | effect_intent` tool taxonomy.
- **Phase 4 / Task 11**: adopt stable `snake_case` logical operation IDs for the machine-facing contract, publish protocol methods separately from tool-catalog entries, and assert those rules in contract tests.
- **Follow-up only**: do not widen this batch into generic agent-owned tool execution bridges, attachment-import bridges, connector adapter catalogs, or integration-specific tool executors unless a later plan explicitly pulls them into scope.

## Stop Point

Stop after Phase 4.

Do not implement these items in this phase:

- setup wizard UI
- password/session UI
- admin dashboards
- conversation pages
- publication pages
- human-facing Turbo or Stimulus work
- Action Cable or browser realtime delivery
- `AutomationTrigger` models or services
- schedule parsing or recurring trigger runners
- webhook ingress endpoints for external trigger dispatch
- automation trigger management APIs or UI

Human-facing deferred surfaces belong to `docs/future-plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`. The non-UI automation-trigger items above remain deferred follow-up scope in this canonical implementation plan.
