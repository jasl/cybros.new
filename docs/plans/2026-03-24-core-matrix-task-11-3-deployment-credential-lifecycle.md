# Core Matrix Task 11.3: Add Deployment Credential Lifecycle Controls

Part of `Core Matrix Kernel Milestone 4: Protocol, Publication, And Verification`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-milestone-4-protocol-publication-and-verification.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 11.3. Treat Task Group 11 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/app/services/agent_deployments/rotate_machine_credential.rb`
- Create: `core_matrix/app/services/agent_deployments/revoke_machine_credential.rb`
- Create: `core_matrix/app/services/agent_deployments/retire.rb`
- Create: `core_matrix/test/services/agent_deployments/rotate_machine_credential_test.rb`
- Create: `core_matrix/test/services/agent_deployments/revoke_machine_credential_test.rb`
- Create: `core_matrix/test/services/agent_deployments/retire_test.rb`
- Create: `core_matrix/test/integration/machine_credential_lifecycle_test.rb`
- Modify: `core_matrix/app/models/agent_deployment.rb`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

**Step 1: Write failing service and integration tests**

Cover at least:

- machine credential rotation issues a fresh secret and invalidates the previous credential atomically
- machine credential revocation makes the current credential unusable before any later re-registration
- deployment retirement moves the deployment into the `retired` state and makes it ineligible for future scheduling
- audit rows for rotation, revocation, and retirement

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/services/agent_deployments/rotate_machine_credential_test.rb test/services/agent_deployments/revoke_machine_credential_test.rb test/services/agent_deployments/retire_test.rb test/integration/machine_credential_lifecycle_test.rb
```

Expected:

- missing service or lifecycle failures

**Step 3: Implement credential lifecycle controls**

Rules:

- machine credential rotation must issue a fresh secret, invalidate the previous credential atomically, and create an audit row
- machine credential revocation must make the current credential unusable and create an audit row before any later re-registration
- deployment retirement must move the deployment into the `retired` state, make it ineligible for future scheduling, and create an audit row
- update the manual checklist for reproducible rotation, revocation, and retirement validation

**Step 4: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/agent_deployments/rotate_machine_credential_test.rb test/services/agent_deployments/revoke_machine_credential_test.rb test/services/agent_deployments/retire_test.rb test/integration/machine_credential_lifecycle_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/models/agent_deployment.rb core_matrix/app/services/agent_deployments core_matrix/test/services core_matrix/test/integration docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md
git -C .. commit -m "feat: add deployment credential lifecycle controls"
```

## Stop Point

Stop after rotation, revocation, and retirement pass their tests.

Do not implement these items in this task:

- outage detection or recovery
- transcript, variable, or publication APIs
- any human-facing admin interface
