# Agent And Execution Runtime Visibility Reset Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace `global/personal` with `public/private`, add symmetric visibility ownership to `ExecutionRuntime`, and make workspace/conversation usability respect the new resource visibility model.

**Architecture:** Rewrite the schema first, then rebuild model invariants and query semantics around `public/private + provisioning_origin`. After that, update binding/bootstrap/app-facing access paths and finish by rewriting docs, helpers, and tests against the reset schema. General API/UI authorization remains outside this plan; only domain invariants plus app-facing resource usability checks land here.

**Tech Stack:** Ruby on Rails, Active Record, PostgreSQL, Minitest

---

### Task 1: Rewrite The Schema Contract

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/*`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb`

**Step 1: Write the failing schema/model tests**

- Add or rewrite tests that expect:
  - `Agent.visibility` only allows `public/private`
  - `Agent.provisioning_origin` exists
  - `ExecutionRuntime.visibility`, `owner_user_id`, and `provisioning_origin` exist

**Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/agent_test.rb test/models/execution_runtime_test.rb
```

**Step 3: Rewrite migrations destructively**

- Replace old `agents.visibility` semantics with `public/private`
- Add `agents.provisioning_origin`
- Add `execution_runtimes.visibility`
- Add `execution_runtimes.owner_user_id`
- Add `execution_runtimes.provisioning_origin`
- Add indexes that support visibility/user lookups

**Step 4: Reset the database and regenerate schema**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

**Step 5: Re-run the schema/model tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/agent_test.rb test/models/execution_runtime_test.rb
```

Expected at this task boundary:

- unknown-attribute and missing-column failures are gone
- remaining failures may still point at model invariants until Task 2 lands

**Step 6: Commit**

```bash
git add core_matrix/db/migrate core_matrix/db/schema.rb core_matrix/test/models/agent_test.rb core_matrix/test/models/execution_runtime_test.rb
git commit -m "refactor: reset agent and runtime visibility schema"
```

### Task 2: Rebuild Agent And Runtime Model Invariants

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/execution_runtime.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/user.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/agent_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/execution_runtime_test.rb`

**Step 1: Write the failing tests**

- Cover valid combinations:
  - system/public/ownerless
  - user_created/public/owned
  - user_created/private/owned
- Cover invalid combinations:
  - private/ownerless
  - system/private
  - user_created/public/ownerless
  - cross-installation owner

**Step 2: Run tests to verify they fail**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/agent_test.rb test/models/execution_runtime_test.rb
```

**Step 3: Implement the minimal model changes**

- Replace old enum semantics
- Avoid bare `public/private` enum helper collisions
- Add validation methods for the new invariants
- Add `owned_execution_runtimes` to `User` if needed for symmetry

**Step 4: Re-run tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/agent_test.rb test/models/execution_runtime_test.rb
```

**Step 5: Commit**

```bash
git add core_matrix/app/models/agent.rb core_matrix/app/models/execution_runtime.rb core_matrix/app/models/user.rb core_matrix/test/models/agent_test.rb core_matrix/test/models/execution_runtime_test.rb
git commit -m "refactor: enforce visibility ownership invariants"
```

### Task 3: Rewrite Visibility Queries

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/queries/agents/visible_to_user_query.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/queries/execution_runtimes/visible_to_user_query.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/queries/agents/visible_to_user_query_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/queries/execution_runtimes/visible_to_user_query_test.rb`

**Step 1: Write failing query tests**

- `public` resources are visible installation-wide
- `private` resources are visible only to the owner
- retired resources stay hidden

**Step 2: Run tests to verify they fail**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/queries/agents/visible_to_user_query_test.rb test/queries/execution_runtimes/visible_to_user_query_test.rb
```

**Step 3: Implement query rewrites**

- Remove `global/personal`
- Add symmetric runtime query

**Step 4: Re-run tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/queries/agents/visible_to_user_query_test.rb test/queries/execution_runtimes/visible_to_user_query_test.rb
```

**Step 5: Commit**

```bash
git add core_matrix/app/queries/agents/visible_to_user_query.rb core_matrix/app/queries/execution_runtimes/visible_to_user_query.rb core_matrix/test/queries/agents/visible_to_user_query_test.rb core_matrix/test/queries/execution_runtimes/visible_to_user_query_test.rb
git commit -m "refactor: rewrite agent and runtime visibility queries"
```

### Task 4: Rebuild Binding And Bootstrap Semantics

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/user_agent_binding.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/user_agent_bindings/enable.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/user_agent_bindings/enable_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/bundled_default_agent_bootstrap_flow_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/user_agent_binding_test.rb`

**Step 1: Write the failing tests**

- `public` agent can be enabled by any installation user
- `private` agent can only be enabled by owner
- bundled bootstrap produces `system/public/ownerless` agent and runtime

**Step 2: Run tests to verify they fail**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/user_agent_bindings/enable_test.rb test/services/installations/register_bundled_agent_runtime_test.rb test/integration/bundled_default_agent_bootstrap_flow_test.rb test/models/user_agent_binding_test.rb
```

**Step 3: Implement minimal code**

- Replace personal/global ownership checks
- Make bundled defaults explicit
- Keep service-layer checks limited to usability/business correctness

**Step 4: Re-run tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/user_agent_bindings/enable_test.rb test/services/installations/register_bundled_agent_runtime_test.rb test/integration/bundled_default_agent_bootstrap_flow_test.rb test/models/user_agent_binding_test.rb
```

**Step 5: Commit**

```bash
git add core_matrix/app/models/user_agent_binding.rb core_matrix/app/services/user_agent_bindings/enable.rb core_matrix/app/services/installations/register_bundled_agent_runtime.rb core_matrix/test/services/user_agent_bindings/enable_test.rb core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb core_matrix/test/integration/bundled_default_agent_bootstrap_flow_test.rb core_matrix/test/models/user_agent_binding_test.rb
git commit -m "refactor: align bindings and bootstrap with visibility reset"
```

### Task 5: Make App-Facing Workspace And Conversation Usability Follow Resource Visibility

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/queries/workspaces/for_user_query.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/base_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/conversation_supervision/authority.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_control/authorize_request.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/conversation_supervision_sessions_controller.rb`
- Modify or create: supporting visibility/usability service objects under `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/`
- Test: workspace, supervision, and conversation access tests

**Step 1: Write the failing tests**

- non-owner loses access to old workspace/conversation after bound public agent becomes private
- owner retains access
- publication-based read-only conversation sharing still works independently

**Step 2: Run tests to verify they fail**

Run the targeted tests that cover workspace lists, transcript/supervision entry,
and conversation control.

**Step 3: Implement a single usability policy**

- create a reusable check for:
  - agent usable by user
  - execution runtime usable by user
  - workspace accessible by user
  - conversation accessible by user
- route app-facing entry points through that policy

**Step 4: Re-run targeted tests**

Re-run the same targeted test set until green.

**Step 5: Commit**

```bash
git add core_matrix/app/queries/workspaces/for_user_query.rb core_matrix/app/controllers/app_api/base_controller.rb core_matrix/app/services/embedded_agents/conversation_supervision/authority.rb core_matrix/app/services/conversation_control/authorize_request.rb core_matrix/app/controllers/app_api/conversation_supervision_sessions_controller.rb core_matrix/test
git commit -m "refactor: gate workspace and conversation access by visibility"
```

### Task 6: Sweep Helpers, Seeds, Docs, And Residual Naming

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/test_helper.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/docs/README.md`
- Modify: behavior docs under `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/`
- Modify: plan indexes if needed

**Step 1: Write or update contract tests**

- helper defaults produce valid `public/system` bundled resources
- no active helper still assumes `global/personal`

**Step 2: Run tests to verify failures**

Run the helper/contract tests that cover factory defaults and bootstrap.

**Step 3: Update helpers and docs**

- replace `global/personal`
- document `public/private + provisioning_origin`
- document that API/UI authorization will later use `Pundit`

**Step 4: Re-run targeted tests**

Re-run the helper/contract tests until green.

**Step 5: Commit**

```bash
git add core_matrix/test/test_helper.rb core_matrix/docs docs/README.md
git commit -m "docs: describe visibility reset semantics"
```

### Task 7: Run Full Verification

**Files:**
- No new files; verification only

**Step 1: Prepare test database**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
```

**Step 2: Run project verification**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails test
bin/rails test:system
```

**Step 3: Run active acceptance if any touched paths require it**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/run_active_suite.sh
```

**Step 4: Commit**

```bash
git add -A
git commit -m "test: verify visibility reset"
```

### Task 8: Final Sweep

**Files:**
- Whole repo sweep

**Step 1: Confirm old semantics are gone**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n \"visibility: \\\"global\\\"|visibility: \\\"personal\\\"|\\.global\\?|\\.personal\\?|CASE visibility WHEN 'global'|must be blank for global|personal agent\" core_matrix
```

Expected: no hits in active code or tests.

**Step 2: Confirm new semantics are documented**

Check:

- `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-11-agent-runtime-visibility-design.md`
- `/Users/jasl/Workspaces/Ruby/cybros/docs/README.md`
- touched behavior docs

**Step 3: Commit**

```bash
git add docs/plans/2026-04-11-agent-runtime-visibility-design.md docs/plans/2026-04-11-agent-runtime-visibility-implementation.md
git commit -m "docs: add visibility reset design and plan"
```
