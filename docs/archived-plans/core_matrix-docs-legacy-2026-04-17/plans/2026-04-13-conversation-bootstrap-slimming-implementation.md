# Conversation Bootstrap Slimming Implementation Plan

> Superseded by `docs/plans/2026-04-13-conversation-bootstrap-phase-two-implementation.md`.
> Keep this file as the narrower Phase A checkpoint only.

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove conversation bootstrap work that is currently preallocated but
not required for a bare `Conversation` to exist: collapse
`ConversationCapabilityPolicy` into `Conversation`, then make lineage substrate
lazy and conversation-owned.

**Architecture:** `Conversation` becomes the single durable holder of
conversation-level supervision/control authority booleans, while lineage
queries tolerate missing references and lineage writes become the only place
that materialize `LineageStore`, root snapshot, and live reference. The
long-term lineage owner concept shifts from `root_conversation` to
`owner_conversation`.

**Tech Stack:** Ruby on Rails, Active Record, PostgreSQL, Minitest,
`db/schema.rb`, behavior docs under `docs/behavior`.

---

### Task 1: Lock The New Contracts And Baseline Measurements

**Files:**
- Create: `test/services/conversations/create_root_weight_test.rb`
- Create: `test/services/conversations/child_lineage_bootstrap_weight_test.rb`
- Modify: `test/services/conversations/create_root_test.rb`
- Modify: `test/services/conversations/create_automation_root_test.rb`
- Modify: `test/services/conversations/create_branch_test.rb`
- Modify: `test/services/conversations/create_checkpoint_test.rb`
- Modify: `test/services/conversations/create_fork_test.rb`
- Modify: `test/services/app_surface/policies/conversation_supervision_access_test.rb`
- Modify: `test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb`
- Modify: `test/services/conversation_control/authorize_request_test.rb`
- Modify: `test/services/conversations/update_supervision_state_test.rb`
- Modify: `test/services/lineage_stores/bootstrap_for_conversation_test.rb`
- Modify: `test/services/lineage_stores/set_test.rb`
- Modify: `test/services/lineage_stores/delete_key_test.rb`
- Modify: `test/services/lineage_stores/compact_snapshot_test.rb`
- Modify: `test/services/lineage_stores/garbage_collect_test.rb`
- Modify: `test/queries/lineage_stores/get_query_test.rb`
- Modify: `test/queries/lineage_stores/list_keys_query_test.rb`
- Modify: `test/queries/lineage_stores/multi_get_query_test.rb`
- Modify: `test/requests/app_api/workspace_policies_test.rb`
- Modify: `test/models/conversation_supervision_snapshot_test.rb`
- Modify: `test/services/conversations/purge_deleted_test.rb`
- Modify: `test/services/conversations/purge_plan_test.rb`
- Modify: `test/test_helper.rb`

**Step 1: Write failing tests for capability-policy collapse**

Change the conversation creation and supervision tests so they expect the end
state after this refactor:

- a new conversation stores supervision authority directly on the
  `Conversation` row
- a new conversation no longer creates a `ConversationCapabilityPolicy` row
- `ConversationSupervisionAccess` reads the booleans from `conversation`
  instead of a joined policy row
- `ConversationControl::AuthorizeRequest` and
  `EmbeddedAgents::ConversationSupervision::Authority` expose a plain
  authority snapshot, not a `ConversationCapabilityPolicy` record
- supervision snapshots still keep `capability_policy_snapshot`, but no longer
  record `conversation_capability_policy_public_id`

Use `test/requests/app_api/workspace_policies_test.rb` to preserve the current
business rule:

- workspace policy updates still affect future conversations
- the projected authority on the new conversation still matches the workspace
  policy at creation time

**Step 2: Write failing tests for lazy lineage bootstrap**

Update root and child conversation tests so they expect:

- `Conversations::CreateRoot` creates no `lineage_store_reference`
- `CreateAutomationRoot` also creates no lineage substrate
- `CreateFork`, `CreateBranch`, and `CreateCheckpoint` copy a lineage
  reference only when the parent already has one
- when the parent has no lineage reference, the child stays reference-free

Update lineage query tests so they expect:

- `GetQuery.call(reference_owner: conversation, key: ...)` returns `nil` when
  no reference exists
- `ListKeysQuery` returns an empty page when no reference exists
- `MultiGetQuery` returns an empty hash when no reference exists

Update lineage write tests so they expect:

- the first `LineageStores::Set` on a conversation with no reference creates:
  - one `LineageStore`
  - one root `LineageStoreSnapshot`
  - one `LineageStoreReference`
- repeated identical writes stay idempotent after bootstrap

**Step 3: Add failing weight tests**

In `test/services/conversations/create_root_weight_test.rb`, add two
assertions that intentionally fail on the current code:

- `Conversations::CreateRoot` must use `<= 13` SQL after the capability-policy
  collapse
- `Conversations::CreateRoot` must later use `<= 8` SQL and create no lineage
  rows after the lineage pass

Split those assertions into two named tests so the intermediate target and the
final target remain visible.

In `test/services/conversations/child_lineage_bootstrap_weight_test.rb`, add
coverage that:

- child creation with a parent that has no lineage reference creates no child
  `LineageStoreReference`
- child creation with a parent that already has lineage state still creates
  exactly one child reference

**Step 4: Run the targeted test set and verify failures**

Run from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_automation_root_test.rb \
  test/services/conversations/create_branch_test.rb \
  test/services/conversations/create_checkpoint_test.rb \
  test/services/conversations/create_fork_test.rb \
  test/services/conversations/create_root_weight_test.rb \
  test/services/conversations/child_lineage_bootstrap_weight_test.rb \
  test/services/app_surface/policies/conversation_supervision_access_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/services/conversation_control/authorize_request_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/lineage_stores/bootstrap_for_conversation_test.rb \
  test/services/lineage_stores/set_test.rb \
  test/services/lineage_stores/delete_key_test.rb \
  test/services/lineage_stores/compact_snapshot_test.rb \
  test/services/lineage_stores/garbage_collect_test.rb \
  test/queries/lineage_stores/get_query_test.rb \
  test/queries/lineage_stores/list_keys_query_test.rb \
  test/queries/lineage_stores/multi_get_query_test.rb \
  test/requests/app_api/workspace_policies_test.rb \
  test/models/conversation_supervision_snapshot_test.rb \
  test/services/conversations/purge_deleted_test.rb \
  test/services/conversations/purge_plan_test.rb
```

Expected: failures showing the current policy row still exists, root bootstrap
still creates lineage substrate, and the new weight budgets are not yet met.

**Step 5: Commit**

```bash
git add \
  test/services/conversations/create_root_weight_test.rb \
  test/services/conversations/child_lineage_bootstrap_weight_test.rb \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_automation_root_test.rb \
  test/services/conversations/create_branch_test.rb \
  test/services/conversations/create_checkpoint_test.rb \
  test/services/conversations/create_fork_test.rb \
  test/services/app_surface/policies/conversation_supervision_access_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/services/conversation_control/authorize_request_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/lineage_stores/bootstrap_for_conversation_test.rb \
  test/services/lineage_stores/set_test.rb \
  test/services/lineage_stores/delete_key_test.rb \
  test/services/lineage_stores/compact_snapshot_test.rb \
  test/services/lineage_stores/garbage_collect_test.rb \
  test/queries/lineage_stores/get_query_test.rb \
  test/queries/lineage_stores/list_keys_query_test.rb \
  test/queries/lineage_stores/multi_get_query_test.rb \
  test/requests/app_api/workspace_policies_test.rb \
  test/models/conversation_supervision_snapshot_test.rb \
  test/services/conversations/purge_deleted_test.rb \
  test/services/conversations/purge_plan_test.rb \
  test/test_helper.rb
git commit -m "test: lock conversation bootstrap slimming contracts"
```

### Task 2: Rewrite Schema For Capability-Authority Collapse

**Files:**
- Modify: `db/migrate/20260324090019_create_conversations.rb`
- Modify: `db/migrate/20260404090100_create_conversation_observation_frames.rb`
- Modify: `db/migrate/20260405092950_create_conversation_capability_policies.rb`
- Modify: `db/schema.rb`

**Step 1: Move authority booleans onto `conversations`**

Rewrite `db/migrate/20260324090019_create_conversations.rb` so
`conversations` directly gets:

- `supervision_enabled`
- `detailed_progress_enabled`
- `side_chat_enabled`
- `control_enabled`

Use `null: false` booleans with safe defaults. Do not add a new durable
payload column here.

**Step 2: Remove policy-row references from supervision snapshots**

Rewrite `db/migrate/20260404090100_create_conversation_observation_frames.rb`
so `conversation_supervision_snapshots` no longer includes:

- `conversation_capability_policy_public_id`

Keep `capability_policy_snapshot` only on
`conversation_supervision_sessions`; snapshots can continue to freeze the
resolved authority inside `bundle_payload["capability_authority"]`.

**Step 3: Remove the policy table**

Rewrite `db/migrate/20260405092950_create_conversation_capability_policies.rb`
into a no-op migration with a comment explaining that the table was removed
before launch and its fields were folded into `conversations`.

Do not leave the table behind as dead schema.

**Step 4: Rebuild the database**

Run from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

Expected:

- schema rebuilds cleanly
- `conversation_capability_policies` disappears from `db/schema.rb`
- `conversations` now owns the four authority booleans
- `conversation_supervision_snapshots` no longer has
  `conversation_capability_policy_public_id`

**Step 5: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "db: inline conversation capability authority"
```

### Task 3: Collapse Capability Authority Into `Conversation` And Remove The Dead Paths

**Files:**
- Delete: `app/models/conversation_capability_policy.rb`
- Modify: `app/models/conversation.rb`
- Modify: `app/services/conversations/creation_support.rb`
- Modify: `app/services/workspace_policies/capabilities.rb`
- Modify: `app/services/app_surface/policies/conversation_supervision_access.rb`
- Modify: `app/services/embedded_agents/conversation_supervision/authority.rb`
- Modify: `app/services/embedded_agents/conversation_supervision/build_snapshot.rb`
- Modify: `app/services/conversations/update_supervision_state.rb`
- Modify: `app/services/conversation_control/authorize_request.rb`
- Modify: `app/controllers/app_api/conversations/supervision/base_controller.rb`
- Modify: `app/services/conversations/purge_plan.rb`
- Modify: `test/support/conversation_supervision_fixture_builder.rb`
- Modify: `test/models/data_lifecycle_test.rb`
- Modify: `test/services/embedded_agents/conversation_supervision/create_session_test.rb`
- Modify: `test/requests/app_api/conversation_supervision_sessions_test.rb`
- Delete: `test/models/conversation_capability_policy_test.rb`

**Step 1: Make `Conversation` the authority owner**

In `app/models/conversation.rb`:

- remove `has_one :conversation_capability_policy`
- add any small normalization needed so the four booleans stay internally
  coherent:
  - no side chat without supervision
  - no control without side chat
  - no detailed progress without supervision

Add a small `capability_authority_snapshot` helper that returns a plain hash
containing the four booleans.

**Step 2: Project workspace authority directly into `Conversation`**

In `Conversations::CreationSupport#create_root_conversation!`, stop creating a
policy row. Instead, merge the projected booleans straight into the
`Conversation.create!` call.

`WorkspacePolicies::Capabilities.projection_attributes_for(workspace:)` can be
kept, but it should now return only the authority booleans needed by
`Conversation`, not a durable row payload for a deleted table.

**Step 3: Rewrite supervision and control readers**

Update these readers to stop expecting an AR policy row:

- `AppSurface::Policies::ConversationSupervisionAccess`
- `EmbeddedAgents::ConversationSupervision::Authority`
- `Conversations::UpdateSupervisionState`
- `ConversationControl::AuthorizeRequest`

Preferred end state:

- `ConversationSupervisionAccess` reads the four booleans directly from
  `conversation`
- `Authority` exposes `capability_snapshot`, not `policy`
- `AuthorizeRequest::Result` stores `capability_snapshot`, not `policy`

Under the destructive-refactor rule, rename fields and helper methods rather
than preserving the old “policy row” vocabulary.

**Step 4: Rewrite supervision snapshot/debug payloads**

In `EmbeddedAgents::ConversationSupervision::BuildSnapshot`:

- remove the `conversation_capability_policy_public_id` write
- remove debug payload fields that only exist to point back to the deleted row
- keep frozen authority booleans in `bundle_payload["capability_authority"]`

In `app/controllers/app_api/conversations/supervision/base_controller.rb`,
remove the eager load for `:conversation_capability_policy`.

**Step 5: Remove dead purge and lifecycle references**

In `Conversations::PurgePlan` and related retention tests:

- stop deleting `ConversationCapabilityPolicy` rows
- remove the table from remaining-owned-row checks
- remove data lifecycle expectations tied to the deleted model

**Step 6: Run focused tests and measure the first reduction**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_root_weight_test.rb \
  test/services/app_surface/policies/conversation_supervision_access_test.rb \
  test/services/embedded_agents/conversation_supervision/create_session_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/services/conversation_control/authorize_request_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/requests/app_api/conversation_supervision_sessions_test.rb \
  test/requests/app_api/workspace_policies_test.rb \
  test/models/conversation_supervision_snapshot_test.rb \
  test/models/data_lifecycle_test.rb
```

Acceptance:

- all tests pass
- `Conversations::CreateRoot` now uses `<= 13` SQL
- no capability-policy row or public-id reference remains in live code

**Step 7: Commit**

```bash
git add app/models/conversation.rb \
  app/services/conversations/creation_support.rb \
  app/services/workspace_policies/capabilities.rb \
  app/services/app_surface/policies/conversation_supervision_access.rb \
  app/services/embedded_agents/conversation_supervision/authority.rb \
  app/services/embedded_agents/conversation_supervision/build_snapshot.rb \
  app/services/conversations/update_supervision_state.rb \
  app/services/conversation_control/authorize_request.rb \
  app/controllers/app_api/conversations/supervision/base_controller.rb \
  app/services/conversations/purge_plan.rb \
  test/support/conversation_supervision_fixture_builder.rb \
  test/models/data_lifecycle_test.rb \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_root_weight_test.rb \
  test/services/app_surface/policies/conversation_supervision_access_test.rb \
  test/services/embedded_agents/conversation_supervision/create_session_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/services/conversation_control/authorize_request_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/requests/app_api/conversation_supervision_sessions_test.rb \
  test/requests/app_api/workspace_policies_test.rb \
  test/models/conversation_supervision_snapshot_test.rb
git rm app/models/conversation_capability_policy.rb test/models/conversation_capability_policy_test.rb
git commit -m "refactor: inline conversation capability authority"
```

### Task 4: Rewrite Lineage Schema From Root-Owned To Conversation-Owned

**Files:**
- Modify: `db/migrate/20260324090042_create_lineage_stores.rb`
- Modify: `db/schema.rb`

**Step 1: Rename lineage ownership**

Rewrite `db/migrate/20260324090042_create_lineage_stores.rb` so
`lineage_stores` uses:

- `owner_conversation_id`

instead of:

- `root_conversation_id`

Update indexes and foreign keys accordingly.

**Step 2: Keep `LineageStoreReference` optional at creation time**

Do not add any schema constraint that implies every conversation must have a
live `LineageStoreReference`.

**Step 3: Rebuild the database**

Run:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

Expected:

- `lineage_stores.owner_conversation_id` exists
- `root_conversation_id` is gone from fresh schema
- no schema path assumes every conversation must have a live reference

**Step 4: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "db: rename lineage ownership to conversation owner"
```

### Task 5: Make Lineage Bootstrap Lazy For Roots And Empty Children

**Files:**
- Modify: `app/models/conversation.rb`
- Modify: `app/models/lineage_store.rb`
- Modify: `app/models/lineage_store_snapshot.rb`
- Modify: `app/models/conversation_blocker_snapshot.rb`
- Modify: `app/services/conversations/creation_support.rb`
- Modify: `app/services/lineage_stores/bootstrap_for_conversation.rb`
- Modify: `app/services/lineage_stores/write_support.rb`
- Modify: `app/services/lineage_stores/set.rb`
- Modify: `app/services/lineage_stores/delete_key.rb`
- Modify: `app/services/lineage_stores/compact_snapshot.rb`
- Modify: `app/queries/lineage_stores/query_support.rb`
- Modify: `app/queries/lineage_stores/get_query.rb`
- Modify: `app/queries/lineage_stores/list_keys_query.rb`
- Modify: `app/queries/lineage_stores/multi_get_query.rb`
- Modify: `app/resolvers/conversation_variables/visible_values_resolver.rb`
- Modify: `app/queries/conversations/blocker_snapshot_query.rb`
- Modify: `app/services/conversations/finalize_deletion.rb`
- Modify: `app/services/conversations/purge_deleted.rb`
- Modify: `app/services/conversations/purge_plan.rb`
- Modify: `app/services/lineage_stores/garbage_collect.rb`
- Modify: `test/test_helper.rb`
- Modify: `test/models/lineage_store_test.rb`
- Modify: `test/models/lineage_store_snapshot_test.rb`
- Modify: `test/models/lineage_store_reference_test.rb`
- Modify: `test/queries/lineage_stores/get_query_test.rb`
- Modify: `test/queries/lineage_stores/list_keys_query_test.rb`
- Modify: `test/queries/lineage_stores/multi_get_query_test.rb`
- Modify: `test/resolvers/conversation_variables/visible_values_resolver_test.rb`
- Modify: `test/services/conversations/reconcile_close_operation_test.rb`

**Step 1: Remove eager root bootstrap**

In `Conversations::CreationSupport#create_root_conversation!`, delete the call
to `LineageStores::BootstrapForConversation.call`.

Bare root conversations should now create:

- the conversation
- the self closure
- no lineage store
- no lineage snapshot
- no lineage reference

**Step 2: Make child lineage copying conditional**

In `initialize_child_conversation!` and `create_lineage_store_reference_for!`:

- if `parent.lineage_store_reference` exists, copy the child reference
- if it does not exist, do nothing

Do not raise on a missing parent reference anymore.

**Step 3: Rework lineage bootstrap as write-time initialization**

Repurpose `LineageStores::BootstrapForConversation` or replace it with a new
internal helper so the write-support layer can do:

1. return the current reference when it exists
2. otherwise create:
   - a `LineageStore` owned by `@conversation`
   - a root snapshot
   - a live reference
3. continue the write against that reference

`LineageStores::Set`, `DeleteKey`, and `CompactSnapshot` should all flow
through that same bootstrap boundary.

**Step 4: Make query support nil-safe**

Update query support so missing references are empty-state, not exceptional:

- `GetQuery` returns `nil`
- `ListKeysQuery` returns an empty page
- `MultiGetQuery` returns `{}`
- `ConversationVariables::VisibleValuesResolver` still merges workspace values
  correctly without forcing bootstrap

**Step 5: Rename blocker and owner semantics everywhere**

Rename:

- `Conversation#root_lineage_store` -> `owned_lineage_store`
- `root_lineage_store_blocker` -> `owned_lineage_store_blocker`
- `LineageStore#root_conversation` -> `owner_conversation`

Update:

- `ConversationBlockerSnapshot`
- `Conversations::BlockerSnapshotQuery`
- `Conversations::PurgeDeleted`
- `LineageStores::GarbageCollect`
- close-operation summary payload expectations

**Step 6: Run focused tests and measure the second reduction**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_automation_root_test.rb \
  test/services/conversations/create_branch_test.rb \
  test/services/conversations/create_checkpoint_test.rb \
  test/services/conversations/create_fork_test.rb \
  test/services/conversations/create_root_weight_test.rb \
  test/services/conversations/child_lineage_bootstrap_weight_test.rb \
  test/services/lineage_stores/bootstrap_for_conversation_test.rb \
  test/services/lineage_stores/set_test.rb \
  test/services/lineage_stores/delete_key_test.rb \
  test/services/lineage_stores/compact_snapshot_test.rb \
  test/services/lineage_stores/garbage_collect_test.rb \
  test/queries/lineage_stores/get_query_test.rb \
  test/queries/lineage_stores/list_keys_query_test.rb \
  test/queries/lineage_stores/multi_get_query_test.rb \
  test/resolvers/conversation_variables/visible_values_resolver_test.rb \
  test/services/conversations/finalize_deletion_test.rb \
  test/services/conversations/purge_deleted_test.rb \
  test/services/conversations/purge_plan_test.rb \
  test/models/conversation_blocker_snapshot_test.rb
```

Acceptance:

- all tests pass
- bare `CreateRoot` uses `<= 8` SQL
- bare `CreateRoot` creates no lineage rows
- child creation against a parent with no lineage state creates no lineage
  reference row
- first conversation-local lineage write bootstraps substrate exactly once

**Step 7: Commit**

```bash
git add app/models/conversation.rb \
  app/models/lineage_store.rb \
  app/models/lineage_store_snapshot.rb \
  app/models/conversation_blocker_snapshot.rb \
  app/services/conversations/creation_support.rb \
  app/services/lineage_stores/bootstrap_for_conversation.rb \
  app/services/lineage_stores/write_support.rb \
  app/services/lineage_stores/set.rb \
  app/services/lineage_stores/delete_key.rb \
  app/services/lineage_stores/compact_snapshot.rb \
  app/queries/lineage_stores/query_support.rb \
  app/queries/lineage_stores/get_query.rb \
  app/queries/lineage_stores/list_keys_query.rb \
  app/queries/lineage_stores/multi_get_query.rb \
  app/resolvers/conversation_variables/visible_values_resolver.rb \
  app/queries/conversations/blocker_snapshot_query.rb \
  app/services/conversations/finalize_deletion.rb \
  app/services/conversations/purge_deleted.rb \
  app/services/conversations/purge_plan.rb \
  app/services/lineage_stores/garbage_collect.rb \
  test/test_helper.rb \
  test/models/lineage_store_test.rb \
  test/models/lineage_store_snapshot_test.rb \
  test/models/lineage_store_reference_test.rb \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_automation_root_test.rb \
  test/services/conversations/create_branch_test.rb \
  test/services/conversations/create_checkpoint_test.rb \
  test/services/conversations/create_fork_test.rb \
  test/services/conversations/create_root_weight_test.rb \
  test/services/conversations/child_lineage_bootstrap_weight_test.rb \
  test/services/lineage_stores/bootstrap_for_conversation_test.rb \
  test/services/lineage_stores/set_test.rb \
  test/services/lineage_stores/delete_key_test.rb \
  test/services/lineage_stores/compact_snapshot_test.rb \
  test/services/lineage_stores/garbage_collect_test.rb \
  test/queries/lineage_stores/get_query_test.rb \
  test/queries/lineage_stores/list_keys_query_test.rb \
  test/queries/lineage_stores/multi_get_query_test.rb \
  test/resolvers/conversation_variables/visible_values_resolver_test.rb \
  test/services/conversations/finalize_deletion_test.rb \
  test/services/conversations/purge_deleted_test.rb \
  test/services/conversations/purge_plan_test.rb \
  test/services/conversations/reconcile_close_operation_test.rb \
  test/models/conversation_blocker_snapshot_test.rb
git commit -m "refactor: make lineage bootstrap lazy"
```

### Task 6: Sync Behavior Docs And Produce The Final Weight Report

**Files:**
- Modify: `docs/behavior/conversation-structure-and-lineage.md`
- Modify: `docs/behavior/conversation-supervision-and-control.md`
- Modify: `docs/behavior/canonical-variable-history-and-promotion.md`
- Modify: `docs/behavior/agent-runtime-resource-apis.md`
- Modify: `docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `docs/plans/2026-04-13-conversation-bootstrap-slimming-design.md`

**Step 1: Rewrite behavior docs**

Update the behavior docs so they describe the landed state:

- conversation capability authority lives on `Conversation`
- supervision snapshots keep frozen authority hashes, not policy-row ids
- bare roots create no lineage substrate
- child conversations only inherit lineage references when the parent has one
- lineage ownership and purge blockers use `owned_lineage_store` language

**Step 2: Add the final measured reductions to the design doc**

Update the design doc with the actual measured landed values:

- final `CreateRoot` SQL count
- final bare-root row delta
- final child-create no-lineage row delta
- first-write lineage bootstrap row delta

Do not leave the design doc with only target numbers once the implementation
is complete.

**Step 3: Run the full verification suite**

Run from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare
PARALLEL_WORKERS=1 bin/rails test
bin/rails test:system
```

If this task lands as part of a larger branch-close pass, run the branch-level
acceptance suite and capstones after the normal `core_matrix` verification
completes. This plan's mandatory local boundary is the full project suite
above; broader acceptance remains required before the branch is considered
finished.

**Step 4: Commit**

```bash
git add \
  docs/behavior/conversation-structure-and-lineage.md \
  docs/behavior/conversation-supervision-and-control.md \
  docs/behavior/canonical-variable-history-and-promotion.md \
  docs/behavior/agent-runtime-resource-apis.md \
  docs/behavior/workflow-scheduler-and-wait-states.md \
  docs/plans/2026-04-13-conversation-bootstrap-slimming-design.md
git commit -m "docs: sync conversation bootstrap slimming behavior"
```

## Execution Notes

- After each task, self-review the diff against this plan before committing.
- If implementation reveals a plan defect, fix the plan first, then continue.
- Do not preserve compatibility shims for the deleted policy table or the old
  `root_lineage_store` naming.
- Every task must leave behind passing tests that prove the corresponding
  reduction actually happened.
