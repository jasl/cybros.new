# Core Matrix Architecture Health Audit Round 1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Run the first repeatable architecture-health audit round for `core_matrix`, collect broad candidate signals through parallel review angles, verify the strongest signals, and publish a durable register plus a round report with actionable findings and unification opportunities.

**Architecture:** The work starts by creating the persistent audit artifacts, then runs four read-only broad scans from fixed viewpoints, then normalizes and verifies candidate signals in the main thread before writing the final round report. The output is intentionally split between a cumulative register and a round-specific report so future rounds can build on the first one instead of starting over.

**Tech Stack:** Markdown, git, ripgrep, sed, find, Ruby on Rails code under `core_matrix`, existing phase and behavior docs

---

Execute this plan from a dedicated worktree rooted at:

- `/Users/jasl/Workspaces/Ruby/cybros`

## Execution Order And Dependencies

Run the tasks in order.

1. Task 1 creates the durable audit artifacts.
2. Task 2 records the current architecture map and scope baseline.
3. Tasks 3 through 6 collect candidates from the four fixed review angles.
4. Task 7 normalizes and clusters those candidates.
5. Task 8 verifies the strongest clusters against code, tests, and docs.
6. Task 9 writes the confirmed findings, healthy patterns, and backlog.
7. Task 10 updates the register, performs the completeness review, and closes
   the round.

Do not skip ahead. Later tasks depend on earlier evidence.

## Completion Gate

Do not consider Round 1 complete until:

- the register exists on disk
- the round report exists on disk
- all four broad-scan viewpoints have been run
- each confirmed finding has evidence, counterpoint, and a practical solution
- each unification opportunity has a target shape and migration path
- the round report distinguishes confirmed findings from candidate-only signals
- the round report names healthy patterns worth preserving

### Task 1: Create The Audit Register And Round Report Scaffolds

**Files:**
- Create: `docs/reports/core-matrix-architecture-health-audit-register.md`
- Create: `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`
- Reference: `docs/plans/2026-03-27-core-matrix-architecture-health-audit-design.md`

**Step 1: Write the register scaffold**

Add these top-level sections:

```markdown
# Core Matrix Architecture Health Audit Register

## Status Model

## Entry Index

## Active Entries

## Resolved Or Retired Entries
```

**Step 2: Write the round report scaffold**

Add these top-level sections:

```markdown
# Core Matrix Architecture Health Audit Round 1

## Scope For This Round

## Executive Summary

## Confirmed Findings

## Candidate Signals

## Healthy Patterns Worth Preserving

## Simplification / Reinforcement Backlog

## Suggested Focus For The Next Round

## Completeness Check
```

**Step 3: Verify both files exist and have the right headings**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "^## " docs/reports/core-matrix-architecture-health-audit-register.md docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md
```

Expected: headings from both scaffolds are listed with no missing section.

**Step 4: Commit the scaffolds**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/reports/core-matrix-architecture-health-audit-register.md docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md
git commit -m "docs: add architecture health audit scaffolds"
```

### Task 2: Record The Architecture Map And Scope Baseline

**Files:**
- Modify: `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`
- Reference: `core_matrix/app/**/*`
- Reference: `core_matrix/test/**/*`
- Reference: `core_matrix/docs/behavior/**/*`

**Step 1: Capture the current top-level shape**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
find app -maxdepth 2 -type d | sort
find test -maxdepth 2 -type d | sort
```

Expected: stable namespace inventory for the audit baseline.

**Step 2: Record the frozen runtime root shape**

Write a short baseline summary into `## Scope For This Round` that names the
current root chain:

```markdown
- frozen execution root shape: `Conversation -> Turn -> WorkflowRun -> WorkflowNode`
- phase context: Milestone A through C landed, with recent hardening around close, mutation, and lineage contracts
- audit emphasis: structure health, not only defect discovery
```

**Step 3: Record the primary review surfaces**

Write the in-scope directories and the four broad-scan viewpoints into the same
section.

**Step 4: Commit the scope baseline**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md
git commit -m "docs: record architecture health audit scope baseline"
```

### Task 3: Run The Layering Broad Scan

**Files:**
- Modify: `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`
- Reference: `core_matrix/app/models/**/*.rb`
- Reference: `core_matrix/app/services/**/*.rb`
- Reference: `core_matrix/app/queries/**/*.rb`
- Reference: `core_matrix/app/controllers/**/*.rb`

**Step 1: Search for large or high-yield files**

Dispatch one fresh read-only subagent for the layering viewpoint. Its only
deliverable is candidate-signal text for the round report.

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
find app/models app/services app/queries app/controllers -type f -name "*.rb" -print0 | xargs -0 wc -l | sort -nr | sed -n '1,80p'
```

Expected: a short ranked list of large files worth inspection.

**Step 2: Read the likely ownership hotspots**

Read the largest or highest-signal files in `conversations`, `workflows`,
`turns`, `agent_control`, and related models.

**Step 3: Add layering candidates**

Write candidate entries under `## Candidate Signals` using this exact shape:

```markdown
### Candidate: [short title]
- Category: `layering`
- Why suspicious:
- Evidence:
- Possible impact:
- Counterpoint:
- Suggested direction:
- Related concepts:
```

**Step 4: Commit the layering candidates**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md
git commit -m "docs: record layering audit candidates"
```

### Task 4: Run The Contract Broad Scan

**Files:**
- Modify: `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`
- Reference: `core_matrix/app/services/**/*.rb`
- Reference: `core_matrix/app/models/**/*.rb`
- Reference: `core_matrix/docs/behavior/**/*.md`

**Step 1: Search for contract family entry points**

Dispatch one fresh read-only subagent for the contract viewpoint. Its only
deliverable is candidate-signal text for the round report.

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rg -n "timeline|mutation|runtime|binding|lineage|provenance|provider|mailbox|control|lease|close" app/models app/services docs/behavior
```

Expected: concentrated hits around the contract families named in the design.

**Step 2: Inspect whether rules are repeated or split**

Compare sibling writers and validators for the same contract family. Look for
multiple owners, repeated guards, or hidden cross-contract dependencies.

**Step 3: Add contract candidates**

Append contract-focused candidate entries under `## Candidate Signals`.

**Step 4: Commit the contract candidates**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md
git commit -m "docs: record contract audit candidates"
```

### Task 5: Run The Complexity Broad Scan

**Files:**
- Modify: `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`
- Reference: `core_matrix/app/**/*.rb`
- Reference: `core_matrix/lib/**/*.rb`
- Reference: `core_matrix/test/**/*_test.rb`

**Step 1: Search for repeated guard or transaction patterns**

Dispatch one fresh read-only subagent for the complexity viewpoint. Its only
deliverable is candidate-signal text for the round report.

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rg -n "with_lock|transaction do|raise .*Error|find_by!|update!|create!" app test
```

Expected: repeated templates that may indicate duplication or concept drift.

**Step 2: Search for likely naming drift**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rg -n "Guard|Validate|With.*Lock|Manual|Retry|Resume|Create|Update|Refresh|Compose" app/services app/models
```

Expected: clusters of similarly named helpers that may or may not map cleanly
to clear ownership.

**Step 3: Add complexity candidates**

Append complexity-focused candidates under `## Candidate Signals`.

**Step 4: Commit the complexity candidates**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md
git commit -m "docs: record complexity audit candidates"
```

### Task 6: Run The Test Reverse View Broad Scan

**Files:**
- Modify: `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`
- Reference: `core_matrix/test/**/*_test.rb`

**Step 1: Identify heavy or repeated test setup**

Dispatch one fresh read-only subagent for the test reverse-view viewpoint. Its
only deliverable is candidate-signal text for the round report.

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
find test -type f -name "*_test.rb" -print0 | xargs -0 wc -l | sort -nr | sed -n '1,80p'
```

Expected: the largest test files and likely high-setup suites.

**Step 2: Review setup shape and assertion style**

Read the high-setup suites and note where tests reveal awkward production
boundaries, excessive fixture choreography, or missing negative-path coverage.

**Step 3: Add reverse-view candidates**

Append test-driven candidates under `## Candidate Signals`.

**Step 4: Commit the reverse-view candidates**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md
git commit -m "docs: record reverse-view audit candidates"
```

### Task 7: Normalize And Cluster Candidate Signals

**Files:**
- Modify: `docs/reports/core-matrix-architecture-health-audit-register.md`
- Modify: `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`

**Step 1: Normalize candidates into shared categories**

Collapse candidate phrasing into a smaller vocabulary:

- `responsibility drift`
- `boundary ambiguity`
- `contract duplication`
- `concept or naming drift`
- `accidental complexity`
- `test-exposed structural weakness`

**Step 2: Assign stable IDs in the register**

Create entries such as:

```markdown
### AH-001
- Status: `candidate`
- Title:
- First seen: `2026-03-27`
- Last reviewed: `2026-03-27`
- Type:
- Confidence:
- Priority:
- Related files:
- Related concepts:
- Linked rounds: `round-1`
- Recommended direction:
```

**Step 3: Cluster obviously related candidates**

Group candidates that likely point at one larger shape problem. Mark likely
cluster leaders in the round report.

**Step 4: Commit the normalized register**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/reports/core-matrix-architecture-health-audit-register.md docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md
git commit -m "docs: normalize architecture audit candidates"
```

### Task 8: Verify The Strongest Clusters

**Files:**
- Modify: `docs/reports/core-matrix-architecture-health-audit-register.md`
- Modify: `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`
- Reference: `core_matrix/app/**/*.rb`
- Reference: `core_matrix/test/**/*_test.rb`
- Reference: `core_matrix/docs/behavior/**/*.md`

**Step 1: Pick the highest-value candidate clusters**

Select only the strongest clusters for promotion. Prefer issues seen from more
than one scan angle.

**Step 2: Re-read code, sibling implementations, and tests**

For each selected cluster, collect evidence from at least two of:

- direct code
- sibling comparison
- tests
- behavior docs

**Step 3: Reject weak or necessary-complexity signals**

Move disproven or overreaching candidates toward `retired` in the register.

**Step 4: Promote surviving items**

Update the register status to `confirmed`, `clustered`, or
`unification-opportunity` as appropriate.

**Step 5: Commit the verified promotions**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/reports/core-matrix-architecture-health-audit-register.md docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md
git commit -m "docs: verify architecture audit findings"
```

### Task 9: Write Confirmed Findings, Healthy Patterns, And Backlog

**Files:**
- Modify: `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`
- Modify: `docs/reports/core-matrix-architecture-health-audit-register.md`

**Step 1: Write the executive summary**

Summarize:

- overall system-health judgment
- the top problem families
- the top healthy patterns
- the next likely follow-up areas

**Step 2: Write confirmed findings in the required shape**

For each confirmed finding, include:

```markdown
### [finding title]
- Priority:
- Confidence:
- Why it matters:
- Evidence:
- Counterpoint:
- Related concepts:
- Local fix:
- Systemic fix:
```

**Step 3: Write unification opportunities**

For each one, include:

```markdown
### [unification title]
- Current shape:
- Why it is not orthogonal:
- Target shape:
- Single owner / source of truth:
- What should be merged / deleted / demoted:
- Migration path:
- Risk if left as-is:
```

**Step 4: Write healthy patterns and backlog**

Populate:

- `## Healthy Patterns Worth Preserving`
- `## Simplification / Reinforcement Backlog`
- `## Suggested Focus For The Next Round`

**Step 5: Commit the round report**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/reports/core-matrix-architecture-health-audit-register.md docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md
git commit -m "docs: publish architecture health audit round 1"
```

### Task 10: Run The Completeness Review

**Files:**
- Modify: `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`
- Modify: `docs/reports/core-matrix-architecture-health-audit-register.md`

**Step 1: Verify the required sections exist**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "^## " docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md docs/reports/core-matrix-architecture-health-audit-register.md
```

Expected: all required top-level sections are present.

**Step 2: Verify every confirmed finding has a solution**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "Local fix:|Systemic fix:|Migration path:" docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md
```

Expected: every confirmed finding and unification opportunity has corrective
guidance.

**Step 3: Write the completeness check**

Fill `## Completeness Check` with:

- what was completed
- what remains candidate-only
- any unresolved blind spots

**Step 4: Commit the completeness pass**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add docs/reports/core-matrix-architecture-health-audit-register.md docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md
git commit -m "docs: finalize architecture health audit round 1"
```
