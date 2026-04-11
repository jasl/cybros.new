# Core Matrix Phase 2 Architecture Health Confirmation Round Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Run one narrow follow-up confirmation round after the archived iterative architecture audit to determine whether any additional high-confidence structural findings remain undiscovered in the current `core_matrix` and its `core_matrix <-> agents/fenix` runtime boundary.

**Architecture:** Treat the archived iterative audit as the baseline, not as a task to repeat from scratch. Re-read the archived findings and round log, then run focused confirmation passes around the most failure-prone neighboring surfaces: runtime capability preservation and reuse, `SubagentConnection` close progression, and the cross-project execution-context boundary. Finish with one anti-pattern sweep over adjacent wrappers and payload families so the round can honestly conclude either "no new high-confidence findings" or "one more concrete issue exists and needs a new cleanup plan."

**Tech Stack:** Markdown, git, `rg`, `find`, `sed`, Ruby on Rails code in `core_matrix`, `agents/fenix` boundary files, archived audit artifacts under `docs/finished-plans`

---

## Execution Rules

- This is a confirmation round, not a full rerun of the archived iterative
  audit.
- Use the archived iterative findings and plan as the starting baseline:
  - `docs/finished-plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md`
  - `docs/finished-plans/2026-03-28-core-matrix-phase-2-plan-iterative-architecture-health-refresh.md`
- Do not restate the archived findings as if they are new discoveries.
- Only report a new finding if it is:
  - adjacent to the archived findings or their neighboring contracts, and
  - high-confidence, structural, and evidence-backed in the current code.
- If the round finds no new high-confidence issue, say that explicitly and end
  with a clear "no new findings" judgment.
- If the round does find a new high-confidence issue, write it down and stop
  the report from claiming closure.
- Do not modify production code in this batch.
- Keep scratch notes uncommitted; the only committed output of this round is
  the confirmation findings document.

## Deliverable

This plan must create and finish:

- `docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md`

That findings document must include:

- `## Scope`
- `## Archived Baseline`
- `## Confirmation Passes`
- `## New High-Confidence Findings`
- `## No-New-Finding Judgment`
- `## Completeness Check`

## Task 1: Create The Confirmation Findings Scaffold

**Files:**
- Create: `docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md`
- Reference: `docs/finished-plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md`

**Step 1: Write the findings scaffold**

Create the file with these exact top-level headings:

```markdown
# Core Matrix Phase 2 Architecture Health Confirmation Round Findings

## Scope

## Archived Baseline

## Confirmation Passes

## New High-Confidence Findings

## No-New-Finding Judgment

## Completeness Check
```

**Step 2: Add the fixed scope baseline**

Under `## Scope`, add bullets that state:

- this is a post-archive confirmation round
- the archived iterative audit is the baseline
- the purpose is to confirm whether any additional high-confidence structural
  issues remain undiscovered
- the review still includes the `core_matrix <-> agents/fenix` boundary

**Step 3: Verify the scaffold**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "^## " docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md
```

Expected: all six section headings are present in the intended order.

**Step 4: Commit**

```bash
git add docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md
git commit -m "docs: add architecture health confirmation scaffold"
```

## Task 2: Reconcile The Archived Baseline Before Looking For Anything New

**Files:**
- Modify: `docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md`
- Reference: `docs/finished-plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md`
- Reference: `docs/finished-plans/2026-03-28-core-matrix-phase-2-plan-iterative-architecture-health-refresh.md`

**Step 1: Re-read the archived findings and round log**

Capture under `## Archived Baseline`:

- the archived system judgment in one short paragraph
- the archived confirmed findings
- the archived risk smells that most plausibly hide adjacent undiscovered work
- the archived top structural priorities

**Step 2: Freeze the confirmation targets**

Under `## Confirmation Passes`, add a checklist of the three required
confirmation targets:

- runtime capability preservation and reuse rules
- `SubagentConnection` close progression and neighboring close-control readers
- `core_matrix <-> fenix` execution-context contract, including model hints and
  visible-tool semantics

Also add one whole-system adjacent-pattern pass:

- wrapper and payload drift around the archived hotspots

**Step 3: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md
git commit -m "docs: record architecture confirmation baseline"
```

## Task 3: Confirm The Runtime Capability Preservation Surface

**Files:**
- Modify: `docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md`
- Reference: `core_matrix/app/models/agent_deployment.rb`
- Reference: `core_matrix/app/models/runtime_capability_contract.rb`
- Reference: `core_matrix/app/services/agent_deployments/build_recovery_plan.rb`
- Reference: `core_matrix/app/services/agent_deployments/apply_recovery_plan.rb`
- Reference: `core_matrix/app/services/conversations/validate_agent_deployment_target.rb`
- Reference: `core_matrix/app/services/agent_deployments/handshake.rb`
- Reference: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Reference: `core_matrix/test/services/agent_deployments`
- Reference: `core_matrix/test/requests/agent_api`

**Step 1: Read the full comparison surface**

Confirm whether any additional contract-preservation or snapshot-reuse path
still escapes the archived finding.

Focus on:

- recovery-time compatibility checks
- manual rebinding checks
- handshake snapshot reuse
- bundled runtime snapshot reuse

**Step 2: Record the pass result**

Under `## Confirmation Passes`, add:

- files reviewed
- whether the pass found any additional high-confidence issue beyond the
  archived capability-preservation and snapshot-reuse concerns

If a new high-confidence issue exists, add it under
`## New High-Confidence Findings`.

**Step 3: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md
git commit -m "docs: record runtime capability confirmation pass"
```

## Task 4: Confirm The `SubagentConnection` Close Surface

**Files:**
- Modify: `docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md`
- Reference: `core_matrix/app/models/subagent_connection.rb`
- Reference: `core_matrix/app/services/subagent_connections/request_close.rb`
- Reference: `core_matrix/app/services/agent_control/create_resource_close_request.rb`
- Reference: `core_matrix/app/services/agent_control/apply_close_outcome.rb`
- Reference: `core_matrix/app/services/subagent_connections`
- Reference: `core_matrix/app/queries/conversations/blocker_snapshot_query.rb`
- Reference: `core_matrix/test/services/subagent_connections`
- Reference: `core_matrix/test/services/agent_control`

**Step 1: Read the close-progression and reader surface**

Confirm whether the archived split-state-machine finding hides any additional
adjacent issue such as:

- a reader that mixes incompatible state axes
- a query that assumes a transition never written
- a close-control helper that bypasses the intended owner

**Step 2: Record the pass result**

Under `## Confirmation Passes`, add:

- files reviewed
- whether any extra high-confidence issue exists beyond the archived
  `SubagentConnection` close-progression split

If one exists, add it under `## New High-Confidence Findings`.

**Step 3: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md
git commit -m "docs: record subagent close confirmation pass"
```

## Task 5: Confirm The `core_matrix <-> fenix` Execution Boundary

**Files:**
- Modify: `docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md`
- Reference: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Reference: `core_matrix/app/services/workflows/create_for_turn.rb`
- Reference: `core_matrix/app/services/agent_control/create_execution_assignment.rb`
- Reference: `agents/fenix/app/services/fenix/context/build_execution_context.rb`
- Reference: `agents/fenix/app/services/fenix/hooks/prepare_turn.rb`
- Reference: `agents/fenix/app/services/fenix/hooks/review_tool_call.rb`
- Reference: `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Reference: `agents/fenix/README.md`

**Step 1: Re-read the end-to-end boundary**

Confirm whether the archived model-hint and visible-tool concerns fully cover
the real boundary, or whether one more adjacent contract leak exists.

Focus on:

- which model-hint fields are frozen versus consumed
- whether `allowed_tool_names` is enforcement, advisory data, or dead weight
- whether docs, local tests, and real assignment payloads still agree

**Step 2: Record the pass result**

Under `## Confirmation Passes`, add:

- files reviewed
- whether any additional high-confidence boundary issue exists beyond the
  archived findings

If one exists, add it under `## New High-Confidence Findings`.

**Step 3: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md
git commit -m "docs: record fenix boundary confirmation pass"
```

## Task 6: Run One Adjacent Anti-Pattern Sweep Before Declaring Closure

**Files:**
- Modify: `docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md`
- Reference: `core_matrix/app/models`
- Reference: `core_matrix/app/services`
- Reference: `core_matrix/app/queries`
- Reference: `agents/fenix/app/services`

**Step 1: Search the neighboring contract families**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rg -n "profile_catalog|tool_catalog|allowed_tool_names|close_requested|close_state|recovery_plan|capability_snapshot|default_config_snapshot|conversation_override_schema_snapshot"
rg -n "with_lock|transaction|close_operation|request_close|apply_close_outcome" app/services app/models
```

Then, if needed, run matching `rg` searches in:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
rg -n "allowed_tool_names|likely_model|model_context|agent_context|profile"
```

**Step 2: Record whether the sweep found anything truly new**

Under `## Confirmation Passes`, add:

- the search patterns used
- whether the sweep found a new high-confidence issue
- or whether it only reinforced already-archived findings

If nothing new was found, say that explicitly.

**Step 3: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md
git commit -m "docs: record architecture confirmation anti-pattern pass"
```

## Task 7: Write The Final Confirmation Judgment

**Files:**
- Modify: `docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md`

**Step 1: Populate `## New High-Confidence Findings`**

If no new finding was discovered, write `None.` and explain briefly that the
confirmation passes did not surface an additional high-confidence structural
issue beyond the archived audit.

If a new finding was discovered, write it with:

- why it matters
- evidence
- structural impact
- action direction

**Step 2: Populate `## No-New-Finding Judgment`**

Write one short paragraph that states one of two outcomes:

- no additional high-confidence issue was found in this confirmation round
- or the round found one more issue, so the archived audit should not yet be
  treated as exhaustive

**Step 3: Populate `## Completeness Check`**

Add bullets that confirm:

- the archived baseline was re-read
- all three targeted confirmation passes ran
- one adjacent anti-pattern sweep ran
- the report explicitly states whether any new high-confidence finding exists

**Step 4: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md
git commit -m "docs: publish architecture health confirmation round"
```

## Final Verification

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git diff --check
git status --short
rg -n "^## " docs/plans/2026-03-29-core-matrix-phase-2-architecture-health-confirmation-round-findings.md
```

Then manually verify that the confirmation findings document:

- references the archived iterative audit as baseline
- names the targeted passes that were run
- clearly says whether a new high-confidence finding exists
- does not pad the result by restating old findings as new material

## Stop Condition

This plan is complete only when:

- the confirmation findings document is finished
- the three targeted confirmation passes and one adjacent anti-pattern sweep
  have all run
- the final report clearly says either `no new high-confidence findings` or
  identifies the concrete new finding
