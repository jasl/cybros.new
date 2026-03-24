# Core Matrix Task 12 Index: Add Publication, Query Objects, Seeds, Checklist Updates, And Final Verification

Part of `Core Matrix Kernel Phase 4: Protocol, Publication, And Verification`.

Use this index together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-phase-4-protocol-publication-and-verification.md`

This task group is split so publication state, read-side queries, and final verification do not compete for context in one execution unit.

---

Execute these subtasks in order:

- [Task 12.1: Add Publication Model And Live Projection](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-12-1-publication-model-and-live-projection.md)
- [Task 12.2: Add Read-Side Queries And Seed Baseline](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-12-2-read-side-queries-and-seed-baseline.md)
- [Task 12.3: Run Verification And Manual Validation](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-12-3-verification-and-manual-validation.md)

Task-group boundaries:

- Task 12.1 owns publication state, access logging, and live projection.
- Task 12.2 owns read-side query objects, seed baseline, and README updates.
- Task 12.3 owns checklist curation, automated verification, and manual real-environment validation.

Execution rules:

- do not implement directly from this index
- load only the active subtask document during implementation
- apply the shared phase-gate audits after each subtask
