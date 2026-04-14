# Workspace-Agent Decoupling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

## Execution Contract

This plan is intentionally destructive.

Mandatory execution rules:

- do not preserve compatibility with the pre-refactor topology
- do not backfill legacy data
- prefer direct schema cleanup and migration rewriting over compatibility
  shims
- when topology migrations are rewritten in place, use the repository-standard
  rebuild flow from `core_matrix`:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:drop
rm db/schema.rb
bin/rails db:create
bin/rails db:migrate
bin/rails db:reset
```

Before starting each task:

- re-read the relevant design and implementation sections
- confirm the task is still coherent and executable against the current branch
  state
- if the docs are incomplete but the intended business logic is clear, update
  the docs first and only then implement
- if the docs are insufficient and the solution cannot be decided confidently,
  stop and discuss with the user before coding

When business flow details are missing:

- consult the reference projects mentioned in the planning docs
- write the resolved rule back into the docs before implementation
- do not let undocumented business logic silently appear in code

Checkpoint protocol:

- treat related task groups as milestones rather than waiting until the end
- after each milestone, run multi-angle static review using subagents or
  equivalent reviewer passes across:
  - architecture/layering
  - business-rule compliance
  - test-plan completeness
  - migration/data-shape correctness
- fix any findings, then create a checkpoint commit

Final quality bar:

- delivery quality is more important than implementation speed
- after all plans are complete, run the full `core_matrix` verification suite,
  the full acceptance suite including the 2048 capstone, and inspect both the
  exported artifacts and the resulting database state

## Milestones

Recommended milestone grouping for this plan:

1. Tasks 1-3: root topology and visibility model
2. Tasks 4-6: interaction locking, runtime defaults, and AppAPI reshaping
3. Tasks 7-9: ingress rebase, sidecar/artifact contracts, and phase checkpoint

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
- Modify: `core_matrix/app/models/agent.rb`
- Modify: `core_matrix/app/models/user.rb`
- Modify: `core_matrix/app/models/installation.rb`
- Delete: `core_matrix/app/models/user_agent_binding.rb`
- Delete: `core_matrix/app/services/user_agent_bindings/enable.rb`
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
- removal of model-level `UserAgentBinding` associations so the app boots cleanly
  after the old aggregate is deleted

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
- Modify: `core_matrix/app/services/subagent_connections/send_message.rb`
- Modify: `core_matrix/app/services/subagent_connections/spawn.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/app/services/turns/start_agent_turn.rb`
- Modify: `core_matrix/app/services/turns/accept_pending_user_turn.rb`
- Modify: `core_matrix/app/services/turns/queue_follow_up.rb`
- Modify: `core_matrix/app/services/conversations/create_fork.rb`
- Modify: `core_matrix/app/services/conversation_exports/build_conversation_payload.rb`
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Create: `core_matrix/test/services/conversations/interaction_lock_test.rb`
- Modify: `core_matrix/test/services/turns/start_agent_turn_test.rb`
- Modify: `core_matrix/test/services/subagent_connections/send_message_test.rb`
- Modify: `core_matrix/test/services/subagent_connections/spawn_test.rb`
- Modify: `core_matrix/test/services/subagent_connections/validate_addressability_test.rb`

**Step 1: Write failing behavior tests**

Cover:

- revoked conversation remains readable
- revoked conversation rejects new owner turns
- revoked conversation rejects follow-up queueing
- ordinary owner/UI mutability is no longer modeled by
  `owner_addressable/agent_addressable`
- agent-internal child conversations still preserve a distinct bounded entry
  surface after `addressability` removal

**Step 2: Implement the new model**

Replace or supersede `addressability` with:

- `interaction_lock_state`
  - `mutable`
  - `locked_agent_access_revoked`
  - `archived`
  - `deleted`

Introduce explicit entry-policy checks instead of overloading addressability.

Required replacement rule:

- ordinary root conversations should use mount/conversation entry policy to
  decide `main_transcript`, `sidecar_query`, `control`, `artifact_ingress`,
  `channel_ingress`, and `automation`
- child conversations that are currently `agent_addressable` must migrate to an
  explicit `agent_internal`-only policy shape instead of becoming owner- or
  channel-addressable by accident

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
- Modify: `core_matrix/app/controllers/app_api/agents/homes_controller.rb`
- Modify: `core_matrix/app/controllers/app_api/agents/workspaces_controller.rb`
- Modify: `core_matrix/app/controllers/app_api/conversations_controller.rb`
- Modify: `core_matrix/app/controllers/app_api/conversations/messages_controller.rb`
- Modify: existing workspace policy and launch controllers as needed
- Modify: `core_matrix/app/services/app_surface/queries/agent_home.rb`
- Modify: `core_matrix/app/services/app_surface/presenters/workspace_presenter.rb`
- Modify: `core_matrix/app/services/app_surface/presenters/agent_presenter.rb`
- Modify: `core_matrix/app/services/workspaces/resolve_default_reference.rb`
- Modify: `core_matrix/app/services/workspaces/create_default.rb`
- Modify: `core_matrix/app/services/workspaces/materialize_default.rb`
- Modify: `core_matrix/app/services/workbench/create_conversation_from_agent.rb`
- Modify: `core_matrix/app/services/workbench/send_message.rb`
- Create: `core_matrix/test/requests/app_api/workspaces/workspace_agents_controller_test.rb`
- Modify: `core_matrix/test/requests/app_api/agent_homes_test.rb`
- Modify: `core_matrix/test/requests/app_api/workspaces_test.rb`
- Modify: `core_matrix/test/requests/app_api/conversations_test.rb`
- Modify: `core_matrix/test/services/workbench/create_conversation_from_agent_test.rb`
- Modify: `core_matrix/test/services/workbench/send_message_test.rb`

**Step 1: Write failing request tests**

Cover:

- user can mount an agent into a workspace
- mount can choose a default execution runtime
- mount can be revoked/disabled
- revoked mount keeps workspace visible but prevents interactive launch
- the old `default_workspace_ref` / virtual-default-workspace contract is
  intentionally removed
- browser launch and follow-up message APIs resolve through `workspace_agent_id`
  instead of `agent_id` plus an implicit default workspace flow

**Step 2: Implement the new management surface**

AppAPI should manage:

- `Workspace`
- `WorkspaceAgent`
- revocation state
- runtime default
- capability/entry policy
- mounted interaction surfaces for:
  - main transcript
  - sidecar query
  - control
  - artifact ingress
  - channel ingress

Do not recreate `UserAgentBinding` under another name.

This task also intentionally removes the old agent-centric browser surface:

- retire or rewrite `/app_api/agents/:agent_id/home`
- retire or rewrite `/app_api/agents/:agent_id/workspaces`
- stop returning `default_workspace_ref`
- stop materializing a default workspace as a hidden side effect of conversation
  creation

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

### Task 7: Freeze The Ingress Rebase Contract On `WorkspaceAgent` And `IngressBinding`

**Files:**
- Modify: `core_matrix/docs/plans/2026-04-15-ingress-api-channel-ingress-design.md`
- Modify: `core_matrix/docs/plans/2026-04-15-ingress-api-telegram-channel-ingress-implementation.md`
- Modify: `core_matrix/docs/behavior/identifier-policy.md`

At checkpoint `b523b53b`, there is no landed `IngressAPI` / `IngressEndpoint`
code path to rename yet. This task is therefore a documentation-and-contract
freeze, not the phase-2 ingress implementation itself.

**Step 1: Rebase the ingress documents onto the new topology**

- replace any remaining legacy ingress resource names such as
  `IngressEndpoint` / `ChannelAccount`
- make phase 2 assume `WorkspaceAgent`, `IngressBinding`, and
  `ChannelConnector` from the start
- remove any remaining references that still talk about
  `Conversation.addressability` as the IM mutability boundary

**Step 2: Verify the documentation contract**

Use a focused text audit rather than app tests:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rg -n "IngressEndpoint|ChannelAccount|owner_addressable|agent_addressable" \
  docs/plans/2026-04-15-ingress-api-channel-ingress-design.md \
  docs/plans/2026-04-15-ingress-api-telegram-channel-ingress-implementation.md \
  docs/behavior/identifier-policy.md
```

Expected: no remaining legacy ingress-root terminology in those target docs.

**Step 3: Commit**

```bash
git add docs/plans app/models test
git commit -m "refactor: rebase ingress on workspace agents and ingress bindings"
```

### Task 8: Establish Sidecar, Command, And Artifact Contracts On The New Mount Model

**Files:**
- Modify: `core_matrix/app/models/workspace_agent.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/docs/behavior/conversation-supervision-and-control.md`
- Modify: `core_matrix/docs/plans/2026-04-15-ingress-api-channel-ingress-design.md`
- Modify: `core_matrix/docs/plans/2026-04-15-ingress-api-telegram-channel-ingress-implementation.md`
- Create: `core_matrix/test/services/conversations/interaction_lock_test.rb`
- Create: `core_matrix/test/services/conversation_supervision/btw_contract_test.rb`

**Step 1: Lock the mounted interaction surfaces in tests and docs**

Cover the intended mounted-agent policy shape:

- sidecar queries such as `/btw` and `/report` are not ordinary transcript turns
- control commands such as `/stop` remain bounded control requests
- artifact ingress is policy-gated separately from ordinary messaging
- revoked mounts keep conversations visible but deny mutable surfaces
- final artifact publication may happen in a later export/publish step instead
  of the same turn that produced the work
- shared channel conversations use sender-scoped follow-up rules: same sender
  may steer, cross-sender input queues instead of steering
- shared channel control commands are sender-scoped by default: a sender may
  stop its own in-flight work but not another sender's work

**Step 2: Define the policy and contract boundaries**

Make the new topology explicit in documentation and policy payloads:

- `WorkspaceAgent.entry_policy_payload` distinguishes:
  - `main_transcript`
  - `sidecar_query`
  - `control`
  - `artifact_ingress`
  - `channel_ingress`
  - `agent_internal`
  - `automation`
- conversation locking semantics block mutable surfaces while preserving
  historical visibility
- `/btw` is defined as a one-off sidecar question over the target conversation
  context and must not mutate the main transcript
- `/report` is defined as a supervision-backed status query
- `/regenerate` is defined as a capability-gated conversation action, not as a
  synthetic user turn
- command handling is factored through explicit parse/authorize/dispatch
  extension points instead of growing a monolithic ingress preprocessor
- deployable web outputs should prefer built artifacts such as `dist/` bundles
  over raw workspace directories as the primary published deliverable
- conversation attachments are the durable delivery boundary for later app/API
  retrieval, including acceptance-style verification flows
- sender identity remains part of dispatch semantics for shared channel
  conversations, so batching and follow-up decisions cannot treat all external
  participants as the same actor
- artifact ingress policy includes a configurable `max_bytes` limit with a
  default of 100 MB and rejects oversize files before attachment creation
- artifact ingress policy includes a configurable `max_count` limit with a
  default of 10 attachments per publish operation
- published attachments expose explicit publication roles so one attachment can
  be identified as the primary deliverable for acceptance and transport
  fallback decisions

**Step 3: Run the focused tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/interaction_lock_test.rb \
  test/services/conversation_supervision/btw_contract_test.rb
```

**Step 4: Commit**

```bash
git add app/models docs/behavior docs/plans test
git commit -m "design: lock mounted sidecar and artifact surfaces"
```

### Task 9: Run Full Verification And Inspect The Refactored Business Shapes

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
