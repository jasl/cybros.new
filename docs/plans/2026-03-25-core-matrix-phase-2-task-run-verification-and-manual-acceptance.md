# Core Matrix Phase 2 Task: Run Verification And Manual Acceptance

Part of `Core Matrix Phase 2: Agent Loop Execution`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
3. `docs/plans/2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md`
4. `docs/design/2026-03-26-core-matrix-phase-2-test-strategy-design.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
6. `docs/reports/README.md`
7. `docs/reports/phase-2/README.md`
8. `docs/design/2026-03-30-core-matrix-phase-2-sequential-execution-design.md`
9. `docs/plans/2026-03-30-core-matrix-phase-2-milestone-f-sequential-execution-plan.md`

Load this file as the final acceptance execution unit for Phase 2. Treat the
phase plan and proof-export documents as ordering indexes, not as the full
task body.

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
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- Modify: `docs/reports/README.md`
- Modify: `docs/reports/phase-2/README.md`
- Create or modify: `docs/reports/phase-2/YYYY-MM-DD-<scenario-slug>/proof.md`
- Create or modify: `docs/reports/phase-2/YYYY-MM-DD-<scenario-slug>/run-*.mmd`
- Modify: `core_matrix/README.md`
- Modify: `agents/fenix/README.md`

**Step 1: Refresh the final manual checklist**

The checklist now acts as the authoritative operator script for the final
manual phase.

Before any real acceptance run:

- make every required scenario section concrete with exact commands
- preserve the execution order defined in the checklist's Phase 2 acceptance
  matrix
- make sure each scenario records expected and observed DAG shape plus
  expected and observed conversation-state results

The checklist must cover at least:

- bundled `Fenix`
- independent external `Fenix`
- deployment rotation across upgrade
- deployment rotation across downgrade
- provider-backed run
- fast terminal path
- stale-work rejection
- human interaction
- subagents
- real tool call
- real Streamable HTTP MCP path
- system skill deployment flow
- third-party skill install and use
- proof export artifact generation

**Step 2: Run the required automated verification**

Run:

```bash
cd core_matrix/vendor/simple_inference
bundle exec rake
cd ../..
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
cd agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare test
```

Expected:

- required automated verification passes

Protocol-E2E expectation:

- Milestone C must already have landed the protocol-E2E harness and first
  mailbox or close golden scenarios before this final task begins
- the Phase 2 automated suite must include protocol-E2E coverage for mailbox
  delivery, transport fallback, turn interrupt, close orchestration, and
  retryable step failure
- existing Rails `test:system` coverage may continue as baseline regression
  coverage, but it is not the place to introduce Phase 2 browser-facing UI E2E
  infrastructure
- browser-facing UI E2E is explicitly out of scope for Phase 2 and must not be
  a completion dependency here

**Step 3: Run the real-environment manual validation**

Run the documented `bin/dev` validation paths using:

- mock provider for fast smoke loops
- real provider for selected acceptance scenarios
- real external capability path
- real external `Fenix`

Expected:

- each required scenario has a reproducible operator path

**Step 4: Generate and commit proof artifacts**

For key yield, wait, resume, and bounded-parallel scenarios:

- export Mermaid with the documented manual command
- write or update `proof.md`
- commit the artifact packages under `docs/reports/phase-2/`

**Step 5: Update README-level product status notes**

Keep both product READMEs aligned with what Phase 2 now proves:

- `Core Matrix` as an agent-loop kernel
- `Fenix` as the default validation agent program

**Step 6: Commit**

```bash
git add docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md docs/reports/README.md docs/reports/phase-2/README.md docs/reports/phase-2 core_matrix/README.md agents/fenix/README.md
git commit -m "docs: record phase 2 acceptance evidence"
```

## Stop Point

Stop after automated verification, manual validation, and committed proof
artifacts demonstrate the full Phase 2 milestone.

Do not implement new runtime behavior in this task. This task is for
verification, acceptance evidence, and final documentation alignment.
