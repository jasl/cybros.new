# Core Matrix Task 12.3: Run Verification And Manual Validation

Part of `Core Matrix Kernel Milestone 4: Protocol, Publication, And Verification`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
3. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-milestone-4-protocol-publication-and-verification.md`
4. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 12.3. Treat Task Group 12 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- Modify: `core_matrix/README.md`
- Modify: `core_matrix/script/manual/dummy_agent_runtime.rb`
- Create: `core_matrix/test/integration/dummy_agent_runtime_test.rb`
- Create: `core_matrix/docs/behavior/verification-and-manual-validation-baseline.md`
- Modify: `docs/plans/README.md`
- Modify: `docs/finished-plans/README.md`
- Modify: `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
- Modify: `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-milestone-4-protocol-publication-and-verification.md`
- Modify: `docs/finished-plans/2026-03-24-core-matrix-phase-1-task-group-11-agent-protocol-and-recovery.md`
- Modify: `docs/finished-plans/2026-03-24-core-matrix-phase-1-task-group-12-publication-and-final-verification.md`

**Step 1: Update the manual validation checklist**

Document exact reproducible steps for at least:

- first-admin bootstrap
- invitation consume flow
- admin grant and revoke flow
- bundled Fenix auto-registration and auto-binding when configured
- agent registration, handshake, heartbeat, health, recovery, and retirement using `script/manual/dummy_agent_runtime.rb`
- connection credential rotation and revocation
- `main` auto selection, explicit candidate pinning, role-local fallback after entitlement exhaustion, and one-time recovery override
- drift-triggered manual resume and manual retry
- conversation root, branch, thread, checkpoint, archive, and unarchive
- conversation tail edit, rollback or fork editing, retry, rerun, and swipe selection
- attachment, import, summary-compaction, and visibility validation
- human form request, human task request, and open-request query validation
- canonical variable write, promotion, and transcript cursor-pagination validation through machine-facing APIs
- publication internal-public access, external-public access, access logging, and revoke

Checklist rule:

- current-batch validation must remain reproducible through shell commands, HTTP requests, Rails console actions, and `script/manual/dummy_agent_runtime.rb`
- do not add browser-only or human-facing UI validation steps to satisfy this backend completion gate

**Step 2: Run full automated verification**

Run:

```bash
cd core_matrix
bin/rails db:test:prepare
bin/rails test
bin/rails db:test:prepare test:system
bun run lint:js
bin/rubocop -f github
bin/brakeman --no-pager
bin/bundler-audit
```

Expected:

- all tests pass
- system tests pass or the suite is empty and green
- JS lint passes
- RuboCop passes
- Brakeman and Bundler Audit are clean or have documented exceptions

**Step 3: Run manual real-environment validation**

Run:

```bash
cd core_matrix
bin/dev
```

Then execute the checklist in `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`.

Expected:

- the documented backend flows can be reproduced in a real environment
- any pairing or M2M flow required by the checklist can be exercised end to end
- checklist notes and `README.md` are updated with actual outcomes and caveats

**Step 4: Commit**

```bash
git -C .. add docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md core_matrix/README.md
git -C .. commit -m "chore: finalize backend verification baseline"
```

## Stop Point

Stop after Task 12.3.

Do not implement these items in this task:

- setup wizard UI
- password or session UI
- admin dashboards
- conversation or publication pages
- human-facing Turbo or Stimulus work
- Action Cable or browser realtime delivery

## Completion Record

- status:
  completed on `2026-03-25`
- landing commit:
  - included in the accompanying `chore: finalize backend verification baseline`
    task commit
- actual landed scope:
  - rewrote the phase-1 manual validation checklist into a self-contained
    shell, runner, HTTP, and dummy-runtime baseline with actual `2026-03-25`
    outcomes
  - updated `core_matrix/README.md` with the phase-1 manual validation
    baseline, reset-helper rule, dummy-runtime requirements, and publication
    caveat
  - fixed `script/manual/dummy_agent_runtime.rb register` to require and send
    `CORE_MATRIX_EXECUTION_ENVIRONMENT_ID` after the live rerun exposed the
    missing registration field
  - added `test/integration/dummy_agent_runtime_test.rb` to prevent regression
    on the dummy runtime payload contract
  - added
    `core_matrix/docs/behavior/verification-and-manual-validation-baseline.md`
    as the durable behavior record for the verification baseline
  - moved the remaining phase-1 execution records from `docs/plans` into
    `docs/finished-plans` and updated the plan indexes so phase 1 is archived
    as completed history rather than left as active work
- plan alignment notes:
  - final backend validation remained non-UI and reproducible from shell
    commands, Rails runner, HTTP requests, and the dummy runtime only
  - publication validation stayed service-level because phase 1 still has no
    publication HTTP routes
  - the archived phase-1 records now live entirely under
    `docs/finished-plans`, while `docs/plans` is reserved for future active
    execution documents
- verification evidence:
  - automated baseline:
    - `cd core_matrix && bin/rails db:test:prepare test`
      passed with `243 runs, 1266 assertions, 0 failures, 0 errors, 0 skips`
    - `cd core_matrix && bin/rails db:test:prepare test:system`
      passed with `0 runs, 0 assertions, 0 failures, 0 errors, 0 skips`
    - `cd core_matrix && bun run lint:js && bin/rubocop -f github && bin/brakeman --no-pager && bin/bundler-audit`
      passed with JS lint and RuboCop clean, `Security Warnings: 0`, and
      `No vulnerabilities found`
    - `git -C .. diff --check`
      passed clean
  - targeted regression:
    - `cd core_matrix && bin/rails test test/integration/dummy_agent_runtime_test.rb test/requests/agent_api/registrations_test.rb`
      passed with `2 runs, 7 assertions, 0 failures, 0 errors, 0 skips`
  - live `bin/dev` rerun:
    - registration, heartbeat, and health passed with
      `register_status: 201`, `heartbeat_status: 200`, and
      `health_status: 200`
    - selector, recovery, transcript, variable, human-interaction,
      conversation-history, form-task, and publication checklist flows were all
      re-executed and captured back into the checklist as dated results
- checklist notes:
  - reset flows now standardize on
    `ApplicationRecord.with_connection { |conn| conn.disable_referential_integrity { ... } }`
    instead of brittle hand-maintained delete chains
  - publication verification is explicitly documented as service-level in
    phase 1
- retained findings:
  - the dummy runtime registration contract depends on both the enrollment
    token and the execution environment id; omitting the latter breaks the
    live registration path even when request tests are green
  - the checklist only stays durable when helper snippets and expected outputs
    are stored locally instead of relying on transient reference repos or
    unstated operator knowledge
- carry-forward notes:
  - future loop or UI phases should extend this checklist instead of replacing
    the current backend baseline with browser-only scripts
  - if public publication routes are added later, they should layer on top of
    the existing publication services and update this verification baseline in
    the same execution unit
