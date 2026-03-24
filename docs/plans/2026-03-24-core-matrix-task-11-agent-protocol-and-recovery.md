# Core Matrix Task 11: Implement Agent Protocol Boundaries, Runtime Resource APIs, Contract Tests, Bootstrap, And Recovery

Part of `Core Matrix Kernel Phase 4: Protocol, Publication, And Verification`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-4-protocol-publication-and-verification.md`
5. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
6. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
7. `docs/plans/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md`

Load this file as the detailed execution unit for Task 11. Treat the phase file as the ordering index, not the full task body.

---


**Files:**
- Create: `core_matrix/app/controllers/agent_api/base_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/registrations_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/heartbeats_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/health_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/capabilities_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/conversation_transcripts_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/conversation_variables_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/workspace_variables_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/human_interactions_controller.rb`
- Create: `core_matrix/app/services/agent_deployments/handshake.rb`
- Create: `core_matrix/app/services/agent_deployments/reconcile_config.rb`
- Create: `core_matrix/app/services/agent_deployments/bootstrap.rb`
- Create: `core_matrix/app/services/agent_deployments/rotate_machine_credential.rb`
- Create: `core_matrix/app/services/agent_deployments/revoke_machine_credential.rb`
- Create: `core_matrix/app/services/agent_deployments/retire.rb`
- Create: `core_matrix/app/services/agent_deployments/mark_unavailable.rb`
- Create: `core_matrix/app/services/agent_deployments/auto_resume_workflows.rb`
- Create: `core_matrix/app/services/workflows/manual_resume.rb`
- Create: `core_matrix/app/services/workflows/manual_retry.rb`
- Create: `core_matrix/app/queries/conversation_transcripts/list_query.rb`
- Create: `core_matrix/app/queries/conversation_variables/get_query.rb`
- Create: `core_matrix/app/queries/conversation_variables/mget_query.rb`
- Create: `core_matrix/app/queries/conversation_variables/list_query.rb`
- Create: `core_matrix/app/queries/conversation_variables/resolve_query.rb`
- Create: `core_matrix/app/queries/workspace_variables/get_query.rb`
- Create: `core_matrix/app/queries/workspace_variables/mget_query.rb`
- Create: `core_matrix/app/queries/workspace_variables/list_query.rb`
- Create: `core_matrix/script/manual/dummy_agent_runtime.rb`
- Create: `core_matrix/test/requests/agent_api/registrations_test.rb`
- Create: `core_matrix/test/requests/agent_api/heartbeats_test.rb`
- Create: `core_matrix/test/requests/agent_api/health_test.rb`
- Create: `core_matrix/test/requests/agent_api/capabilities_test.rb`
- Create: `core_matrix/test/requests/agent_api/conversation_transcripts_test.rb`
- Create: `core_matrix/test/requests/agent_api/conversation_variables_test.rb`
- Create: `core_matrix/test/requests/agent_api/workspace_variables_test.rb`
- Create: `core_matrix/test/requests/agent_api/human_interactions_test.rb`
- Create: `core_matrix/test/services/agent_deployments/handshake_test.rb`
- Create: `core_matrix/test/services/agent_deployments/reconcile_config_test.rb`
- Create: `core_matrix/test/services/agent_deployments/bootstrap_test.rb`
- Create: `core_matrix/test/services/agent_deployments/rotate_machine_credential_test.rb`
- Create: `core_matrix/test/services/agent_deployments/revoke_machine_credential_test.rb`
- Create: `core_matrix/test/services/agent_deployments/retire_test.rb`
- Create: `core_matrix/test/services/agent_deployments/mark_unavailable_test.rb`
- Create: `core_matrix/test/services/agent_deployments/auto_resume_workflows_test.rb`
- Create: `core_matrix/test/services/workflows/manual_resume_test.rb`
- Create: `core_matrix/test/services/workflows/manual_retry_test.rb`
- Create: `core_matrix/test/queries/conversation_transcripts/list_query_test.rb`
- Create: `core_matrix/test/queries/conversation_variables/get_query_test.rb`
- Create: `core_matrix/test/queries/conversation_variables/mget_query_test.rb`
- Create: `core_matrix/test/queries/conversation_variables/list_query_test.rb`
- Create: `core_matrix/test/queries/conversation_variables/resolve_query_test.rb`
- Create: `core_matrix/test/queries/workspace_variables/get_query_test.rb`
- Create: `core_matrix/test/queries/workspace_variables/mget_query_test.rb`
- Create: `core_matrix/test/queries/workspace_variables/list_query_test.rb`
- Create: `core_matrix/test/integration/agent_protocol_contract_test.rb`
- Create: `core_matrix/test/integration/agent_recovery_flow_test.rb`
- Modify: `core_matrix/config/routes.rb`
- Modify: `core_matrix/app/models/agent_deployment.rb`
- Modify: `core_matrix/app/models/capability_snapshot.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`

**Step 1: Write failing request, service, and query tests**

Cover at least:

- machine credential authentication
- registration exchanging enrollment token for durable machine credential
- heartbeat update behavior
- health check response shape
- capabilities refresh response shape
- cursor-paginated canonical transcript listing
- conversation variable `get`, `mget`, `list`, and `resolve` behavior
- workspace variable `get`, `mget`, and `list` behavior
- variable write and promotion intent handling through machine-facing APIs
- human interaction request creation through machine-facing APIs
- handshake payload parsing and snapshot persistence
- stable `snake_case` logical operation IDs for the public contract
- capability snapshots separating protocol methods from tool catalog entries
- tool-catalog entries exposing stable tool-kind metadata for `kernel_primitive`, `agent_observation`, and `effect_intent`
- best-effort config reconciliation across schema changes
- preserving deployment-level model slots and role-catalog references whenever the capability or schema snapshot includes selector-bearing defaults or slots
- machine credential rotation and revocation behavior
- deployment retirement behavior
- audit rows for bootstrap, config-reconciliation fallback, credential rotation, revocation, retirement, outage-state transitions, and manual recovery
- manual resume and manual retry compatibility checks after drift, including one-time selector overrides

**Step 2: Write failing contract and integration tests**

`agent_protocol_contract_test.rb` should cover:

- registration request and response schema
- heartbeat request and response schema
- health request and response schema
- capabilities request and response schema
- transcript listing request and response schema including cursor semantics
- variable read and write request and response schema
- human interaction request schema
- handshake semantics for capability snapshots and config snapshots
- logical operation IDs using stable `snake_case` naming rather than dotted tool-style names
- capability snapshots publishing `protocol_methods` separately from `tool_catalog`

`agent_recovery_flow_test.rb` should cover:

- bootstrap creating a system-owned run or workflow record
- transient outage marking work waiting
- prolonged outage pausing work
- auto-resume only when fingerprint and capabilities version did not drift
- drift requiring explicit manual resume or manual retry before work continues
- allowing one-time `role:*` or explicit-candidate overrides during manual recovery without mutating durable conversation or deployment config
- manual resume rejected when logical-agent, capability, or pinned-config compatibility checks fail
- manual retry preserving the paused run as history while starting a fresh workflow from the last stable selected input
- audit rows for bootstrap, degradation, retirement, paused-agent-unavailable transition, and explicit recovery decisions

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/requests/agent_api/registrations_test.rb test/requests/agent_api/heartbeats_test.rb test/requests/agent_api/health_test.rb test/requests/agent_api/capabilities_test.rb test/requests/agent_api/conversation_transcripts_test.rb test/requests/agent_api/conversation_variables_test.rb test/requests/agent_api/workspace_variables_test.rb test/requests/agent_api/human_interactions_test.rb test/services/agent_deployments/handshake_test.rb test/services/agent_deployments/reconcile_config_test.rb test/services/agent_deployments/bootstrap_test.rb test/services/agent_deployments/rotate_machine_credential_test.rb test/services/agent_deployments/revoke_machine_credential_test.rb test/services/agent_deployments/retire_test.rb test/services/agent_deployments/mark_unavailable_test.rb test/services/agent_deployments/auto_resume_workflows_test.rb test/services/workflows/manual_resume_test.rb test/services/workflows/manual_retry_test.rb test/queries/conversation_transcripts/list_query_test.rb test/queries/conversation_variables/get_query_test.rb test/queries/conversation_variables/mget_query_test.rb test/queries/conversation_variables/list_query_test.rb test/queries/conversation_variables/resolve_query_test.rb test/queries/workspace_variables/get_query_test.rb test/queries/workspace_variables/mget_query_test.rb test/queries/workspace_variables/list_query_test.rb test/integration/agent_protocol_contract_test.rb test/integration/agent_recovery_flow_test.rb
```

Expected:

- missing route, controller, or service failures

**Step 4: Implement minimal machine-facing boundaries**

Rules:

- no human-facing UI controllers
- machine-facing controllers should be thin wrappers around services
- machine-facing protocol work in this phase must not introduce schedule-trigger or webhook-ingress controllers
- public logical operation IDs in this contract should use `snake_case`; controller names and HTTP routes may stay resource-oriented
- transcript listing must return the canonical visible transcript only and must support cursor pagination
- variable APIs should expose explicit `get`, `mget`, `list`, and `resolve` semantics rather than ambiguous read verbs
- machine-facing variable writes and promotions remain kernel-declared intent boundaries, not direct agent-owned database writes
- machine-facing human interaction creation must create workflow-owned request resources and projection events through kernel services
- capability snapshots should expose protocol methods separately from tool catalog metadata and should not overload one mixed `supported_methods` list as the long-term public contract
- machine credential rotation must issue a fresh secret, invalidate the previous credential atomically, and create an audit row
- machine credential revocation must make the current credential unusable and create an audit row before any later re-registration
- deployment retirement must move the deployment into the `retired` state, make it ineligible for future scheduling, and create an audit row
- drift blocks silent continuation
- explicit manual resume or manual retry is required after drift before paused work can continue
- manual resume is only allowed when the replacement deployment satisfies same-logical-agent and required-capability compatibility
- manual retry must preserve the paused workflow as historical state and create a fresh execution path
- manual recovery may accept a one-time selector override, but it must not mutate the persisted conversation selector or deployment slot config
- bootstrap, config-reconciliation fallback, outage-state transitions, retirement, and manual recovery decisions must produce audit records
- agents declare intent; kernel materializes durable side effects

**Step 5: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/requests/agent_api/registrations_test.rb test/requests/agent_api/heartbeats_test.rb test/requests/agent_api/health_test.rb test/requests/agent_api/capabilities_test.rb test/requests/agent_api/conversation_transcripts_test.rb test/requests/agent_api/conversation_variables_test.rb test/requests/agent_api/workspace_variables_test.rb test/requests/agent_api/human_interactions_test.rb test/services/agent_deployments/handshake_test.rb test/services/agent_deployments/reconcile_config_test.rb test/services/agent_deployments/bootstrap_test.rb test/services/agent_deployments/rotate_machine_credential_test.rb test/services/agent_deployments/revoke_machine_credential_test.rb test/services/agent_deployments/retire_test.rb test/services/agent_deployments/mark_unavailable_test.rb test/services/agent_deployments/auto_resume_workflows_test.rb test/services/workflows/manual_resume_test.rb test/services/workflows/manual_retry_test.rb test/queries/conversation_transcripts/list_query_test.rb test/queries/conversation_variables/get_query_test.rb test/queries/conversation_variables/mget_query_test.rb test/queries/conversation_variables/list_query_test.rb test/queries/conversation_variables/resolve_query_test.rb test/queries/workspace_variables/get_query_test.rb test/queries/workspace_variables/mget_query_test.rb test/queries/workspace_variables/list_query_test.rb test/integration/agent_protocol_contract_test.rb test/integration/agent_recovery_flow_test.rb
```

Expected:

- targeted tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/app/controllers/agent_api core_matrix/config/routes.rb core_matrix/app/models core_matrix/app/services/agent_deployments core_matrix/app/services/workflows core_matrix/app/queries/conversation_transcripts core_matrix/app/queries/conversation_variables core_matrix/app/queries/workspace_variables core_matrix/script/manual/dummy_agent_runtime.rb core_matrix/test/requests core_matrix/test/services core_matrix/test/queries core_matrix/test/integration
git -C .. commit -m "feat: add agent protocol boundaries and recovery flows"
```
