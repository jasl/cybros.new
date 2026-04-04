# Conversation Observation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a first-class `ConversationObservation` supervision surface to `core_matrix`, then switch the Fenix 2048 capstone acceptance harness to monitor in-flight progress through `observe` instead of direct database and filesystem probing.

**Architecture:** Build `ConversationObservation` as the first `EmbeddedAgent` capability with its own side-session models, a deterministic builtin responder, and a bounded observation bundle sourced from transcript, workflow, diagnostics, and lightweight durable runtime events. Keep transcript mutation and control semantics out of scope, and land only the builtin observation path required for app API supervision and capstone acceptance.

**Tech Stack:** Ruby on Rails, Active Record, Action Cable, Minitest, acceptance harness scripts

---

## Execution Rules

- Every task follows a strict write-check-fix loop:
  1. write or extend the failing test
  2. run only that narrow test target and confirm the failure is the expected one
  3. implement the minimum code to make it pass
  4. rerun the narrow target until green
  5. if the fix changes assumptions used by later tasks, update the plan notes before moving on
- After every task, do a dependency and blocker sweep:
  - verify the next task still has everything it needs
  - verify no new raw-`bigint` exposure was introduced at app or agent-facing boundaries
  - verify no task quietly pulled `control` semantics into the `observe` slice
- Prefer one commit per task or per tightly related pair of tasks.
- Do not implement the `program_contract` responder path in this plan. Add only the seam needed to support it later.

## Dependency And Blocker Preflight

This plan is executable without external runtime changes because it intentionally
cuts scope in three places:

- `ConversationObservation` ships with a deterministic builtin responder first.
  No `agents/fenix` protocol change is required for the acceptance slice.
- The lightweight runtime projection reuses `ConversationEvent` and current
  runtime event kinds instead of inventing a second event ledger.
- The acceptance harness changes only after the app-facing observation API is
  stable and proven by request and service tests.

Known blockers to watch:

- Current runtime visibility is mostly broadcast-only.
  Mitigation: add one shared publish path that can both broadcast and project
  compact durable runtime events.
- The accepted design speaks in conceptual `*_id` anchors, but the
  implementation should store proof-facing snapshot strings as public ids on
  observation frames to avoid accidental internal-id leakage.
- The acceptance harness currently uses
  [`core_matrix/script/manual/manual_acceptance_support.rb`](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/script/manual/manual_acceptance_support.rb)
  and the top-level scenario together. Both files must move in lockstep.

## Status

- Implementation is complete and verified.
- The builtin observation path, app-facing observation API, and capstone
  supervision migration all landed in code.
- The approved design source is
  [2026-04-04-core-matrix-conversation-observation-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-04-04-core-matrix-conversation-observation-design.md).
- Verification completed with:
  - `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rubocop -f github`
  - `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bun run lint:js`
  - `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails db:test:prepare test`
  - `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails db:test:prepare test:system`
  - `cd /Users/jasl/Workspaces/Ruby/cybros && bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh`

### Task 1: Add the observation persistence layer

**Files:**
- Create: `core_matrix/db/migrate/20260404090000_create_conversation_observation_sessions.rb`
- Create: `core_matrix/db/migrate/20260404090100_create_conversation_observation_frames.rb`
- Create: `core_matrix/db/migrate/20260404090200_create_conversation_observation_messages.rb`
- Create: `core_matrix/app/models/conversation_observation_session.rb`
- Create: `core_matrix/app/models/conversation_observation_frame.rb`
- Create: `core_matrix/app/models/conversation_observation_message.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Test: `core_matrix/test/models/conversation_observation_session_test.rb`
- Test: `core_matrix/test/models/conversation_observation_frame_test.rb`
- Test: `core_matrix/test/models/conversation_observation_message_test.rb`

**Step 1: Write failing model tests**

- Cover associations, `HasPublicId`, allowed roles, and basic validation shape.
- Assert frame snapshot fields store public-id strings for proof-facing anchors:
  - `anchor_turn_public_id`
  - `active_workflow_run_public_id`
  - `active_workflow_node_public_id`
  - `active_subagent_session_public_ids`

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/conversation_observation_session_test.rb test/models/conversation_observation_frame_test.rb test/models/conversation_observation_message_test.rb
```

Expected: FAIL because the tables and models do not exist yet.

**Step 2: Create the migrations and models**

- `ConversationObservationSession`:
  - belongs to `installation`
  - belongs to `target_conversation`, class name `Conversation`
  - has many frames and messages
- `ConversationObservationFrame`:
  - belongs to session
  - stores snapshot public-id strings and `assessment_payload`
- `ConversationObservationMessage`:
  - belongs to session
  - belongs to frame
  - supports `user`, `observer_agent`, `system`

**Step 3: Wire core associations**

- Add `has_many :conversation_observation_sessions, foreign_key: :target_conversation_id`
  on `Conversation`.

**Step 4: Re-run the narrow tests**

Run the same model test command until green.

**Step 5: Commit**

- Commit message: `feat: add conversation observation models`

### Task 2: Introduce the embedded-agent invocation spine

**Files:**
- Create: `core_matrix/app/services/embedded_agents/invoke.rb`
- Create: `core_matrix/app/services/embedded_agents/registry.rb`
- Create: `core_matrix/app/services/embedded_agents/result.rb`
- Create: `core_matrix/app/services/embedded_agents/errors.rb`
- Create: `core_matrix/app/services/embedded_agents/conversation_observation/invoke.rb`
- Create: `core_matrix/app/services/embedded_agents/conversation_observation/authority.rb`
- Test: `core_matrix/test/services/embedded_agents/invoke_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_observation/authority_test.rb`

**Step 1: Write failing service tests**

- `EmbeddedAgents::Invoke` dispatches by `agent_key`
- unknown keys raise a typed error
- `ConversationObservation::Authority` permits an owner on their own
  conversation
- raw internal ids are never accepted at the entry boundary

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/embedded_agents/invoke_test.rb test/services/embedded_agents/conversation_observation/authority_test.rb
```

Expected: FAIL because the services do not exist yet.

**Step 2: Implement the minimum spine**

- `EmbeddedAgents::Registry` maps `"conversation_observation"` to its handler
- `EmbeddedAgents::Invoke` normalizes arguments and returns a consistent result
- `Authority` validates actor/target access using conversation visibility and
  ownership

**Step 3: Re-run the narrow tests**

Use the same command until green.

**Step 4: Commit**

- Commit message: `feat: add embedded agent invocation spine`

### Task 3: Add one shared runtime event publish path with durable projection

**Files:**
- Create: `core_matrix/app/services/conversation_runtime/publish_event.rb`
- Create: `core_matrix/test/services/conversation_runtime/publish_event_test.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Modify: `core_matrix/app/services/agent_control/handle_execution_report.rb`
- Modify: `core_matrix/app/services/processes/broadcast_runtime_event.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`
- Modify: `core_matrix/test/services/agent_control/report_test.rb`
- Create: `core_matrix/test/services/processes/broadcast_runtime_event_test.rb`

**Step 1: Write failing tests around durable runtime projection**

- `ConversationRuntime::PublishEvent` broadcasts and writes a compact
  `ConversationEvent`
- `stream_key` compaction keeps one live projection entry per runtime resource
- provider-step, agent-task, and process runtime events land in the conversation
  event stream without creating transcript messages

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/conversation_runtime/publish_event_test.rb test/services/provider_execution/execute_turn_step_test.rb test/services/agent_control/report_test.rb test/services/processes/broadcast_runtime_event_test.rb
```

Expected: FAIL because runtime writers still broadcast only.

**Step 2: Implement `ConversationRuntime::PublishEvent`**

- Always broadcast through the existing Action Cable path
- Optionally project a compact `ConversationEvent` for supported runtime kinds
- Use replaceable `stream_key` values based on public ids such as:
  - `runtime.workflow_node:<workflow_node_public_id>`
  - `runtime.agent_task:<agent_task_run_public_id>`
  - `runtime.process_run:<process_run_public_id>`

**Step 3: Rewire current writers**

- Replace direct `ConversationRuntime::Broadcast` calls in:
  - `ProviderExecution::ExecuteTurnStep`
  - `AgentControl::HandleExecutionReport`
  - `Processes::BroadcastRuntimeEvent`
- Keep event kinds aligned with existing runtime names so no transport consumer
  breaks.

**Step 4: Re-run the narrow tests**

Use the same test command until green.

**Step 5: Commit**

- Commit message: `feat: project lightweight durable runtime events`

### Task 4: Build the observation frame and bounded bundle

**Files:**
- Create: `core_matrix/app/services/embedded_agents/conversation_observation/build_frame.rb`
- Create: `core_matrix/app/services/embedded_agents/conversation_observation/build_bundle.rb`
- Create: `core_matrix/test/services/embedded_agents/conversation_observation/build_frame_test.rb`
- Create: `core_matrix/test/services/embedded_agents/conversation_observation/build_bundle_test.rb`

**Step 1: Write failing builder tests**

- `BuildFrame` freezes one anchor from the current target conversation state
- `BuildBundle` returns:
  - `transcript_view`
  - `workflow_view`
  - `activity_view`
  - `subagent_view`
  - `diagnostic_view`
  - `memory_view`
- `transcript_view` reads only transcript-bearing messages
- `activity_view` reads compact `ConversationEvent.live_projection`
- no raw internal ids appear in the bundle

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/embedded_agents/conversation_observation/build_frame_test.rb test/services/embedded_agents/conversation_observation/build_bundle_test.rb
```

Expected: FAIL because the builders do not exist yet.

**Step 2: Implement `BuildFrame`**

- snapshot the current target state once
- persist public-id snapshot strings and compact status
- avoid full transcript or graph copies

**Step 3: Implement `BuildBundle`**

- transcript: use `ConversationTranscripts::PageProjection` or the same message
  eligibility rules behind it
- workflow: read current workflow run, node, wait state, and blocker
- activity: read the live-projection tail of runtime `ConversationEvent` rows
- diagnostics: reuse `ConversationDiagnostics::RecomputeConversationSnapshot`
- subagents: read current `SubagentSession` rows
- memory: return an empty or minimal conversation-scoped summary in v1 if no
  dedicated memory store exists yet

**Step 4: Re-run the narrow tests**

Use the same command until green.

**Step 5: Commit**

- Commit message: `feat: build conversation observation frames and bundles`

### Task 5: Implement the canonical assessment and builtin responder

**Files:**
- Create: `core_matrix/app/services/embedded_agents/conversation_observation/build_assessment.rb`
- Create: `core_matrix/app/services/embedded_agents/conversation_observation/responders/builtin.rb`
- Create: `core_matrix/app/services/embedded_agents/conversation_observation/route_responder.rb`
- Create: `core_matrix/test/services/embedded_agents/conversation_observation/build_assessment_test.rb`
- Create: `core_matrix/test/services/embedded_agents/conversation_observation/responders/builtin_test.rb`

**Step 1: Write failing assessment tests**

- one canonical `assessment` is produced per frame
- `supervisor_status` and `human_sidechat` derive from the same assessment
- proof refs cite the same public ids in both projections
- builtin responder is deterministic and does not require an external model call

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/embedded_agents/conversation_observation/build_assessment_test.rb test/services/embedded_agents/conversation_observation/responders/builtin_test.rb
```

Expected: FAIL because the assessment and responder services do not exist yet.

**Step 2: Implement `BuildAssessment`**

- derive:
  - `overall_state`
  - `current_activity`
  - `last_progress_at`
  - `stall_for_ms`
  - `blocking_reason`
  - `recent_activity_items`
  - `proof_refs`
  - `proof_text`
- keep the payload machine-stable and deterministic

**Step 3: Implement the builtin responder**

- render `supervisor_status` as structured JSON-ready data
- render `human_sidechat` as a short templated explanation
- save the full assessment into `frame.assessment_payload`

**Step 4: Re-run the narrow tests**

Use the same command until green.

**Step 5: Commit**

- Commit message: `feat: add deterministic conversation observation responder`

### Task 6: Add the app-facing observation session API

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/app_api/conversation_observation_sessions_controller.rb`
- Create: `core_matrix/app/services/embedded_agents/conversation_observation/create_session.rb`
- Create: `core_matrix/test/requests/app_api/conversation_observation_sessions_test.rb`

**Step 1: Write failing request tests**

- create session returns `201`
- show returns the stored session
- both paths use target conversation public id and session public id only
- raw internal ids return `404`

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/app_api/conversation_observation_sessions_test.rb
```

Expected: FAIL because the route, controller, and service do not exist yet.

**Step 2: Implement session create/show**

- `POST /app_api/conversation_observation_sessions`
- `GET /app_api/conversation_observation_sessions/:id`
- persist actor, target conversation, and responder strategy
- start with builtin responder only; reject unsupported strategies explicitly

**Step 3: Re-run the narrow tests**

Use the same command until green.

**Step 4: Commit**

- Commit message: `feat: expose conversation observation sessions through app api`

### Task 7: Add the observation message API and persist frame-backed exchanges

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/app_api/conversation_observation_messages_controller.rb`
- Create: `core_matrix/app/services/embedded_agents/conversation_observation/append_message.rb`
- Create: `core_matrix/test/requests/app_api/conversation_observation_messages_test.rb`
- Create: `core_matrix/test/services/embedded_agents/conversation_observation/append_message_test.rb`

**Step 1: Write failing request and service tests**

- posting a message:
  - creates a frame
  - creates the user observation message
  - creates the observer response message
  - returns `assessment`, `supervisor_status`, and `human_sidechat`
- listing messages returns side-session history only
- no transcript-bearing message is appended to the target conversation

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/embedded_agents/conversation_observation/append_message_test.rb test/requests/app_api/conversation_observation_messages_test.rb
```

Expected: FAIL because append-message orchestration and routes do not exist yet.

**Step 2: Implement append-message orchestration**

- authorize actor against session target
- create the frame first
- persist the user message
- build bundle and assessment
- persist the observer message with the same frame
- return the canonical response envelope

**Step 3: Re-run the narrow tests**

Use the same command until green.

**Step 4: Commit**

- Commit message: `feat: add observation message exchange api`

### Task 8: Add manual-acceptance helpers for the observation API

**Files:**
- Modify: `core_matrix/script/manual/manual_acceptance_support.rb`
- Modify: `core_matrix/test/lib/manual_acceptance_support_test.rb`

**Step 1: Write failing helper tests**

- add helper methods for:
  - creating an observation session
  - posting an observation message
- assert they call the new app API endpoints and return public-id-based payloads

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/manual_acceptance_support_test.rb
```

Expected: FAIL because the helper methods do not exist yet.

**Step 2: Implement the helper methods**

- add:
  - `app_api_create_conversation_observation_session!`
  - `app_api_append_conversation_observation_message!`
- keep the helpers thin and app-api-shaped

**Step 3: Re-run the narrow tests**

Use the same command until green.

**Step 4: Commit**

- Commit message: `feat: add manual acceptance helpers for conversation observation`

### Task 9: Switch the Fenix capstone scenario to supervisor-style observe polling

**Files:**
- Modify: `acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`
- Modify: `acceptance/lib/conversation_runtime_validation.rb` only if the result-shaping helper needs observe-aware proof handling

**Step 1: Write the failing acceptance-side supervision checks**

- replace the in-flight direct terminal waits used for progress supervision with
  an observe polling loop
- keep post-completion transcript, diagnostics, export/import, and host/browser
  checks intact
- capture both:
  - `supervisor_status` for machine decisions
  - `human_sidechat` for proof output

**Step 2: Implement the observe polling loop**

- create one observation session per target conversation
- poll by posting observation messages such as:
  - `"Summarize current progress for supervisor_status"`
- stop polling when:
  - `overall_state` becomes `completed`
  - `overall_state` becomes `failed`
  - `stall_for_ms` breaches the scenario threshold
- only then continue to the existing transcript and export assertions

**Step 3: Re-run the capstone scenario in the narrowest stable mode**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

Expected: the scenario should now treat observation as the truth for in-flight
progress and only use transcript/export diagnostics after completion.

**Step 4: Commit**

- Commit message: `feat: supervise capstone progress through observation api`

### Task 10: Update behavior docs and active plan indexes

**Files:**
- Create: `core_matrix/docs/behavior/conversation-observation-and-supervisor-status.md`
- Modify: `core_matrix/docs/behavior/human-interactions-and-conversation-events.md`
- Modify: `docs/design/README.md` only if the new behavior doc needs cross-linking
- Modify: `docs/plans/README.md`

**Step 1: Write the docs update after code shape stabilizes**

- document:
  - observation session semantics
  - frame and assessment shape
  - public-id-only response rules
  - lightweight runtime projection additions to `ConversationEvent`
  - acceptance-harness supervision flow

**Step 2: Update plan indexes**

- add this plan to the active plans index while it is still open

**Step 3: Commit**

- Commit message: `docs: record conversation observation behavior`

### Task 11: Self-review, blocker sweep, and full verification

**Files:**
- No code changes by default

**Step 1: Run a self-review pass before full verification**

- inspect the final diff for:
  - any raw internal-id exposure
  - any target-transcript mutation from observation
  - any accidental `control` semantics in the observe slice
  - any heavy snapshot payloads on frames
  - any direct database or filesystem reads left in the capstone in-flight
    supervision path
- if the review finds issues, fix them immediately and rerun the affected
  narrow tests before proceeding

**Step 2: Run targeted verification first**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/models/conversation_observation_session_test.rb \
  test/models/conversation_observation_frame_test.rb \
  test/models/conversation_observation_message_test.rb \
  test/services/embedded_agents/invoke_test.rb \
  test/services/embedded_agents/conversation_observation/authority_test.rb \
  test/services/conversation_runtime/publish_event_test.rb \
  test/services/embedded_agents/conversation_observation/build_frame_test.rb \
  test/services/embedded_agents/conversation_observation/build_bundle_test.rb \
  test/services/embedded_agents/conversation_observation/build_assessment_test.rb \
  test/services/embedded_agents/conversation_observation/responders/builtin_test.rb \
  test/services/embedded_agents/conversation_observation/append_message_test.rb \
  test/requests/app_api/conversation_observation_sessions_test.rb \
  test/requests/app_api/conversation_observation_messages_test.rb \
  test/lib/manual_acceptance_support_test.rb
```

Expected: PASS

**Step 3: Run full project verification once targeted tests are green**

For `core_matrix`:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
```

For `agents/fenix`:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare test
```

For `simple_inference`:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference
bundle exec rake
```

**Step 4: Re-run acceptance**

- run the Fenix 2048 capstone acceptance flow and confirm:
  - in-flight supervision goes through `observe`
  - the scenario records `supervisor_status` and `human_sidechat`
  - final transcript, diagnostics, export/import, and browser checks still pass

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

**Step 5: Final blocker review**

- verify no unresolved blocker remains for the shipped builtin path
- explicitly record deferred items, if any, as follow-up work rather than
  leaving them implicit
