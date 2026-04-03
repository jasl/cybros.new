# Agent Program And Execution Runtime Reset Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current conversation-bound deployment and execution-environment model with a turn-bound runtime model built around `AgentProgram`, `AgentProgramVersion`, optional `ExecutionRuntime`, and single-active session authentication.

**Architecture:** Reset the domain in one destructive migration pass. `Conversation` binds only to `AgentProgram`. `Turn` freezes `AgentProgramVersion` and optional `ExecutionRuntime`. Live authentication and control-plane ownership move to `AgentSession` and `ExecutionSession`. Capability assembly, attachment delivery, recovery, and bundled `Fenix` bootstrap are rewritten around the new model. Obsolete services, docs, and tests are deleted instead of shimmed.

**Tech Stack:** Ruby on Rails, Active Record, Action Cable, Active Job, Active Storage, mailbox control-plane services, provider-backed agent loop in `core_matrix`, Dockerized `agents/fenix`, React acceptance app in mounted workspace, OpenRouter-backed model access from `core_matrix/.env`.

---

## Preconditions

- Approved design:
  - `docs/plans/2026-04-03-agent-program-execution-runtime-reset-design.md`
- Required skills during execution:
  - `superpowers:test-driven-development`
  - `superpowers:verification-before-completion`
- Required acceptance checklist:
  - `docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md`
- Database reset command after migration edits:

```bash
cd core_matrix && bin/rails db:drop && rm db/schema.rb && bin/rails db:create && bin/rails db:migrate && bin/rails db:reset
```

## Guardrails

- no compatibility shims
- no legacy naming aliases
- no dead code preservation
- no conversation-scoped runtime binding
- no direct authentication as program-version or execution-runtime rows
- no completion claims without fresh verification output

## Final Verification Gate

Before closing the work, verify all of the following with fresh evidence:

- `core_matrix` verification commands from `AGENTS.md`
- `agents/fenix` relevant tests and runtime checks
- repo-wide sweep for old names and deleted concepts
- provider-backed 2048 capstone acceptance under the new model

### Task 1: Write the approved design doc and implementation plan

**Files:**
- Create: `docs/plans/2026-04-03-agent-program-execution-runtime-reset-design.md`
- Create: `docs/plans/2026-04-03-agent-program-execution-runtime-reset.md`

**Step 1: Write the approved design doc**

- record the renamed aggregates
- record session-based authentication
- record turn-scoped runtime binding
- record attachment reset
- record the required rewrite sweep

**Step 2: Write the implementation plan**

- list the schema reset
- list the service rewrites
- list the docs and acceptance rewrites

**Step 3: Verify the docs exist**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
test -f docs/plans/2026-04-03-agent-program-execution-runtime-reset-design.md
test -f docs/plans/2026-04-03-agent-program-execution-runtime-reset.md
```

Expected: exit 0

### Task 2: Reset migrations, schema names, and base models

**Files:**
- Modify: `core_matrix/db/migrate/20260324090006_create_agent_installations.rb`
- Modify: `core_matrix/db/migrate/20260324090007_create_execution_environments.rb`
- Modify: `core_matrix/db/migrate/20260324090009_create_agent_deployments.rb`
- Modify: `core_matrix/db/migrate/20260324090010_create_capability_snapshots.rb`
- Modify: `core_matrix/db/migrate/20260324090011_create_user_agent_bindings.rb`
- Modify: `core_matrix/db/migrate/20260324090019_create_conversations.rb`
- Modify: `core_matrix/db/migrate/20260324090021_create_turns.rb`
- Modify: `core_matrix/db/migrate/20260326113000_add_agent_control_contract.rb`
- Modify: `core_matrix/db/migrate/20260324090034_create_process_runs.rb`
- Create: `core_matrix/app/models/agent_program.rb`
- Create: `core_matrix/app/models/user_program_binding.rb`
- Create: `core_matrix/app/models/agent_program_version.rb`
- Create: `core_matrix/app/models/execution_runtime.rb`
- Create: `core_matrix/app/models/agent_session.rb`
- Create: `core_matrix/app/models/execution_session.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/process_run.rb`
- Delete: `core_matrix/app/models/agent_installation.rb`
- Delete: `core_matrix/app/models/user_agent_binding.rb`
- Delete: `core_matrix/app/models/agent_deployment.rb`
- Delete: `core_matrix/app/models/execution_environment.rb`
- Delete: `core_matrix/app/models/capability_snapshot.rb`
- Test: `core_matrix/test/models/agent_program_test.rb`
- Test: `core_matrix/test/models/user_program_binding_test.rb`
- Test: `core_matrix/test/models/agent_program_version_test.rb`
- Test: `core_matrix/test/models/execution_runtime_test.rb`
- Test: `core_matrix/test/models/agent_session_test.rb`
- Test: `core_matrix/test/models/execution_session_test.rb`
- Test: `core_matrix/test/models/conversation_test.rb`
- Test: `core_matrix/test/models/turn_test.rb`
- Test: `core_matrix/test/models/process_run_test.rb`

**Step 1: Write failing model tests for the reset**

- conversation binds only to agent program
- turn requires agent program version
- turn allows `execution_runtime` to be nil
- process run validates against turn execution runtime
- single-active-session invariants
- display-name persistence
- no capability-snapshot table or dependency remains

**Step 2: Run the failing model tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/agent_program_test.rb test/models/user_program_binding_test.rb test/models/agent_program_version_test.rb test/models/execution_runtime_test.rb test/models/agent_session_test.rb test/models/execution_session_test.rb test/models/conversation_test.rb test/models/turn_test.rb test/models/process_run_test.rb
```

Expected: FAIL against the old model

**Step 3: Implement the schema and model reset**

- edit migrations in place
- rebuild the schema from scratch
- port model validations and associations to new names and new ownership

**Step 4: Rebuild the database and rerun the tests**

Run:

```bash
cd core_matrix && bin/rails db:drop && rm db/schema.rb && bin/rails db:create && bin/rails db:migrate && bin/rails db:reset
bin/rails test test/models/agent_program_test.rb test/models/user_program_binding_test.rb test/models/agent_program_version_test.rb test/models/execution_runtime_test.rb test/models/agent_session_test.rb test/models/execution_session_test.rb test/models/conversation_test.rb test/models/turn_test.rb test/models/process_run_test.rb
```

Expected: PASS

### Task 3: Reset factories, fixtures, and context builders before deeper rewrites

**Files:**
- Modify: `core_matrix/test/test_helper.rb`
- Modify: `core_matrix/test/support/**/*.rb`
- Modify: `core_matrix/script/manual/manual_acceptance_support.rb`

**Step 1: Write failing tests around the new helper contracts**

- default test contexts produce `agent_program`, `agent_program_version`,
  optional `execution_runtime`, and sessions
- helper methods no longer expose old names

**Step 2: Run the targeted helper tests or dependent model/service tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/conversation_test.rb test/models/turn_test.rb test/services/turns/start_user_turn_test.rb
```

Expected: FAIL until helpers are updated

**Step 3: Rewrite helper builders**

- replace `create_agent_installation!`
- replace `create_agent_deployment!`
- replace `create_execution_environment!`
- add session builders
- make old helper names disappear instead of aliasing

**Step 4: Rerun the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/conversation_test.rb test/models/turn_test.rb test/services/turns/start_user_turn_test.rb
```

Expected: PASS

### Task 4: Rewrite turn entry, follow-up, workflow snapshot, and capability assembly

**Files:**
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/app/services/turns/start_agent_turn.rb`
- Modify: `core_matrix/app/services/turns/start_automation_turn.rb`
- Modify: `core_matrix/app/services/turns/queue_follow_up.rb`
- Create: `core_matrix/app/services/turns/select_execution_runtime.rb`
- Create: `core_matrix/app/services/turns/freeze_program_version.rb`
- Modify: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- Delete: `core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb`
- Delete: `core_matrix/app/services/conversations/refresh_runtime_contract.rb`
- Modify: `core_matrix/app/models/runtime_capability_contract.rb`
- Modify: `core_matrix/app/services/tool_bindings/freeze_for_task.rb`
- Modify: `core_matrix/app/services/tool_bindings/freeze_for_workflow_node.rb`
- Test: `core_matrix/test/services/turns/start_user_turn_test.rb`
- Test: `core_matrix/test/services/turns/start_agent_turn_test.rb`
- Test: `core_matrix/test/services/turns/start_automation_turn_test.rb`
- Test: `core_matrix/test/services/turns/queue_follow_up_test.rb`
- Test: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Test: `core_matrix/test/services/tool_bindings/freeze_for_task_test.rb`
- Test: `core_matrix/test/services/tool_bindings/freeze_for_workflow_node_test.rb`

**Step 1: Write failing tests for turn-scoped runtime behavior**

- turn freezes the active program version
- turn resolves execution runtime by the new policy
- turns can be created without execution runtime
- capability surface excludes execution tools when runtime is nil
- snapshot no longer carries `runtime_attachment_manifest`

**Step 2: Run the failing tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/turns/start_user_turn_test.rb test/services/turns/start_agent_turn_test.rb test/services/turns/start_automation_turn_test.rb test/services/turns/queue_follow_up_test.rb test/services/workflows/build_execution_snapshot_test.rb test/services/tool_bindings/freeze_for_task_test.rb test/services/tool_bindings/freeze_for_workflow_node_test.rb
```

Expected: FAIL

**Step 3: Implement the new turn runtime flow**

- remove all reads of `conversation.agent_deployment`
- remove all reads of `conversation.execution_environment`
- freeze program version from session
- select optional execution runtime
- build capability surface from turn inputs only

**Step 4: Rerun the tests**

Run the same command again.

Expected: PASS

### Task 5: Rewrite program-plane and execution-plane sessions, routing, and controllers

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/program_api/base_controller.rb`
- Create: `core_matrix/app/controllers/execution_api/base_controller.rb`
- Port and rename controllers under `core_matrix/app/controllers/agent_api/`
- Delete: `core_matrix/app/controllers/agent_api/**/*.rb`
- Modify: `core_matrix/app/services/agent_control/create_execution_assignment.rb`
- Modify: `core_matrix/app/services/agent_control/create_agent_program_request.rb`
- Modify: `core_matrix/app/services/agent_control/resolve_target_runtime.rb`
- Modify: `core_matrix/app/services/agent_control/handle_runtime_resource_report.rb`
- Modify: `core_matrix/app/services/agent_control/validate_execution_report_freshness.rb`
- Modify: `core_matrix/app/services/agent_control/validate_close_report_freshness.rb`
- Modify: `core_matrix/app/models/agent_control_mailbox_item.rb`
- Modify: `core_matrix/app/channels/application_cable/connection.rb`
- Test: `core_matrix/test/requests/program_api/**/*_test.rb`
- Test: `core_matrix/test/requests/execution_api/**/*_test.rb`
- Test: `core_matrix/test/services/agent_control/**/*_test.rb`
- Test: `core_matrix/test/channels/application_cable/connection_test.rb`

**Step 1: Write failing request and routing tests**

- program API authenticates sessions
- execution API authenticates execution sessions
- stale sessions get `409`
- mailbox plane values are `program` and `execution`

**Step 2: Run the failing tests**

Run:

```bash
cd core_matrix
bin/rails test test/requests test/services/agent_control test/channels/application_cable/connection_test.rb
```

Expected: FAIL

**Step 3: Port the controllers and routing**

- split program and execution APIs
- remove direct deployment authentication
- route mailbox work through sessions and logical owners

**Step 4: Rerun the tests**

Run the same command again.

Expected: PASS

### Task 6: Rewrite recovery, close, process, and import/export flows to the new binding model

**Files:**
- Modify: `core_matrix/app/services/workflows/manual_resume.rb`
- Modify: `core_matrix/app/services/workflows/manual_retry.rb`
- Modify: `core_matrix/app/services/workflows/step_retry.rb`
- Modify: `core_matrix/app/services/conversations/request_turn_interrupt.rb`
- Modify: `core_matrix/app/services/agent_control/closable_resource_routing.rb`
- Modify: `core_matrix/app/services/conversation_bundle_imports/create_request.rb`
- Modify: `core_matrix/app/services/conversation_bundle_imports/rehydrate_conversation.rb`
- Modify: `core_matrix/app/services/conversation_debug_exports/build_payload.rb`
- Delete: `core_matrix/app/services/conversations/switch_agent_deployment.rb`
- Delete: `core_matrix/app/services/conversations/validate_agent_deployment_target.rb`
- Delete or replace: `core_matrix/app/services/agent_deployments/**/*.rb`
- Test: `core_matrix/test/services/workflows/manual_resume_test.rb`
- Test: `core_matrix/test/services/workflows/manual_retry_test.rb`
- Test: `core_matrix/test/services/conversation_bundle_imports/**/*_test.rb`
- Test: `core_matrix/test/services/conversation_debug_exports/**/*_test.rb`
- Test: `core_matrix/test/integration/agent_recovery_flow_test.rb`

**Step 1: Write failing tests for the new recovery and import rules**

- retry/resume no longer mutate conversation runtime identity
- import targets agent program, not deployment
- debug payload emits new names and frozen turn bindings

**Step 2: Run the failing tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/workflows/manual_resume_test.rb test/services/workflows/manual_retry_test.rb test/services/conversation_bundle_imports test/services/conversation_debug_exports test/integration/agent_recovery_flow_test.rb
```

Expected: FAIL

**Step 3: Implement the rewrites and delete obsolete services**

- remove old deployment-rebind semantics
- rewrite recovery around frozen turn bindings and active sessions
- update import/export payloads

**Step 4: Rerun the tests**

Run the same command again.

Expected: PASS

### Task 7: Rewrite attachment delivery and execution-owned tool flow

**Files:**
- Modify: `core_matrix/app/services/attachments/materialize_refs.rb`
- Create: `core_matrix/app/services/execution_attachments/request.rb`
- Create: `core_matrix/app/models/attachment_access_grant.rb`
- Modify: `core_matrix/app/services/provider_execution/route_tool_call.rb`
- Modify: `core_matrix/app/controllers/execution_api/*`
- Test: `core_matrix/test/services/attachments/materialize_refs_test.rb`
- Test: `core_matrix/test/services/execution_attachments/request_test.rb`
- Test: `core_matrix/test/integration/transcript_visibility_attachment_flow_test.rb`
- Test: `core_matrix/test/integration/runtime_process_flow_test.rb`

**Step 1: Write failing tests**

- no `runtime_attachment_manifest`
- execution attachment access is request-based
- execution runtime must match the frozen turn runtime
- turns without runtime cannot request execution attachment access

**Step 2: Run the failing tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/attachments/materialize_refs_test.rb test/services/execution_attachments/request_test.rb test/integration/transcript_visibility_attachment_flow_test.rb test/integration/runtime_process_flow_test.rb
```

Expected: FAIL

**Step 3: Implement the new attachment flow**

- keep canonical manifest
- add access grants
- remove old runtime attachment projection

**Step 4: Rerun the tests**

Run the same command again.

Expected: PASS

### Task 8: Rewrite bundled bootstrap, external registration, and Fenix contract handling

**Files:**
- Modify: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Modify: `core_matrix/app/services/installations/bootstrap_bundled_agent_binding.rb`
- Modify: `core_matrix/app/services/agent_enrollments/issue.rb`
- Modify: `core_matrix/script/manual/**/*.rb`
- Modify: `agents/fenix/**/*`
- Test: `core_matrix/test/integration/bundled_default_agent_bootstrap_flow_test.rb`
- Test: `core_matrix/test/integration/external_fenix_pairing_flow_test.rb`
- Test: `core_matrix/test/integration/agent_registration_contract_test.rb`
- Test: `agents/fenix/test/**/*_test.rb`

**Step 1: Write failing tests for the new program/runtime split**

- bundled bootstrap creates program and execution runtime separately
- external Fenix pairing uses sessions and new names
- Fenix accepts the new plane names and API namespaces

**Step 2: Run the failing tests**

Run:

```bash
cd core_matrix
bin/rails test test/integration/bundled_default_agent_bootstrap_flow_test.rb test/integration/external_fenix_pairing_flow_test.rb test/integration/agent_registration_contract_test.rb
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test
```

Expected: FAIL

**Step 3: Rewrite bundled bootstrap and Fenix contract handling**

- split program and execution registration flows
- update Fenix runtime worker contract and names
- update Docker/runtime helper scripts

**Step 4: Rerun the tests**

Run the same commands again.

Expected: PASS

### Task 9: Rewrite behavior docs and perform repo-wide obsolete-term sweeps

**Files:**
- Modify: `core_matrix/docs/behavior/**/*.md`
- Modify: `docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md`
- Modify: `docs/plans/*.md` where old design assumptions remain
- Modify: `agents/fenix/README.md`
- Modify: `agents/fenix/docs/plans/*.md` as needed

**Step 1: Run the first sweep**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "AgentInstallation|UserAgentBinding|AgentDeployment|ExecutionEnvironment|agent_api|conversation\\.agent_deployment|conversation\\.execution_environment|conversation_attachment_upload" core_matrix agents/fenix docs -g '!references/**'
```

Expected: many hits

**Step 2: Rewrite or delete every remaining obsolete reference**

- update behavior docs to the new ownership model
- delete docs that only describe the removed design
- update checklist terms to the new contract

**Step 3: Run the sweep again**

Run the same command again.

Expected: either zero hits or only intentionally historical references in archived material

### Task 10: Full verification loop and provider-backed 2048 capstone acceptance

**Files:**
- Modify as required by verification findings
- Produce proof outputs under the paths selected during acceptance execution

**Step 1: Run the repository verification commands**

Run:

```bash
cd core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference
bundle exec rake
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare test
```

Expected: PASS

**Step 2: Run the final obsolete-term and dead-path sweeps**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "SwitchAgentDeployment|ValidateAgentDeploymentTarget|RefreshRuntimeContract|ResolveDeliveryEndpoint|runtime_attachment_manifest|conversation_attachment_upload" core_matrix agents/fenix docs -g '!references/**'
```

Expected: zero hits outside intentional archived records

**Step 3: Execute the Fenix 2048 capstone acceptance**

Use:

- `docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md`

Required outcomes:

- Dockerized Fenix registers under the new program/runtime model
- a provider-backed conversation builds a playable React 2048 game in `tmp/fenix`
- host-side playability verification passes
- app API diagnostics/export/debug export/import still work
- proof package is recorded

**Step 4: Run one more verification pass after any acceptance fixes**

Repeat the verification commands from Step 1.

Expected: PASS

**Step 5: Final sweep**

Repeat the sweep from Step 2.

Expected: PASS with no new issues found

## Execution Assumption

The user explicitly requested uninterrupted execution in the current session.
Proceed with in-session implementation and repeated verification loops unless a
new design blocker appears that requires a product decision.
