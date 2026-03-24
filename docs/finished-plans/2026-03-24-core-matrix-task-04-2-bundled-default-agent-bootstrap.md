# Core Matrix Task 04.2: Add Bundled Default-Agent Bootstrap

Part of `Core Matrix Kernel Milestone 1: Foundations`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-kernel-milestone-1-foundations.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 04.2. Treat Task Group 04 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Create: `core_matrix/app/services/installations/bootstrap_bundled_agent_binding.rb`
- Create: `core_matrix/docs/behavior/bundled-default-agent-bootstrap.md`
- Create: `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Create: `core_matrix/test/services/installations/bootstrap_bundled_agent_binding_test.rb`
- Create: `core_matrix/test/integration/bundled_default_agent_bootstrap_flow_test.rb`
- Modify: `core_matrix/app/services/installations/bootstrap_first_admin.rb`
- Modify: `core_matrix/test/test_helper.rb`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

**Step 1: Write failing service and integration tests**

Cover at least:

- bundled runtime registration reconciles registry rows before binding
- bundled runtime registration is idempotent and must not duplicate logical or deployment rows
- bundled-agent bootstrap only runs when explicitly configured
- first-admin bootstrap auto-binds the bundled agent only after registry reconciliation
- first-admin bootstrap creates the default workspace through existing workspace services

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/services/installations/register_bundled_agent_runtime_test.rb test/services/installations/bootstrap_bundled_agent_binding_test.rb test/integration/bundled_default_agent_bootstrap_flow_test.rb
```

Expected:

- failures for missing services or missing bootstrap behavior

**Step 3: Implement bundled bootstrap behavior**

Rules:

- bundled runtime registration must reconcile `AgentInstallation`, `ExecutionEnvironment`, and `AgentDeployment` before user binding
- bundled bootstrap must compose existing binding and workspace services rather than duplicating their rules
- first-admin bootstrap must stay opt-in through configuration
- keep bundled bootstrap scoped to the one packaged runtime and do not widen this into a generic connector or bridge layer
- update the manual checklist for the reproducible bundled-bootstrap flow

**Step 4: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/installations/register_bundled_agent_runtime_test.rb test/services/installations/bootstrap_bundled_agent_binding_test.rb test/integration/bundled_default_agent_bootstrap_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Update behavior and manual validation docs**

- Add `core_matrix/docs/behavior/bundled-default-agent-bootstrap.md`
  describing bundled runtime reconciliation, first-admin composition order, and
  idempotency expectations.
- Update `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
  with shell-reproducible bundled-runtime bootstrap and reconciliation steps.

**Step 6: Commit**

```bash
git -C .. add core_matrix/app/services/installations core_matrix/docs/behavior/bundled-default-agent-bootstrap.md core_matrix/test/services core_matrix/test/integration core_matrix/test/test_helper.rb docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md
git -C .. commit -m "feat: add bundled default agent bootstrap"
```

## Stop Point

Stop after bundled runtime reconciliation and bundled first-admin bootstrap pass their tests.

Do not implement these items in this task:

- generic multi-agent bootstrap
- human-facing setup flows
- any schedule, webhook, or IM integration behavior

## Completion Record

- status:
  completed on `2026-03-24` in commit `508ab0b`
- actual landed scope:
  - added `Installations::RegisterBundledAgentRuntime` and
    `Installations::BootstrapBundledAgentBinding`
  - extended `Installations::BootstrapFirstAdmin` to optionally compose bundled
    runtime registration and binding through
    `Rails.configuration.x.bundled_agent`
  - added `core_matrix/docs/behavior/bundled-default-agent-bootstrap.md`,
    checklist coverage, integration coverage, and supporting test-helper data
- plan alignment notes:
  - the file list above has been updated to match the actual landed behavior
    doc and test-helper support changes
  - the task stayed within bundled-runtime scope and did not widen into a
    generic connector layer
- verification evidence:
  - the original acceptance gate for this task was the targeted test command in
    Step 4
  - the `2026-03-24` doc-hardening rerun included
    `cd core_matrix && bin/rails test test/integration/bundled_default_agent_bootstrap_flow_test.rb`
    inside the Milestone 1 integration spot-check, which passed
  - the same rerun also passed `cd core_matrix && bin/rails test` with
    `40 runs, 188 assertions, 0 failures, 0 errors`
- retained findings:
  - bundled runtime reconciliation reuses an existing deployment by matching the
    configured fingerprint first and otherwise the active deployment for the
    logical bundled agent
  - capability snapshots are matched by content; when an existing matching
    snapshot is reused, the deployment is repointed to that snapshot instead of
    creating a duplicate
  - no product-behavior conclusion from non-authoritative reference projects
    was retained for this task
- carry-forward notes:
  - packaged runtime bootstrap remains opt-in and should keep using the same
    registry and binding abstractions as external runtimes
  - later external execution adapters should attach through registry and
    binding services rather than bypassing them with one-off bootstrap tables
