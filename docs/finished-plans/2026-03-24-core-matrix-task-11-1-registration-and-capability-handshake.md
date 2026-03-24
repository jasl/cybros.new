# Core Matrix Task 11.1: Add Registration And Capability Handshake Boundaries

Part of `Core Matrix Kernel Milestone 4: Protocol, Publication, And Verification`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-kernel-milestone-4-protocol-publication-and-verification.md`
5. `docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md`

Load this file as the detailed execution unit for Task 11.1. Treat Task Group 11 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/app/controllers/agent_api/base_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/registrations_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/heartbeats_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/health_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/capabilities_controller.rb`
- Create: `core_matrix/app/services/agent_deployments/handshake.rb`
- Create: `core_matrix/app/services/agent_deployments/reconcile_config.rb`
- Create: `core_matrix/test/requests/agent_api/registrations_test.rb`
- Create: `core_matrix/test/requests/agent_api/heartbeats_test.rb`
- Create: `core_matrix/test/requests/agent_api/health_test.rb`
- Create: `core_matrix/test/requests/agent_api/capabilities_test.rb`
- Create: `core_matrix/test/services/agent_deployments/handshake_test.rb`
- Create: `core_matrix/test/services/agent_deployments/reconcile_config_test.rb`
- Create: `core_matrix/test/integration/agent_registration_contract_test.rb`
- Modify: `core_matrix/config/routes.rb`
- Modify: `core_matrix/app/models/agent_deployment.rb`
- Modify: `core_matrix/app/models/capability_snapshot.rb`

**Step 1: Write failing request, service, and contract tests**

Cover at least:

- machine credential authentication
- registration exchanging enrollment token for durable machine credential
- heartbeat update behavior
- health check response shape
- capabilities refresh response shape
- handshake payload parsing and snapshot persistence
- stable `snake_case` logical operation IDs for the public contract
- capability snapshots separating `protocol_methods` from `tool_catalog`
- tool-catalog entries exposing stable tool-kind metadata for `kernel_primitive`, `agent_observation`, and `effect_intent`
- preserving deployment-level model slots and role-catalog references whenever the capability or schema snapshot includes selector-bearing defaults or slots

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/requests/agent_api/registrations_test.rb test/requests/agent_api/heartbeats_test.rb test/requests/agent_api/health_test.rb test/requests/agent_api/capabilities_test.rb test/services/agent_deployments/handshake_test.rb test/services/agent_deployments/reconcile_config_test.rb test/integration/agent_registration_contract_test.rb
```

Expected:

- missing route, controller, or service failures

**Step 3: Implement minimal registration and handshake boundaries**

Rules:

- no human-facing UI controllers
- machine-facing controllers must be thin wrappers around services
- machine-facing protocol work in this task must not introduce schedule-trigger or webhook-ingress controllers
- public logical operation IDs in this contract must use `snake_case`
- capability snapshots must expose `protocol_methods` separately from `tool_catalog`
- config reconciliation stays best-effort across schema changes and must not silently drop selector-bearing defaults or slot references
- agents declare intent; kernel materializes durable side effects

**Step 4: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/requests/agent_api/registrations_test.rb test/requests/agent_api/heartbeats_test.rb test/requests/agent_api/health_test.rb test/requests/agent_api/capabilities_test.rb test/services/agent_deployments/handshake_test.rb test/services/agent_deployments/reconcile_config_test.rb test/integration/agent_registration_contract_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/controllers/agent_api core_matrix/config/routes.rb core_matrix/app/models/agent_deployment.rb core_matrix/app/models/capability_snapshot.rb core_matrix/app/services/agent_deployments core_matrix/test/requests core_matrix/test/services core_matrix/test/integration
git -C .. commit -m "feat: add agent registration and handshake boundaries"
```

## Stop Point

Stop after registration, heartbeat, health, capability refresh, and handshake contract tests pass.

Do not implement these items in this task:

- transcript or variable APIs
- human-interaction APIs
- machine-credential rotation or retirement
- outage recovery flows

## Completion Record

- status:
  completed on `2026-03-25`
- landing commit:
  - `513c1e4` `feat: add agent registration and handshake boundaries`
- actual landed scope:
  - added machine-facing `AgentAPI` controllers for registration, heartbeat,
    health, capability refresh, and capability handshake
  - added `AgentDeployments::Handshake` and
    `AgentDeployments::ReconcileConfig` as the application-layer boundaries for
    capability refresh and selector-bearing default retention
  - extended `CapabilitySnapshot` to validate stable public
    `protocol_methods` and `tool_catalog` contract families separately
  - extended `AgentDeployment` with machine-credential digest lookup and active
    capability-version access for authenticated protocol responses
  - added request, service, and integration coverage for registration exchange,
    machine-credential authentication, capability refresh, and handshake
    reconciliation
  - added
    `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`
- plan alignment notes:
  - controllers remain thin machine-facing wrappers around existing services;
    no browser UI controller or schedule or webhook ingress was introduced
  - public logical IDs stay in `snake_case`, and capability snapshots now
    publish `protocol_methods` separately from `tool_catalog`
  - handshake reconciliation remains best-effort and preserves
    selector-bearing defaults only when the new schema still exposes those
    keys
- verification evidence:
  - `cd core_matrix && bin/rails zeitwerk:check`
    passed with `All is good!`
  - `cd core_matrix && bin/rails test test/requests/agent_api/registrations_test.rb test/requests/agent_api/heartbeats_test.rb test/requests/agent_api/health_test.rb test/requests/agent_api/capabilities_test.rb test/services/agent_deployments/handshake_test.rb test/services/agent_deployments/reconcile_config_test.rb test/integration/agent_registration_contract_test.rb`
    passed with `8 runs, 41 assertions, 0 failures, 0 errors`
- checklist notes:
  - updated manual-validation examples to use the current `tool_catalog`
    contract shape and `kernel_primitive` tool kind
- retained findings:
  - Rails autoloading for `app/controllers/agent_api` resolves to `AgentAPI`,
    so the controller module namespace must use the acronym form
  - `ActionController::API` needs explicit inclusion of HTTP token
    authentication helpers for bearer-token machine credentials
