# Core Matrix Task 12.3: Run Verification And Manual Validation

Part of `Core Matrix Kernel Milestone 4: Protocol, Publication, And Verification`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-milestone-4-protocol-publication-and-verification.md`
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

**Step 1: Update the manual validation checklist**

Document exact reproducible steps for at least:

- first-admin bootstrap
- invitation consume flow
- admin grant and revoke flow
- bundled Fenix auto-registration and auto-binding when configured
- agent registration, handshake, heartbeat, health, recovery, and retirement using `script/manual/dummy_agent_runtime.rb`
- machine credential rotation and revocation
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
