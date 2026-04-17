# Agent Runtime Conversation Reset Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the remaining `Agent` / `ExecutionRuntime` / dual-role runtime assumptions with the final `Agent` / `ExecutionRuntime` / `Conversation` architecture, split Fenix and Nexus into separate registration identities, and update the monorepo so code, APIs, docs, files, and folders all use the new architecture.

> Superseded by `/Users/jasl/Workspaces/Ruby/cybros/docs/archived-plans/core_matrix-docs-legacy-2026-04-17/plans/2026-04-12-agent-canonical-config-and-runtime-pairing-design.md`; terminology is normalized here to match the implemented model.

**Architecture:** CoreMatrix becomes the single orchestrator for `Agent`, `ExecutionRuntime`, `Conversation`, and frozen turn snapshots. Fenix becomes the pure agent decision layer, while Nexus becomes the single execution runtime appliance that owns runtime tools, runtime context materialization, filesystem-backed skill assets, and filesystem-backed memory. Tool resolution follows `ExecutionRuntime > Agent > CoreMatrix`, except for reserved CoreMatrix names that can never be overridden.

**Tech Stack:** Ruby on Rails, Active Record, Action Cable, Active Job, filesystem-backed skill packages, filesystem-backed memory, mailbox control plane, acceptance harness, Dockerized runtime image.

---

### Task 1: Write the approved design and active execution records

**Files:**
- Create: `docs/plans/2026-04-11-agent-runtime-conversation-reset-design.md`
- Create: `docs/plans/2026-04-11-agent-runtime-conversation-reset.md`
- Modify: `docs/plans/README.md`

**Step 1: Write the design doc**

- record the new aggregate names
- record the new registration split
- record skill/memory boundary decisions
- record tool priority and reserved-name rules

**Step 2: Write the implementation plan**

- break the reset into CoreMatrix, Fenix, Nexus, docs, and acceptance tasks

**Step 3: Update the plans index**

- add both new active plan files to `docs/plans/README.md`

**Step 4: Verify the files exist**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
test -f docs/plans/2026-04-11-agent-runtime-conversation-reset-design.md
test -f docs/plans/2026-04-11-agent-runtime-conversation-reset.md
```

Expected: exit `0`

### Task 2: Write failing CoreMatrix model tests for the new domain names

**Files:**
- Create: `core_matrix/test/models/agent_test.rb`
- Create: `core_matrix/test/models/agent_snapshot_test.rb`
- Create: `core_matrix/test/models/execution_runtime_test.rb`
- Create: `core_matrix/test/models/execution_runtime_connection_test.rb`
- Create: `core_matrix/test/models/agent_connection_test.rb`
- Modify: `core_matrix/test/models/conversation_test.rb`
- Modify: `core_matrix/test/models/turn_test.rb`
- Modify: `core_matrix/test/models/process_run_test.rb`
- Modify: `core_matrix/test/test_helper.rb`

**Step 1: Write failing tests**

- `Conversation` binds to `Agent` and `ExecutionRuntime`
- `Turn` freezes `AgentDefinitionVersion` and the selected execution-runtime contract
- single active connection is enforced per `Agent`
- single active connection is enforced per `ExecutionRuntime`
- runtime default binding uses `default_execution_runtime`
- `Conversation` remains the user-facing thread aggregate
- `Session` remains reserved for user authentication and connection credentials

**Step 2: Run the model tests and confirm failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/agent_test.rb test/models/agent_snapshot_test.rb test/models/execution_runtime_test.rb test/models/execution_runtime_connection_test.rb test/models/agent_connection_test.rb test/models/conversation_test.rb test/models/turn_test.rb test/models/process_run_test.rb
```

Expected: FAIL because the new model classes and associations do not exist yet.

### Task 3: Reset CoreMatrix schema, model files, and folder names

**Files:**
- Modify in place: `core_matrix/db/migrate/*`
- Create: `core_matrix/app/models/agent.rb`
- Create: `core_matrix/app/models/agent_snapshot.rb`
- Create: `core_matrix/app/models/execution_runtime.rb`
- Create: `core_matrix/app/models/agent_connection.rb`
- Create: `core_matrix/app/models/execution_runtime_connection.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/process_run.rb`
- Delete: `core_matrix/app/models/agent.rb`
- Delete: `core_matrix/app/models/agent_snapshot.rb`
- Delete: `core_matrix/app/models/execution_runtime.rb`
- Delete: `core_matrix/app/models/agent_connection.rb`
- Delete: `core_matrix/app/models/execution_runtime_connection.rb`
- Keep: `core_matrix/app/models/conversation.rb`
- Keep: `core_matrix/app/services/conversations`
- Keep: `core_matrix/test/services/conversations`

**Step 1: Implement the schema reset**

- rename tables and foreign keys in the editable migrations
- remove legacy columns and names
- rename connection-credential fields away from `session_*`
- keep `Conversation`; do not rename the user-facing thread aggregate to `Session`

**Step 2: Implement the new models**

- port validations and associations to the new names
- add `default_execution_runtime`
- add execution-contract freeze ownership and relationships

**Step 3: Rebuild the database from scratch**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:drop && rm db/schema.rb && bin/rails db:create && bin/rails db:migrate && bin/rails db:reset
```

Expected: exit `0`

**Step 4: Re-run the model tests**

Run the Task 2 test command again.

Expected: PASS

### Task 4: Rewrite CoreMatrix service, route, controller, and API naming

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Rename folder: `core_matrix/app/controllers/executor_api` -> `core_matrix/app/controllers/execution_runtime_api`
- Modify all files under:
  - `core_matrix/app/controllers/agent_api`
  - `core_matrix/app/controllers/execution_runtime_api`
  - `core_matrix/app/services/agent_control`
  - `core_matrix/app/services/runtime_capabilities`
  - `core_matrix/app/services/turns`
  - `core_matrix/app/services/workflows`
  - `core_matrix/app/services/installations`
  - `core_matrix/app/channels`
- Modify matching tests under:
  - `core_matrix/test/requests`
  - `core_matrix/test/services`
  - `core_matrix/test/integration`
  - `core_matrix/test/channels`

**Step 1: Write failing request/integration tests**

- separate agent registration from execution runtime registration
- `execution_runtime_api/*` replaces `executor_api/*`
- `Conversation` remains the user-facing thread while user-auth `Session` stays separate
- turn execution freezes both snapshots

**Step 2: Run the targeted tests and confirm failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/agent_api test/requests/execution_runtime_api test/integration/agent_registration_contract_test.rb test/integration/bundled_default_agent_bootstrap_flow_test.rb
```

Expected: FAIL because the API names and payload contracts have changed.

**Step 3: Rewrite the service/controller layer**

- split registrations into agent-only and runtime-only flows
- keep request/response keys on the product surface as `conversation`
- rename request/response keys from `execution_runtime` to `execution_runtime`
- remove bundled dual-role registration assumptions

**Step 4: Re-run the targeted tests**

Run the same command after updating paths as needed.

Expected: PASS

### Task 5: Rewrite capability composition, masking, and tool precedence

**Files:**
- Modify: `core_matrix/app/models/runtime_capability_contract.rb`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_for_turn.rb`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_visible_tool_catalog.rb`
- Modify: `core_matrix/app/services/tool_bindings/*`
- Modify related tests under:
  - `core_matrix/test/models/runtime_capability_contract_test.rb`
  - `core_matrix/test/services/runtime_capabilities/*`
  - `core_matrix/test/services/tool_bindings/*`

**Step 1: Write failing precedence and masking tests**

- `ExecutionRuntime` overrides `Agent` for same non-reserved tool names
- `Agent` overrides non-reserved CoreMatrix names
- reserved CoreMatrix names remain protected
- agent profiles can mask CoreMatrix tools such as `subagent_*`

**Step 2: Run the targeted tests and confirm failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/runtime_capability_contract_test.rb test/services/runtime_capabilities test/services/tool_bindings
```

Expected: FAIL

**Step 3: Implement the new precedence rules**

- preserve reserved-name protection
- allow non-reserved override by runtime and agent
- keep visible-tool masking at the agent/profile level

**Step 4: Re-run the targeted tests**

Expected: PASS

### Task 6: Rewrite Fenix into a pure agent decision layer

**Files:**
- Rename namespaces and folders under `agents/fenix/app/services`
- Modify:
  - `agents/fenix/app/services/requests/prepare_round.rb`
  - `agents/fenix/app/services/requests/execute_tool.rb`
  - `agents/fenix/app/services/application/build_round_instructions.rb`
  - `agents/fenix/app/services/runtime/manifest/pairing_manifest.rb`
  - `agents/fenix/README.md`
- Delete or move runtime-owned code under:
  - `agents/fenix/app/services/executor`
  - filesystem-backed skill repository/storage code
  - filesystem-backed memory store implementation
- Update affected tests under `agents/fenix/test`

**Step 1: Write failing agent-side tests**

- Fenix registers only as an agent
- Fenix requests runtime-owned skill/memory context instead of reading filesystem assets directly
- Fenix no longer exposes runtime execution tools in its manifest

**Step 2: Run the targeted tests and confirm failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test
```

Expected: FAIL in manifest and round-preparation behavior.

**Step 3: Rewrite Fenix**

- keep agent decision and policy logic
- remove runtime-owned implementations
- update manifest and docs to the new role

**Step 4: Re-run `agents/fenix` tests**

Expected: PASS

### Task 7: Rewrite Nexus into the single execution runtime appliance

**Files:**
- Rename all copied `fenix` namespaces and paths under `execution_runtimes/nexus`
- Modify:
  - `execution_runtimes/nexus/app/services/**`
  - `execution_runtimes/nexus/app/jobs/**`
  - `execution_runtimes/nexus/app/controllers/runtime_manifests_controller.rb`
  - `execution_runtimes/nexus/README.md`
  - `execution_runtimes/nexus/env.sample`
  - `execution_runtimes/nexus/bin/*`
  - `execution_runtimes/nexus/config/*`
  - `execution_runtimes/nexus/test/**`
- Move runtime-owned skill repository and filesystem-backed memory store into Nexus-owned namespaces

**Step 1: Write failing runtime-side tests**

- Nexus registers only as an `ExecutionRuntime`
- runtime manifest emits runtime-only identity
- runtime-owned skills and memory remain available
- no copied `Fenix` namespace remains in runtime code

**Step 2: Run the targeted runtime tests and confirm failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus
bin/rails test
```

Expected: FAIL

**Step 3: Rewrite Nexus**

- rename namespaces from copied `Fenix` paths to `Nexus`
- keep runtime tooling, skills, memory, and control loop
- remove bundled dual-role assumptions

**Step 4: Re-run `execution_runtimes/nexus` tests**

Expected: PASS

### Task 8: Rewrite seeds, onboarding, and default binding

**Files:**
- Modify:
  - `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
  - `core_matrix/app/services/installations/bootstrap_bundled_agent_binding.rb`
  - `core_matrix/db/seeds.rb`
  - `core_matrix/test/services/installations/*`
  - `core_matrix/test/integration/bundled_default_agent_bootstrap_flow_test.rb`

**Step 1: Write failing onboarding tests**

- first admin bootstrap creates default `Agent + ExecutionRuntime`
- conversation defaults resolve to the runtime instead of the old executor name
- separate registration paths still support bundled bootstrap

**Step 2: Run the onboarding tests and confirm failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/installations test/integration/bundled_default_agent_bootstrap_flow_test.rb
```

Expected: FAIL

**Step 3: Implement the new onboarding flow**

- rename default binding fields
- create bundled agent/runtime rows under the new names
- keep `Fenix + Nexus` as the bundled default

**Step 4: Re-run the onboarding tests**

Expected: PASS

### Task 9: Rewrite docs, acceptance, file names, and directory names

**Files:**
- Modify matching files under:
  - `docs/**`
  - `acceptance/**`
  - `core_matrix/README.md`
  - `agents/fenix/README.md`
  - `execution_runtimes/nexus/README.md`
- Rename files and directories whose names still encode old concepts

**Step 1: Sweep and rewrite old names**

- `Agent` -> `Agent`
- `AgentSnapshot` -> `AgentDefinitionVersion`
- `ExecutionRuntime` -> `ExecutionRuntime`
- `AgentConnection` -> `AgentConnection`
- `ExecutionRuntimeConnection` -> `ExecutionRuntimeConnection`
- keep `Conversation` for the user-facing thread aggregate
- keep `Session` only for user-auth and unrelated platform session concepts

**Step 2: Run repo-wide sweeps**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "Agent|AgentDefinitionVersion|ExecutionRuntime|AgentConnection|ExecutionRuntimeConnection" core_matrix agents/fenix execution_runtimes/nexus docs acceptance
rg -n "Agent|ExecutionRuntime|AgentConnection|ExecutionRuntimeConnection|connection_credential|connection credential" core_matrix agents/fenix execution_runtimes/nexus docs acceptance -g '!docs/finished-plans/**' -g '!docs/archived-plans/**'
```

Expected: no remaining active-code matches except intentionally historical archived material.

### Task 10: Run final verification and acceptance

**Files:**
- No new files

**Step 1: Verify `core_matrix`**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare
bin/rails test
bin/rails test:system
```

Expected: all commands exit `0`

**Step 2: Verify `agents/fenix`**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare
bin/rails test
```

Expected: all commands exit `0`

**Step 3: Verify `execution_runtimes/nexus`**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare
bin/rails test
```

Expected: all commands exit `0`

**Step 4: Verify the new end-to-end contract**

Run the updated acceptance scenarios for:

- separate agent registration
- separate runtime registration
- bundled `Fenix + Nexus` onboarding
- turn freeze of agent/runtime snapshots
- runtime-owned skill and memory context
- runtime-unavailable failure behavior

Expected: PASS with fresh artifacts.
