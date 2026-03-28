# Core Matrix Phase 2 Post-Consolidation Repair Loop Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close the concrete contract leaks and residual wrapper paths left after the structural consolidation follow-up, then repeat targeted review until no new actionable findings remain in that scope.

**Architecture:** Keep the repair loop narrow and evidence-driven. First fix the two confirmed findings from the post-consolidation review, then collapse the remaining duplicate contract entry points around provider execution, capability bootstrap, and blocker/wait wrappers. After each batch, run focused verification and repeat the same review surface instead of expanding into unrelated Phase 2 work.

**Tech Stack:** Ruby on Rails, Active Record, Minitest, RuboCop, provider execution services, runtime capability contracts, conversation/workflow guard services.

---

## Scope

This follow-up stays inside the structural-consolidation surface:

- provider request-setting schema enforcement
- provider execution request-context flow
- timeline mutation guard locking and validation
- runtime capability bootstrap and registration contract shaping
- dead or redundant wrapper entry points created during the consolidation

Out of scope:

- new provider features
- new runtime protocol fields
- new conversation lifecycle semantics
- broad query-layer redesign beyond the already-reviewed blocker surface

## Loop Rule

Execute this work in short loops:

1. repair one bounded contract family
2. run focused tests and diff checks immediately
3. re-review the same surface for residual old paths
4. either fix the next concrete issue or stop when only stylistic preferences remain

Do not open a new architecture branch unless the review finds a fresh, concrete defect or duplicate ownership path.

## Task 1: Fail Closed On Invalid Runtime Request Overrides

**Files:**
- Modify: `core_matrix/app/models/provider_request_settings_schema.rb`
- Modify: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `core_matrix/test/models/provider_request_settings_schema_test.rb`
- Modify: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`

**Intent:**

- make the canonical schema validate runtime overrides, not just catalog defaults
- fail snapshot assembly at the turn boundary when runtime overrides are invalid
- prove unsupported keys are still filtered while invalid values now raise

**Verification:**

- `bin/rails test test/models/provider_request_settings_schema_test.rb test/services/workflows/build_execution_snapshot_test.rb`
- `bin/rubocop app/models/provider_request_settings_schema.rb app/services/workflows/build_execution_snapshot.rb test/models/provider_request_settings_schema_test.rb test/services/workflows/build_execution_snapshot_test.rb`
- `git diff --check`

## Task 2: Keep Timeline Mutation Guards On The Locked Conversation Instance

**Files:**
- Modify: `core_matrix/app/services/turns/validate_timeline_mutation_target.rb`
- Modify: `core_matrix/test/services/turns/validate_timeline_mutation_target_test.rb`
- Modify: `core_matrix/test/services/workflows/manual_resume_test.rb`

**Intent:**

- make `ValidateTimelineMutationTarget` consume the passed `conversation:` object
- remove the residual extra association hop back to `current_turn.conversation`
- prove the shared blocker-snapshot path still drives both timeline mutation and paused manual resume validation

**Verification:**

- `bin/rails test test/services/turns/validate_timeline_mutation_target_test.rb test/services/workflows/manual_resume_test.rb`
- `bin/rubocop app/services/turns/validate_timeline_mutation_target.rb test/services/turns/validate_timeline_mutation_target_test.rb test/services/workflows/manual_resume_test.rb`
- `git diff --check`

## Task 3: Pass ProviderRequestContext End-To-End

**Files:**
- Modify: `core_matrix/app/services/provider_execution/build_request_context.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Modify: `core_matrix/app/services/provider_execution/dispatch_request.rb`
- Modify: `core_matrix/app/services/provider_execution/persist_turn_step_success.rb`
- Modify: `core_matrix/app/services/provider_execution/persist_turn_step_failure.rb`
- Modify: `core_matrix/test/services/provider_execution/build_request_context_test.rb`
- Modify: `core_matrix/test/services/provider_execution/dispatch_request_test.rb`
- Modify: `core_matrix/test/services/provider_execution/persist_turn_step_success_test.rb`
- Modify: `core_matrix/test/services/provider_execution/persist_turn_step_failure_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`

**Intent:**

- stop returning a raw hash from `BuildRequestContext`
- let provider execution collaborators accept one canonical request-context object
- remove repeated `ProviderRequestContext.new(...)` reparsing inside each collaborator

**Verification:**

- `bin/rails test test/services/provider_execution`
- `bin/rubocop app/services/provider_execution test/services/provider_execution`
- `git diff --check`

## Task 4: Collapse Residual Runtime Capability Bootstrap Drift

**Files:**
- Modify: `core_matrix/app/services/agent_deployments/register.rb`
- Modify: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Modify: `core_matrix/app/controllers/agent_api/registrations_controller.rb`
- Modify: `core_matrix/app/models/capability_snapshot.rb`
- Modify: `core_matrix/app/models/execution_environment.rb`
- Modify: `core_matrix/test/services/agent_deployments/register_test.rb`
- Modify: `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Modify: `core_matrix/test/requests/agent_api/registrations_test.rb`
- Modify: `core_matrix/test/integration/agent_registration_contract_test.rb`

**Intent:**

- run initial registration and bundled runtime snapshot shaping through the same runtime capability contract family used by handshake
- keep only the wrappers that still carry a real boundary meaning
- avoid maintaining two separate writers for agent-plane contract payloads

**Verification:**

- `bin/rails test test/services/agent_deployments/register_test.rb test/services/installations/register_bundled_agent_runtime_test.rb test/requests/agent_api/registrations_test.rb test/integration/agent_registration_contract_test.rb`
- `bin/rubocop app/services/agent_deployments/register.rb app/services/installations/register_bundled_agent_runtime.rb app/controllers/agent_api/registrations_controller.rb app/models/capability_snapshot.rb app/models/execution_environment.rb test/services/agent_deployments/register_test.rb test/services/installations/register_bundled_agent_runtime_test.rb test/requests/agent_api/registrations_test.rb test/integration/agent_registration_contract_test.rb`
- `git diff --check`

## Task 5: Delete Dead Wrappers And Re-Review The Same Surface

**Files:**
- Modify: `core_matrix/app/services/agent_deployments/unavailable_pause_state.rb`
- Modify: `core_matrix/app/services/conversations/work_quiescence_guard.rb`
- Modify: `core_matrix/app/services/conversations/validate_timeline_suffix_supersession.rb`
- Modify tests that exercise those paths only if behavior changes

**Intent:**

- remove dead helpers that no longer serve as a real boundary
- decide whether the remaining blocker/work-barrier message mapping should collapse now or stay put
- re-run the exact same review surface and only continue if a new concrete issue appears

**Verification:**

- `bin/rails test test/services/conversations test/services/agent_deployments`
- `bin/rubocop app/services/conversations app/services/agent_deployments`
- `git diff --check`

## Final Verification

After the last repair loop, run:

- `bin/rails test test/services/provider_execution test/services/agent_deployments test/services/turns test/services/workflows test/services/conversations test/services/runtime_capabilities test/services/execution_environments test/models/provider_request_settings_schema_test.rb test/models/provider_request_context_test.rb test/models/capability_snapshot_test.rb test/models/execution_environment_test.rb test/queries/conversations test/requests/agent_api/capabilities_test.rb test/requests/agent_api/registrations_test.rb test/integration/agent_registration_contract_test.rb`
- `bin/rubocop app/models/provider_request_settings_schema.rb app/models/provider_request_context.rb app/models/runtime_capability_contract.rb app/models/capability_snapshot.rb app/models/execution_environment.rb app/models/workflow_wait_snapshot.rb app/services/provider_execution app/services/agent_deployments app/services/workflows app/services/turns app/services/conversations app/services/runtime_capabilities app/services/execution_environments test/services/provider_execution test/services/agent_deployments test/services/turns test/services/workflows test/services/conversations test/services/runtime_capabilities test/services/execution_environments test/models/provider_request_settings_schema_test.rb test/models/provider_request_context_test.rb test/models/capability_snapshot_test.rb test/models/execution_environment_test.rb test/queries/conversations test/requests/agent_api/capabilities_test.rb test/requests/agent_api/registrations_test.rb test/integration/agent_registration_contract_test.rb`
- `git diff --check`
- `git status --short`

## Stop Condition

Stop the loop when:

- the original findings are fixed
- the residual duplicate entry points in this scope are either removed or intentionally retained with one obvious owner
- a fresh targeted review of this same surface produces no new concrete bugs, contract leaks, or duplicate ownership paths

If a new issue requires changing Phase 2 scope rather than tightening this surface, stop and discuss it before continuing.
