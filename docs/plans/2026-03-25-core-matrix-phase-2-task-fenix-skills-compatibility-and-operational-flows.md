# Core Matrix Phase 2 Task: Add Fenix Skills Compatibility And Operational Flows

Part of `Core Matrix Phase 2: Agent Loop Execution`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-25-fenix-phase-2-validation-and-skills-design.md`
3. `docs/research-notes/2026-03-25-fenix-skills-and-agent-skills-spec-research-note.md`
4. `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
5. `docs/plans/2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md`
6. `docs/plans/2026-03-25-core-matrix-phase-2-task-external-fenix-pairing-and-deployment-rotation.md`

Load this file as the detailed skills execution unit for `Fenix` inside
Phase 2. Treat the milestone and preceding `Fenix` task documents as ordering
indexes, not as the full task body.

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
- Modify: `agents/fenix/README.md`
- Likely create: `agents/fenix/app/services/fenix/skills/*`
- Likely create: `agents/fenix/test/services/fenix/skills/*`
- Likely create: `agents/fenix/test/integration/skills_flow_test.rb`
- Create: `agents/fenix/skills/.system/`
- Create: `agents/fenix/skills/.curated/`
- Likely create: `agents/fenix/skills/.system/deploy-agent/SKILL.md`
- Likely create: `agents/fenix/skills/.system/deploy-agent/*`

**Step 1: Write failing service and integration tests**

Cover at least:

- `skills_catalog_list`
- `skills_load`
- `skills_read_file`
- `skills_install`
- separation between `.system` and `.curated`
- staged install and promote behavior
- activation on the next top-level turn
- reserved system skill names may not be overridden

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd agents/fenix
bin/rails test test/services/fenix/skills test/integration/skills_flow_test.rb
```

Expected:

- missing skill-service, catalog, or install-flow failures

**Step 3: Implement the minimal Phase 2 skill surface**

Rules:

- skills remain agent-program-owned
- `Fenix` must install and use standard third-party Agent Skills when they fit
  the supported surface
- `.system` holds bundled reserved system skills
- `.curated` holds bundled third-party catalog material
- installs must stage, validate, and promote instead of writing live
- installed or refreshed skills become effective on the next top-level turn

Validate both:

- one built-in system skill that deploys another agent
- one third-party package, ideally
  [obra/superpowers](https://github.com/obra/superpowers)

**Step 4: Update local docs**

Document exact retained behavior for:

- system versus curated skill roots
- install and activation flow
- compatibility boundary for third-party Agent Skills
- `Fenix`-private skill behavior where applicable

**Step 5: Run the targeted tests**

Run:

```bash
cd agents/fenix
bin/rails test test/services/fenix/skills test/integration/skills_flow_test.rb
```

Expected:

- targeted skill tests pass

**Step 6: Run real skill validation**

Validate:

- built-in deploy-agent skill
- third-party install and use
- next-top-level-turn activation behavior

**Step 7: Commit**

```bash
git -C .. add agents/fenix/README.md agents/fenix/app/services/fenix/skills agents/fenix/test/services/fenix/skills agents/fenix/test/integration/skills_flow_test.rb agents/fenix/skills/.system agents/fenix/skills/.curated
git -C .. commit -m "feat: add fenix skill compatibility"
```

## Stop Point

Stop after `Fenix` supports the Phase 2 skill surface, the built-in deploy
skill, and one third-party skill package.

Do not implement these items in this task:

- kernel-owned skills
- plugin packaging or marketplace features
- Web UI productization
