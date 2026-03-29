# Core Matrix Phase 2 Milestone F Sequential Execution Plan

> **For Codex:** REQUIRED SUB-SKILL: Use [$executing-plans](/Users/jasl/.codex/skills/executing-plans/SKILL.md) to implement this plan task-by-task.

**Goal:** Finish Phase 2 validation breadth, proof export, real-environment acceptance, and final audit across `core_matrix` and `agents/fenix`.

**Architecture:** Keep `Fenix` agent-program-owned while using it as the default real validation partner for `Core Matrix`. The acceptance path must prove the full agent loop in real conditions, not just synthetic tests, and must capture workflow proof artifacts as durable acceptance evidence.

**Tech Stack:** Ruby on Rails, Minitest, `bin/dev`, OpenRouter-backed provider runs, `docs/reports/phase-2/` proof packages

---

## Required Inputs

- `AGENTS.md`
- `docs/design/2026-03-30-core-matrix-phase-2-sequential-execution-design.md`
- `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
- `docs/plans/2026-03-25-core-matrix-phase-2-task-fenix-skills-compatibility-and-operational-flows.md`
- `docs/plans/2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md`
- `docs/plans/2026-03-25-core-matrix-phase-2-task-run-verification-and-manual-acceptance.md`
- `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

## Execution Contract

- do not start Milestone `F` until Milestones `D` and `E` have actually passed
  their exit gates
- refresh the checklist before running any final manual scenario
- treat the checklist as a real operator script, not as a loose list of ideas
- stop if a required real-world validation cannot be performed truthfully

## Batch 1: Milestone F Preflight And F1

### Task 1: Run the Milestone F preflight

**Files:**
- Review: `agents/fenix/README.md`
- Review: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- Review: `docs/plans/2026-03-25-core-matrix-phase-2-task-fenix-skills-compatibility-and-operational-flows.md`

Confirm:

- the checklist already enumerates every required Phase 2 acceptance scenario
- `agents/fenix` still lacks the planned skill surface or only contains the
  intended in-progress work
- the real validation path can use the configured `OPENROUTER_API_KEY`

Stop if:

- the final acceptance scenarios are still incomplete or ambiguous in the
  checklist

### Task 2: Execute F1 with TDD

**Files:**
- Modify: `agents/fenix/README.md`
- Modify or create: `agents/fenix/app/services/fenix/skills/*`
- Modify or create: `agents/fenix/test/services/fenix/skills/*`
- Modify or create: `agents/fenix/test/integration/skills_flow_test.rb`
- Modify or create: `agents/fenix/skills/.system/*`
- Modify or create: `agents/fenix/skills/.curated/*`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Run first:

```bash
cd agents/fenix
bin/rails test test/services/fenix/skills test/integration/skills_flow_test.rb
```

Expected before implementation:

- failure for the missing skill catalog, load, read, or install behavior

Then implement only the F1 scope recorded in the task doc:

- minimal skill surface
- staged install and promote flow
- separation between `.system` and `.curated`
- built-in deploy-agent skill
- one third-party skill install path

Run after implementation:

```bash
cd agents/fenix
bin/rails test test/services/fenix/skills test/integration/skills_flow_test.rb
```

Expected after implementation:

- the F1 targeted suite passes

## Batch 2: F2 And Acceptance Prep

### Task 3: Execute F2 with TDD

**Files:**
- Create or modify: `core_matrix/app/queries/workflows/proof_export_query.rb`
- Create or modify: `core_matrix/app/services/workflows/visualization/mermaid_exporter.rb`
- Create or modify: `core_matrix/app/services/workflows/visualization/proof_record_renderer.rb`
- Create or modify: `core_matrix/script/manual/workflow_proof_export.rb`
- Create or modify: `core_matrix/test/queries/workflows/proof_export_query_test.rb`
- Create or modify: `core_matrix/test/services/workflows/visualization/mermaid_exporter_test.rb`
- Create or modify: `core_matrix/test/services/workflows/visualization/proof_record_renderer_test.rb`
- Create or modify: `core_matrix/test/integration/workflow_proof_export_flow_test.rb`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- Modify: `docs/reports/README.md`
- Modify: `docs/reports/phase-2/README.md`
- Modify: `core_matrix/README.md`
- Modify: `core_matrix/docs/behavior/read-side-queries-and-seed-baseline.md`
- Modify: `core_matrix/docs/behavior/verification-and-manual-validation-baseline.md`

Run first:

```bash
cd core_matrix
bin/rails test test/queries/workflows/proof_export_query_test.rb test/services/workflows/visualization/mermaid_exporter_test.rb test/services/workflows/visualization/proof_record_renderer_test.rb test/integration/workflow_proof_export_flow_test.rb
```

Expected before implementation:

- failure for the missing proof-export query, renderers, or script

Then implement only the F2 scope recorded in the task doc:

- proof-export query bundle
- Mermaid and proof record rendering
- manual export script
- report and checklist updates for proof capture

Run after implementation:

```bash
cd core_matrix
bin/rails test test/queries/workflows/proof_export_query_test.rb test/services/workflows/visualization/mermaid_exporter_test.rb test/services/workflows/visualization/proof_record_renderer_test.rb test/integration/workflow_proof_export_flow_test.rb
```

Expected after implementation:

- the F2 targeted suite passes

### Task 4: Convert the checklist into the final operator script

**Files:**
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- Modify: `docs/plans/2026-03-25-core-matrix-phase-2-task-run-verification-and-manual-acceptance.md`

Before any final acceptance run, make sure the checklist contains exact steps
for every required scenario, including:

- bundled `Fenix`
- independent external `Fenix`
- deployment rotation upgrade and downgrade
- real provider-backed loop
- fast terminal loop
- during-generation steering
- human interaction
- subagents under `wait_all`
- real governed tool path
- real governed MCP path
- system skill deployment
- third-party skill install and use
- proof export generation
- conversation and DAG evidence capture

Expected:

- the checklist can be executed linearly without inventing missing steps

## Batch 3: Final Verification, Manual Acceptance, And Audit

### Task 5: Run the full automated verification set

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
cd ../agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare test
```

Expected:

- the full automated verification set passes

### Task 6: Run the full real-environment manual validation

**Files:**
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- Create or modify: `docs/reports/phase-2/YYYY-MM-DD-<scenario-slug>/proof.md`
- Create or modify: `docs/reports/phase-2/YYYY-MM-DD-<scenario-slug>/run-*.mmd`

Run the checklist under `bin/dev` and record, for each required scenario:

- conversation `public_id`
- turn `public_id`
- workflow-run `public_id`
- deployment and provider/model used
- expected DAG shape
- observed DAG shape
- expected conversation state
- observed conversation state
- proof artifact path when applicable

Expected:

- the real loop is demonstrated for the full required Phase 2 acceptance set

### Task 7: Run final code and documentation audit

**Files:**
- Review: `core_matrix/README.md`
- Review: `agents/fenix/README.md`
- Review: `docs/reports/README.md`
- Review: `docs/reports/phase-2/README.md`
- Review: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Confirm:

- code behavior matches plans and design docs
- checklist and reports match the actual operator flow used
- no stale status notes remain in README-level docs

Stop if:

- the manual results expose a semantic mismatch that would require guessing the
  intended product behavior

## Milestone F Exit Criteria

- F1 and F2 targeted suites pass
- the full automated verification set passes
- the full real-environment checklist has been executed and recorded
- proof artifacts exist for the required workflow scenarios
- README, behavior docs, and report docs match the code and observed runtime
- the remaining output to the user is only the final acceptance conclusion and
  any explicit product decisions they must make

## Must-Stop Conditions

- a required real validation path cannot run truthfully with the available
  environment
- proof export cannot represent the required DAG evidence without new product
  semantics
- final manual validation reveals a mismatch that is not resolvable by the
  existing plans or design docs
