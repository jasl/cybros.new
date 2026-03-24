# Core Matrix Task 01: Re-Baseline The Rails Shell And Validation Scaffolding

Part of `Core Matrix Kernel Milestone 1: Foundations`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-kernel-milestone-1-foundations.md`

Load this file as the detailed execution unit for Task 01. Treat the milestone file as the ordering index, not the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---


**Files:**
- Verify: `core_matrix/Gemfile`
- Verify: `core_matrix/db/schema.rb`
- Verify: `core_matrix/app/models/application_record.rb`
- Verify: `core_matrix/config/routes.rb`
- Create: `core_matrix/docs/behavior/shell-baseline.md`
- Create: `core_matrix/test/support/.keep`
- Create: `core_matrix/test/services/.keep`
- Create: `core_matrix/test/queries/.keep`
- Create: `core_matrix/test/integration/.keep`
- Create: `core_matrix/test/requests/.keep`
- Create: `core_matrix/script/manual/.keep`
- Modify: `core_matrix/README.md`

**Step 1: Document the backend phase boundary**

- Update `core_matrix/README.md` to point at the greenfield design doc, UI follow-up doc, and manual validation checklist.
- State explicitly that human-facing UI is out of scope for this phase.
- Add `core_matrix/docs/behavior/shell-baseline.md` describing the shell
  baseline, validation contract, and phase boundary for this execution unit.

**Step 2: Verify the shell baseline**

Run:

```bash
cd core_matrix
bin/rails db:version
bin/rails test
bin/rubocop app/models/application_record.rb
```

Expected:

- database version resolves without missing migration errors
- test suite is either empty or green
- RuboCop passes for the baseline file

**Step 3: Add empty directories for test and manual-validation work**

- Create `core_matrix/test/support/.keep`
- Create `core_matrix/test/services/.keep`
- Create `core_matrix/test/queries/.keep`
- Create `core_matrix/test/integration/.keep`
- Create `core_matrix/test/requests/.keep`
- Create `core_matrix/script/manual/.keep`

**Step 4: Commit**

```bash
git -C .. add core_matrix/README.md core_matrix/docs/behavior/shell-baseline.md core_matrix/test/support/.keep core_matrix/test/services/.keep core_matrix/test/queries/.keep core_matrix/test/integration/.keep core_matrix/test/requests/.keep core_matrix/script/manual/.keep docs/finished-plans/2026-03-24-core-matrix-task-01-shell-baseline.md
git -C .. commit -m "chore: reset core matrix backend shell baseline"
```

## Stop Point

Stop after the backend shell baseline, behavior doc, empty directories, and
baseline validation commands are in place.

Do not implement these items in this task:

- domain models or migrations
- machine-facing protocol endpoints
- any human-facing UI

## Completion Record

- status:
  completed on `2026-03-24` in commit `0dd2f6a`
- actual landed scope:
  - updated `core_matrix/README.md` to point at the canonical design, active
    implementation plan, deferred UI follow-up, manual checklist, and behavior
    docs
  - added `core_matrix/docs/behavior/shell-baseline.md` as the durable record
    for backend-only scope and shell validation expectations
  - verified the existing placeholder test and manual-script directories were
    already sufficient for the baseline; no new `.keep` files were needed in
    the landing commit
- verification evidence:
  - `cd core_matrix && bin/rails db:version` reported development schema
    version `20260324090012`
  - `cd core_matrix && bin/rubocop app/models/application_record.rb` passed
    with no offenses during the `2026-03-24` doc-hardening rerun
  - `cd core_matrix && bin/rails test` passed with
    `40 runs, 188 assertions, 0 failures, 0 errors` during the same rerun
- retained findings:
  - no product-behavior conclusion from non-authoritative reference projects
    was retained for this task
  - the important lasting boundary is that phase 1 stays backend-only and keeps
    human-facing UI out of scope
- carry-forward notes:
  - later tasks should continue recording durable backend behavior in
    `core_matrix/docs/behavior/`
  - shell-reproducible validation belongs in the checklist and manual scripts,
    not in UI-only notes
