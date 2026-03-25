# Core Matrix Phase 2 Task 01: Re-Run Structural Gate And Freeze Scope

Part of `Core Matrix Phase 2 Milestone 1: Kernel Execution Foundations`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/design/2026-03-25-core-matrix-platform-phases-and-validation-design.md`
4. `docs/plans/2026-03-25-core-matrix-phase-2-milestone-1-kernel-execution-foundations.md`
5. `docs/future-plans/2026-03-25-core-matrix-phase-2-activation-checklist.md`

Load this file as the detailed execution unit for Task 01. Treat the milestone
file as the ordering index, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the
  consulted source section and the retained conclusion, invariant, or
  intentional difference in this task document or another local document
  updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs,
  carry that conclusion into those docs instead of leaving only a bare
  reference path
- keep reference paths as index pointers only; restate the relevant behavior
  locally so this task remains understandable if the reference later drifts

---

**Files:**
- Modify: `docs/plans/2026-03-25-core-matrix-phase-2-milestone-1-kernel-execution-foundations.md`
- Modify: `docs/plans/2026-03-25-core-matrix-phase-2-task-01-structural-gate-and-scope-freeze.md`
- Modify: `docs/plans/README.md`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- Review: `core_matrix/docs/behavior/*.md`

**Step 1: Re-read the landed substrate and active milestone scope**

Confirm at minimum:

- the landed Phase 1 behavior docs still match the code
- no root-shape ambiguity remains around `Conversation`, `Turn`,
  `WorkflowRun`, `WorkflowNode`, `AgentDeployment`, or capability lineage
- Milestone 1 remains limited to Tasks 01-05

**Step 2: Record any scope or activation corrections locally**

Rules:

- do not widen Milestone 1 into human interaction, subagents, MCP, or `Fenix`
  runtime work
- if a newly discovered prerequisite is required, record it in the active
  milestone docs rather than leaving it in chat only
- breaking changes remain allowed

**Step 3: Refresh the active milestone entry point if needed**

Refresh:

- milestone goals
- task order
- local completion gate
- manual-checklist prerequisites relevant to Milestone 1

**Step 4: Verify the active docs are consistent**

Run:

```bash
git diff --check
```

Expected:

- no formatting errors
- no unresolved scope ambiguity left in the active milestone docs

**Step 5: Commit**

```bash
git add docs/plans/2026-03-25-core-matrix-phase-2-milestone-1-kernel-execution-foundations.md docs/plans/2026-03-25-core-matrix-phase-2-task-01-structural-gate-and-scope-freeze.md docs/plans/README.md docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md
git commit -m "docs: activate phase 2 milestone 1"
```

## Stop Point

Stop after the active Milestone 1 scope is confirmed and the task entry point
is stable.

Do not implement workflow, execution, or provider code in this task.
