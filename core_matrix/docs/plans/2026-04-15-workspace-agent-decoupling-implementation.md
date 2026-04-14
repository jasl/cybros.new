# Workspace-Agent Decoupling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor CoreMatrix so `Workspace` becomes the user's top-level
personal space, `WorkspaceAgent` becomes the revocable mounted-agent context,
`Conversation` hangs from that mount, and ingress can later attach to the mount
without depending on `UserAgentBinding`.

**Architecture:** Perform a destructive topology refactor instead of layering
compatibility code on top of the current model. Replace the current
`UserAgentBinding + Workspace(agent-bound)` shape with `Workspace +
WorkspaceAgent`, move execution defaults and capability/entry policy to
`WorkspaceAgent`, and introduce read-only locking semantics when agent
entitlement is revoked.

**Tech Stack:** Ruby on Rails, Active Record migrations, PostgreSQL,
Minitest, existing conversation/turn/workflow infrastructure, and the existing
CoreMatrix app surface.

---

### Task 1: Lock The New Topology In Tests Before Rewriting Models

**Files:**
- Create: `core_matrix/test/models/workspace_agent_test.rb`
- Modify: `core_matrix/test/models/workspace_test.rb`
- Modify: `core_matrix/test/models/conversation_test.rb`
- Modify: `core_matrix/test/models/user_agent_binding_test.rb`
- Create: `core_matrix/test/integration/workspace_agent_revocation_flow_test.rb`
- Reference: `core_matrix/app/models/workspace.rb`
- Reference: `core_matrix/app/models/conversation.rb`
- Reference: `core_matrix/app/models/user_agent_binding.rb`

**Step 1: Write failing model tests for the target shape**

Cover:

- `Workspace` does not require `agent_id`
- `Workspace` does not require `default_execution_runtime_id`
- `WorkspaceAgent` belongs to `workspace`, `agent`, and optional
  `default_execution_runtime`
- `WorkspaceAgent` is unique per active `(workspace_id, agent_id)`
- `Conversation` requires `workspace_agent`
- revoking a `WorkspaceAgent` does not delete `Conversation`
- revoking a `WorkspaceAgent` causes related conversations to become locked

**Step 2: Write failing tests for `UserAgentBinding` removal intent**

Add explicit expectations that:

- the new root flow does not require `UserAgentBinding`
- old enablement behavior is no longer part of the target topology

**Step 3: Run the focused tests and verify failure**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/models/workspace_agent_test.rb \
  test/models/workspace_test.rb \
  test/models/conversation_test.rb \
  test/models/user_agent_binding_test.rb \
  test/integration/workspace_agent_revocation_flow_test.rb
```

**Step 4: Commit**

```bash
git add test/models/workspace_agent_test.rb \
  test/models/workspace_test.rb \
  test/models/conversation_test.rb \
  test/models/user_agent_binding_test.rb \
  test/integration/workspace_agent_revocation_flow_test.rb
git commit -m "test: lock workspace agent target topology"
```

### Task 2: Rewrite The Core Schema Around `WorkspaceAgent`

**Files:**
- Modify: `core_matrix/db/schema.rb`
- Modify or Replace: `core_matrix/db/migrate/*` for the affected topology tables
- Create: `core_matrix/db/migrate/20260415110000_create_workspace_agents.rb`
- Modify: `core_matrix/app/models/workspace.rb`
- Create: `core_matrix/app/models/workspace_agent.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Delete: `core_matrix/app/models/user_agent_binding.rb`
- Modify: `core_matrix/test/test_helper.rb`

**Step 1: Introduce the new table and columns**

Add `workspace_agents` with:

- `public_id`
- `installation_id`
- `workspace_id`
- `agent_id`
- `default_execution_runtime_id`
- `lifecycle_state`
- `revoked_at`
- `revoked_reason_kind`
- `capability_policy_payload`
- `entry_policy_payload`

Add `workspace_agent_id` and `interaction_lock_state` to `conversations`.

Remove:

- `workspaces.agent_id`
- `workspaces.default_execution_runtime_id`
- `user_agent_bindings`

**Step 2: Update model associations and validations**

Implement:

- `Workspace` as user-owned top-level root
- `WorkspaceAgent` as the mounted agent aggregate
- `Conversation` validation against `workspace_agent`

Keep external lookups on `public_id` only.

**Step 3: Rebuild the database schema cleanly**

This is a destructive topology refactor. Use the repository-standard rebuild:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:drop
rm db/schema.rb
bin/rails db:create
bin/rails db:migrate
bin/rails db:reset
```

**Step 4: Re-run the focused model tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
PARALLEL_WORKERS=1 bin/rails test \
  test/models/workspace_agent_test.rb \
  test/models/workspace_test.rb \
  test/models/conversation_test.rb \
  test/integration/workspace_agent_revocation_flow_test.rb
```

**Step 5: Commit**

```bash
git add db app/models test/test_helper.rb
git commit -m "refactor: introduce workspace agents and remove user bindings"
```

### Task 3: Re-anchor Workspace And Agent Access Queries

**Files:**
- Modify: `core_matrix/app/models/workspace.rb`
- Modify: `core_matrix/app/models/agent.rb`
- Create: `core_matrix/app/queries/workspace_agents/for_user_query.rb`
- Modify: `core_matrix/app/queries/workspaces/for_user_query.rb`
- Modify: `core_matrix/app/controllers/app_api/base_controller.rb`
- Modify: `core_matrix/test/requests/app_api/agent_homes_test.rb`
- Modify: `core_matrix/test/requests/app_api/workspaces_test.rb` if present

**Step 1: Write failing request/query tests**

Cover:

- workspaces remain visible to their owner even when an agent mount is revoked
- revoked mounts are not returned as launchable or mutable
- lookup helpers resolve conversations through `workspace_agent`

**Step 2: Replace agent-bound workspace access**

Make:

- workspace visibility depend on workspace ownership
- mounted-agent visibility/mutability depend on `WorkspaceAgent.lifecycle_state`

Do not hide the workspace just because one agent mount is revoked.

**Step 3: Run the focused tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/requests/app_api/agent_homes_test.rb \
  test/integration/workspace_agent_revocation_flow_test.rb
```

**Step 4: Commit**

```bash
git add app/queries app/controllers/app_api/base_controller.rb test
git commit -m "refactor: separate workspace visibility from agent entitlement"
```

### Task 4: Replace `Conversation.addressability` With Explicit Interaction Locking And Entry Policy

**Files:**
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/services/subagent_connections/validate_addressability.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/app/services/turns/accept_pending_user_turn.rb`
- Modify: `core_matrix/app/services/turns/queue_follow_up.rb`
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Create: `core_matrix/test/services/conversations/interaction_lock_test.rb`

**Step 1: Write failing behavior tests**

Cover:

- revoked conversation remains readable
- revoked conversation rejects new owner turns
- revoked conversation rejects follow-up queueing
- internal subagent-only semantics are no longer modeled by
  `owner_addressable/agent_addressable`

**Step 2: Implement the new model**

Replace or supersede `addressability` with:

- `interaction_lock_state`
  - `mutable`
  - `locked_agent_access_revoked`
  - `archived`
  - `deleted`

Introduce explicit entry-policy checks instead of overloading addressability.

**Step 3: Run the focused tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/interaction_lock_test.rb \
  test/services/turns/queue_follow_up_test.rb
```

**Step 4: Commit**

```bash
git add app/models/conversation.rb app/services docs/behavior/conversation-structure-and-lineage.md test
git commit -m "refactor: replace conversation addressability with interaction locking"
```

### Task 5: Move Runtime And Capability Defaults To `WorkspaceAgent`

**Files:**
- Modify: `core_matrix/app/services/conversations/creation_support.rb`
- Modify: `core_matrix/app/services/turns/select_execution_runtime.rb`
- Modify: `core_matrix/app/services/workspace_policies/capabilities.rb`
- Modify: `core_matrix/app/models/workspace_agent.rb`
- Modify: `core_matrix/test/services/conversations/create_root_test.rb`
- Modify: `core_matrix/test/services/turns/select_execution_runtime_test.rb`

**Step 1: Write failing tests for the new resolution order**

Cover:

- conversation creation resolves runtime from `WorkspaceAgent.default_execution_runtime`
- fallback remains `Agent.default_execution_runtime`
- capability defaults come from `WorkspaceAgent.capability_policy_payload`

**Step 2: Implement the new resolution rules**

Target runtime selection order:

1. explicit request
2. conversation current runtime
3. workspace-agent default runtime
4. agent default runtime

Do not resolve through `Workspace.default_execution_runtime`.

**Step 3: Run the focused tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/create_root_test.rb \
  test/services/turns/select_execution_runtime_test.rb
```

**Step 4: Commit**

```bash
git add app/services app/models/workspace_agent.rb test
git commit -m "refactor: move runtime and capability defaults to workspace agents"
```

### Task 6: Redesign AppAPI Around `WorkspaceAgent`

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/app_api/workspaces/workspace_agents_controller.rb`
- Modify: existing workspace policy and launch controllers as needed
- Modify: `core_matrix/app/services/app_surface/presenters/workspace_presenter.rb`
- Modify: `core_matrix/app/services/app_surface/presenters/agent_presenter.rb`
- Create: `core_matrix/test/requests/app_api/workspaces/workspace_agents_controller_test.rb`

**Step 1: Write failing request tests**

Cover:

- user can mount an agent into a workspace
- mount can choose a default execution runtime
- mount can be revoked/disabled
- revoked mount keeps workspace visible but prevents interactive launch

**Step 2: Implement the new management surface**

AppAPI should manage:

- `Workspace`
- `WorkspaceAgent`
- revocation state
- runtime default
- capability/entry policy

Do not recreate `UserAgentBinding` under another name.

**Step 3: Run the focused tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/requests/app_api/workspaces/workspace_agents_controller_test.rb
```

**Step 4: Commit**

```bash
git add config/routes.rb app/controllers/app_api app/services/app_surface test
git commit -m "feat: add workspace agent management surface"
```

### Task 7: Rebase Ingress On `WorkspaceAgent` And `IngressBinding`

**Files:**
- Modify: `core_matrix/docs/plans/2026-04-15-ingress-api-channel-ingress-design.md`
- Modify: `core_matrix/docs/plans/2026-04-15-ingress-api-telegram-channel-ingress-implementation.md`
- Create or Rename: ingress endpoint models/controllers/services to `IngressBinding`
- Create: `core_matrix/app/models/channel_connector.rb`
- Modify: `core_matrix/app/models/channel_session.rb`
- Modify: `core_matrix/test/services/ingress_api/preprocessors/create_or_bind_conversation_test.rb`

**Step 1: Write failing ingress tests against the new root**

Cover:

- ingress binding belongs to `WorkspaceAgent`
- revoked workspace-agent disables ingress binding
- ingress can still read the historical conversation binding but cannot create
  new turns after revocation

**Step 2: Replace endpoint semantics**

Make:

- `ChannelConnector` own transport credentials/state
- `IngressBinding` own the external route and secret
- conversation creation resolve through `WorkspaceAgent`

**Step 3: Run the focused tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/ingress_api/preprocessors/create_or_bind_conversation_test.rb
```

**Step 4: Commit**

```bash
git add docs/plans app/models test
git commit -m "refactor: rebase ingress on workspace agents and ingress bindings"
```

### Task 8: Run Full Verification And Inspect The Refactored Business Shapes

**Files:**
- Modify as needed from prior tasks only

**Step 1: Run the standard CoreMatrix verification suite**

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

**Step 2: Run acceptance because this changes acceptance-critical entry and lifecycle behavior**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

**Step 3: Inspect the resulting data state**

Confirm:

- workspaces remain visible after agent revocation
- workspace agents are revoked instead of deleted
- conversations remain visible but locked
- new turns are blocked on revoked mounts
- ingress bindings are disabled after mount revocation
- no external boundary leaks bigint ids

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor: complete workspace agent topology rewrite"
```
