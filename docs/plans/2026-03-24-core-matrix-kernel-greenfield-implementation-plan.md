# Core Matrix Kernel Greenfield Implementation Plan

> **Execution Note:** Work phase-by-phase and task-by-task, applying the shared phase-gate audits after every task before continuing.

**Goal:** Rebuild `core_matrix` from a clean backend baseline that matches the approved kernel design, including the preserved conversation runtime capabilities, automated coverage, and real-environment manual validation rules.

**Architecture:** Implement the kernel from the ownership roots downward: installation and identity first, then agent registry and user bindings, then provider catalog and governance, then conversation and workflow runtime, then machine-facing protocol boundaries and publication. Keep the phase backend-first and model-first, but allow minimal machine-facing request endpoints when they are required to exercise agent enrollment, registration, heartbeat, health, and recovery in a real environment. Human-facing UI remains deferred to the follow-up document.

**Tech Stack:** Rails 8.2, PostgreSQL, Active Storage, Minitest, ActionDispatch integration and request tests, bcrypt `has_secure_password`, RuboCop, Brakeman, Bundler Audit, Bun for existing frontend tooling only, `bin/dev` for manual environment validation.

---

## Source Documents

Read these before each phase:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
4. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Do not use the deleted 2026-03-23 plan documents as implementation truth.

## Implementation Guardrails

- Build root aggregates before conversation and workflow runtime tables.
- Keep only `personal` and `global` resource scopes.
- Keep `Identity` and `User` separate.
- Keep `AgentInstallation` and `AgentDeployment` separate.
- Keep `Workspace` private and `Publication` read-only.
- Preserve the required conversation runtime baseline: attachments, imports, summary segments, visibility overlays, queued turns, steer-before-side-effect, variant pointers, workflow event streams, leases, timeouts, background-service control, and archive lifecycle.
- Keep the provider catalog config-backed. Do not build provider-model tables in SQL.
- Require both unit tests and integration tests for every major flow.
- Allow minimal machine-facing controllers and request tests only where needed for M2M runtime validation.
- Do not implement human-facing UI in this phase.
- Keep the manual validation checklist updated as work lands.
- Finish with a real `bin/dev` validation pass, not just automated tests.
- Commit after each finished task.

## Phase Gates

At the end of each task, perform these audits before continuing:

1. Missing-fields audit: check for missing columns, indexes, associations, validations, enums, snapshots, and foreign keys.
2. Boundary audit: verify the task did not collapse `Identity` versus `User`, `AgentInstallation` versus `AgentDeployment`, `Workspace` versus `Publication`, or agent intent versus kernel side effects.
3. Coverage audit: verify the task includes unit tests, at least one integration or request test when a real flow exists, and boundary or extreme-case assertions where applicable.
4. Checklist audit: if the task introduced or changed a manually testable flow, update `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md` inside the same task.

If any audit fails, fix it inside the same task before moving on.

## Phase Documents

Execute the phase files in order:

1. `docs/plans/2026-03-24-core-matrix-kernel-phase-1-foundations.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-phase-2-governance-and-accounting.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-phase-3-conversation-and-runtime.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-4-protocol-publication-and-verification.md`

## Phase Summary

- **Phase 1**: Tasks 1-4. Build shell, identity, agent registry, bindings, private workspaces, and bundled default-agent bootstrap.
- **Phase 2**: Tasks 5-6. Build provider catalog, governance, usage accounting, and profiling facts.
- **Phase 3**: Tasks 7-10. Build conversation kinds, archive lifecycle, transcript controls, workflow scheduling, and runtime resources.
- **Phase 4**: Tasks 11-12. Build machine-facing protocol boundaries, recovery flows, publication, seeds, and the final automated plus manual verification pass.

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

Those belong to `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`.
