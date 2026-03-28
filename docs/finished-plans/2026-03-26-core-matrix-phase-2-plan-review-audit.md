# Core Matrix Review Audit Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Audit the scoped Core Matrix Ruby code for leftover development code, Ruby and Rails philosophy drift, and potential risks, then write the conclusions to a persistent findings document.

**Architecture:** Use a fixed multi-pass review flow. Start with a read-only global signal scan, then inspect layered runtime paths, then re-check the same themes through cross-cutting rules and tests. Persist the conclusions in a findings artifact and do a final completeness review before calling the work done.

**Tech Stack:** Ruby on Rails, Active Record, Minitest, ripgrep, git

---

## Execution Order and Dependencies

Run the tasks strictly in order.

1. Task 1 creates the persistent review artifact and establishes the review
   rules.
2. Task 2 identifies the highest-yield targets and provides inputs to the deeper
   passes.
3. Task 3 performs the main layered inspection against those targets.
4. Task 4 validates boundary, lifecycle, and infrastructure risks that cut
   across the layered pass.
5. Task 5 re-checks earlier conclusions through tests and can downgrade or
   confirm them.
6. Task 6 finalizes the findings, runs the completeness check, and closes the
   audit.

No task should be skipped or reordered because the later tasks depend on the
evidence gathered earlier.

## Completion Gate

Do not consider the review complete until:

- the findings artifact exists on disk
- all scoped Ruby directories have been reviewed
- each issue class has been checked in both the primary and reverse pass
- every conclusion has evidence and a recommended action
- the report clearly separates findings, suggestions, and watch-list items
- the completeness check passes without needing unwritten assumptions

---

### Task 1: Establish Review Artifacts and Context

**Files:**
- Modify: `README.md`
- Modify: `docs/behavior/identifier-policy.md`
- Modify: `docs/plans/2026-03-26-core-matrix-phase-2-review-audit-design.md`
- Create: `docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md`

**Step 1: Create the findings scaffold**

Add a findings document with these sections:

```markdown
# Core Matrix Review Audit Findings

## Scope

## Findings

## Suggestions

## Watch List

## Cross-check Summary

## Completeness Check
```

**Step 2: Load project context**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
sed -n '1,220p' README.md
sed -n '1,220p' docs/behavior/identifier-policy.md
```

Expected: the product context and `public_id` boundary rules are visible and can
be used as review baselines.

**Step 3: Record the scope and rules in the findings doc**

Write the review scope, excluded areas, and the requirement to check each issue
class twice.

**Step 4: Verify the scaffold is complete**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
sed -n '1,200p' docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md
```

Expected: the findings document has all required top-level sections.

**Step 5: Commit the review scaffold**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md
git commit -m "docs: add core matrix review audit findings scaffold"
```

### Task 2: Run the Global Signal Scan

**Files:**
- Modify: `docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md`
- Modify: `app/**/*.rb`
- Modify: `lib/**/*.rb`
- Modify: `config/**/*.rb`
- Modify: `db/**/*.rb`
- Modify: `test/**/*_test.rb`

**Step 1: Search for leftover or transitional signals**

Run targeted searches for transitional names, debug remnants, broad rescues,
callback-heavy models, and suspicious boundary code.

**Step 2: Record high-yield targets**

Write the target namespaces, files, and why they were selected into the findings
doc under `Scope` or `Cross-check Summary`.

**Step 3: Search for possible style and layering drift**

Run commands to locate long files, large service namespaces, repeated patterns,
and suspicious object names.

**Step 4: Verify the scan produced actionable targets**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
sed -n '1,260p' docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md
```

Expected: the document now names specific high-yield namespaces or files for the
main review pass.

**Step 5: Commit the inventory update**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md
git commit -m "docs: record core matrix review audit targets"
```

### Task 3: Audit Layered Runtime Paths

**Files:**
- Modify: `docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md`
- Modify: `app/controllers/**/*.rb`
- Modify: `app/services/**/*.rb`
- Modify: `app/queries/**/*.rb`
- Modify: `app/models/**/*.rb`

**Step 1: Review controllers for business-logic leakage**

Check whether controllers are coordinating requests cleanly or embedding domain
decisions and lifecycle branching.

**Step 2: Review services for orchestration quality**

Check for service objects that act as dumping grounds or mix orchestration,
domain policy, persistence, and presentation concerns.

**Step 3: Review queries and models together**

Check whether read concerns stay in queries and domain rules stay close to
models, without hidden callback or lifecycle traps.

**Step 4: Record confirmed findings with evidence**

For each confirmed issue, add file references, impact, category, and a proposed
action to the findings doc.

**Step 5: Commit the layered review results**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md
git commit -m "docs: capture layered review findings"
```

### Task 4: Audit Data, Boundary, and Lifecycle Risks

**Files:**
- Modify: `docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md`
- Modify: `config/**/*.rb`
- Modify: `db/**/*.rb`
- Modify: `app/models/**/*.rb`
- Modify: `app/services/**/*.rb`

**Step 1: Check boundary identifier usage**

Search for boundary-facing payloads or lookups that could expose internal ids
instead of `public_id`.

**Step 2: Check transaction, callback, and rescue behavior**

Find flows where partial writes, hidden side effects, or swallowed failures
could exist.

**Step 3: Check config and migration cleanup**

Look for transitional flags, unstable environment branching, and schema or data
paths that still look phase-specific or provisional.

**Step 4: Record new findings or downgrade weak signals**

Update the findings doc so only evidence-backed issues remain in `Findings`.
Move uncertain items to `Watch List`.

**Step 5: Commit the risk audit results**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md
git commit -m "docs: capture core matrix risk audit findings"
```

### Task 5: Run the Test Reverse Pass

**Files:**
- Modify: `docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md`
- Modify: `test/**/*_test.rb`

**Step 1: Review tests for heavy setup and repeated scaffolding**

Look for places where the tests reveal unstable or overly coupled production
objects.

**Step 2: Review negative-path coverage**

Check whether failure modes, invalid lifecycle transitions, and boundary
violations are meaningfully covered.

**Step 3: Cross-check earlier findings**

Confirm, refine, or reject findings from the earlier passes based on test
evidence.

**Step 4: Write the cross-check summary**

Document what the reverse pass confirmed, expanded, or weakened.

**Step 5: Commit the reverse-pass results**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md
git commit -m "docs: capture reverse-pass audit results"
```

### Task 6: Finalize the Findings Document

**Files:**
- Modify: `docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md`

**Step 1: Order findings by severity**

Put must-fix items first, then suggestions, then watch-list items.

**Step 2: Ensure every conclusion is on disk**

Check that each conclusion includes category, impact, evidence, and a suggested
action.

**Step 3: Run the completeness check**

Verify:

- task goal is explicit
- work scope is explicit
- all conclusions are persisted
- acceptance conditions are sufficient
- task relationships remain logically ordered
- the audit can be executed automatically without inventing new rules

**Step 4: Re-read the document end-to-end**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
sed -n '1,260p' docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md
```

Expected: the report reads as a complete artifact and does not rely on chat-only
context.

**Step 5: Commit the final report**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md
git commit -m "docs: finalize core matrix review audit findings"
```
