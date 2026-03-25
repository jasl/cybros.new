# Core Matrix Phase 2 Task: Add Workflow Proof Export And Validation Artifacts

Part of `Core Matrix Phase 2: Agent Loop Execution`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-25-core-matrix-workflow-proof-and-mermaid-export-design.md`
3. `docs/future-plans/2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md`
4. `docs/future-plans/2026-03-25-core-matrix-phase-2-activation-checklist.md`
5. `docs/reports/README.md`
6. `docs/reports/phase-2/README.md`

Load this file as the detailed execution unit for the workflow-proof slice
inside Phase 2. Treat the broader Phase 2 initial plan as the ordering index,
not as the full task body.

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
- Create: `core_matrix/app/queries/workflows/proof_export_query.rb`
- Create: `core_matrix/app/services/workflows/visualization/mermaid_exporter.rb`
- Create: `core_matrix/app/services/workflows/visualization/proof_record_renderer.rb`
- Create: `core_matrix/script/manual/workflow_proof_export.rb`
- Create: `core_matrix/test/queries/workflows/proof_export_query_test.rb`
- Create: `core_matrix/test/services/workflows/visualization/mermaid_exporter_test.rb`
- Create: `core_matrix/test/services/workflows/visualization/proof_record_renderer_test.rb`
- Likely create: `core_matrix/test/integration/workflow_proof_export_flow_test.rb`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- Modify: `core_matrix/README.md`
- Modify: `core_matrix/docs/behavior/read-side-queries-and-seed-baseline.md`
- Modify: `core_matrix/docs/behavior/verification-and-manual-validation-baseline.md`
- Modify: `docs/reports/README.md`
- Modify: `docs/reports/phase-2/README.md`

**Step 1: Write failing query, rendering, and manual-script tests**

Cover at least:

- one proof-export query path rooted at `WorkflowRun`
- stable eager loading of workflow nodes, edges, and selected event summaries
- no per-node follow-up lookup pattern hidden in the exporter
- Mermaid rendering for:
  - one yielding agent step
  - one kernel-governed durable node
  - one wait or barrier hint
  - one successor agent step
- proof-record rendering for:
  - scenario metadata
  - workflow identifiers
  - node and edge counts
  - Mermaid file path
- manual export script argument handling for:
  - `workflow_run_id`
  - `scenario`
  - `out`
  - overwrite protection

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/queries/workflows/proof_export_query_test.rb test/services/workflows/visualization/mermaid_exporter_test.rb test/services/workflows/visualization/proof_record_renderer_test.rb test/integration/workflow_proof_export_flow_test.rb
```

Expected:

- missing file, class, or command failures

**Step 3: Implement the workflow proof-export read path and renderers**

Rules:

- `Workflows::ProofExportQuery` is the authoritative bundle loader for one
  proof export rooted at one `WorkflowRun`
- the query must use bounded eager loading and explicit query-shape rules
- the query must not hide graph-reconstruction SQL in controller or script code
- the query result should behave like an immutable proof bundle, not a mutable
  Active Record graph
- `Workflows::Visualization::MermaidExporter` returns Mermaid text only
- `Workflows::Visualization::ProofRecordRenderer` returns `proof.md` text only
- exporter labels must not dump transcript bodies or full runtime logs
- `internal_only` nodes remain included in proof export by default
- acceptance artifacts live under `docs/reports/phase-2/`
- temp exports may still be generated elsewhere, but they do not count as
  acceptance evidence

**Step 4: Implement the operator-facing manual export command**

Rules:

- use `core_matrix/script/manual/workflow_proof_export.rb`
- keep the script thin; it should delegate query and rendering logic to
  application code
- the command should support one explicit `workflow_run_id`
- the command should support one scenario slug or title
- the command should support one output directory
- the command should refuse to overwrite existing artifacts unless an explicit
  force flag is passed
- one workflow run should produce one `run-<workflow-run-id>.mmd` file
- one scenario directory should contain one `proof.md` plus one or more Mermaid
  files

**Step 5: Update the manual validation checklist and behavior docs**

Document exact reproducible steps for at least:

- exporting one proof package after a workflow-yield scenario
- recording one `proof.md` package under `docs/reports/phase-2/`
- capturing one yield, one wait or barrier, and one successor-agent-step shape
- using the proof package as part of Phase 2 completion evidence

Behavior note requirements:

- record the query-object boundary in `read-side-queries-and-seed-baseline.md`
- record the operator-facing proof-export contract in
  `verification-and-manual-validation-baseline.md`
- keep the proof-export contract backend-facing and shell-reproducible, not UI
  dependent

**Step 6: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/queries/workflows/proof_export_query_test.rb test/services/workflows/visualization/mermaid_exporter_test.rb test/services/workflows/visualization/proof_record_renderer_test.rb test/integration/workflow_proof_export_flow_test.rb
```

Expected:

- targeted proof-export tests pass

**Step 7: Run one manual export pass**

Run:

```bash
cd core_matrix
ruby script/manual/workflow_proof_export.rb export \
  --workflow-run-id=<workflow_run_id> \
  --scenario=<scenario_slug> \
  --out=../docs/reports/phase-2/YYYY-MM-DD-<scenario-slug>
```

Expected:

- one Mermaid file is written
- one `proof.md` file is written or updated through the documented rule
- the artifact package is suitable for later manual-validation evidence

**Step 8: Commit**

```bash
git -C .. add core_matrix/app/queries/workflows/proof_export_query.rb core_matrix/app/services/workflows/visualization core_matrix/script/manual/workflow_proof_export.rb core_matrix/test/queries/workflows/proof_export_query_test.rb core_matrix/test/services/workflows/visualization core_matrix/test/integration/workflow_proof_export_flow_test.rb core_matrix/docs/behavior/read-side-queries-and-seed-baseline.md core_matrix/docs/behavior/verification-and-manual-validation-baseline.md docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md docs/reports/README.md docs/reports/phase-2/README.md
git -C .. commit -m "feat: add workflow proof export artifacts"
```

## Stop Point

Stop after workflow proof export, proof-record rendering, manual export, and
their targeted tests pass.

Do not implement these items in this task:

- browser-native graph viewers
- live-updating workflow dashboards
- arbitrary graph diff tooling
- broader analytics over workflow history
- UI-only validation paths
