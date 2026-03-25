# Core Matrix Phase 2 Task: Build Fenix Runtime Surface And Retain Execution Hooks

Part of `Core Matrix Phase 2: Agent Loop Execution`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-25-fenix-phase-2-validation-and-skills-design.md`
3. `docs/research-notes/2026-03-25-agent-program-public-api-and-transport-research-note.md`
4. `docs/future-plans/2026-03-25-core-matrix-phase-2-milestone-agent-loop-execution.md`
5. `docs/future-plans/2026-03-25-core-matrix-phase-2-task-agent-task-run-and-execution-contract-safety.md`
6. `docs/future-plans/2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md`

Load this file as the detailed `Fenix` runtime execution unit for Phase 2.
Treat the milestone and kernel-side task documents as ordering indexes, not as
the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the
  consulted slice and the retained conclusion, invariant, or intentional
  difference in this task document or another local document updated by the
  same execution unit
- when this task updates behavior docs, checklist docs, or other local docs,
  carry that conclusion into those docs instead of leaving only a bare
  reference path
- keep reference paths as index pointers only; restate the relevant behavior
  locally so this task remains understandable if the reference later drifts

---

**Files:**
- Modify: `agents/fenix/config/routes.rb`
- Modify: `agents/fenix/README.md`
- Likely create: `agents/fenix/app/controllers/runtime/*`
- Likely create: `agents/fenix/app/services/fenix/runtime/*`
- Likely create: `agents/fenix/app/services/fenix/runtime_surface/*`
- Likely create: `agents/fenix/app/services/fenix/hooks/*`
- Likely create: `agents/fenix/app/services/fenix/context/*`
- Likely create: `agents/fenix/test/integration/runtime_flow_test.rb`
- Likely create: `agents/fenix/test/services/fenix/runtime/*`
- Likely create: `agents/fenix/test/services/fenix/hooks/*`

**Step 1: Write failing service and integration tests**

Cover at least:

- machine-facing runtime endpoint handling for claim, progress, and terminal
  delivery
- retained hook family:
  - `prepare_turn`
  - `compact_context`
  - `review_tool_call`
  - `project_tool_result`
  - `finalize_output`
  - `handle_error`
- helper family:
  - `estimate_tokens`
  - `estimate_messages`
- one deterministic or mixed code-plus-LLM path
- one path that uses likely-model hints for proactive compaction

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd agents/fenix
bin/rails test test/integration/runtime_flow_test.rb test/services/fenix/runtime test/services/fenix/hooks
```

Expected:

- missing runtime-surface, hook, or estimation failures

**Step 3: Implement the minimal Phase 2 runtime surface**

Rules:

- prompt building remains agent-program-owned
- `Fenix` should consume the kernel contract; it should not redefine it
- retain a stage-shaped runtime hook surface instead of collapsing behavior
  into one opaque service
- allow code-driven execution paths; do not force every decision through an
  LLM call
- breaking changes are allowed in Phase 2

**Step 4: Update local docs**

Document exact retained behavior for:

- runtime contract surface
- hook lifecycle
- token and message estimation helpers
- likely-model-hint usage

**Step 5: Run the targeted tests**

Run:

```bash
cd agents/fenix
bin/rails test test/integration/runtime_flow_test.rb test/services/fenix/runtime test/services/fenix/hooks
```

Expected:

- targeted `Fenix` runtime tests pass

**Step 6: Commit**

```bash
git -C .. add agents/fenix/config/routes.rb agents/fenix/README.md agents/fenix/app/controllers/runtime agents/fenix/app/services/fenix/runtime agents/fenix/app/services/fenix/runtime_surface agents/fenix/app/services/fenix/hooks agents/fenix/app/services/fenix/context agents/fenix/test/integration/runtime_flow_test.rb agents/fenix/test/services/fenix/runtime agents/fenix/test/services/fenix/hooks
git -C .. commit -m "feat: add fenix runtime surface"
```

## Stop Point

Stop after `Fenix` can act as a real Phase 2 agent program with retained
execution hooks and local estimation helpers.

Do not implement these items in this task:

- deployment rotation
- skill installation
- MCP breadth
- final manual acceptance
