# Core Matrix Phase 2 Task: Re-Run Structural Gate And Freeze Scope

Part of `Core Matrix Phase 2: Agent Loop Execution`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/design/2026-03-25-core-matrix-platform-phases-and-validation-design.md`
4. `docs/future-plans/2026-03-25-core-matrix-phase-2-milestone-agent-loop-execution.md`
5. `docs/future-plans/2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md`
6. `docs/future-plans/2026-03-25-core-matrix-phase-2-activation-checklist.md`

Load this file as the first Phase 2 execution unit. Treat the milestone,
initial-plan, and activation-checklist documents as ordering indexes, not as
the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the
  consulted source section and the retained conclusion, invariant, or intentional
  difference in this task document or another local document updated by the
  same execution unit
- when this task updates behavior docs, checklist docs, or other local docs,
  carry that conclusion into those docs instead of leaving only a bare
  reference path
- keep reference paths as index pointers only; restate the relevant behavior
  locally so this task remains understandable if the reference later drifts

---

**Files:**
- Modify: `docs/future-plans/2026-03-25-core-matrix-phase-2-milestone-agent-loop-execution.md`
- Modify: `docs/future-plans/2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md`
- Modify: `docs/future-plans/2026-03-25-core-matrix-phase-2-activation-checklist.md`
- Modify: `docs/future-plans/2026-03-25-core-matrix-phase-2-activation-ready-outline.md`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- Review: `core_matrix/docs/behavior/*.md`

**Step 1: Re-read the landed substrate and activation docs**

Confirm at minimum:

- workflow, wait-state, runtime-resource, and recovery substrate are present in
  landed Phase 1 code and behavior docs
- no root-shape ambiguity remains around `Conversation`, `Turn`,
  `WorkflowRun`, `WorkflowNode`, `AgentDeployment`, or capability lineage
- Phase 2 still excludes Web UI, triggers, channel surfaces, and plugin
  systems

**Step 2: Record scope corrections in local docs**

Rules:

- Phase 2 may assume breaking changes are allowed
- Phase 2 should consume substrate rather than reimplement it
- if a new prerequisite is discovered, either:
  - record it as a missing loop prerequisite and update the design baseline
  - or defer it back out of Phase 2

Do not leave unresolved ambiguity in chat only.

**Step 3: Refresh the activation documents**

Refresh:

- Phase 2 milestone wording
- initial-plan ordering and task index
- activation checklist gates
- activation-ready outline
- manual-validation checklist prerequisites

The refreshed docs should name the exact formal Phase 2 task set and its
dependency order.

**Step 4: Verify the documentation set is internally consistent**

Run:

```bash
git diff --check
```

Expected:

- no formatting errors
- no remaining Phase 2 placeholder language claiming tasks are not yet split

**Step 5: Commit**

```bash
git add docs/future-plans/2026-03-25-core-matrix-phase-2-milestone-agent-loop-execution.md docs/future-plans/2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md docs/future-plans/2026-03-25-core-matrix-phase-2-activation-checklist.md docs/future-plans/2026-03-25-core-matrix-phase-2-activation-ready-outline.md docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md
git commit -m "docs: refresh phase 2 activation gate"
```

## Stop Point

Stop after the Phase 2 activation docs reflect the landed substrate, the scope
is frozen, and the formal task set is explicit.

Do not implement these items in this task:

- workflow substrate changes
- `AgentTaskRun`
- provider execution
- capability governance
- `Fenix` runtime work
