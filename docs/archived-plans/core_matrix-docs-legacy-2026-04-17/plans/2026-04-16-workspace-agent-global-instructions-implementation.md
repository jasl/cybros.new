# Workspace-Agent Global Instructions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add mount-scoped `global_instructions` for `WorkspaceAgent`, project
those instructions into Fenix as explicit runtime context, freeze them once per
turn using the existing deduplicated `JsonDocument` pattern, and remove
Fenix's local workspace prompt-file loading.

**Architecture:** Keep prompt assembly authority in Fenix and keep durable
mount-scoped data in CoreMatrix. Extend `WorkspaceAgent` with
`global_instructions`, freeze the current value onto `ExecutionContract` through
a document ref, materialize `workspace_agent_context` from that frozen state for
direct and mailbox-reconstructed `prepare_round` payloads, and make Fenix
consume only `workspace_agent_context.global_instructions`. Do not implement
mount settings/schema/default publication in this round.

**Tech Stack:** Ruby on Rails, Active Record, PostgreSQL schema migrations,
Minitest, `JsonDocument`-backed deduplicated frozen payloads, existing
CoreMatrix provider-execution/mailbox pipeline, and existing Fenix prompt
assembly.

---

## Execution Rules

- Required execution skills: `@test-driven-development`, `@layered-rails`,
  `@verification-before-completion`.
- Do not preserve compatibility for `workspace_root`,
  `FENIX_WORKSPACE_ROOT`, `Dir.pwd`, or local `AGENTS.md` loading in Fenix.
- For CoreMatrix schema changes, do not add new additive migrations for this
  feature. Update the owning original migration files in place and then rebuild
  the database/schema using the repository-standard destructive flow from
  `AGENTS.md`.
- Do not add `global_instructions` to `Workspace.config` or workspace policy
  APIs.
- Do not add `WorkspaceAgent.settings`, settings schema/default publication, or
  mount settings app exposure in this round. Keep that as an explicit follow-up.
- Keep `agents/fenix/prompts/SOUL.md`, `USER.md`, and `WORKER.md` as code-owned
  prompt assets.
- Frozen turn state must reuse content-addressed `JsonDocument` rows instead of
  duplicating the same `global_instructions` string in multiple normalized rows.
- Because this touches an app-facing roundtrip and agent request payloads, the
  final milestone must run full `core_matrix` verification, the full acceptance
  suite including the 2048 capstone, and the full `agents/fenix` verification
  suite, and must include direct inspection of both capstone export artifacts
  and the resulting database state.

## Milestones

1. Lock the `global_instructions` contract in failing tests
2. Persist mount instructions and frozen document-ref storage in CoreMatrix
3. Expose `global_instructions` through the workspace-agent app surface
4. Project `workspace_agent_context` through CoreMatrix runtime and mailbox
   paths
5. Make Fenix consume `global_instructions` and delete filesystem workspace
   loading
6. Full verification and acceptance review

### Task 1: Lock The New Contract In Failing Tests

**Files:**
- Modify: `core_matrix/test/models/workspace_agent_test.rb`
- Modify: `core_matrix/test/requests/app_api/workspaces/workspace_agents_controller_test.rb`
- Modify: `core_matrix/test/requests/app_api/workspaces_test.rb`
- Modify: `core_matrix/test/services/app_surface/presenters/workspace_presenter_test.rb`
- Create: `core_matrix/test/services/app_surface/presenters/workspace_agent_presenter_test.rb`
- Create: `core_matrix/test/models/execution_contract_test.rb`
- Modify: `core_matrix/test/models/turn_execution_snapshot_test.rb`
- Modify: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Modify: `core_matrix/test/services/provider_execution/prepare_agent_round_test.rb`
- Modify: `core_matrix/test/services/agent_control/create_agent_request_test.rb`
- Modify: `core_matrix/test/services/agent_control/serialize_mailbox_item_test.rb`
- Modify: `agents/fenix/test/services/build_round_instructions_test.rb`
- Modify: `agents/fenix/test/services/shared/payload_context_test.rb`
- Modify: `agents/fenix/test/services/requests/prepare_round_test.rb`
- Modify: `agents/fenix/test/services/runtime/execute_mailbox_item_test.rb`
- Delete/Replace: `agents/fenix/test/services/prompts/workspace_instruction_loader_test.rb`

**Step 1: Write failing CoreMatrix app-surface tests for mount global instructions**

Cover:

- `WorkspaceAgent` normalizes blank `global_instructions`
- `POST /app_api/workspaces/:workspace_id/workspace_agents` accepts
  `global_instructions`
- `PATCH /app_api/workspaces/:workspace_id/workspace_agents/:workspace_agent_id`
  updates and clears `global_instructions`
- `WorkspaceAgentPresenter` emits `global_instructions`
- workspace list payloads fan out the same field
- payloads use public ids only

Example assertion shape:

```ruby
assert_equal "Always prefer concise Chinese responses.\n",
  response.parsed_body.dig("workspace_agent", "global_instructions")
```

**Step 2: Write failing frozen-runtime tests**

Assert that:

- `Workflows::BuildExecutionSnapshot` freezes the current mount instructions for
  the turn
- identical instruction content reuses one `JsonDocument`
- editing `WorkspaceAgent.global_instructions` after snapshot creation does not
  change the frozen payload for that turn
- direct `prepare_round` and queued/reconstructed mailbox payloads both include:

```ruby
assert_equal(
  {
    "workspace_agent_id" => context.fetch(:workspace_agent).public_id,
    "global_instructions" => "Always prefer concise Chinese responses.\n",
  },
  request_payload.fetch("workspace_agent_context")
)
```

Also assert `workspace_root` is absent from the payload.

**Step 3: Write failing Fenix tests for the new input shape**

Update Fenix tests to expect:

- `Shared::PayloadContext` preserves `workspace_agent_context`
- `BuildRoundInstructions` uses `workspace_agent_context.global_instructions`
- no test uses temporary `AGENTS.md` files or `workspace_root`

**Step 4: Run focused tests to confirm failure**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/models/workspace_agent_test.rb \
  test/requests/app_api/workspaces/workspace_agents_controller_test.rb \
  test/requests/app_api/workspaces_test.rb \
  test/services/app_surface/presenters/workspace_presenter_test.rb \
  test/services/app_surface/presenters/workspace_agent_presenter_test.rb \
  test/models/execution_contract_test.rb \
  test/models/turn_execution_snapshot_test.rb \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/provider_execution/prepare_agent_round_test.rb \
  test/services/agent_control/create_agent_request_test.rb \
  test/services/agent_control/serialize_mailbox_item_test.rb

cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/build_round_instructions_test.rb \
  test/services/shared/payload_context_test.rb \
  test/services/requests/prepare_round_test.rb \
  test/services/runtime/execute_mailbox_item_test.rb
```

Expected: failures referencing missing `global_instructions`,
`workspace_agent_context`, missing frozen document refs, and lingering
`workspace_root` / `AGENTS.md` assumptions.

**Step 5: Commit**

```bash
git add core_matrix/test/models/workspace_agent_test.rb \
  core_matrix/test/requests/app_api/workspaces/workspace_agents_controller_test.rb \
  core_matrix/test/requests/app_api/workspaces_test.rb \
  core_matrix/test/services/app_surface/presenters/workspace_presenter_test.rb \
  core_matrix/test/services/app_surface/presenters/workspace_agent_presenter_test.rb \
  core_matrix/test/models/execution_contract_test.rb \
  core_matrix/test/models/turn_execution_snapshot_test.rb \
  core_matrix/test/services/workflows/build_execution_snapshot_test.rb \
  core_matrix/test/services/provider_execution/prepare_agent_round_test.rb \
  core_matrix/test/services/agent_control/create_agent_request_test.rb \
  core_matrix/test/services/agent_control/serialize_mailbox_item_test.rb \
  agents/fenix/test/services/build_round_instructions_test.rb \
  agents/fenix/test/services/shared/payload_context_test.rb \
  agents/fenix/test/services/requests/prepare_round_test.rb \
  agents/fenix/test/services/runtime/execute_mailbox_item_test.rb
git commit -m "test: lock workspace agent global instructions contract"
```

### Task 2: Persist Mount Instructions And Frozen Document-Ref Storage In CoreMatrix

**Files:**
- Modify: `core_matrix/db/migrate/20260415110000_create_workspace_agents.rb`
- Modify: `core_matrix/db/migrate/20260326113000_add_agent_control_contract.rb`
- Modify: `core_matrix/db/schema.rb`
- Modify: `core_matrix/app/models/workspace_agent.rb`
- Modify: `core_matrix/app/models/execution_contract.rb`
- Modify: `core_matrix/test/models/workspace_agent_test.rb`
- Create: `core_matrix/test/models/execution_contract_test.rb`
- Modify: `core_matrix/test/test_helper.rb`

**Step 1: Add `WorkspaceAgent` persistence field**

Update the original `CreateWorkspaceAgents` migration to include:

- `global_instructions :text`

**Step 2: Add frozen document ref to `ExecutionContract`**

Update the original `AddAgentControlContract` migration so `execution_contracts`
includes a nullable reference:

- `workspace_agent_global_instructions_document`

pointing to `JsonDocument`.

**Step 3: Implement model normalization and validation**

In `WorkspaceAgent`:

- normalize blank `global_instructions` to `nil`
- validate `global_instructions` is a string when present

In `ExecutionContract`:

- add the `belongs_to` association
- add a reader for the frozen `global_instructions` payload
- validate installation consistency for the new document ref

The frozen document payload format must be:

```ruby
{ "global_instructions" => "..." }
```

**Step 4: Rebuild schema state using the destructive AGENTS flow**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rails db:drop
rm db/schema.rb
rails db:create
rails db:migrate
rails db:reset
bin/rails db:test:prepare
```

**Step 5: Run focused tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/models/workspace_agent_test.rb \
  test/models/execution_contract_test.rb
```

Expected: schema/model failures resolved, but app-surface/runtime path tests
still failing.

**Step 6: Commit**

```bash
git add core_matrix/db/schema.rb \
  core_matrix/db/migrate/20260415110000_create_workspace_agents.rb \
  core_matrix/db/migrate/20260326113000_add_agent_control_contract.rb \
  core_matrix/app/models/workspace_agent.rb \
  core_matrix/app/models/execution_contract.rb \
  core_matrix/test/models/workspace_agent_test.rb \
  core_matrix/test/models/execution_contract_test.rb \
  core_matrix/test/test_helper.rb
git commit -m "feat: persist workspace agent global instructions"
```

### Task 3: Expose `global_instructions` Through The Workspace-Agent App Surface

**Files:**
- Modify: `core_matrix/app/controllers/app_api/workspaces/workspace_agents_controller.rb`
- Modify: `core_matrix/app/services/app_surface/presenters/workspace_agent_presenter.rb`
- Modify: `core_matrix/app/services/app_surface/presenters/workspace_presenter.rb`
- Modify: `core_matrix/test/requests/app_api/workspaces/workspace_agents_controller_test.rb`
- Create: `core_matrix/test/services/app_surface/presenters/workspace_agent_presenter_test.rb`
- Modify: `core_matrix/test/requests/app_api/workspaces_test.rb`
- Modify: `core_matrix/test/services/app_surface/presenters/workspace_presenter_test.rb`

**Step 1: Extend create/update parameter handling**

Accept `global_instructions` on create and update.

Rules:

- absent field preserves the stored value on update
- blank string clears the value

**Step 2: Extend presenter output**

Return:

```ruby
"global_instructions" => @workspace_agent.global_instructions,
```

alongside the existing mount fields.

Because the field lives directly on `workspace_agents`, this round should not
need new association preloads for the workspace list path.

**Step 3: Run focused app-surface tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/requests/app_api/workspaces/workspace_agents_controller_test.rb \
  test/services/app_surface/presenters/workspace_agent_presenter_test.rb \
  test/requests/app_api/workspaces_test.rb \
  test/services/app_surface/presenters/workspace_presenter_test.rb
```

Expected: PASS.

**Step 4: Commit**

```bash
git add core_matrix/app/controllers/app_api/workspaces/workspace_agents_controller.rb \
  core_matrix/app/services/app_surface/presenters/workspace_agent_presenter.rb \
  core_matrix/app/services/app_surface/presenters/workspace_presenter.rb \
  core_matrix/test/requests/app_api/workspaces/workspace_agents_controller_test.rb \
  core_matrix/test/services/app_surface/presenters/workspace_agent_presenter_test.rb \
  core_matrix/test/requests/app_api/workspaces_test.rb \
  core_matrix/test/services/app_surface/presenters/workspace_presenter_test.rb
git commit -m "feat: expose workspace agent global instructions"
```

### Task 4: Project `workspace_agent_context` Through CoreMatrix Runtime Paths

**Files:**
- Modify: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `core_matrix/app/models/turn_execution_snapshot.rb`
- Modify: `core_matrix/app/services/provider_execution/prepare_agent_round.rb`
- Modify: `core_matrix/app/services/agent_control/create_agent_request.rb`
- Modify: `core_matrix/app/models/agent_control_mailbox_item.rb`
- Modify: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Modify: `core_matrix/test/models/turn_execution_snapshot_test.rb`
- Modify: `core_matrix/test/services/provider_execution/prepare_agent_round_test.rb`
- Modify: `core_matrix/test/services/agent_control/create_agent_request_test.rb`
- Modify: `core_matrix/test/services/agent_control/serialize_mailbox_item_test.rb`
- Modify: `shared/fixtures/contracts/core_matrix_fenix_prepare_round_mailbox_item.json`
- Modify: `agents/fenix/test/services/requests/prepare_round_test.rb`
- Modify: `agents/fenix/test/services/runtime/execute_mailbox_item_test.rb`

**Step 1: Freeze current mount instructions once per turn**

Update `Workflows::BuildExecutionSnapshot` so it reads the current
`WorkspaceAgent.global_instructions` and stores it on the turn's
`ExecutionContract` via:

```ruby
JsonDocuments::Store.call(
  installation: turn.installation,
  document_kind: "workspace_agent_global_instructions",
  payload: { "global_instructions" => workspace_agent.global_instructions }
)
```

If the mount has no instructions, clear the document ref.

**Step 2: Add `workspace_agent_context` to `TurnExecutionSnapshot`**

Expose:

```ruby
{
  "workspace_agent_id" => turn.conversation.workspace_agent.public_id,
  "global_instructions" => execution_contract.workspace_agent_global_instructions,
}
```

while omitting the `global_instructions` key when the frozen value is blank.

**Step 3: Add `workspace_agent_context` to direct `prepare_round` payload construction**

Make `PrepareAgentRound` read the already-shaped value from the execution
snapshot rather than rebuilding it ad hoc.

**Step 4: Preserve the same context through mailbox compaction/reconstruction**

Update:

- `AgentControl::CreateAgentRequest`
- `AgentControlMailboxItem#reconstructed_agent_request_payload`
- `AgentControl::SerializeMailboxItem` expectations

so queued/reconstructed payloads reuse the same frozen snapshot-backed context.
Do not store a second inline copy of `global_instructions` inside compacted
payload documents when the `ExecutionContract` already holds the frozen
document ref.

**Step 5: Update shared contract fixtures and both sides' tests**

Make the fixture and Fenix-side request/execute tests expect
`workspace_agent_context`, and assert `workspace_root` is gone.

**Step 6: Run focused contract tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/models/turn_execution_snapshot_test.rb \
  test/services/provider_execution/prepare_agent_round_test.rb \
  test/services/agent_control/create_agent_request_test.rb \
  test/services/agent_control/serialize_mailbox_item_test.rb

cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/requests/prepare_round_test.rb \
  test/services/runtime/execute_mailbox_item_test.rb
```

Expected: PASS.

**Step 7: Commit**

```bash
git add core_matrix/app/services/workflows/build_execution_snapshot.rb \
  core_matrix/app/models/turn_execution_snapshot.rb \
  core_matrix/app/services/provider_execution/prepare_agent_round.rb \
  core_matrix/app/services/agent_control/create_agent_request.rb \
  core_matrix/app/models/agent_control_mailbox_item.rb \
  core_matrix/test/services/workflows/build_execution_snapshot_test.rb \
  core_matrix/test/models/turn_execution_snapshot_test.rb \
  core_matrix/test/services/provider_execution/prepare_agent_round_test.rb \
  core_matrix/test/services/agent_control/create_agent_request_test.rb \
  core_matrix/test/services/agent_control/serialize_mailbox_item_test.rb \
  shared/fixtures/contracts/core_matrix_fenix_prepare_round_mailbox_item.json \
  agents/fenix/test/services/requests/prepare_round_test.rb \
  agents/fenix/test/services/runtime/execute_mailbox_item_test.rb
git commit -m "feat: carry workspace agent context in prepare round"
```

### Task 5: Make Fenix Consume `global_instructions` And Delete Filesystem Workspace Loading

**Files:**
- Modify: `agents/fenix/app/services/shared/payload_context.rb`
- Modify: `agents/fenix/app/services/build_round_instructions.rb`
- Modify: `agents/fenix/app/services/prompts/assembler.rb`
- Delete: `agents/fenix/app/services/prompts/workspace_instruction_loader.rb`
- Modify: `agents/fenix/test/services/shared/payload_context_test.rb`
- Modify: `agents/fenix/test/services/build_round_instructions_test.rb`
- Modify: `agents/fenix/test/services/requests/prepare_round_test.rb`
- Modify: `agents/fenix/test/services/runtime/execute_mailbox_item_test.rb`
- Delete/Replace: `agents/fenix/test/services/prompts/workspace_instruction_loader_test.rb`

**Step 1: Remove `workspace_root` fallback logic**

Delete:

- payload fallback to env/current directory
- `workspace_root` normalization
- `AGENTS.md` loader object

**Step 2: Consume only `workspace_agent_context.global_instructions`**

Pass that value into `Prompts::Assembler` and render it as a dedicated
`Global Instructions` section with a stable fallback string when absent.

**Step 3: Update tests**

Rewrite tests so they build pure payloads and never touch temp directories or
repo-local instruction files.

**Step 4: Run focused Fenix tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/shared/payload_context_test.rb \
  test/services/build_round_instructions_test.rb \
  test/services/requests/prepare_round_test.rb \
  test/services/runtime/execute_mailbox_item_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add agents/fenix/app/services/shared/payload_context.rb \
  agents/fenix/app/services/build_round_instructions.rb \
  agents/fenix/app/services/prompts/assembler.rb \
  agents/fenix/test/services/shared/payload_context_test.rb \
  agents/fenix/test/services/build_round_instructions_test.rb \
  agents/fenix/test/services/requests/prepare_round_test.rb \
  agents/fenix/test/services/runtime/execute_mailbox_item_test.rb
git rm agents/fenix/app/services/prompts/workspace_instruction_loader.rb \
  agents/fenix/test/services/prompts/workspace_instruction_loader_test.rb
git commit -m "feat: use workspace agent global instructions in fenix"
```

### Task 6: Run Full Verification And Acceptance

**Files:**
- No new product files
- Review artifacts under the normal test and acceptance output locations

**Step 1: Run full Fenix verification**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare
bin/rails test
```

**Step 2: Run full CoreMatrix verification**

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

**Step 3: Run acceptance**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

**Step 4: Inspect artifacts and database state**

Confirm:

- workspaces and workspace agents still use only public ids at app-facing
  boundaries
- `global_instructions` is stored on the targeted `WorkspaceAgent`
- the turn's frozen instructions are stored through a deduplicated
  `JsonDocument` ref on `ExecutionContract`
- repeated identical instructions reuse one `JsonDocument`
- `prepare_round` payloads sent during acceptance contain
  `workspace_agent_context.global_instructions`
- no code path still relies on repo-local `AGENTS.md`
- the exported 2048 capstone result is correct and complete for the scenario
- the resulting database rows and JSON payloads have the intended post-refactor
  shape

**Step 5: Commit**

```bash
git add core_matrix/db/schema.rb \
  core_matrix/db/migrate/20260415110000_create_workspace_agents.rb \
  core_matrix/db/migrate/20260326113000_add_agent_control_contract.rb \
  core_matrix/app/models/workspace_agent.rb \
  core_matrix/app/models/execution_contract.rb \
  core_matrix/app/controllers/app_api/workspaces/workspace_agents_controller.rb \
  core_matrix/app/services/app_surface/presenters/workspace_agent_presenter.rb \
  core_matrix/app/services/app_surface/presenters/workspace_presenter.rb \
  core_matrix/app/services/workflows/build_execution_snapshot.rb \
  core_matrix/app/models/turn_execution_snapshot.rb \
  core_matrix/app/services/provider_execution/prepare_agent_round.rb \
  core_matrix/app/services/agent_control/create_agent_request.rb \
  core_matrix/app/models/agent_control_mailbox_item.rb \
  core_matrix/test/test_helper.rb \
  core_matrix/test/models/workspace_agent_test.rb \
  core_matrix/test/models/execution_contract_test.rb \
  core_matrix/test/requests/app_api/workspaces/workspace_agents_controller_test.rb \
  core_matrix/test/requests/app_api/workspaces_test.rb \
  core_matrix/test/services/app_surface/presenters/workspace_presenter_test.rb \
  core_matrix/test/services/app_surface/presenters/workspace_agent_presenter_test.rb \
  core_matrix/test/services/workflows/build_execution_snapshot_test.rb \
  core_matrix/test/models/turn_execution_snapshot_test.rb \
  core_matrix/test/services/provider_execution/prepare_agent_round_test.rb \
  core_matrix/test/services/agent_control/create_agent_request_test.rb \
  core_matrix/test/services/agent_control/serialize_mailbox_item_test.rb \
  agents/fenix/app/services/shared/payload_context.rb \
  agents/fenix/app/services/build_round_instructions.rb \
  agents/fenix/app/services/prompts/assembler.rb \
  agents/fenix/test/services/shared/payload_context_test.rb \
  agents/fenix/test/services/build_round_instructions_test.rb \
  agents/fenix/test/services/requests/prepare_round_test.rb \
  agents/fenix/test/services/runtime/execute_mailbox_item_test.rb \
  shared/fixtures/contracts/core_matrix_fenix_prepare_round_mailbox_item.json
git rm agents/fenix/app/services/prompts/workspace_instruction_loader.rb \
  agents/fenix/test/services/prompts/workspace_instruction_loader_test.rb
git commit -m "feat: add workspace agent global instructions"
```

## Deferred Follow-Up: Mount Settings Schema And Defaults

This plan intentionally defers the following to a separate task:

- `WorkspaceAgent.settings`
- `AgentDefinitionVersion.workspace_agent_settings_schema_document`
- `AgentDefinitionVersion.default_workspace_agent_settings_document`
- registration/capability contract exposure for those settings docs
- read-only app payload exposure for settings schema/defaults

When that follow-up is resumed, keep the same conventions:

- mutable per-mount values live on `WorkspaceAgent`
- versioned agent-owned schema/default contracts live on
  `AgentDefinitionVersion`
- prompt assembly authority remains in Fenix
