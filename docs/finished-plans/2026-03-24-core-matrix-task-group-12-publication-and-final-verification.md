# Core Matrix Task Group 12: Add Publication, Query Objects, Seeds, Checklist Updates, And Final Verification

Part of `Core Matrix Kernel Milestone 4: Protocol, Publication, And Verification`.

Use this task-group index together with:

1. `AGENTS.md`
2. `docs/finished-plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
3. `docs/finished-plans/2026-03-24-core-matrix-kernel-milestone-4-protocol-publication-and-verification.md`

This task group is split so publication state, read-side queries, and final verification do not compete for context in one execution unit.

---

Execute these tasks in order:

- [Task 12.1: Add Publication Model And Live Projection](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-12-1-publication-model-and-live-projection.md)
- [Task 12.2: Add Read-Side Queries And Seed Baseline](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-12-2-read-side-queries-and-seed-baseline.md)
- [Task 12.3: Run Verification And Manual Validation](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-12-3-verification-and-manual-validation.md)

Task group boundaries:

- Task 12.1 owns publication state, access logging, and live projection.
- Task 12.2 owns read-side query objects, seed baseline, and README updates.
- Task 12.3 owns checklist curation, automated verification, and manual real-environment validation.

Execution rules:

- do not implement directly from this index
- load only the active task document during implementation
- apply the shared execution-gate audits after each task
- if a child task consults `references/` or external implementations, write the retained conclusion into that task document and any local docs it updates; do not leave only a bare reference path behind

## Completion Record

- status:
  completed on `2026-03-25`
- landed scope:
  - added publication state, access logging, revocation, and live projection
  - added read-side query objects for visibility, inbox-style request lookup,
    workspace listing, usage windows, and profiling summaries
  - hardened the backend-safe seed baseline and documented it in the README
  - completed the full automated verification pass plus the live `bin/dev`
    manual backend rerun, then archived the finished phase-1 plan records
- verification evidence:
  - Task 12.1 targeted publication coverage passed with `9 runs, 58 assertions,
    0 failures, 0 errors`
  - Task 12.2 and Task 12.3 retain the seed, full-suite, lint, security, and
    manual-validation evidence needed for reruns
- carry-forward notes:
  - future publication HTTP or UI work should layer on top of the publication
    services and query boundaries already landed here
  - future active plans should start from `docs/plans`, while these records
    remain the archival source for how phase 1 was actually validated
