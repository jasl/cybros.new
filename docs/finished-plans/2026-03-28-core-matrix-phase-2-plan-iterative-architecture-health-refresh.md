# Core Matrix Phase 2 Iterative Architecture Health Refresh Audit Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Run a refreshed whole-system architecture-health audit of `core_matrix`, reconcile it against the earlier audit and cleanup plans, and keep scanning until the current codebase yields no new high-confidence structural findings for two consecutive rounds.

**Architecture:** Start by creating one new findings artifact and freezing the current architecture baseline plus prior-audit reconciliation state. Then execute the mandatory five-round scan model from the approved design: baseline reconciliation, boundary review, hotspot deep dive, cross-cut anti-pattern pass, and counter-evidence pass. If any round surfaces new high-confidence issues, keep running targeted extra rounds on the neighboring contract family until two consecutive rounds add nothing new. Publish only evidence-backed findings and risk smells, split into residual earlier issues versus newly discovered issues.

**Tech Stack:** Markdown, git, `rg`, `find`, `sed`, Ruby on Rails code under `core_matrix`, Minitest as reverse evidence, behavior docs in `core_matrix/docs/behavior`, and `agents/fenix` as the external runtime boundary

---

## Execution Rules

- Audit the whole current `core_matrix`; do not silently narrow the work to
  only the newest Phase 2 files.
- Use the earlier audit, structural-consolidation plan, and repair-loop plan
  as hypotheses and comparison points, not as conclusions to inherit.
- Treat `agents/fenix` only as the external boundary of `core_matrix`; do not
  expand this into an independent full audit of `fenix`.
- Do not modify production code in this batch.
- Keep private round notes uncommitted; the only committed output of the audit
  itself is the refreshed findings document.
- Only publish items that clear the approved evidence bar.
- Every reported item must say whether it is:
  - a residual earlier issue
  - a newly discovered issue
  - a residual earlier risk smell
  - a newly discovered risk smell
- The audit must run at least five rounds.
- After Round 5, keep going if a round finds any new high-confidence issue.
- Stop only after two consecutive rounds add no new high-confidence findings.
- The final report must end with exactly three structural priorities.

## Deliverable

This plan must create and finish:

- `docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md`

That findings document must include:

- `## Scope`
- `## System Judgment`
- `## Confirmed Findings`
- `## Risk Smells / Reinforcement Opportunities`
- `## Top Structural Priorities`
- `## Round Log`
- `## Completeness Check`

Within `## Confirmed Findings`, use these second-level subsections:

- `### Residual Earlier Findings`
- `### Newly Discovered Findings`

Within `## Risk Smells / Reinforcement Opportunities`, use these second-level
subsections:

- `### Residual Earlier Risk Smells`
- `### Newly Discovered Risk Smells`

## Task 1: Create The Refreshed Findings Scaffold

**Files:**
- Create: `docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md`
- Reference: `docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-design.md`

**Step 1: Write the findings scaffold**

Create the file with these exact top-level headings:

```markdown
# Core Matrix Phase 2 Iterative Architecture Health Refresh Findings

## Scope

## System Judgment

## Confirmed Findings

### Residual Earlier Findings

### Newly Discovered Findings

## Risk Smells / Reinforcement Opportunities

### Residual Earlier Risk Smells

### Newly Discovered Risk Smells

## Top Structural Priorities

## Round Log

## Completeness Check
```

**Step 2: Add the fixed scope baseline**

Under `## Scope`, add bullets that state:

- this is a whole-system audit of the current `core_matrix`
- the method is `mixed refresh + iterative scanning`
- the work reconciles earlier audit conclusions against current code
- the work is a Phase 2 mid-flight cleanup audit where destructive follow-up is
  acceptable

**Step 3: Verify the scaffold**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "^## |^### " docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md
```

Expected: all required section headings are present and ordered correctly.

**Step 4: Commit**

```bash
git add docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md
git commit -m "docs: add iterative architecture refresh findings scaffold"
```

## Task 2: Capture The Current Architecture Baseline And Prior-Audit State

**Files:**
- Modify: `docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md`
- Reference: `docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md`
- Reference: `docs/plans/2026-03-28-core-matrix-phase-2-plan-structural-consolidation-follow-up.md`
- Reference: `docs/plans/2026-03-28-core-matrix-phase-2-plan-post-consolidation-repair-loop.md`
- Reference: `core_matrix/app`
- Reference: `core_matrix/test`

**Step 1: Capture the current shape**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
find app -maxdepth 2 -type d | sort
find test -maxdepth 2 -type d | sort
for d in app/models app/services app/controllers app/queries test/services test/models test/requests test/integration; do
  printf "%s " "$d"
  find "$d" -type f | wc -l
done
find app/services -mindepth 1 -maxdepth 1 -type d -exec sh -c 'printf "%s " "$(basename "$1")"; find "$1" -type f | wc -l' _ {} \; | sort -k2nr
```

Expected: a stable inventory of current architecture hotspots.

**Step 2: Reconcile the earlier audit baseline**

Read:

- `docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md`
- `docs/plans/2026-03-28-core-matrix-phase-2-plan-structural-consolidation-follow-up.md`
- `docs/plans/2026-03-28-core-matrix-phase-2-plan-post-consolidation-repair-loop.md`

Then add bullets under `## Scope` and `## Round Log` that record:

- the frozen execution root shape:
  `Conversation -> Turn -> WorkflowRun -> WorkflowNode`
- the current heaviest namespaces by file count
- which earlier findings appear resolved in code
- which earlier findings still look residual and need re-verification
- which newer surfaces now require deeper review

**Step 3: Start the completeness log**

Under `## Completeness Check`, add bullets that say:

- baseline inventory captured
- prior audit reconciled against current plans
- the audit still owes round-by-round code review and counter-evidence

**Step 4: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md
git commit -m "docs: record iterative audit baseline"
```

## Task 3: Run Round 2 Boundary Review Across Conversation, Workflow, And Control

**Files:**
- Modify: `docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md`
- Reference: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Reference: `core_matrix/docs/behavior/workflow-graph-foundations.md`
- Reference: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Reference: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Reference: `core_matrix/app/models/conversation.rb`
- Reference: `core_matrix/app/services/conversations`
- Reference: `core_matrix/app/services/workflows`
- Reference: `core_matrix/app/services/agent_control`
- Reference: `core_matrix/test/services/conversations`
- Reference: `core_matrix/test/services/workflows`
- Reference: `core_matrix/test/services/agent_control`

**Step 1: Read the contracts and implementations**

Focus on:

- who writes lifecycle state
- whether blockers, guards, and close progression still have one authority
- whether workflow and runtime control boundaries stay separate
- whether tests reinforce the intended boundaries or compensate for weak ones

**Step 2: Keep private scratch notes**

For each candidate item, record privately:

- candidate title
- evidence files
- structural cost
- counterpoint
- provisional type: residual earlier or newly discovered

Do not write candidate findings into the committed report yet.

**Step 3: Record round coverage**

Under `## Round Log`, add:

- the files or namespaces reviewed in this round
- whether the round produced any new high-confidence candidates
- whether any earlier findings were rejected as no longer current

Under `## Completeness Check`, note that Round 2 is complete.

**Step 4: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md
git commit -m "docs: record boundary review round"
```

## Task 4: Run Round 3 Boundary Review Across Runtime Binding, Provider, And Read Side

**Files:**
- Modify: `docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md`
- Reference: `core_matrix/app/models/execution_environment.rb`
- Reference: `core_matrix/app/models/agent_deployment.rb`
- Reference: `core_matrix/app/services/execution_environments`
- Reference: `core_matrix/app/services/agent_deployments`
- Reference: `core_matrix/app/services/runtime_capabilities`
- Reference: `core_matrix/app/services/provider_catalog`
- Reference: `core_matrix/app/services/provider_execution`
- Reference: `core_matrix/app/services/provider_credentials`
- Reference: `core_matrix/app/services/provider_entitlements`
- Reference: `core_matrix/app/services/provider_policies`
- Reference: `core_matrix/app/services/provider_usage`
- Reference: `core_matrix/app/queries`
- Reference: `core_matrix/app/controllers/agent_api`
- Reference: `core_matrix/test/services/agent_deployments`
- Reference: `core_matrix/test/services/provider_execution`
- Reference: `core_matrix/test/services/provider_usage`
- Reference: `core_matrix/test/queries`
- Reference: `core_matrix/test/requests/agent_api`

**Step 1: Read the runtime, provider, and read-side contracts**

Focus on:

- ownership of runtime identity
- whether runtime capability projection has one obvious owner
- whether provider governance and execution remain orthogonal
- whether read-side objects are still read-only and decision-light
- whether controllers stay boundary-thin

**Step 2: Append private scratch notes**

Extend the same private scratch notes from Task 3. Do not publish candidates
yet.

**Step 3: Record round coverage**

Under `## Round Log`, add:

- reviewed files or namespaces
- whether new high-confidence candidates appeared
- whether any earlier residual concern now looks fully resolved

Under `## Completeness Check`, note that Round 3 is complete.

**Step 4: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md
git commit -m "docs: record runtime and provider review round"
```

## Task 5: Run Round 4 Hotspot Deep Dive On The Newest Phase 2 Surfaces

**Files:**
- Modify: `docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md`
- Reference: `core_matrix/app/models/subagent_connection.rb`
- Reference: `core_matrix/app/services/subagent_connections`
- Reference: `core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb`
- Reference: `core_matrix/app/models/runtime_capability_contract.rb`
- Reference: `core_matrix/app/models/turn_execution_snapshot.rb`
- Reference: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Reference: `core_matrix/app/services/conversations/reconcile_close_operation.rb`
- Reference: `core_matrix/app/services/conversations/request_resource_closes.rb`
- Reference: `core_matrix/test/services/subagent_connections`
- Reference: `core_matrix/test/services/runtime_capabilities`
- Reference: `core_matrix/test/services/conversations`
- Reference: `agents/fenix/app/services/runtime/pairing_manifest.rb`
- Reference: `agents/fenix/app/services/context/build_execution_context.rb`
- Reference: `agents/fenix/app/services/runtime/execute_assignment.rb`

**Step 1: Deep-read the hotspot contracts**

Focus on:

- whether subagent control is actually conversation-first in current code
- whether runtime capability shaping has duplicate owners
- whether execution snapshot context and runtime payloads stay coherent
- whether close-control and session-control concepts overlap
- whether `core_matrix` and `fenix` are each owning the right half of the
  runtime contract

**Step 2: Append private scratch notes**

Record new candidates, especially if they only become visible when the newest
Phase 2 boundaries are considered together.

**Step 3: Record round coverage**

Under `## Round Log`, add:

- hotspot files reviewed
- newly discovered versus residual candidate counts
- whether this round expanded the audit into any extra neighboring surface

Under `## Completeness Check`, note that Round 4 is complete.

**Step 4: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md
git commit -m "docs: record hotspot deep dive round"
```

## Task 6: Run Round 5 Cross-Cut Anti-Pattern Pass

**Files:**
- Modify: `docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md`
- Reference: `core_matrix/app/models`
- Reference: `core_matrix/app/services`
- Reference: `core_matrix/app/queries`
- Reference: `core_matrix/test`

**Step 1: Search for cross-cutting patterns**

Run focused searches such as:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rg -n "with_lock|transaction|ValidateMutableState|BlockerSnapshotQuery|to_h|deep_stringify_keys|profile_catalog|tool_catalog|request_context|close_operation|subagent_connection"
rg -n "class .*Query|class .*Projection|class .*Resolver" app/queries app/services
rg -n "payload|metadata|snapshot" app/models app/services
```

Expected: a map of repeated guard families, hash-contract families, and wrapper
layers that may not show up clearly in boundary-by-boundary reading.

**Step 2: Re-check sibling implementations**

Compare repeated patterns and decide whether they represent:

- a real duplicate path
- an intentional boundary seam
- a misleading but harmless naming pattern

**Step 3: Record round coverage**

Under `## Round Log`, add:

- the search patterns used
- which candidates were strengthened
- which candidates were weakened or dropped

Under `## Completeness Check`, note that Round 5 is complete.

**Step 4: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md
git commit -m "docs: record anti-pattern review round"
```

## Task 7: Run The Counter-Evidence Pass And Promote Only Survivors

**Files:**
- Modify: `docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md`
- Reference: `core_matrix/test`
- Reference: `core_matrix/docs/behavior`
- Reference: any file previously cited as candidate evidence

**Step 1: Challenge every candidate**

For every surviving candidate from earlier rounds, explicitly check:

- whether neighboring code already centralizes the concern
- whether tests already lock the contract down tightly enough to weaken the
  concern
- whether behavior docs show the current shape is intentional and still
  coherent

Drop any candidate that fails this challenge.

**Step 2: Write the report content**

Populate:

- `## System Judgment`
- `### Residual Earlier Findings`
- `### Newly Discovered Findings`
- `### Residual Earlier Risk Smells`
- `### Newly Discovered Risk Smells`
- `## Top Structural Priorities`

Every kept item must include:

- why it matters
- evidence
- structural impact
- action direction
- practical priority

**Step 3: Record the fifth-round result**

Under `## Round Log`, add:

- how many candidates survived
- how many were dropped by counter-evidence
- whether Round 5 still produced any new high-confidence findings

Under `## Completeness Check`, note that the mandatory five rounds are done.

**Step 4: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md
git commit -m "docs: publish iterative architecture audit findings"
```

## Task 8: Continue Extra Rounds Until The Stop Condition Is Actually True

**Files:**
- Modify: `docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md`
- Reference: whichever files were implicated by the last round

**Step 1: Decide whether an extra round is required**

If Round 5 found any new high-confidence issue, or if the immediately
following round also finds one, continue.

Do not stop just because the mandatory five rounds are complete.

**Step 2: Run the extra round on the neighboring surface**

Read the adjacent boundary or contract family that could reveal whether the
new issue is:

- local
- duplicated elsewhere
- only a symptom of a deeper authority problem

**Step 3: Update the report and round log**

Under `## Round Log`, add:

- round number
- focus surface
- whether the round produced new high-confidence findings
- the running count of consecutive no-new-finding rounds

Revise findings or risk smells if the extra round materially changes the
conclusion.

**Step 4: Repeat until the stop condition holds**

Stop only when:

- at least five rounds are complete
- two consecutive rounds have produced no new high-confidence findings

**Step 5: Commit after each extra round**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md
git commit -m "docs: record iterative audit extra round"
```

## Final Verification

After the final round, run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git diff --check
git status --short
rg -n "^## |^### " docs/plans/2026-03-28-core-matrix-phase-2-iterative-architecture-health-refresh-findings.md
```

Then manually verify that the findings document:

- reflects a whole-system audit
- clearly separates residual earlier issues from newly discovered issues
- clearly separates confirmed findings from risk smells
- records how many rounds were run
- states why the audit stopped
- ends with exactly three structural priorities

## Stop Condition

This plan is complete only when:

- the findings document is finished
- at least five rounds ran
- two consecutive rounds added no new high-confidence findings
- only evidence-backed items remain in the report
- the report is specific enough that the next cleanup plan can be written
  directly from it without rediscovering the architecture questions
