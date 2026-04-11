# Core Matrix Task 04.1: Build User Bindings And Private Workspaces

Part of `Core Matrix Kernel Milestone 1: Foundations`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-milestone-1-foundations.md`

Load this file as the detailed execution unit for Task 04.1. Treat Task Group 04 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090011_create_user_agent_bindings.rb`
- Create: `core_matrix/db/migrate/20260324090012_create_workspaces.rb`
- Modify: `core_matrix/app/models/agent_installation.rb`
- Modify: `core_matrix/app/models/installation.rb`
- Modify: `core_matrix/app/models/user.rb`
- Create: `core_matrix/app/models/user_agent_binding.rb`
- Create: `core_matrix/app/models/workspace.rb`
- Create: `core_matrix/app/services/user_agent_bindings/enable.rb`
- Create: `core_matrix/app/services/workspaces/create_default.rb`
- Create: `core_matrix/docs/behavior/user-bindings-and-workspaces.md`
- Create: `core_matrix/test/models/user_agent_binding_test.rb`
- Create: `core_matrix/test/models/workspace_test.rb`
- Create: `core_matrix/test/services/user_agent_bindings/enable_test.rb`
- Create: `core_matrix/test/services/workspaces/create_default_test.rb`
- Create: `core_matrix/test/integration/user_binding_workspace_flow_test.rb`
- Modify: `core_matrix/test/test_helper.rb`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- one binding per user and agent installation pair
- binding ownership constrained to one installation
- workspace privacy and ownership
- one default workspace per binding
- default workspace creation reusing the binding ownership boundary
- enabling a global agent for a user without creating duplicate bindings

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/user_agent_binding_test.rb test/models/workspace_test.rb test/services/user_agent_bindings/enable_test.rb test/services/workspaces/create_default_test.rb test/integration/user_binding_workspace_flow_test.rb
```

Expected:

- failures for missing tables, models, or services

**Step 3: Write migrations, models, and services**

Rules:

- `user_agent_bindings` must belong to `Installation`, `User`, and `AgentInstallation`
- `workspaces` must belong to `Installation`, `User`, and `UserAgentBinding`
- `Workspace` remains private and user-owned in v1
- default-workspace uniqueness is per binding, not per installation
- reuse services for ownership checks instead of ad hoc controller or model callbacks
- do not add bundled runtime registration or first-admin bootstrap behavior in this task

**Step 4: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/user_agent_binding_test.rb test/models/workspace_test.rb test/services/user_agent_bindings/enable_test.rb test/services/workspaces/create_default_test.rb test/integration/user_binding_workspace_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Update behavior and manual validation docs**

- Add `core_matrix/docs/behavior/user-bindings-and-workspaces.md` describing
  binding ownership, workspace privacy, default-workspace rules, and service
  composition boundaries.
- Update `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
  with shell-reproducible steps for binding enablement and default-workspace
  creation.

**Step 6: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/user_agent_bindings core_matrix/app/services/workspaces core_matrix/docs/behavior/user-bindings-and-workspaces.md core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/test/test_helper.rb core_matrix/db/schema.rb docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md
git -C .. commit -m "feat: add user bindings and workspaces"
```

## Stop Point

Stop after bindings, workspaces, and default-workspace creation pass their tests.

Do not implement these items in this task:

- bundled runtime registration
- bundled first-admin auto-binding
- changes to `bootstrap_first_admin`

## Completion Record

- status:
  completed on `2026-03-24` in commit `fe34078`
- actual landed scope:
  - added `UserAgentBinding` and `Workspace` plus migrations
    `20260324090011` and `20260324090012`
  - added `UserAgentBindings::Enable` and
    `Workspaces::CreateDefault`
  - updated parent associations on `AgentInstallation`, `Installation`, and
    `User`, extended `core_matrix/test/test_helper.rb`, and added checklist and
    behavior-doc coverage
- plan alignment notes:
  - the file list above has been updated to match the actual landed parent-model
    association changes and local-doc updates
- verification evidence:
  - the original acceptance gate for this task was the targeted test command in
    Step 4
  - the `2026-03-24` doc-hardening rerun included
    `cd core_matrix && bin/rails test test/integration/user_binding_workspace_flow_test.rb`
    inside the Milestone 1 integration spot-check, which passed
  - the same rerun also passed `cd core_matrix && bin/rails test` with
    `40 runs, 188 assertions, 0 failures, 0 errors`
- retained findings:
  - binding enablement is idempotent for a given user-agent pair
  - default-workspace uniqueness is scoped to one binding, not the whole
    installation
  - no product-behavior conclusion from non-authoritative reference projects
    was retained for this task
- carry-forward notes:
  - future bootstrap, onboarding, or enablement flows should keep using
    `UserAgentBindings::Enable` and `Workspaces::CreateDefault`
  - workspaces remain private user-owned aggregates and should not be widened
    into shared/public scope inside phase 1
