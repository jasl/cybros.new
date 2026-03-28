# Architecture Health Audit Follow-Up Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Run one whole-system architecture health audit of `core_matrix`, publish only evidence-backed findings plus simplification or reinforcement opportunities, and end with a short system judgment that can drive the next Milestone C cleanup batch.

**Architecture:** The audit starts by creating one findings artifact and freezing the current architecture map and hotspot inventory. It then reviews the system through the six-boundary model in grouped passes, runs a separate anti-pattern and test reverse pass, and only then promotes evidence-backed conclusions into the final report. The work ends with a document-quality self-check that verifies completeness, prose flow, and whether the report is actionable enough to plan from directly.

**Tech Stack:** Markdown, git, ripgrep, sed, find, Ruby on Rails code under `core_matrix`, existing Phase 2 planning and behavior docs

---

## Execution Rules

- Audit the whole current `core_matrix`; do not silently narrow the work to only
  the newest Phase 2 files.
- Do not modify production code in this batch.
- Use `core_matrix/docs/behavior` and the existing Phase 2 planning docs as
  contract references, not as a substitute for reading the implementation.
- Keep local scratch notes uncommitted; the only committed output of the audit
  itself is the findings document.
- Do not publish candidate-only smells. Every reported item must clear the
  evidence bar from the design document.
- Keep the final report to the two requested result sections only:
  `Findings` and `Simplification / Reinforcement Opportunities`.
- End with a short system judgment and exactly three structural priorities.
- After each task, re-read the edited markdown before committing.

## Deliverable

The execution of this plan must create and finish:

- `docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md`

That findings document must include:

- `## Scope`
- `## System Judgment`
- `## Findings`
- `## Simplification / Reinforcement Opportunities`
- `## Top Structural Priorities`
- `## Completeness Check`

### Task 1: Create The Findings Scaffold

**Files:**
- Create: `docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md`
- Reference: `docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-design.md`

**Step 1: Write the findings document scaffold**

Create the file with these exact top-level headings:

```markdown
# Core Matrix Phase 2 Architecture Health Audit Follow-Up Findings

## Scope

## System Judgment

## Findings

## Simplification / Reinforcement Opportunities

## Top Structural Priorities

## Completeness Check
```

**Step 2: Add the fixed scope baseline**

Under `## Scope`, add bullets that state:

- this is a whole-application audit of `core_matrix`
- the primary review surfaces are `app/models`, `app/services`,
  `app/queries`, `app/controllers`, and `test`
- the method is `six-boundary review + anti-pattern cross-check`
- the work is a Milestone C follow-up

**Step 3: Verify the scaffold**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "^## " docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md
```

Expected: all six section headings are present and in the intended order.

**Step 4: Commit**

```bash
git add docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md
git commit -m "docs: add architecture health audit findings scaffold"
```

### Task 2: Record The Architecture Map And Hotspot Inventory

**Files:**
- Modify: `docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md`
- Reference: `core_matrix/app`
- Reference: `core_matrix/test`
- Reference: `core_matrix/docs/behavior`

**Step 1: Capture the current top-level shape**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
find app -maxdepth 2 -type d | sort
find test -maxdepth 2 -type d | sort
for d in app/models app/services app/controllers app/queries test/services test/integration test/models; do
  printf "%s " "$d"
  find "$d" -type f | wc -l
done
find app/services -mindepth 1 -maxdepth 1 -type d -exec sh -c 'printf "%s " "$(basename "$1")"; find "$1" -type f | wc -l' _ {} \; | sort -k2nr
```

Expected: a stable namespace inventory and a ranked hotspot list.

**Step 2: Record the architecture baseline**

Expand `## Scope` with:

- the frozen execution root shape:
  `Conversation -> Turn -> WorkflowRun -> WorkflowNode`
- the heaviest namespaces by volume
- the six audit boundaries from the design document
- the note that recent hardening concentrated around close, runtime binding,
  mutation safety, and lineage or provenance

**Step 3: Start the completeness log**

Under `## Completeness Check`, add bullets that note:

- the system map was captured
- the hotspot inventory was recorded
- the audit still owes boundary review, cross-check, and final writing

**Step 4: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md
git commit -m "docs: record architecture audit baseline"
```

### Task 3: Review Conversation, Workflow, And Control-Plane Boundaries

**Files:**
- Modify: `docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md`
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

**Step 1: Read the boundary contracts**

Read the four behavior docs above and the highest-signal implementation files in
`conversations`, `workflows`, and `agent_control`.

Focus on:

- authority drift
- split lifecycle writers
- duplicated guards or reconciler logic
- service objects that look like scripts instead of contracts

**Step 2: Keep local scratch notes**

Capture possible findings in local scratch only. Do not write them into the
committed findings document yet.

For each scratch item, record:

- candidate title
- evidence files
- counterpoint
- why it might matter
- whether it looks like a finding or a simplification opportunity

**Step 3: Record coverage in the findings document**

Under `## Completeness Check`, add bullets that confirm the three boundary
families were reviewed and name the highest-signal files or namespaces touched.

**Step 4: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md
git commit -m "docs: record lifecycle and control audit coverage"
```

### Task 4: Review Runtime Binding, Provider, And Read-Side Boundaries

**Files:**
- Modify: `docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md`
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
- Reference: `core_matrix/test/services/provider_catalog`
- Reference: `core_matrix/test/services/provider_credentials`
- Reference: `core_matrix/test/services/provider_entitlements`
- Reference: `core_matrix/test/services/provider_policies`
- Reference: `core_matrix/test/services/provider_usage`
- Reference: `core_matrix/test/services/providers`
- Reference: `core_matrix/test/queries`
- Reference: `core_matrix/test/requests/agent_api`

**Step 1: Read the runtime-binding and provider contracts**

Read the deployment, execution-environment, provider-governance, and read-side
implementations plus their neighboring tests.

Focus on:

- ownership of runtime identity
- whether provider governance and provider execution stay orthogonal
- whether read-side objects stay read-only and decision-light
- whether controller and API surfaces are thin boundaries or mixed orchestration

**Step 2: Keep local scratch notes**

Append any new candidates to the same local scratch notes from Task 3. Do not
promote anything to the final report yet.

**Step 3: Record coverage in the findings document**

Under `## Completeness Check`, add bullets confirming that runtime binding,
provider, and read-side boundaries were reviewed.

**Step 4: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md
git commit -m "docs: record runtime and provider audit coverage"
```

### Task 5: Run The Anti-Pattern And Test Reverse Pass

**Files:**
- Modify: `docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md`
- Reference: `core_matrix/app`
- Reference: `core_matrix/test`

**Step 1: Scan for repeated structural patterns**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rg -n "with_lock|ApplicationRecord\\.transaction|update!\\(|update_columns\\(|origin_payload|wait_reason_payload|summary_payload|blocking_resource_id|public_id" app test
rg -n "payload|metadata|contract|reconcile|resume|retry|rerun|rollback|close|archive|delete" app/services app/models test
find app/models app/services app/queries app/controllers -type f -name "*.rb" -print0 | xargs -0 wc -l | sort -nr | sed -n '1,80p'
```

Expected: concentrated hits around repeated lock, payload, lifecycle, and
large-file patterns.

**Step 2: Compare siblings and tests**

Use the grep results to revisit sibling services and their tests. Confirm or
reject each scratch candidate by checking whether:

- the same rule is implemented more than once
- tests reveal awkward setup or unclear ownership
- a supposed smell is actually necessary because the behavior contract is
  explicitly wider than it first appeared

**Step 3: Record coverage in the findings document**

Under `## Completeness Check`, add bullets confirming that:

- the anti-pattern cross-check ran
- tests were used as reverse evidence
- some scratch candidates were dropped or weakened if the second pass did not
  support them

**Step 4: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md
git commit -m "docs: record architecture audit cross-check coverage"
```

### Task 6: Write The Final Findings And Opportunities

**Files:**
- Modify: `docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md`

**Step 1: Promote only evidence-backed conclusions**

Re-read the local scratch notes and keep only the items that survived both the
boundary review and the anti-pattern cross-check.

Write each entry under one of the two result sections using this exact shape:

```markdown
### [Short title]
- Why it matters:
- Evidence:
- Impact:
- Suggested direction:
```

Do not leave any item in the report unless all four bullets are present.

**Step 2: Write the system judgment**

Under `## System Judgment`, write a short paragraph or short bullet list that
answers:

- whether the architecture is broadly healthy
- where the necessary complexity is concentrated
- where accidental complexity is starting to appear

**Step 3: Write the top priorities**

Under `## Top Structural Priorities`, write exactly three numbered items. Each
priority must name a structural cleanup direction, not a vague topic area.

**Step 4: Verify the report structure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "^- Why it matters:|^- Evidence:|^- Impact:|^- Suggested direction:" docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md
```

Expected: every reported entry contributes all four required bullets.

**Step 5: Commit**

```bash
git add docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md
git commit -m "docs: write architecture health audit findings"
```

### Task 7: Self-Check Completeness, Text Flow, And Executability

**Files:**
- Modify: `docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md`

**Step 1: Re-read the full report for flow**

Read the entire findings document from top to bottom and tighten any sentence
that is repetitive, vague, or harder to follow than necessary.

Specifically re-check that the document flows in this order:

1. scope and audit method
2. system judgment
3. findings
4. simplification or reinforcement opportunities
5. priorities
6. completeness check

**Step 2: Fill the completeness checklist**

Under `## Completeness Check`, confirm all of the following in plain bullets:

- the whole current `core_matrix` application was covered
- all six boundaries were reviewed
- the anti-pattern cross-check ran
- tests were used as reverse evidence
- every reported item has evidence and an action direction
- the report ends with exactly three priorities
- the prose was re-read once for flow before final commit

**Step 3: Run the final self-check commands**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "^## |^### " docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md
rg -n "TODO|TBD|FIXME|pending cross-check|candidate-only" docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md
sed -n '1,260p' docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md
```

Expected:

- the sections appear in the intended order
- no placeholder or scratch markers remain
- the prose reads cleanly without missing transitions or incomplete bullets

**Step 4: Commit**

```bash
git add docs/plans/2026-03-28-core-matrix-phase-2-architecture-health-audit-follow-up-findings.md
git commit -m "docs: finalize architecture health audit follow-up"
```
