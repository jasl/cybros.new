# Turn Lazy Bootstrap Implementation Plan

> Superseded by `docs/plans/2026-04-13-conversation-bootstrap-phase-two-implementation.md`.
> Keep this file as the narrower Phase B checkpoint only.

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move workflow substrate creation out of the synchronous API turn-entry
path so API requests only persist accepted-turn boundary truth and background
execution materializes workflow rows later.

**Phase Position:** This implementation plan is a follow-up to
`2026-04-13-conversation-bootstrap-slimming-design.md` and
`2026-04-13-conversation-bootstrap-slimming-implementation.md`. Phase 1 slims
conversation/root bootstrap; this phase assumes that direction and addresses
the remaining heavy turn-entry workflow bootstrap path.

**Architecture:** `Turn` becomes the durable acceptance boundary for new
execution requests. Synchronous API work creates `Conversation` / `Turn` /
`Message`, persists bootstrap intent and bootstrap state on `Turn`, projects a
minimal queued supervision state, and enqueues a bootstrap job keyed by
`turn.public_id`. That job idempotently materializes workflow substrate and
then hands off to the existing dispatch / execution chain.

**Tech Stack:** Ruby on Rails, Active Record, PostgreSQL, Active Job,
Minitest, `db/schema.rb`, behavior docs under `docs/behavior`.

---

### Task 1: Lock The Pending-Turn Contract Before Moving Workflow Creation

**Files:**
- Modify: `test/requests/app_api/conversations_test.rb`
- Modify: `test/requests/app_api/conversation_messages_test.rb`
- Modify: `test/services/workbench/create_conversation_from_agent_test.rb`
- Modify: `test/services/workbench/send_message_test.rb`
- Modify: `test/services/turns/start_user_turn_test.rb`
- Modify: `test/services/conversations/update_supervision_state_test.rb`
- Modify: `test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb`
- Modify: `test/services/conversation_supervision/publish_update_test.rb`
- Modify: `test/services/conversation_supervision/build_board_card_test.rb`
- Modify: `test/services/conversation_supervision/list_board_cards_test.rb`
- Modify: `test/requests/app_api/conversation_turn_feeds_controller_test.rb`
- Modify: `test/requests/app_api/conversation_turn_todo_plans_controller_test.rb`
- Create: `test/services/conversations/project_pending_turn_test.rb`
- Create: `test/jobs/turns/materialize_and_dispatch_job_test.rb`
- Create: `test/services/turns/materialize_bootstrap_test.rb`

**Step 1: Write failing request tests for the new API contract**

Change the request specs so they expect the end state after this refactor:

- `conversations#create` and `conversation_messages#create` still return `201`
- the response now exposes `execution_status = "pending"`
- the response exposes `accepted_at`
- the response may omit `workflow_run_id` during pending
- the request no longer needs `WorkflowRun.count +1` to succeed
- the request enqueues the new turn-bootstrap job, not
  `Workflows::ExecuteNodeJob`

Use both request files so first-turn and follow-up turn entry are covered.

**Step 2: Write failing service tests for turn-owned bootstrap truth**

Change workbench service tests so they expect:

- `Turn` persists bootstrap status on acceptance
- `Turn` persists bootstrap payload with selector/root-node intent
- `conversation.latest_active_workflow_run` is allowed to remain empty at the
  end of the synchronous call
- no `WorkflowRun` row is created synchronously
- workbench result objects no longer promise a synchronous `workflow_run`
  result unless you intentionally keep that field as `nil`

Also update `Turns::StartUserTurn` tests so they lock the new split contract:

- legacy callers still default to `bootstrap_state = "ready"` unless they opt
  into pending bootstrap attributes
- API entry callers can atomically create pending turns by passing the
  bootstrap attributes explicitly

**Step 3: Write failing tests for the pending projector**

Create `test/services/conversations/project_pending_turn_test.rb` and lock the
minimal queued projection:

- `overall_state = "queued"`
- `board_lane = "queued"`
- `current_owner_kind = "turn"`
- `current_owner_public_id = turn.public_id`
- `request_summary` uses the turn input content summary
- no workflow/task/subagent rows are required for projection
- the projector publishes the normal supervision update notification

Also update read-side projection tests so they expect pending preservation:

- `Conversations::UpdateSupervisionState` keeps `queued` when a pending or
  materializing bootstrap turn exists and no richer owner exists yet
- supervision snapshot / feed / todo-plan refreshes do not regress queued
  pending work back to `idle`
- board card / board list reads surface the queued pending owner as
  `current_owner_kind = "turn"`
- pending projection publishes the same supervision update notification shape
  used by richer projector updates

**Step 4: Write failing tests for bootstrap materialization**

Create job/service coverage that expects:

- a pending turn with no workflow materializes exactly one `WorkflowRun`
- the new job creates exactly one root `WorkflowNode`
- repeated job execution does not duplicate `WorkflowRun` or `WorkflowNode`
- bootstrap failure writes `turn.bootstrap_state = "failed"` and records
  `bootstrap_failure_payload`
- retry after failure can succeed and continue into the existing dispatch path

**Step 5: Run the targeted test set and verify failures**

Run from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/requests/app_api/conversations_test.rb \
  test/requests/app_api/conversation_messages_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/services/workbench/send_message_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/services/conversation_supervision/publish_update_test.rb \
  test/services/conversation_supervision/build_board_card_test.rb \
  test/services/conversation_supervision/list_board_cards_test.rb \
  test/requests/app_api/conversation_turn_feeds_controller_test.rb \
  test/requests/app_api/conversation_turn_todo_plans_controller_test.rb \
  test/services/conversations/project_pending_turn_test.rb \
  test/services/turns/materialize_bootstrap_test.rb \
  test/jobs/turns/materialize_and_dispatch_job_test.rb
```

Expected: failures showing the old workflow rows are still created
synchronously, the new pending response fields do not exist yet, and the
bootstrap job does not exist yet.

**Step 6: Commit**

```bash
git add \
  test/requests/app_api/conversations_test.rb \
  test/requests/app_api/conversation_messages_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/services/workbench/send_message_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/services/conversation_supervision/publish_update_test.rb \
  test/services/conversation_supervision/build_board_card_test.rb \
  test/services/conversation_supervision/list_board_cards_test.rb \
  test/requests/app_api/conversation_turn_feeds_controller_test.rb \
  test/requests/app_api/conversation_turn_todo_plans_controller_test.rb \
  test/services/conversations/project_pending_turn_test.rb \
  test/services/turns/materialize_bootstrap_test.rb \
  test/jobs/turns/materialize_and_dispatch_job_test.rb
git commit -m "test: lock turn lazy bootstrap contracts"
```

### Task 2: Rewrite Turn Schema For Bootstrap Truth

**Files:**
- Modify: `db/migrate/20260324090021_create_turns.rb`
- Modify: `db/schema.rb`

**Step 1: Add bootstrap state and payload columns to turns**

Rewrite `db/migrate/20260324090021_create_turns.rb` so `turns` directly gets:

- `bootstrap_state`, `null: false`
- `bootstrap_payload`, `jsonb`, default `{}`
- `bootstrap_failure_payload`, `jsonb`, default `{}`
- `bootstrap_requested_at`
- `bootstrap_started_at`
- `bootstrap_finished_at`

Use a safe default of `bootstrap_state = "ready"` for legacy turn-creation
paths that already materialize workflow substrate synchronously. Writer changes
in later tasks will set pending/materializing explicitly for user-turn API
entry.

**Step 2: Add schema-level constraints for bootstrap pairing**

Add check constraints so:

- `bootstrap_payload` is always a hash
- `bootstrap_failure_payload` is always a hash
- `bootstrap_started_at` / `bootstrap_finished_at` are present only when they
  make sense for the state

Do not over-constrain retry semantics in the schema.

**Step 3: Rebuild the database**

Run:

```bash
bin/rails db:drop && rm db/schema.rb && bin/rails db:create && bin/rails db:migrate && bin/rails db:reset
```

Expected:

- `turns` now exposes the bootstrap columns in `db/schema.rb`
- fresh rebuild succeeds without follow-up migrations

**Step 4: Commit**

```bash
git add db/migrate/20260324090021_create_turns.rb db/schema.rb
git commit -m "db: add turn bootstrap state"
```

### Task 3: Make Turn Entry Persist Pending Bootstrap Truth

**Files:**
- Modify: `app/models/turn.rb`
- Modify: `app/services/turns/start_user_turn.rb`
- Modify: `app/services/workbench/create_conversation_from_agent.rb`
- Modify: `app/services/workbench/send_message.rb`
- Modify: `app/controllers/app_api/conversations_controller.rb`
- Modify: `app/controllers/app_api/conversations/messages_controller.rb`
- Modify: `test/services/turns/start_user_turn_test.rb`

**Step 1: Add turn model helpers for bootstrap lifecycle**

In `app/models/turn.rb`:

- validate `bootstrap_state`
- validate bootstrap payload hashes
- add helpers such as:
  - `bootstrap_pending?`
  - `bootstrap_materializing?`
  - `bootstrap_ready?`
  - `bootstrap_failed?`

Do not overload `Turn.lifecycle_state`; keep bootstrap state separate.

**Step 2: Keep `StartUserTurn` generic while allowing API entry to create pending turns atomically**

Change `Turns::StartUserTurn` so it:

- still freezes execution identity
- still creates `Turn`
- still creates the input `UserMessage`
- still refreshes turn/message anchors
- does **not** resolve selector or create workflow substrate

Do **not** make every `StartUserTurn` caller globally default to pending. This
service is used far beyond the API entry path.

Instead, add an explicit way for API entry services to opt into pending
bootstrap attributes at creation time while legacy/internal callers keep the
default ready semantics.

The API-created turn should atomically persist:

- `bootstrap_state = "pending"`
- `bootstrap_requested_at = turn.created_at` (or equivalent acceptance time)
- empty `bootstrap_failure_payload`

`resolved_config_snapshot` and `resolved_model_selection_snapshot` should stay
valid hashes but no longer be treated as the complete workflow-bootstrap
result on this synchronous path.

**Step 3: Persist bootstrap payload from the workbench entry services**

In both `Workbench::CreateConversationFromAgent` and `Workbench::SendMessage`:

- remove the synchronous `Workflows::CreateForTurn.call`
- remove the synchronous `Workflows::ExecuteRun.call`
- write the durable bootstrap payload onto the created turn
- enqueue `Turns::MaterializeAndDispatchJob.perform_later(turn.public_id)`

Required payload fields include:

- selector source
- selector
- root node key/type
- decision source
- metadata

Keep the payload intentionally small and boundary-owned.

If the internal `Result` structs still expose `workflow_run`, either:

- remove that field under the destructive-refactor rule, or
- keep it present but explicitly `nil` during pending

Do not leave internal result objects pretending synchronous workflow substrate
still exists.

**Step 4: Change the API contract to return pending**

Update the controllers so the response explicitly returns:

- `execution_status: "pending"`
- `accepted_at`
- `request_summary`

Do not return fabricated workflow ids during pending.

Keep the response truthful rather than backward-shaped. Do not force
`ConversationPresenter` to imply workflow materialization if it does not need
to expose the new pending fields.

**Step 5: Run focused tests**

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/requests/app_api/conversations_test.rb \
  test/requests/app_api/conversation_messages_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/services/workbench/send_message_test.rb \
  test/services/turns/start_user_turn_test.rb
```

Acceptance:

- tests pass
- synchronous turn-entry no longer creates `WorkflowRun`
- API responses now expose `pending`

**Step 6: Commit**

```bash
git add \
  app/models/turn.rb \
  app/services/turns/start_user_turn.rb \
  app/services/workbench/create_conversation_from_agent.rb \
  app/services/workbench/send_message.rb \
  app/controllers/app_api/conversations_controller.rb \
  app/controllers/app_api/conversations/messages_controller.rb \
  test/services/turns/start_user_turn_test.rb \
  test/requests/app_api/conversations_test.rb \
  test/requests/app_api/conversation_messages_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/services/workbench/send_message_test.rb
git commit -m "refactor: make api turn entry return pending"
```

### Task 4: Add The Pending Projector

**Files:**
- Create: `app/services/conversations/project_pending_turn.rb`
- Modify: `app/services/workbench/create_conversation_from_agent.rb`
- Modify: `app/services/workbench/send_message.rb`
- Modify: `test/services/conversations/project_pending_turn_test.rb`
- Modify: `test/services/conversations/update_supervision_state_test.rb`
- Modify: `test/services/conversation_supervision/publish_update_test.rb`
- Modify: `test/services/conversation_supervision/build_board_card_test.rb`
- Modify: `test/services/conversation_supervision/list_board_cards_test.rb`

**Step 1: Implement a tiny queued-state projector**

Create `Conversations::ProjectPendingTurn` that:

- accepts `conversation:` and `turn:`
- upserts `ConversationSupervisionState`
- publishes the same supervision update event shape used by normal state
  updates, reusing `ConversationSupervision::PublishUpdate`
- writes only:
  - owner context
  - `overall_state = "queued"`
  - `board_lane = "queued"`
  - `current_owner_kind = "turn"`
  - `current_owner_public_id = turn.public_id`
  - `request_summary`
  - `last_progress_at`

Do not query `WorkflowRun`, `AgentTaskRun`, subagent state, feed state, or
runtime evidence.

**Step 2: Call the projector from synchronous API entry**

After turn creation and before enqueue, update both workbench entry services to
call `Conversations::ProjectPendingTurn`.

The synchronous API boundary should now create:

- `Conversation` / `Turn` / `Message`
- minimal pending supervision state
- queued bootstrap job

and nothing heavier.

**Step 3: Keep the rich projector separate**

Do not use `Conversations::UpdateSupervisionState` as the synchronous pending
projector.

That service must remain the richer runtime projector after workflow substrate
exists, but it **does** need a read-side pending-preservation branch so later
refreshes do not overwrite a pending turn back to `idle`.

The correct end state is:

- synchronous API path calls `Conversations::ProjectPendingTurn`
- `Conversations::UpdateSupervisionState` recognizes pending/materializing
  bootstrap turns only when no richer runtime owner exists yet
- once workflow/task/subagent state exists, normal richer precedence wins again

**Step 4: Run focused tests**

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/project_pending_turn_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/conversation_supervision/publish_update_test.rb \
  test/services/conversation_supervision/build_board_card_test.rb \
  test/services/conversation_supervision/list_board_cards_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/services/workbench/send_message_test.rb
```

Acceptance:

- pending projector tests pass
- synchronous entry still avoids workflow substrate
- UI-facing queued state exists immediately after the API mutation

**Step 5: Commit**

```bash
git add \
  app/services/conversations/project_pending_turn.rb \
  app/services/workbench/create_conversation_from_agent.rb \
  app/services/workbench/send_message.rb \
  test/services/conversations/project_pending_turn_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/conversation_supervision/publish_update_test.rb \
  test/services/conversation_supervision/build_board_card_test.rb \
  test/services/conversation_supervision/list_board_cards_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/services/workbench/send_message_test.rb
git commit -m "feat: project pending turns for queued ui state"
```

### Task 5: Add Idempotent Turn Bootstrap Materialization

**Files:**
- Create: `app/jobs/turns/materialize_and_dispatch_job.rb`
- Create: `app/services/turns/materialize_bootstrap.rb`
- Modify: `app/services/workflows/create_for_turn.rb`
- Modify: `app/services/workflows/execute_run.rb`
- Modify: `app/services/workflows/dispatch_runnable_nodes.rb`
- Modify: `app/services/conversations/update_supervision_state.rb`
- Modify: `test/jobs/turns/materialize_and_dispatch_job_test.rb`
- Modify: `test/services/turns/materialize_bootstrap_test.rb`
- Modify: `test/services/workflows/create_for_turn_test.rb`
- Modify: `test/services/conversations/update_supervision_state_test.rb`
- Modify: `test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb`
- Modify: `test/requests/app_api/conversation_turn_feeds_controller_test.rb`
- Modify: `test/requests/app_api/conversation_turn_todo_plans_controller_test.rb`

**Step 1: Extract turn-bootstrap materialization into a service**

Create `Turns::MaterializeBootstrap` that:

- loads a turn
- locks the turn
- returns immediately when:
  - turn is terminal/canceled
  - `turn.workflow_run` already exists and bootstrap is already complete
- moves `bootstrap_state: pending -> materializing`
- resolves selector from `turn.bootstrap_payload`
- builds execution snapshot
- creates `WorkflowRun`
- creates the root `WorkflowNode`
- creates initial `AgentTaskRun` / assignment when the payload requires it
- refreshes latest workflow anchor
- marks `bootstrap_state = ready`

Use `turn.workflow_run` and the unique `workflow_runs.turn_id` boundary as the
idempotency guard.

**Step 2: Add the background job**

Create `Turns::MaterializeAndDispatchJob` that:

- finds the turn by public id
- no-ops if the turn no longer exists or the turn lifecycle is already
  terminal/canceled
- calls `Turns::MaterializeBootstrap`
- continues into the existing dispatch path once workflow substrate exists

If materialization raises, write:

- `bootstrap_state = failed`
- `bootstrap_failure_payload`

and re-raise only when you want Active Job retry behavior. Keep the retry
policy explicit inside this job rather than relying on implicit queue behavior.
`bootstrap_state = failed` alone must remain explicitly retryable.

**Step 3: Narrow `Workflows::CreateForTurn` to substrate allocation**

Refactor `Workflows::CreateForTurn` so it can be reused by the new bootstrap
service without assuming it runs directly from the synchronous request.

If the cleanest shape is to split:

- “prepare selector/snapshot input”
- “allocate workflow substrate for this turn”

do that now. Keep the allocation logic reusable from the new turn-bootstrap
service.

**Step 4: Keep dispatch reusable after materialization**

Make sure the new bootstrap job can hand off to the existing dispatch flow
without duplicating scheduling logic.

If `Workflows::ExecuteRun` or `DispatchRunnableNodes` needs a narrower entry
point after lazy materialization, make that extraction here.

**Step 5: Add the read-side pending-preservation branch**

Update `Conversations::UpdateSupervisionState` so it preserves queued pending
turns when:

- a pending/materializing bootstrap turn exists
- no active/waiting/blocked workflow exists
- no active task or subagent owner exists

That branch must reuse the same minimal semantics as
`Conversations::ProjectPendingTurn`, but it should stay inside the richer
projector only for read-side correctness.

**Step 6: Run focused tests**

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/jobs/turns/materialize_and_dispatch_job_test.rb \
  test/services/turns/materialize_bootstrap_test.rb \
  test/services/workflows/create_for_turn_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/requests/app_api/conversation_turn_feeds_controller_test.rb \
  test/requests/app_api/conversation_turn_todo_plans_controller_test.rb
```

Acceptance:

- first bootstrap creates exactly one `WorkflowRun` and one root node
- repeated bootstrap does not duplicate substrate
- bootstrap failure is durable on `Turn`
- read-side pending refreshes remain queued until richer runtime state exists
- successful bootstrap still dispatches into the existing execution chain

**Step 7: Commit**

```bash
git add \
  app/jobs/turns/materialize_and_dispatch_job.rb \
  app/services/turns/materialize_bootstrap.rb \
  app/services/workflows/create_for_turn.rb \
  app/services/workflows/execute_run.rb \
  app/services/workflows/dispatch_runnable_nodes.rb \
  app/services/conversations/update_supervision_state.rb \
  test/jobs/turns/materialize_and_dispatch_job_test.rb \
  test/services/turns/materialize_bootstrap_test.rb \
  test/services/workflows/create_for_turn_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/requests/app_api/conversation_turn_feeds_controller_test.rb \
  test/requests/app_api/conversation_turn_todo_plans_controller_test.rb
git commit -m "feat: lazy materialize workflow substrate per turn"
```

### Task 6: Cover Failure Recovery, Retry, And Provider Handoff

**Files:**
- Modify: `test/services/agent_control/handle_execution_report_test.rb`
- Modify: `test/services/provider_execution/dispatch_request_test.rb`
- Modify: `test/jobs/workflows/execute_node_job_test.rb`
- Modify: `test/integration/provider_backed_turn_execution_test.rb`
- Modify: `test/integration/turn_entry_flow_test.rb`
- Modify: `test/services/subagent_connections/send_message_test.rb`
- Modify: `test/services/conversation_bundle_imports/rehydrate_conversation_test.rb`

**Step 1: Add regression coverage for the normal execution chain after bootstrap**

Lock the following behavior:

- once bootstrap is ready, `Workflows::ExecuteNodeJob` still receives a real
  `workflow_node.public_id`
- provider-backed turn execution still reaches the same success / wait / fail
  outcomes as before
- execution reports still reconcile against the same workflow/task rows once
  they exist

**Step 2: Add retry and duplicate-enqueue coverage**

Add tests that prove:

- enqueuing the bootstrap job twice does not duplicate workflow substrate
- retry after a failed bootstrap can later succeed
- subagent and import paths that depend on turn-owned execution identity still
  function when workflow substrate is delayed

**Step 3: Run the targeted regression set**

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/agent_control/handle_execution_report_test.rb \
  test/services/provider_execution/dispatch_request_test.rb \
  test/jobs/workflows/execute_node_job_test.rb \
  test/integration/provider_backed_turn_execution_test.rb \
  test/integration/turn_entry_flow_test.rb \
  test/services/subagent_connections/send_message_test.rb \
  test/services/conversation_bundle_imports/rehydrate_conversation_test.rb
```

Acceptance:

- bootstrap-lazy turns still execute through the existing provider/runtime
  pipeline
- duplicate enqueue remains safe
- downstream report handling semantics do not drift

**Step 4: Commit**

```bash
git add \
  test/services/agent_control/handle_execution_report_test.rb \
  test/services/provider_execution/dispatch_request_test.rb \
  test/jobs/workflows/execute_node_job_test.rb \
  test/integration/provider_backed_turn_execution_test.rb \
  test/integration/turn_entry_flow_test.rb \
  test/services/subagent_connections/send_message_test.rb \
  test/services/conversation_bundle_imports/rehydrate_conversation_test.rb
git commit -m "test: cover turn bootstrap retry and execution handoff"
```

### Task 7: Sync Behavior Docs And Record New Baselines

**Files:**
- Modify: `docs/behavior/turn-entry-and-selector-state.md`
- Modify: `docs/behavior/conversation-supervision-and-control.md`
- Modify: `docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- Modify: `docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `docs/plans/2026-04-13-turn-lazy-bootstrap-design.md`

**Step 1: Rewrite behavior docs for the new acceptance boundary**

Update behavior docs so they describe the landed state:

- API turn entry records accepted turns as `pending`
- workflow substrate is created later by a turn-bootstrap job
- pending-phase API responses may omit workflow-backed fields
- queued UI state during pending comes from the pending projector, not from
  pre-created workflow rows

**Step 2: Add final measured before/after values to the design doc**

Record:

- request-path SQL reduction for `conversations#create`
- request-path SQL reduction for `conversation_messages#create`
- final synchronous row deltas
- first-bootstrap async row deltas

Do not leave the design doc with only target numbers after implementation.

**Step 3: Run the full verification suite**

Run from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
bin/rails db:drop && rm db/schema.rb && bin/rails db:create && bin/rails db:migrate && bin/rails db:reset
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
  docs/behavior/turn-entry-and-selector-state.md \
  docs/behavior/conversation-supervision-and-control.md \
  docs/behavior/workflow-context-assembly-and-execution-snapshot.md \
  docs/behavior/workflow-scheduler-and-wait-states.md \
  docs/plans/2026-04-13-turn-lazy-bootstrap-design.md
git commit -m "docs: sync turn lazy bootstrap behavior"
```

## Execution Notes

- After each task, self-review the diff against this plan before committing.
- If implementation reveals a plan defect, fix the plan first, then continue.
- Keep the synchronous boundary limited to accepted-turn truth and the minimal
  queued projection; do not let workflow substrate creep back onto the API
  path.
- Every task must leave behind passing tests that prove the corresponding
  contract and weight reduction actually happened.
