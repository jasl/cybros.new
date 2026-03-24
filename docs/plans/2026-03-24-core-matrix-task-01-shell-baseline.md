# Core Matrix Task 01: Re-Baseline The Rails Shell And Validation Scaffolding

Part of `Core Matrix Kernel Phase 1: Foundations`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-1-foundations.md`
5. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
6. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 01. Treat the phase file as the ordering index, not the full task body.

---


**Files:**
- Verify: `core_matrix/Gemfile`
- Verify: `core_matrix/db/schema.rb`
- Verify: `core_matrix/app/models/application_record.rb`
- Verify: `core_matrix/config/routes.rb`
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
git -C .. add core_matrix/README.md core_matrix/test/support/.keep core_matrix/test/services/.keep core_matrix/test/queries/.keep core_matrix/test/integration/.keep core_matrix/test/requests/.keep core_matrix/script/manual/.keep
git -C .. commit -m "chore: reset core matrix backend shell baseline"
```

