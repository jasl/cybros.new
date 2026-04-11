# Supervisor Observability And Control Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace observation-only progress reporting with a first-class supervision substrate that gives durable, human-meaningful visibility into agent and subagent work, powers natural-language sidechat and lightweight activity feeds, and opens a clean path to limited supervisor control.

**Architecture:** Promote supervision to a first-class runtime concern. Persist canonical conversation-level supervision state outside the sidechat session, add normalized progress facts plus structured plan/progress rows on `AgentTaskRun` and `SubagentConnection`, generate a short-lived current-or-previous-turn activity feed from explicit semantic changes, and make sidechat a renderer over frozen supervision snapshots instead of a translator over internal workflow tokens. Put capability enablement and authority in a higher conversation-capability layer, then let future control reuse and extend the mailbox-first `AgentControl` substrate behind a conversation-scoped external control plane with auditable control requests and narrow request kinds.

**Tech Stack:** Rails 8.2, Active Record/Postgres, JSONB/public-id boundaries, Minitest, ActionDispatch request tests, root acceptance harness under `/Users/jasl/Workspaces/Ruby/cybros/acceptance`

---

## Destructive Assumptions

- This plan intentionally does **not** preserve compatibility with the current
  `ConversationObservation*` schema or service namespace.
- Formal domain naming changes to **ConversationSupervision**. `observation`
  remains only as a historical migration term, not as the primary product or
  code name.
- Edit baseline migrations in place where that yields a cleaner schema.
- After schema edits, reset the local database from
  `/Users/jasl/Workspaces/Ruby/cybros/core_matrix` with:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

- `ConversationEvent.live_projection` remains useful for proof and diagnostics,
  but it is no longer the primary user-facing progress substrate.
- `side chat` remains an **interface** over supervision, not the source of
  truth.
- Do not keep compatibility aliases as primary paths. Controllers, routes,
  service namespaces, tests, docs, and acceptance artifacts should be revised
  to the new supervision naming in one pass.

## Repository Scan Findings

The codebase scan surfaced a few implementation-critical facts that should
shape execution order:

- `ConversationObservation` is not a thin wrapper. It spans schema, embedded
  agent services, app API controllers, request tests, manual acceptance
  helpers, acceptance artifacts, purge logic, lifecycle classification, and
  behavior docs. Treat this as a domain replacement, not a wording pass.
- The most likely hidden blockers for an otherwise-correct implementation are
  the manual acceptance harness and capstone scenario:
  - `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/manual_support.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/manual_support_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/fresh_start_stack_contract_test.rb`
- Purge and lifecycle ownership are also first-order work, not cleanup:
  - `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/purge_plan.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/purge_plan_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/purge_deleted_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/data_lifecycle_test.rb`
- Existing control backends are stable substrate and should be reused rather
  than replaced:
  - `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/request_turn_interrupt.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/request_close.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/manual_resume.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/step_retry.rb`
- Internal main-agent to subagent delegation is a protected behavior seam.
  `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/subagent_connections/send_message.rb`
  and
  `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/execute_core_matrix_tool.rb`
  must remain behavior-preserving even if they start sharing lower-level
  helpers with `ConversationControl`.
- The old observation builders are not worth porting forward. Delete and
  replace them; do not preserve them under new names:
  - `build_assessment`
  - `build_supervisor_status`
  - `build_human_sidechat`
  - `build_bundle_snapshot`
- The practical blast radius appears contained to `core_matrix` plus the root
  `acceptance` harness. No additional `agents/fenix` product-code refactor was
  found to be required beyond keeping the existing runtime/acceptance scripts
  working.

## Phase Order

1. **Phase 1 / P0 Foundation:** introduce the canonical supervision domain and
   schema.
2. **Phase 2 / P0 Runtime Facts:** make agent and subagent runtime resources
   emit normalized progress state.
3. **Phase 3 / P1 Read Model:** build the conversation-level supervision
   projection that acceptance and sidechat can read directly.
4. **Phase 3.5 / P1 Board And Feed Readiness:** add stable board lanes,
   short-lived activity feed seams, and update signaling without building a
   dashboard yet.
5. **Phase 4 / P1 Sidechat:** rebuild natural-language supervision replies on
   top of frozen supervision snapshots.
6. **Phase 5 / P2 Control:** add a narrowly scoped, auditable external
   conversation-control plane.
7. **Phase 5.5 / P2 Intentful Control UX:** let side chat map high-confidence
   natural-language control intents onto bounded control verbs.
8. **Phase 6 / P1 Hardening:** tighten acceptance, exports, compaction, and
   operator-facing hooks.

No sidechat wording work should land before Phases 1 through 3 exist, or the
system will regress to guessing from internal workflow details again.

## Execution Cadence

Execute this plan as a strict sequence of small, reviewable slices:

1. write the focused failing tests for the current task
2. implement only the code needed for that task
3. run the task-local verification command until it passes
4. make one task-scoped commit
5. only then begin the next task

Do not batch multiple tasks into one unverified working set.

Use these broader checkpoints between blocks:

- **Checkpoint A:** after Task 4B, rebuild the database once and run the
  focused supervision-state, purge, and lifecycle suites before starting
  sidechat work.
- **Checkpoint B:** after Task 5A and Task 7, run `bin/rails test` from
  `/Users/jasl/Workspaces/Ruby/cybros/core_matrix` before moving on to final
  acceptance hardening.
- **Checkpoint C:** after Task 8, run the full verification sequence,
  including the 2048 capstone acceptance and the provider-backed control
  matrix when enabled.

If any checkpoint fails, fix that block before proceeding. Do not stack later
tasks on top of a failing intermediate state.

## Target End State

By the end of this plan, `Core Matrix` should have:

- one canonical `ConversationSupervisionState` per conversation
- normalized progress facts on `AgentTaskRun` and `SubagentConnection`
- structured task/plan items and semantic progress entries
- stable board-lane metadata and board-card projection seams
- a short-lived supervision activity feed for the current turn, or the
  previous turn when no newer turn has started yet
- frozen supervision snapshots for sidechat exchanges
- a conversation capability layer that can explicitly enable supervision and
  optionally enable control for a target conversation
- human-readable sidechat answers built from supervision state
- a conversation-scoped external control plane that can refresh status, stop
  or close work safely, send narrow guidance, and request safe intervention on
  subagents or blocked workflows
- a side-chat control-intent layer that can turn high-confidence natural
  language requests such as "stop" into bounded control verbs when control is
  enabled and authorized
- preserved main-agent-to-subagent management behavior, treated as a special
  internal caller over the new control substrate rather than a deprecated path
- acceptance tests that fail if human-visible supervision text leaks internal
  runtime vocabulary

### Naming Contract And Side Chat Baseline

Use the following naming split consistently:

- **Domain name:** `ConversationSupervision`
- **Human interaction surface:** `side chat`
- **Machine surface:** `machine_status` or `supervision_status`
- **Historical term only:** `observation`

This naming is intentional:

- `ConversationSupervision` is the durable conversation-scoped capability
- `side chat` is the natural-language interface over that capability
- `observation` is too narrow because the surface now includes visibility plus
  future limited control

The side-chat capability baseline must cover and exceed the `/btw` model from
the Claude reference:

- it can answer from the current conversation's full semantic context
- it can answer from canonical supervision state
- it does not interrupt the mainline agent loop
- it does not mutate the mainline state unless the user explicitly triggers a
  control request
- it can discuss conversation facts, assistant commitments, completed work,
  active work, blockers, subagent status, and evidence-backed next steps
- it does not expose internal runtime structure in human-visible prose

That makes side chat:

- **conversation-aware**, like `/btw`
- **supervision-aware**, unlike `/btw`
- **control-capable by explicit action only**, unlike an unrestricted operator
  shell

### Canonical Conversation Supervision State

The conversation-level read model should be explicit, durable, and cheap to
read:

```ruby
{
  "overall_state" => "idle|queued|running|waiting|blocked|completed|failed|interrupted|canceled",
  "last_terminal_state" => "completed|failed|interrupted|canceled|nil",
  "last_terminal_at" => "...iso8601...",
  "current_owner" => {
    "kind" => "agent_task_run|subagent_connection|workflow_run",
    "id" => "...public_id..."
  },
  "request_summary" => "...",
  "current_focus_summary" => "...",
  "recent_progress_summary" => "...",
  "waiting_summary" => "...",
  "blocked_summary" => "...",
  "next_step_hint" => "...",
  "last_progress_at" => "...iso8601...",
  "board_lane" => "idle|queued|active|waiting|blocked|handoff|done|failed",
  "board_badges" => [...],
  "active_plan_items" => [...],
  "active_subagents" => [...]
}
```

`overall_state` answers what the conversation is doing now. `last_terminal_state`
and `last_terminal_at` answer how the previous work segment ended.

When there is no active turn, no running workflow or task, no active subagent
work, and no waiting or blocked state, the projector should emit `idle`. A
conversation that just finished or failed should normally project as:

- `overall_state = idle`
- `last_terminal_state = completed|failed`

That state is the source of truth for supervisor reads. Sidechat snapshots
freeze it; they do not reconstruct it from raw workflow tokens.

### Runtime Progress Contract

Agent-controlled work should publish normalized supervision updates:

```json
{
  "supervision_update": {
    "supervision_state": "running",
    "focus_kind": "implementation",
    "request_summary": "improve supervisor progress reporting",
    "current_focus_summary": "Updating the conversation supervision pipeline.",
    "recent_progress_summary": "Finished reviewing the old observation output.",
    "waiting_summary": null,
    "blocked_summary": null,
    "next_step_hint": "Add the new supervision projection tests.",
    "plan_items": [
      { "key": "projection", "title": "Add conversation supervision state", "status": "completed" },
      { "key": "renderer", "title": "Rebuild sidechat renderer", "status": "in_progress" }
    ]
  }
}
```

The kernel validates and stores these fields as durable supervision facts. Raw
provider rounds, tool slots, and runtime event names stay below the
human-facing line.

### Supervisor Control Scope

The first control surface should stay deliberately small:

- `request_status_refresh`
- `request_turn_interrupt`
- `request_conversation_close`
- `send_guidance_to_active_agent`
- `send_guidance_to_subagent`
- `request_subagent_close`
- `retry_blocked_step`
- `resume_waiting_workflow`

Anything broader than that belongs in a later operator surface, not in the
initial sidechat API.

### Conversation Control Plane Principles

Control should reuse the current backend control substrate, but not expose the
existing main-agent-to-subagent product semantics directly.

The control split should be:

- `ConversationSupervision` owns read models, sidechat, and human-facing
  status explanations
- `ConversationControl` owns durable, auditable state-changing requests
- `AgentControl`, `Conversations::RequestTurnInterrupt`, and
  `Conversations::RequestClose` remain the execution backend

That implies these rules:

- conversation-level `interrupt` and `close` should directly reuse the
  existing conversation control backend
- guidance should **not** expose `SubagentConnections::SendMessage` as the
  product API; it should flow through a conversation-control translation layer
- observation and conversation-fact questions stay non-invasive and do not
  mutate transcript state
- control requests are durable, auditable, and fence-protected
- authorization should combine installation scope, relationship policy, and
  explicit grants before dispatch

This keeps the system orthogonal:

- `observe` remains read-only and context-aware
- `control` becomes a generic external plane for conversations
- both share target resolution, authorization, audit, and backend dispatch
  layers without collapsing into one abstraction

The existing main-agent-to-subagent management path should survive as a
specialized internal caller:

- it may keep stronger delegation semantics than product-facing side chat
- it must not lose current abilities such as child guidance and child close
- it should converge on the same backend dispatch and audit seams where that
  does not degrade current behavior
- regressions in agent-managed subagent control are not acceptable in this
  refactor

### Capability Gating And Authority Boundary

`ConversationSupervision` should be opt-in, not globally on by default.

Model that as a higher-level capability layer, for example:

- `supervision_enabled`
- `side_chat_enabled`
- `control_enabled`

These switches belong to conversation capability policy, not to
`ConversationSupervisionState`.

That yields a clean split:

- `ConversationSupervisionState` stores only observed work state
- `ConversationCapabilityPolicy` decides whether supervision surfaces are
  available for a target conversation
- `ConversationCapabilityGrant` decides which caller can read supervision or
  issue control requests
- `ConversationControlRequest` is the durable write-side audit trail

Important consequences:

- if supervision is disabled, no side-chat session should open for that target
  conversation
- if control is disabled, side chat can still answer questions but cannot
  dispatch control requests
- action availability should be derived at request time from capability policy
  plus authority context, not persisted inside the supervision read model
- permission checks live above supervision and control read models, at the
  application boundary

### Board-Ready Contract Without A Dashboard

This plan should leave `ConversationSupervision` ready for a future kanban
without requiring another schema rethink.

That means landing these seams now:

- a stable `board_lane` on `ConversationSupervisionState`
- lightweight board-card metrics such as:
  - `active_plan_item_count`
  - `completed_plan_item_count`
  - `active_subagent_count`
  - `lane_changed_at`
  - `retry_due_at`
- a pure application-level multi-conversation projection service that can list
  board cards without depending on side chat or free-text summaries
- a simple update signal so future live UIs can subscribe to supervision
  changes instead of polling every card individually

The goal is not to ship a dashboard now. The goal is to ensure a future board
is an additive presentation layer over existing supervision data.

### Short-Lived Supervision Feed Contract

This plan should also leave `ConversationSupervision` ready for lightweight
status indicators and timelines without forcing every observer through side
chat.

The feed should be:

- generated from explicit supervision write boundaries, not from LLM output
- generated from semantic state changes, not from generic row diffs
- append-only within its retention window
- scoped to the current turn, or the immediately previous turn when no newer
  turn has started yet
- presentation-oriented, not a replacement for workflow or conversation audit

Do **not** use:

- model callbacks such as `after_update`
- ad hoc database diffing over `ConversationSupervisionState`
- LLM-generated summaries as the source of feed truth

Instead, `Conversations::UpdateSupervisionState` and related write boundaries
should emit a semantic changeset, then use that same changeset to:

- persist the new `ConversationSupervisionState`
- append one or more `ConversationSupervisionFeedEntry` rows
- publish a realtime update

The first feed taxonomy should stay small and indicator-oriented:

- `turn_started`
- `progress_recorded`
- `waiting_started`
- `waiting_cleared`
- `blocker_started`
- `blocker_cleared`
- `subagent_started`
- `subagent_completed`
- `control_requested`
- `control_completed`
- `control_failed`
- `turn_completed`
- `turn_failed`
- `turn_interrupted`

This feed is for current-state visibility and short timelines. Deep audit and
forensics remain the job of workflow, conversation, and runtime rows.

### Task 1: Replace observation-only schema with a supervision domain

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260404090000_create_conversation_observation_sessions.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260404090100_create_conversation_observation_frames.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260404090200_create_conversation_observation_messages.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260405092950_create_conversation_capability_policies.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260405093000_create_conversation_supervision_states.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260405093100_create_conversation_control_requests.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260405093110_create_conversation_capability_grants.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/conversation_capability_policy.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/conversation_supervision_session.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/conversation_supervision_snapshot.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/conversation_supervision_message.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/conversation_supervision_state.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/conversation_control_request.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/conversation_capability_grant.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/conversation_capability_policy_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/conversation_supervision_session_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/conversation_supervision_snapshot_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/conversation_supervision_message_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/conversation_supervision_state_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/conversation_control_request_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/conversation_capability_grant_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/conversation.rb`

**Step 1: Write the failing model tests**

Cover the new aggregate boundaries:

- one `ConversationSupervisionState` per target conversation
- one `ConversationCapabilityPolicy` per target conversation
- supervision session rows remain `ephemeral_observability`
- snapshots freeze supervision-state refs plus compact bundle payloads
- messages stay in the side-session and never mutate the target transcript
- control requests are auditable and carry `request_kind`, `target_kind`,
  `lifecycle_state`, and `result_payload`
- capability policy gates whether supervision, side chat, and control are
  enabled for a target conversation
- capability grants define who may read supervision or perform which control
  verbs against which target conversation
- the new naming is authoritative and no `ConversationObservation*` model is
  left as the canonical entrypoint

Add assertions that only `public_id` values appear at app-facing boundaries.

**Step 2: Rewrite the baseline supervision migrations**

Repurpose the current observation tables into:

- `conversation_supervision_sessions`
- `conversation_supervision_snapshots`
- `conversation_supervision_messages`

Add a new canonical read model table:

```ruby
create_table :conversation_supervision_states do |t|
  t.references :installation, null: false, foreign_key: true
  t.references :target_conversation, null: false, foreign_key: { to_table: :conversations }, index: { unique: true, name: "idx_conversation_supervision_states_target" }
  t.uuid :public_id, null: false, default: -> { "uuidv7()" }
  t.string :overall_state, null: false, default: "idle"
  t.string :last_terminal_state
  t.datetime :last_terminal_at
  t.string :current_owner_kind
  t.string :current_owner_public_id
  t.string :request_summary
  t.string :current_focus_summary
  t.string :recent_progress_summary
  t.string :waiting_summary
  t.string :blocked_summary
  t.string :next_step_hint
  t.datetime :last_progress_at
  t.integer :projection_version, null: false, default: 0
  t.jsonb :status_payload, null: false, default: {}
  t.timestamps
end
```

Add a capability-policy table above supervision:

```ruby
create_table :conversation_capability_policies do |t|
  t.references :installation, null: false, foreign_key: true
  t.references :target_conversation, null: false, foreign_key: { to_table: :conversations }, index: { unique: true, name: "idx_conversation_capability_policies_target" }
  t.uuid :public_id, null: false, default: -> { "uuidv7()" }
  t.boolean :supervision_enabled, null: false, default: false
  t.boolean :side_chat_enabled, null: false, default: false
  t.boolean :control_enabled, null: false, default: false
  t.jsonb :policy_payload, null: false, default: {}
  t.timestamps
end
```

Add an auditable conversation-control request table:

```ruby
create_table :conversation_control_requests do |t|
  t.references :installation, null: false, foreign_key: true
  t.references :conversation_supervision_session, null: false, foreign_key: true
  t.references :target_conversation, null: false, foreign_key: { to_table: :conversations }
  t.uuid :public_id, null: false, default: -> { "uuidv7()" }
  t.string :request_kind, null: false
  t.string :target_kind, null: false
  t.string :target_public_id
  t.string :lifecycle_state, null: false, default: "queued"
  t.jsonb :request_payload, null: false, default: {}
  t.jsonb :result_payload, null: false, default: {}
  t.datetime :completed_at
  t.timestamps
end
```

Add an explicit capability-grant table:

```ruby
create_table :conversation_capability_grants do |t|
  t.references :installation, null: false, foreign_key: true
  t.references :target_conversation, null: false, foreign_key: { to_table: :conversations }
  t.uuid :public_id, null: false, default: -> { "uuidv7()" }
  t.string :grantee_kind, null: false
  t.string :grantee_public_id, null: false
  t.string :capability, null: false
  t.string :grant_state, null: false, default: "active"
  t.jsonb :policy_payload, null: false, default: {}
  t.datetime :expires_at
  t.timestamps
end
```

**Step 3: Implement the new models and associations**

Make the conversation-level supervision state easy to traverse:

- `Conversation has_one :conversation_capability_policy`
- `Conversation has_one :conversation_supervision_state`
- `Conversation has_many :conversation_supervision_sessions`
- `Conversation has_many :conversation_control_requests`,
  foreign_key: :target_conversation_id
- `Conversation has_many :conversation_capability_grants`,
  foreign_key: :target_conversation_id
- `ConversationSupervisionSession has_many :conversation_supervision_snapshots`
- `ConversationSupervisionSession has_many :conversation_supervision_messages`
- `ConversationSupervisionSession has_many :conversation_control_requests`

Do not wire sidechat directly to runtime tables yet.

**Step 4: Reset the database and re-export the schema**

Run from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

Expected: the renamed supervision tables appear in `db/schema.rb` and old
`conversation_observation_*` tables are gone.

**Step 5: Run the model tests and commit**

Run:

```bash
bin/rails test test/models/conversation_capability_policy_test.rb test/models/conversation_supervision_session_test.rb test/models/conversation_supervision_snapshot_test.rb test/models/conversation_supervision_message_test.rb test/models/conversation_supervision_state_test.rb test/models/conversation_control_request_test.rb test/models/conversation_capability_grant_test.rb
```

Commit:

```bash
git add db/migrate db/schema.rb app/models test/models
git commit -m "feat: introduce conversation supervision domain"
```

### Task 1A: Move lifecycle and purge ownership to the supervision domain

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/purge_plan.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/purge_plan_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/purge_deleted_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/data_lifecycle_test.rb`

**Step 1: Write failing lifecycle and purge tests**

Cover:

- `ConversationSupervisionSession`, `ConversationSupervisionSnapshot`, and
  `ConversationSupervisionMessage` are classified correctly for data lifecycle
- `ConversationSupervisionState` uses the intended lifecycle class for a
  durable conversation read model
- `ConversationControlRequest` and `ConversationCapabilityGrant` are purged
  when the owning conversation is purged
- old `ConversationObservation*` rows are no longer referenced by purge or
  lifecycle tests

**Step 2: Update purge and lifecycle ownership**

Replace the old observation row cleanup in `Conversations::PurgePlan` with the
new supervision/session/message/state/control rows. Keep purge ordering valid:
session messages and snapshots before sessions, state and capability rows
before conversations.

**Step 3: Run the tests and commit**

Run:

```bash
bin/rails test test/models/data_lifecycle_test.rb test/services/conversations/purge_plan_test.rb test/services/conversations/purge_deleted_test.rb
```

Commit:

```bash
git add app/services/conversations test/models test/services/conversations
git commit -m "refactor: move purge and lifecycle ownership to supervision"
```

### Task 2: Normalize progress state on runtime resources

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260326113000_add_agent_control_contract.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090038_create_subagent_connections.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090031_add_wait_state_to_workflow_runs.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_task_run.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/subagent_connection.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/workflow_run.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/concerns/supervision_state_fields.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/agent_task_run_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/subagent_connection_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/workflow_run_test.rb`

**Step 1: Write failing model tests for the new supervision fields**

Add tests for:

- valid `supervision_state` transitions
- valid `focus_kind` values
- human-facing summary fields must be short strings or nil
- `last_progress_at` updates must exist for non-queued states
- `SubagentConnection` can carry supervision rollup text without changing its
  `observed_status` semantics
- `WorkflowRun` exposes derived `blocked?` / `waiting?` helpers that map to the
  new conversation supervision state machine

**Step 2: Add the normalized supervision columns**

Extend `agent_task_runs` with:

```ruby
t.string :supervision_state, null: false, default: "queued"
t.string :focus_kind, null: false, default: "general"
t.string :request_summary
t.string :current_focus_summary
t.string :recent_progress_summary
t.string :waiting_summary
t.string :blocked_summary
t.string :next_step_hint
t.datetime :last_progress_at
t.integer :supervision_sequence, null: false, default: 0
t.jsonb :supervision_payload, null: false, default: {}
```

Extend `subagent_connections` with the same rollup fields except
`supervision_sequence` may remain optional if you prefer session-local ordering
through progress entries.

Add lightweight conversation-facing helpers to `WorkflowRun`, but do not copy
full human text onto workflow rows. `WorkflowRun` stays the canonical wait
owner; its supervision role is classification, not narration.

**Step 3: Implement shared validation and helper behavior**

Extract a concern or PORO for:

- allowed `supervision_state` values:
  `queued`, `running`, `waiting`, `blocked`, `completed`, `failed`,
  `interrupted`, `canceled`
- allowed `focus_kind` values:
  `planning`, `research`, `implementation`, `testing`, `review`, `waiting`,
  `general`
- `human_summary_fields` validation
- `advance_supervision_sequence!`

Keep `progress_payload` and `terminal_payload` machine-oriented. New summary
columns are the user-facing layer.

**Step 4: Run the model tests**

Run:

```bash
bin/rails test test/models/agent_task_run_test.rb test/models/subagent_connection_test.rb test/models/workflow_run_test.rb
```

Expected: PASS with the new supervision state contract in place.

**Step 5: Commit**

```bash
git add db/migrate app/models test/models
git commit -m "feat: add normalized supervision state to runtime resources"
```

### Task 3: Add structured plan items and semantic progress entries

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260405093200_create_agent_task_plan_items.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260405093300_create_agent_task_progress_entries.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_task_plan_item.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_task_progress_entry.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_task_runs/replace_plan_items.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_task_runs/append_progress_entry.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_task_run.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/subagent_connection.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/agent_task_plan_item_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/agent_task_progress_entry_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_task_runs/replace_plan_items_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_task_runs/append_progress_entry_test.rb`

**Step 1: Write failing tests for plan items and progress entries**

Cover:

- one `in_progress` plan item per `AgentTaskRun`
- optional `parent_plan_item` support for nested plans
- optional `delegated_subagent_connection` link for work handed to a child
- append-only progress entry sequencing per task
- progress entries reject raw internal token summaries like
  `provider_round_3_tool_1`

**Step 2: Create the new tables**

Use explicit rows instead of overloaded JSON blobs:

```ruby
create_table :agent_task_plan_items do |t|
  t.references :installation, null: false, foreign_key: true
  t.references :agent_task_run, null: false, foreign_key: true
  t.references :parent_plan_item, foreign_key: { to_table: :agent_task_plan_items }
  t.references :delegated_subagent_connection, foreign_key: { to_table: :subagent_connections }
  t.uuid :public_id, null: false, default: -> { "uuidv7()" }
  t.string :item_key, null: false
  t.string :title, null: false
  t.string :status, null: false, default: "pending"
  t.integer :position, null: false, default: 0
  t.jsonb :details_payload, null: false, default: {}
  t.datetime :last_status_changed_at
  t.timestamps
end
```

```ruby
create_table :agent_task_progress_entries do |t|
  t.references :installation, null: false, foreign_key: true
  t.references :agent_task_run, null: false, foreign_key: true
  t.references :subagent_connection, foreign_key: true
  t.uuid :public_id, null: false, default: -> { "uuidv7()" }
  t.integer :sequence, null: false
  t.string :entry_kind, null: false
  t.string :summary, null: false
  t.jsonb :details_payload, null: false, default: {}
  t.datetime :occurred_at, null: false
  t.timestamps
end
```

**Step 3: Implement the write boundaries**

- `AgentTaskRuns::ReplacePlanItems` owns plan replacement or reconciliation
- `AgentTaskRuns::AppendProgressEntry` owns semantic progress log writes
- both services update the parent task's rollup columns and
  `last_progress_at`

Do not let controllers or report handlers write plan items directly.

**Step 4: Run the tests**

Run:

```bash
bin/rails test test/models/agent_task_plan_item_test.rb test/models/agent_task_progress_entry_test.rb test/services/agent_task_runs/replace_plan_items_test.rb test/services/agent_task_runs/append_progress_entry_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add db/migrate app/models app/services/agent_task_runs test/models test/services/agent_task_runs
git commit -m "feat: add structured task plans and semantic progress entries"
```

### Task 4: Make runtime report handling update supervision state instead of leaking internals

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/apply_supervision_update.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/update_supervision_state.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_execution_report.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_close_report.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_agent_report.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/execution_reports/workflow_follow_up.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/subagent_connections/spawn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/subagent_connections/wait.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/subagent_connections/send_message.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/subagent_connections/request_close.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/handle_execution_report_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/handle_close_report_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/update_supervision_state_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/subagent_connections/spawn_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/subagent_connections/wait_test.rb`

**Step 1: Write failing tests for supervision-aware report ingestion**

Add tests proving:

- `execution_progress` with `supervision_update` writes task rollup text and
  progress entries
- completion/failure/interruption produce final semantic progress entries
- subagent spawn initializes child supervision state and updates the parent
  conversation supervision state
- parent barrier waits summarize child state as user-meaningful waiting text,
  not `subagent_barrier`

**Step 2: Add `AgentControl::ApplySupervisionUpdate`**

This service should:

- validate allowed supervision fields
- update `AgentTaskRun` rollup columns
- reconcile plan items
- append semantic progress entries
- call `Conversations::UpdateSupervisionState`

Accepted payload shape:

```ruby
payload.fetch("supervision_update").slice(
  "supervision_state",
  "focus_kind",
  "request_summary",
  "current_focus_summary",
  "recent_progress_summary",
  "waiting_summary",
  "blocked_summary",
  "next_step_hint",
  "plan_items"
)
```

Reject updates that only contain raw runtime event labels or obviously internal
tokens.

**Step 3: Add `Conversations::UpdateSupervisionState`**

This service is the canonical conversation-level projector. It should merge:

- active `WorkflowRun` lifecycle and wait state
- active or terminal `AgentTaskRun` supervision rollup
- current `SubagentConnection` supervision rollup
- latest `AgentTaskProgressEntry`
- active plan items

Output is persisted onto `ConversationSupervisionState`, not returned as an
ephemeral hash only. The service should also produce a semantic changeset that
later read-side seams can reuse for feed entries and update publishing.

**Step 4: Run the service tests**

Run:

```bash
bin/rails test test/services/agent_control/handle_execution_report_test.rb test/services/agent_control/handle_close_report_test.rb test/services/conversations/update_supervision_state_test.rb test/services/subagent_connections/spawn_test.rb test/services/subagent_connections/wait_test.rb
```

Expected: PASS with conversation-level supervision state updating on material
runtime changes.

**Step 5: Commit**

```bash
git add app/services/agent_control app/services/conversations app/services/subagent_connections test/services
git commit -m "feat: project runtime progress into conversation supervision state"
```

### Task 4A: Add board-ready projections and update signals without building a dashboard

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260405093000_create_conversation_supervision_states.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/conversation_supervision_state.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_supervision/classify_board_lane.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_supervision/build_board_card.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_supervision/list_board_cards.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_supervision/publish_update.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/update_supervision_state.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/conversation_supervision_state_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_supervision/classify_board_lane_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_supervision/build_board_card_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_supervision/list_board_cards_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_supervision/publish_update_test.rb`

**Step 1: Write failing tests for board-lane classification and board-card projection**

Cover:

- `ConversationSupervisionState` exposes a stable `board_lane`
- lane classification does not depend on human-readable sidechat strings
- board cards include enough structured fields for a future kanban card
- multi-card listing returns deterministic sorting and filtering
- update publishing fires when supervision state materially changes and is a
  no-op for cosmetic rewrites

Recommended lane taxonomy:

- `idle`
- `queued`
- `active`
- `waiting`
- `blocked`
- `handoff`
- `done`
- `failed`

**Step 2: Extend `conversation_supervision_states` with board metadata**

Amend the create migration to add fields such as:

```ruby
t.string :board_lane, null: false, default: "idle"
t.datetime :lane_changed_at
t.datetime :retry_due_at
t.integer :active_plan_item_count, null: false, default: 0
t.integer :completed_plan_item_count, null: false, default: 0
t.integer :active_subagent_count, null: false, default: 0
t.jsonb :board_badges, null: false, default: []
```

These fields should be projection-friendly, not UI-specific.

**Step 3: Implement board-ready projection services**

- `ClassifyBoardLane` maps supervision state and workflow wait facts into the
  stable lane taxonomy
- `BuildBoardCard` returns one structured card payload from one
  `ConversationSupervisionState`
- `ListBoardCards` returns filtered/sorted card payloads across conversations
- `PublishUpdate` emits a lightweight change signal for future live views or
  APIs

Do not build a dashboard controller or LiveView equivalent here. This task is
strictly about stable projection seams.

**Step 4: Update the conversation projector to maintain board metadata**

`Conversations::UpdateSupervisionState` should also maintain:

- `last_terminal_state`
- `last_terminal_at`
- `board_lane`
- `lane_changed_at`
- `retry_due_at`
- plan-item counts
- active subagent count
- `board_badges`

`overall_state` should only remain terminal when the conversation is being
presented as a terminal archived/deleted surface. Otherwise, once live work has
stopped, the projector should fall back to `idle` and preserve the prior result
in `last_terminal_state`.

That keeps the single-card truth and future board truth aligned.

**Step 5: Run the tests**

Run:

```bash
bin/rails test test/models/conversation_supervision_state_test.rb test/services/conversation_supervision/classify_board_lane_test.rb test/services/conversation_supervision/build_board_card_test.rb test/services/conversation_supervision/list_board_cards_test.rb test/services/conversation_supervision/publish_update_test.rb test/services/conversations/update_supervision_state_test.rb
```

Expected: PASS with no dashboard UI yet, but with a stable board-ready
projection contract.

**Step 6: Commit**

```bash
git add db/migrate app/models app/services/conversation_supervision app/services/conversations test/models test/services/conversation_supervision
git commit -m "feat: add board-ready supervision projections"
```

### Task 4B: Add a short-lived supervision activity feed for indicators and timelines

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260405093410_create_conversation_supervision_feed_entries.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/conversation_supervision_feed_entry.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_supervision/append_feed_entries.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_supervision/build_activity_feed.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_supervision/prune_feed_window.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/update_supervision_state.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_supervision/publish_update.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/conversation_supervision_feed_entry_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_supervision/append_feed_entries_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_supervision/build_activity_feed_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_supervision/prune_feed_window_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/update_supervision_state_test.rb`

**Step 1: Write failing tests for the short-lived feed window**

Cover:

- feed entries are appended from semantic supervision changes, not from raw
  row diffs
- feed entries are scoped to the current turn when one is active
- when no newer turn has started, the previous turn's feed remains readable
- once a newer turn writes its first feed entry, older turn feed rows outside
  the current/previous window are pruned
- feed summaries stay human-readable without leaking internal runtime tokens
- publish updates can include enough feed metadata for indicators without
  requiring side chat

**Step 2: Create the feed-entry table**

Use an explicit read-side table:

```ruby
create_table :conversation_supervision_feed_entries do |t|
  t.references :installation, null: false, foreign_key: true
  t.references :target_conversation, null: false, foreign_key: { to_table: :conversations }
  t.references :target_turn, foreign_key: { to_table: :turns }
  t.uuid :public_id, null: false, default: -> { "uuidv7()" }
  t.integer :sequence, null: false
  t.string :event_kind, null: false
  t.string :summary, null: false
  t.jsonb :details_payload, null: false, default: {}
  t.datetime :occurred_at, null: false
  t.timestamps
end
```

Do not treat this as a permanent audit log. It is a short-lived presentation
feed tied to the active or immediately previous turn.

**Step 3: Implement the feed writers and readers**

- `AppendFeedEntries` turns semantic changesets from
  `Conversations::UpdateSupervisionState` into feed rows
- `BuildActivityFeed` returns the current-turn feed, or the previous-turn feed
  when no newer turn has started
- `PruneFeedWindow` removes entries outside the current/previous-turn window
- `PublishUpdate` should be able to emit feed-aware update payloads for
  high-level indicators or timelines

Keep event kinds bounded and semantic:

- `turn_started`
- `progress_recorded`
- `waiting_started`
- `waiting_cleared`
- `blocker_started`
- `blocker_cleared`
- `subagent_started`
- `subagent_completed`
- `control_requested`
- `control_completed`
- `control_failed`
- `turn_completed`
- `turn_failed`
- `turn_interrupted`

**Step 4: Wire the conversation projector**

`Conversations::UpdateSupervisionState` should, in the same explicit write
boundary:

- persist `ConversationSupervisionState`
- compute a semantic changeset
- append feed entries from that changeset
- publish an update

Do not implement this through Active Record callbacks on
`ConversationSupervisionState`.

**Step 5: Run the tests**

Run:

```bash
bin/rails test test/models/conversation_supervision_feed_entry_test.rb test/services/conversation_supervision/append_feed_entries_test.rb test/services/conversation_supervision/build_activity_feed_test.rb test/services/conversation_supervision/prune_feed_window_test.rb test/services/conversations/update_supervision_state_test.rb test/services/conversation_supervision/publish_update_test.rb
```

Expected: PASS with a deterministic current-or-previous-turn activity feed and
no LLM dependency.

**Step 6: Commit**

```bash
git add db/migrate app/models app/services/conversation_supervision app/services/conversations test/models test/services/conversation_supervision test/services/conversations
git commit -m "feat: add short-lived supervision activity feed"
```

### Task 5: Rebuild the sidechat surface on frozen supervision snapshots

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/conversation_supervision/create_session.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/conversation_supervision/append_message.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/conversation_supervision/build_snapshot.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/conversation_supervision/build_machine_status.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/conversation_supervision/build_human_sidechat.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/conversation_supervision/build_human_summary.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/conversation_supervision/responders/builtin.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/conversation_supervision_sessions_controller.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/conversation_supervision_messages_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/routes.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/conversation_observation_sessions_controller.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/conversation_observation_messages_controller.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/conversation_observation/*`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/embedded_agents/conversation_supervision/create_session_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/embedded_agents/conversation_supervision/append_message_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/conversation_supervision_messages_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/conversation_supervision_sessions_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/conversation_observation_messages_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/conversation_observation_sessions_test.rb`

**Step 1: Write failing side-chat tests against supervision state, not runtime tokens**

Cover:

- "what are you doing now?"
- "what changed most recently?"
- "what are you waiting on?"
- "what will you do next?"
- subagent progress questions
- conversation-context questions in the `/btw` style, such as:
  - "what did we already agree on?"
  - "has this turn already committed to adding tests?"
  - "what fact about the 2048 acceptance flow is already established?"

Expected text should read like a human progress report and must reject:

- `provider_round`
- `tool_`
- `runtime.workflow_node`
- `subagent_barrier`
- other snake_case wait/event tokens

Also assert that side chat can answer conversation-fact questions from context
without quoting full transcript text into the frozen snapshot.

**Step 2: Freeze supervision snapshots**

`BuildSnapshot` should freeze:

- a copy of the current `ConversationSupervisionState`
- a copy of the current `ConversationCapabilityPolicy`
- a compact `conversation_context_view` built from transcript and current-turn
  facts
- the short-lived current-or-previous-turn activity feed
- active plan items
- active subagent summaries
- a compact proof/debug section built from `WorkflowRun` and
  `ConversationEvent`
- a capability-and-authority descriptor for the current caller, including
  whether control is enabled and which control verbs are currently available

Do not build human text from raw workflow node keys.
Do not port `BuildAssessment`, `BuildSupervisorStatus`, or the old observation
bundle builders under new names; replace them with supervision-native machine
status and snapshot builders.

**Step 3: Implement the renderer**

`BuildHumanSidechat` should answer in this order:

1. current work
2. most recent progress
3. waiting or blocker reason when relevant
4. next step when justified
5. direct conversation-fact answer when the question is context-oriented
6. compact grounding sentence

Use question intent classification:

- `current_status`
- `recent_progress`
- `blocker`
- `next_step`
- `subagent_status`
- `conversation_fact`
- `general_status`

Keep `BuildMachineStatus` explicit and stable for harnesses. Sidechat becomes a
renderer over the same frozen snapshot.

**Step 4: Run the service and request tests**

Run:

```bash
bin/rails test test/services/embedded_agents/conversation_supervision/create_session_test.rb test/services/embedded_agents/conversation_supervision/append_message_test.rb test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/requests/app_api/conversation_supervision_messages_test.rb test/requests/app_api/conversation_supervision_sessions_test.rb
```

Expected: PASS with human-visible content grounded in supervision summaries.

**Step 5: Commit**

```bash
git add app/services/embedded_agents app/controllers/app_api test/services/embedded_agents test/requests/app_api
git commit -m "feat: rebuild sidechat on conversation supervision snapshots"
```

### Task 5A: Migrate embedded-agent registration and manual acceptance helpers

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/registry.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/invoke.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/manual_support.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/manual_support_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/embedded_agents/invoke_test.rb`

**Step 1: Write failing helper and registry tests**

Cover:

- embedded-agent registry resolves `conversation_supervision`, not
  `conversation_observation`
- manual helper APIs use supervision naming and payload keys
- helper serialization still uses `public_id` only
- helper methods expose machine-readable supervision status, sidechat content,
  and supervision snapshot identifiers without requiring old observation names

**Step 2: Replace the helper and registry surface**

Update the manual harness to create and append conversation supervision
sessions/messages, and to serialize the new payload shape. Keep the helper API
purpose the same: acceptance can drive side chat and inspect machine status
without scraping transcript internals.

**Step 3: Run the tests and commit**

Run:

```bash
bin/rails test test/lib/acceptance/manual_support_test.rb test/services/embedded_agents/invoke_test.rb
```

Commit:

```bash
git add app/services/embedded_agents script/manual test/lib test/services/embedded_agents
git commit -m "refactor: migrate supervision helper entrypoints"
```

### Task 6: Add a conversation-scoped external control plane on top of the existing backend substrate

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_control/create_request.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_control/authorize_request.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_control/dispatch_request.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_control/resolve_target_runtime.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_conversation_control_request.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_agent_request.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/report_dispatch.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/serialize_mailbox_item.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/request_turn_interrupt.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/request_close.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/subagent_connections/request_close.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/manual_resume.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/step_retry.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_control/create_request_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_control/authorize_request_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_control/dispatch_request_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/create_agent_request_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/request_turn_interrupt_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/request_close_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/subagent_connections/request_close_test.rb`

**Step 1: Write failing tests for the first control verbs**

Add tests for:

- `request_status_refresh` creates an auditable conversation-control request and a
  mailbox request
- `request_turn_interrupt` routes through
  `Conversations::RequestTurnInterrupt`
- `request_conversation_close` routes through
  `Conversations::RequestClose`
- `send_guidance_to_subagent` creates a durable control request and does not
  directly mutate the target transcript at request-creation time
- `request_subagent_close` routes through `SubagentConnections::RequestClose`
- disabled supervision or control capability blocks request creation before
  dispatch begins
- unauthorized callers are rejected by relationship policy and explicit
  capability-grant checks before dispatch
- `resume_waiting_workflow` and `retry_blocked_step` are rejected unless the
  current `WorkflowRun` wait reason permits them
- existing main-agent-to-subagent guidance and close flows still work after
  the refactor and do not lose delegation-specific behavior

**Step 2: Extend the request taxonomy**

Prefer one new `AgentControl` request creator over ad hoc side effects. Extend
program requests with supervision-specific `request_kind` values:

- `supervision_status_refresh`
- `supervision_guidance`

Use existing `resource_close_request` for close behavior. Do not invent a new
close plane.

**Step 3: Implement the action dispatch boundary**

`ConversationControlRequest` should move through:

- `queued`
- `dispatched`
- `acknowledged`
- `completed`
- `failed`
- `rejected`

`AuthorizeRequest` should combine:

- capability policy switches for the target conversation
- installation scoping
- conversation relationship policy
- explicit `ConversationCapabilityGrant` rows
- target conversation runtime state

`DispatchRequest` decides whether the request maps to:

- a mailbox request
- a conversation interrupt
- a conversation close
- a control-guidance mailbox request
- a close request
- a workflow resume/retry service call

Do not expose `SubagentConnections::SendMessage` as the product control API.
If subagent guidance ultimately becomes a child-facing message, that should be
decided inside the control adapter, not at the sidechat boundary.

Preserve agent-managed subagent control as an internal special case. The new
conversation-control plane should become the shared backend seam, but the
existing agent delegation path may retain richer caller semantics as long as
observable behavior does not regress.

All results must be written back to `result_payload` so sidechat can explain
what happened.

**Step 4: Run the tests**

Run:

```bash
bin/rails test test/services/conversation_control/create_request_test.rb test/services/conversation_control/authorize_request_test.rb test/services/conversation_control/dispatch_request_test.rb test/services/agent_control/create_agent_request_test.rb test/services/conversations/request_turn_interrupt_test.rb test/services/conversations/request_close_test.rb test/services/subagent_connections/request_close_test.rb
```

Expected: PASS with auditable, authorized, bounded control behavior.

**Step 5: Commit**

```bash
git add app/services/conversation_control app/services/agent_control app/services/conversations app/services/subagent_connections app/services/workflows test/services
git commit -m "feat: add conversation-scoped control plane"
```

### Task 7: Add natural-language control intent mapping to side chat

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/conversation_supervision/classify_control_intent.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/conversation_supervision/maybe_dispatch_control_intent.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/conversation_supervision/append_message.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/conversation_supervision/responders/builtin.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/conversation_supervision/build_snapshot.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_control/create_request.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/subagent_connections/send_message.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/embedded_agents/conversation_supervision/classify_control_intent_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/embedded_agents/conversation_supervision/maybe_dispatch_control_intent_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/embedded_agents/conversation_supervision/append_message_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/subagent_connections/send_message_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/conversation_supervision_messages_test.rb`

**Step 1: Write failing tests for natural-language control intents**

Add tests for:

- "快住手" or "stop" maps to `request_turn_interrupt` when control is enabled
  and the caller is authorized
- "关闭这个任务" maps to `request_conversation_close`
- "让子任务停下" maps to `request_subagent_close` when an active child exists
- ambiguous language stays in chat mode and does not dispatch control
- disabled control capability yields an explanatory chat response instead of
  request creation
- unauthorized control attempts yield a denial response without mutating the
  target conversation
- a successful control-intent dispatch produces a human-readable confirmation
  message in side chat
- existing agent-managed `SubagentConnections::SendMessage` behavior still passes
  unchanged for internal delegation use cases

**Step 2: Add a bounded intent classifier**

`ClassifyControlIntent` should map only high-confidence phrases onto existing
`ConversationControl` verbs.

Start with a small, explicit set:

- `request_turn_interrupt`
- `request_conversation_close`
- `request_subagent_close`
- `resume_waiting_workflow`
- `retry_blocked_step`

Do not allow open-ended instruction following here. This is a bounded
classifier, not a general tool-use planner.

**Step 3: Add the side-chat dispatch adapter**

`MaybeDispatchControlIntent` should:

- check `ConversationCapabilityPolicy` first
- check caller authority through the existing grant layer
- classify the incoming side-chat message
- create and dispatch a `ConversationControlRequest` when confidence is high
- otherwise fall back to ordinary side-chat handling

The user-facing interaction should feel conversational, but the implementation
must remain verb-based under the hood.

**Step 4: Preserve internal agent-to-subagent delegation semantics**

Keep agent-managed child control as a supported internal path:

- owner-agent guidance to child conversations must keep working
- owner-agent child close requests must keep working
- if internal delegation starts using shared `ConversationControl` helpers,
  that reuse must be behavior-preserving

The new side-chat control UX must not degrade or simplify away existing
main-agent-to-subagent management.

**Step 5: Run the tests**

Run:

```bash
bin/rails test test/services/embedded_agents/conversation_supervision/classify_control_intent_test.rb test/services/embedded_agents/conversation_supervision/maybe_dispatch_control_intent_test.rb test/services/embedded_agents/conversation_supervision/append_message_test.rb test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/services/subagent_connections/send_message_test.rb test/requests/app_api/conversation_supervision_messages_test.rb
```

Expected: PASS with bounded natural-language control and no regression in
internal child-management behavior.

**Step 6: Commit**

```bash
git add app/services/embedded_agents/conversation_supervision app/services/conversation_control app/services/subagent_connections test/services/embedded_agents test/services/subagent_connections test/requests/app_api
git commit -m "feat: add bounded sidechat control intents"
```

### Task 8: Tighten acceptance, exports, compaction, and operator hooks

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/fixtures/conversation_control_phrase_matrix.yml`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/conversation_control_phrase_matrix.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/fresh_start_stack_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/conversation-observation-and-supervisor-status.md`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/conversation-supervision-and-control.md`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-progress-and-plan-items.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/data-retention-and-lifecycle-classes.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/human-interactions-and-conversation-events.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/subagent-connections-and-execution-leases.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-runtime-resource-apis.md`

**Step 1: Write failing acceptance contract tests**

Add assertions that:

- human-visible supervision text fails if it includes internal runtime
  vocabulary
- exported supervision markdown includes plan items, subagent summaries,
  waiting/blocker summaries, capability state, currently available control
  actions, and the short-lived supervision feed
- the acceptance harness reads terminal state from conversation supervision,
  not by scraping workflow internals from free text
- high-confidence control phrases in side chat dispatch the expected bounded
  control verbs only when capability and authority permit
- the phrase-matrix fixture includes positive, negative, and ambiguous control
  utterances instead of only one canonical wording per verb
- acceptance artifacts and prompts use supervision naming rather than
  observation naming
- contract tests cover the renamed manual-helper and artifact entrypoints so
  the capstone harness cannot silently drift back to observation terminology

**Step 2: Update the acceptance scenario**

The scenario should:

- create a supervision session, not an observation session
- poll the machine-readable conversation supervision state
- record the human sidechat separately from proof/debug refs
- rename exported artifacts to supervision-oriented names, for example:
  - `supervision-sidechat.md`
  - `supervision-status.md`
  - `supervision-feed.md`
- run a provider-backed control-intent matrix against a real live conversation
  when `CAPSTONE_ENABLE_CONTROL_ACCEPTANCE=1`
- cover multiple utterance shapes per verb, including:
  - direct imperatives such as "stop"
  - colloquial variants such as "快住手"
  - indirect phrasing such as "别继续了"
  - negative or ambiguous chat that should **not** dispatch control
- write one artifact that records the utterance, classified intent, capability
  state, authority decision, dispatch result, and final runtime effect for each
  matrix case
- scan human-visible text for suspicious internal vocabulary

Suggested suspicious tokens:

```ruby
%r{
  provider_round|
  tool_[a-z0-9_]+|
  runtime\.[a-z0-9_.]+|
  subagent_barrier|
  wait_reason_kind|
  workflow_node
}ix
```

The live control-intent matrix should use a real provider-backed run, not a
mock responder, because the user-facing risk is intent recognition under real
language variation. The existing capstone selector already runs against a live
provider-qualified model, so this should extend that harness instead of
inventing a separate fake environment.

Do **not** make the provider-backed phrase matrix the only correctness gate.
Keep a deterministic corpus-based contract layer in `core_matrix` service tests
and use the live matrix as a higher-cost end-to-end validation layer for
release confidence, nightly runs, or explicit acceptance runs.

**Step 3: Refresh the behavior docs**

Make the new docs the source of truth for:

- canonical supervision state
- short-lived supervision feed generation and retention
- runtime progress updates
- sidechat rendering
- conversation control flow
- control-intent acceptance strategy, including deterministic corpus tests plus
  provider-backed live matrix validation

The old observation behavior doc should become a migration note or redirect,
not the living source of truth.

**Step 4: Run focused verification plus the full project checks**

Run:

```bash
bin/rails test test/lib/fresh_start_stack_contract_test.rb test/lib/fenix_capstone_acceptance_contract_test.rb
bin/rails test
bin/rails test:system
bin/brakeman --no-pager
bin/bundler-audit
bun run lint:js
```

Expected: PASS.

If the sidechat and control blocks have already landed cleanly, run the 2048
capstone acceptance once before the final step as an intermediate confidence
check. This is especially useful after large acceptance-artifact renames.

For live acceptance runs, also execute the provider-backed scenario with
control acceptance enabled from `/Users/jasl/Workspaces/Ruby/cybros`:

```bash
CAPSTONE_ENABLE_CONTROL_ACCEPTANCE=1 acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

Expected: PASS with a populated control-intent artifact showing both successful
dispatches and intentionally non-dispatched ambiguous utterances.

**Step 5: Commit**

```bash
git add acceptance/scenarios core_matrix/test/lib core_matrix/docs/behavior
git commit -m "test: harden supervision acceptance and documentation"
```

## Final Verification Sequence

After all tasks are done, run the full destructive rebuild once more from
`/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
bin/brakeman --no-pager
bin/bundler-audit
bun run lint:js
```

Then run the root acceptance flow from `/Users/jasl/Workspaces/Ruby/cybros`:

```bash
acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
CAPSTONE_ENABLE_CONTROL_ACCEPTANCE=1 acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

The exported supervision artifacts should read like a human progress report and
must not expose internal runtime structure in the visible sidechat text. When
control acceptance is enabled, the generated control-intent artifact should
show both successful dispatches and intentionally non-dispatched ambiguous
utterances.

## Notes For The Implementer

- Prefer query/projection objects for conversation-level read models instead of
  bloating controllers or responders.
- Keep human-readable summaries and machine-readable payloads separate.
- Do not let `WorkflowRun.node_key`, `ConversationEvent.event_kind`, or
  `AgentControlMailboxItem.payload` become de facto UI strings.
- Use `public_id` at every app-facing boundary, including new supervision
  state and conversation control requests.
- `SubagentConnection` remains the durable child-control aggregate; supervision
  adds visibility around it, while conversation control reuses it as an
  execution backend rather than exposing its native agent-to-subagent API.
- `ConversationSupervisionState` is a read model and should be fully
  reconstructible from durable runtime rows if needed.
- `ConversationSupervisionFeedEntry` is not an audit log. Keep it short-lived,
  current-or-previous-turn scoped, and generated from explicit projector
  changesets rather than Active Record callbacks.
- This plan supersedes the narrower
  `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-05-observation-progress-reporting.md`
  for any work beyond sidechat wording.
