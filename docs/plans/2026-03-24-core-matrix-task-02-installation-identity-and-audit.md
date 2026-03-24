# Core Matrix Task 02: Build Installation, Identity, User, Invitation, Session, And Audit Foundations

Part of `Core Matrix Kernel Milestone 1: Foundations`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-milestone-1-foundations.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 02. Treat the milestone file as the ordering index, not the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---


**Files:**
- Create: `core_matrix/db/migrate/20260324090000_create_installations.rb`
- Create: `core_matrix/db/migrate/20260324090001_create_identities.rb`
- Create: `core_matrix/db/migrate/20260324090002_create_users.rb`
- Create: `core_matrix/db/migrate/20260324090003_create_invitations.rb`
- Create: `core_matrix/db/migrate/20260324090004_create_sessions.rb`
- Create: `core_matrix/db/migrate/20260324090005_create_audit_logs.rb`
- Create: `core_matrix/app/models/installation.rb`
- Create: `core_matrix/app/models/identity.rb`
- Create: `core_matrix/app/models/user.rb`
- Create: `core_matrix/app/models/invitation.rb`
- Create: `core_matrix/app/models/session.rb`
- Create: `core_matrix/app/models/audit_log.rb`
- Create: `core_matrix/app/services/installations/bootstrap_first_admin.rb`
- Create: `core_matrix/app/services/invitations/consume.rb`
- Create: `core_matrix/app/services/users/grant_admin.rb`
- Create: `core_matrix/app/services/users/revoke_admin.rb`
- Create: `core_matrix/docs/behavior/installation-identity-and-audit-foundations.md`
- Create: `core_matrix/test/models/installation_test.rb`
- Create: `core_matrix/test/models/identity_test.rb`
- Create: `core_matrix/test/models/user_test.rb`
- Create: `core_matrix/test/models/invitation_test.rb`
- Create: `core_matrix/test/models/session_test.rb`
- Create: `core_matrix/test/models/audit_log_test.rb`
- Create: `core_matrix/test/services/installations/bootstrap_first_admin_test.rb`
- Create: `core_matrix/test/services/invitations/consume_test.rb`
- Create: `core_matrix/test/services/users/grant_admin_test.rb`
- Create: `core_matrix/test/services/users/revoke_admin_test.rb`
- Create: `core_matrix/test/integration/installation_bootstrap_flow_test.rb`
- Modify: `core_matrix/config/initializers/filter_parameter_logging.rb`
- Modify: `core_matrix/test/test_helper.rb`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

**Step 1: Write failing unit tests for root aggregates**

Cover at least:

- single-row installation bootstrap assumptions
- `Identity` email normalization and uniqueness
- `Identity` password presence and authentication via `has_secure_password`
- `User` admin role semantics
- admin grant and revoke legality
- forbidding revocation of the last active admin
- invitation token uniqueness, expiration, and consumption
- session token uniqueness, expiration, and revocation
- audit log actor and subject shape

**Step 2: Write a failing integration flow test**

`installation_bootstrap_flow_test.rb` should cover:

- creating the first installation, identity, and admin user
- rejecting or safely no-oping a second bootstrap attempt
- creating an invitation and consuming it for a second user
- granting and revoking admin on a later user
- audit rows written for bootstrap, invite consumption, and admin role changes

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/installation_test.rb test/models/identity_test.rb test/models/user_test.rb test/models/invitation_test.rb test/models/session_test.rb test/models/audit_log_test.rb test/services/installations/bootstrap_first_admin_test.rb test/services/invitations/consume_test.rb test/services/users/grant_admin_test.rb test/services/users/revoke_admin_test.rb test/integration/installation_bootstrap_flow_test.rb
```

Expected:

- failures for missing tables, models, and validations

**Step 4: Write migrations and models**

Include:

- `installations` with name, bootstrap state, and global settings JSON
- `identities` with email, password digest, auth metadata, and disable state
- `users` with installation FK, identity FK, role state, display name, preferences JSON
- `invitations` with installation FK, inviter FK, token digest, email, expires_at, consumed_at
- `sessions` with identity FK, user FK, token digest, expires_at, revoked_at, metadata
- `audit_logs` with installation FK, actor polymorphism, action, subject polymorphism, metadata JSON

**Step 5: Implement minimal services**

- use transactions for bootstrap and invitation consumption
- implement explicit admin grant and revoke services with audit writes
- block revocation of the last active admin user
- keep orchestration in services, not callbacks
- filter auth secrets in logs

**Step 6: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/installation_test.rb test/models/identity_test.rb test/models/user_test.rb test/models/invitation_test.rb test/models/session_test.rb test/models/audit_log_test.rb test/services/installations/bootstrap_first_admin_test.rb test/services/invitations/consume_test.rb test/services/users/grant_admin_test.rb test/services/users/revoke_admin_test.rb test/integration/installation_bootstrap_flow_test.rb
```

Expected:

- migrations apply cleanly
- targeted tests pass

**Step 7: Update behavior and manual validation docs**

- Add `core_matrix/docs/behavior/installation-identity-and-audit-foundations.md`
  describing the installation, identity, user, invitation, session, and audit
  foundations plus their service boundaries and failure modes.
- Update `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
  with backend-reproducible shell steps for first-admin bootstrap, invitation
  creation and consumption, and admin grant and revoke.

**Step 8: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/installations core_matrix/app/services/invitations core_matrix/app/services/users core_matrix/docs/behavior/installation-identity-and-audit-foundations.md core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/test/test_helper.rb core_matrix/config/initializers/filter_parameter_logging.rb core_matrix/db/schema.rb docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md docs/plans/2026-03-24-core-matrix-task-02-installation-identity-and-audit.md
git -C .. commit -m "feat: add installation identity foundations"
```

## Stop Point

Stop after installation, identity, user, invitation, session, and audit
foundations pass their tests and the behavior plus checklist docs are aligned.

Do not implement these items in this task:

- agent registry models
- user bindings or workspaces
- provider governance or runtime protocol work

## Completion Record

- status:
  completed on `2026-03-24` in commit `098508f`
- actual landed scope:
  - added migrations `20260324090000` through `20260324090005`
  - added `Installation`, `Identity`, `User`, `Invitation`, `Session`, and
    `AuditLog` plus the installation bootstrap, invitation consumption, admin
    grant, and admin revoke services
  - added `core_matrix/docs/behavior/installation-identity-and-audit-foundations.md`
    and manual checklist flows for first-admin bootstrap, invitation
    consumption, and admin grant or revoke
- plan alignment notes:
  - the task landed within its original domain boundary
  - later Task 04.2 extended `Installations::BootstrapFirstAdmin` to optionally
    compose bundled bootstrap after the installation bootstrap audit row; the
    base installation, identity, user, invitation, session, and audit behavior
    from this task remains authoritative when bundled bootstrap is disabled
- verification evidence:
  - the original acceptance gate for this task was the targeted test command in
    Step 6
  - the `2026-03-24` doc-hardening rerun included
    `cd core_matrix && bin/rails test test/integration/installation_bootstrap_flow_test.rb`
    inside the Milestone 1 integration spot-check, which passed
  - the same rerun also passed `cd core_matrix && bin/rails test` with
    `40 runs, 188 assertions, 0 failures, 0 errors`
- retained findings:
  - active-admin safety is defined by admin users whose linked identities remain
    enabled, not by raw admin-row count
  - no product-behavior conclusion from non-authoritative reference projects
    was retained for this task
- carry-forward notes:
  - future work must preserve `Identity` versus `User` separation
  - bootstrap, invitation, and admin-role side effects should continue to live
    in explicit services rather than model callbacks
