# Core Matrix Boundary Coverage Campaign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Scan every `app/**/*.rb` file, strengthen tests for major and edge branches across the codebase, and finish with a ledger-backed self-audit plus current SimpleCov evidence.

**Architecture:** Work breadth-first through four waves. Keep a persistent working ledger for every application file, convert weak or missing branch coverage into focused tests, fix real bugs when tests prove them, and verify every wave with both targeted and full-suite runs.

**Tech Stack:** Ruby on Rails, Minitest, SimpleCov, PostgreSQL

---

### Task 1: Seed The Campaign Docs And Ledger

**Files:**
- Create: `docs/plans/2026-03-29-core-matrix-boundary-coverage-campaign-design.md`
- Create: `docs/plans/2026-03-29-core-matrix-boundary-coverage-campaign.md`
- Create: `docs/plans/2026-03-29-core-matrix-boundary-coverage-working-ledger.md`
- Modify: `docs/plans/2026-03-29-core-matrix-test-suite-audit-findings.md`

**Step 1: Write the failing test**

This task is documentation-first. Instead of a code test, write the factual
baseline into the ledger:

- latest SimpleCov line result
- app file count
- test file count
- initial `pending_scan` inventory for every `app/**/*.rb`

**Step 2: Run baseline commands**

Run:

```bash
find app -type f -name '*.rb' | sort | wc -l
find test -type f -name '*.rb' | sort | wc -l
bin/rails test
```

Expected:

- deterministic app and test file counts
- a current full-suite passing result
- a current SimpleCov line percentage

**Step 3: Write minimal implementation**

Create the design doc, plan, and working ledger. Update the prior findings doc
only where the new campaign reframes the next phase.

**Step 4: Verify the docs are consistent**

Check that:

- the ledger contains every `app/**/*.rb` file
- all entries start in `pending_scan`
- the baseline SimpleCov figure matches the latest full run

**Step 5: Commit**

```bash
git add docs/plans/2026-03-29-core-matrix-boundary-coverage-campaign-design.md \
  docs/plans/2026-03-29-core-matrix-boundary-coverage-campaign.md \
  docs/plans/2026-03-29-core-matrix-boundary-coverage-working-ledger.md \
  docs/plans/2026-03-29-core-matrix-test-suite-audit-findings.md
git commit -m "docs: add boundary coverage campaign plan"
```

### Task 2: Execute Wave 1 Write-Side State Machine Sweep

**Files:**
- Modify: `docs/plans/2026-03-29-core-matrix-boundary-coverage-working-ledger.md`
- Modify: `docs/plans/2026-03-29-core-matrix-test-suite-audit-findings.md`
- Modify: `app/services/workflows/**/*`
- Modify: `app/services/turns/**/*`
- Modify: `app/services/conversations/**/*`
- Modify: `app/services/provider_execution/**/*`
- Modify: `app/services/agent_deployments/**/*`
- Modify: corresponding tests under `test/services/**/*` and `test/integration/**/*`

**Step 1: Write the failing test**

For each selected file, add or strengthen a branch-focused test that proves one
of:

- invalid preconditions reject
- stale or duplicate execution rejects
- state transitions converge correctly
- malformed payloads do not slip through
- retry, resume, or cancel semantics remain coherent

**Step 2: Run focused files**

Run only the affected files and nearest integration flows first.

Expected:

- failures point at missing branch protection or real implementation bugs

**Step 3: Write minimal implementation**

- update tests
- fix product code only when the new test proves a real bug
- update the ledger statuses for every scanned file in the wave
- capture remaining gaps explicitly

**Step 4: Run wave verification**

Run a Wave 1 aggregate plus full `bin/rails test`.

Expected:

- all targeted files green
- full suite green
- latest SimpleCov line figure recorded in the ledger

**Step 5: Commit**

```bash
git add docs/plans/2026-03-29-core-matrix-boundary-coverage-working-ledger.md \
  docs/plans/2026-03-29-core-matrix-test-suite-audit-findings.md \
  app/services/workflows \
  app/services/turns \
  app/services/conversations \
  app/services/provider_execution \
  app/services/agent_deployments \
  test/services \
  test/integration
git commit -m "test: execute wave 1 boundary coverage sweep"
```

### Task 3: Execute Wave 2 Control Plane And Recovery Sweep

**Files:**
- Modify: `docs/plans/2026-03-29-core-matrix-boundary-coverage-working-ledger.md`
- Modify: `docs/plans/2026-03-29-core-matrix-test-suite-audit-findings.md`
- Modify: `app/services/agent_control/**/*`
- Modify: `app/services/subagent_connections/**/*`
- Modify: `app/services/installations/**/*`
- Modify: `app/services/execution_environments/**/*`
- Modify: `app/services/leases/**/*`
- Modify: `app/services/processes/**/*`
- Modify: corresponding tests under `test/services/**/*`, `test/requests/**/*`, and `test/integration/**/*`

**Step 1: Write the failing test**

Target:

- wrong owner or wrong runtime
- stale mailbox reports
- heartbeat expiry
- degraded or offline recovery
- nested subagent edge cases
- close-in-progress or pending-delete control-plane behavior

**Step 2: Run focused files**

Run only touched files plus the closest integration or request tests.

**Step 3: Write minimal implementation**

- strengthen or add tests
- fix control-plane bugs proved by the new tests
- update ledger statuses and remaining gaps

**Step 4: Run wave verification**

Run a Wave 2 aggregate and then full `bin/rails test`.

**Step 5: Commit**

```bash
git add docs/plans/2026-03-29-core-matrix-boundary-coverage-working-ledger.md \
  docs/plans/2026-03-29-core-matrix-test-suite-audit-findings.md \
  app/services/agent_control \
  app/services/subagent_connections \
  app/services/installations \
  app/services/execution_environments \
  app/services/leases \
  app/services/processes \
  test/services \
  test/requests \
  test/integration
git commit -m "test: execute wave 2 boundary coverage sweep"
```

### Task 4: Execute Wave 3 Read-Side And External Contract Sweep

**Files:**
- Modify: `docs/plans/2026-03-29-core-matrix-boundary-coverage-working-ledger.md`
- Modify: `docs/plans/2026-03-29-core-matrix-test-suite-audit-findings.md`
- Modify: `app/controllers/agent_api/**/*`
- Modify: `app/queries/**/*`
- Modify: `app/projections/**/*`
- Modify: `app/resolvers/**/*`
- Modify: corresponding tests under `test/requests/**/*`, `test/queries/**/*`, `test/projections/**/*`, `test/resolvers/**/*`, and `test/integration/**/*`

**Step 1: Write the failing test**

Target:

- invalid payloads
- empty results
- filtered reads
- pagination and cursor boundaries
- aggregation across mixed dimensions
- `public_id` contract boundaries

**Step 2: Run focused files**

Run the relevant request, query, projection, resolver, and integration files.

**Step 3: Write minimal implementation**

- add or tighten tests
- fix externally visible contract bugs immediately
- update ledger statuses and remaining gaps

**Step 4: Run wave verification**

Run a Wave 3 aggregate and then full `bin/rails test`.

**Step 5: Commit**

```bash
git add docs/plans/2026-03-29-core-matrix-boundary-coverage-working-ledger.md \
  docs/plans/2026-03-29-core-matrix-test-suite-audit-findings.md \
  app/controllers/agent_api \
  app/queries \
  app/projections \
  app/resolvers \
  test/requests \
  test/queries \
  test/projections \
  test/resolvers \
  test/integration
git commit -m "test: execute wave 3 boundary coverage sweep"
```

### Task 5: Execute Wave 4 Model And Extreme Constraint Sweep

**Files:**
- Modify: `docs/plans/2026-03-29-core-matrix-boundary-coverage-working-ledger.md`
- Modify: `docs/plans/2026-03-29-core-matrix-test-suite-audit-findings.md`
- Modify: `app/models/**/*`
- Modify: `app/models/concerns/**/*`
- Modify: selected integration and support files under `test/models/**/*`, `test/integration/**/*`, and `test/support/**/*`

**Step 1: Write the failing test**

Target:

- illegal state combinations
- missing required timestamps or associated records
- ownership mismatches
- append-only and supersession invariants
- supported type or enum restrictions

**Step 2: Run focused files**

Run only the touched model and integration tests first.

**Step 3: Write minimal implementation**

- strengthen model tests
- fix model-level validation or transition bugs when proven
- finish ledger statuses for all scanned model files

**Step 4: Run wave verification**

Run model-focused files and then full `bin/rails test`.

**Step 5: Commit**

```bash
git add docs/plans/2026-03-29-core-matrix-boundary-coverage-working-ledger.md \
  docs/plans/2026-03-29-core-matrix-test-suite-audit-findings.md \
  app/models \
  test/models \
  test/integration \
  test/support
git commit -m "test: execute wave 4 boundary coverage sweep"
```

### Task 6: Perform Final Self-Audit

**Files:**
- Modify: `docs/plans/2026-03-29-core-matrix-boundary-coverage-working-ledger.md`
- Modify: `docs/plans/2026-03-29-core-matrix-test-suite-audit-findings.md`

**Step 1: Verify the ledger**

Confirm:

- every `app/**/*.rb` file is listed
- no file remains `pending_scan`
- each file has a factual status

**Step 2: Run final verification**

Run:

```bash
bin/rails test
```

Expected:

- full suite green
- SimpleCov line result captured in the final report and ledger

**Step 3: Write the self-audit**

Record:

- what was strengthened
- what bugs were fixed
- what remaining gaps are intentional
- how the final SimpleCov result compares to the baseline

**Step 4: Commit**

```bash
git add docs/plans/2026-03-29-core-matrix-boundary-coverage-working-ledger.md \
  docs/plans/2026-03-29-core-matrix-test-suite-audit-findings.md
git commit -m "docs: finalize boundary coverage self-audit"
```
