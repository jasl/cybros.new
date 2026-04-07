# Fenix Runtime and Supervision UI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current low-information runtime and supervision wording with one canonical turn event stream plus one semantic supervision view that power cowork mode, verbose mode, and the `2048` acceptance gate.

**Architecture:** Build a canonical `TurnEventStream` read model in `core_matrix`, make acceptance runtime projections render from it, then rebuild supervision on top of enriched semantic summaries instead of raw workflow/tool labels. Treat this as breaking cleanup: remove or bypass old observation-era wording paths instead of preserving compatibility shims.

**Tech Stack:** Ruby, Rails service objects, Active Record, JSON/public-id boundaries, acceptance helpers, Minitest, app API request tests

**Execution Notes:**
- Keep the existing persisted `ConversationSupervisionState` column names such as `current_focus_summary` and `recent_progress_summary` in this follow-up. Add semantic runtime enrichment without introducing a schema rename.
- Keep `conversation_turn_feeds` as the app-facing supervision feed surface. Add a separate runtime-event endpoint for `TurnEventStream`; do not overload the existing turn-feed API with the runtime timeline contract.
- Run Rails/test commands from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`, but run `git add` / `git commit` from `/Users/jasl/Workspaces/Ruby/cybros` because the write set spans both `core_matrix/` and top-level `acceptance/`.
- If verification or the fresh `2048` acceptance rerun fails in an unexpected way, switch to `systematic-debugging` before applying follow-up fixes.

---

### Task 1: Add failing contract coverage for semantic runtime and supervision wording

**Files:**
- Modify: `core_matrix/test/lib/acceptance/turn_runtime_transcript_test.rb`
- Modify: `core_matrix/test/lib/acceptance/live_progress_feed_test.rb`
- Modify: `core_matrix/test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb`
- Modify: `core_matrix/test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb`
- Modify: `core_matrix/test/services/embedded_agents/conversation_supervision/append_message_test.rb`

**Step 1: Add a failing runtime transcript assertion for safe command summaries**

Extend `AcceptanceTurnRuntimeTranscriptTest` so command-backed entries must
show user-facing summaries such as:

- `Ran the test-and-build check in /workspace/game-2048`
- `Started the preview server in /workspace/game-2048`

and no longer rely on raw tool names or workflow node keys for the primary
summary.

**Step 2: Add a failing live progress assertion for semantic summaries plus exact refs**

Extend `AcceptanceLiveProgressFeedTest` so normalized entries expose both:

- a safe human summary
- exact refs like `command_run_public_id` / `workflow_node_key` for verbose or
  debug inspection

Assert that `command_run_wait` and `provider_round_*` are not the primary
human-visible summary text.

**Step 3: Add failing supervision responder assertions for low-information leaks**

Update the builtin, summary-model, and append-message tests so they fail unless:

- `provider round` wording is absent from the sidechat content
- `command_run_wait` is absent from the sidechat content
- waiting on a command mentions the command purpose or a safe command summary
- command/process waits are described in user language

**Step 4: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/acceptance/turn_runtime_transcript_test.rb test/lib/acceptance/live_progress_feed_test.rb test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb test/services/embedded_agents/conversation_supervision/append_message_test.rb
```

Expected: FAIL because the current runtime and supervision wording is still too
close to raw workflow/tool labels.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/test/lib/acceptance/turn_runtime_transcript_test.rb core_matrix/test/lib/acceptance/live_progress_feed_test.rb core_matrix/test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb core_matrix/test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb core_matrix/test/services/embedded_agents/conversation_supervision/append_message_test.rb
git commit -m "test: require semantic runtime and supervision wording"
```

### Task 2: Introduce the canonical turn event stream builder

**Files:**
- Create: `core_matrix/app/services/conversation_runtime/build_turn_event_stream.rb`
- Create: `core_matrix/app/services/conversation_runtime/build_safe_activity_summary.rb`
- Create: `core_matrix/test/services/conversation_runtime/build_turn_event_stream_test.rb`
- Create: `core_matrix/test/services/conversation_runtime/build_safe_activity_summary_test.rb`

**Step 1: Write the failing pure projection tests**

Add tests for a builder that accepts normalized turn inputs and emits a linear
event stream with fields like:

```ruby
{
  "sequence" => 12,
  "actor_type" => "main_agent",
  "actor_label" => "main",
  "family" => "command_activity",
  "kind" => "command_completed",
  "summary" => "Ran the test-and-build check in /workspace/game-2048",
  "detail" => "Command completed successfully.",
  "command_run_public_id" => "cmd_public_123",
  "workflow_node_key" => "provider_round_6_tool_1",
}
```

Also add safe-summary tests for:

- `npm test`
- `npm test && npm run build`
- `npm run preview`
- long heredoc file-write commands
- generic directory inspection commands

**Step 2: Run the new tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/conversation_runtime/build_turn_event_stream_test.rb test/services/conversation_runtime/build_safe_activity_summary_test.rb
```

Expected: FAIL because no canonical turn event stream builder exists yet.

**Step 3: Implement the event stream builder**

Create a pure projection service that:

- accepts normalized messages, workflow-node events, tool invocations,
  command runs, process runs, subagent updates, supervision checkpoints, host
  validation milestones, and artifact milestones
- emits one ordered linear event stream
- preserves exact refs for verbose/debug surfaces
- carries safe summaries for cowork/supervision surfaces

Keep classification logic out of controllers and acceptance helpers.

**Step 4: Implement the safe activity summarizer**

Create a companion summarizer that converts low-level activity into user-safe
categories such as:

- `running tests`
- `running the test-and-build check`
- `starting the preview server`
- `editing game files`
- `inspecting the workspace`

The summarizer must never use raw `provider_round_*` or snake_case tool names
as the primary summary.

**Step 5: Re-run the new tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/services/conversation_runtime/build_turn_event_stream_test.rb test/services/conversation_runtime/build_safe_activity_summary_test.rb
```

Expected: PASS.

**Step 6: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/services/conversation_runtime/build_turn_event_stream.rb core_matrix/app/services/conversation_runtime/build_safe_activity_summary.rb core_matrix/test/services/conversation_runtime/build_turn_event_stream_test.rb core_matrix/test/services/conversation_runtime/build_safe_activity_summary_test.rb
git commit -m "feat: add canonical turn event stream builder"
```

### Task 3: Route acceptance runtime projections through the canonical event stream

**Files:**
- Modify: `acceptance/lib/turn_runtime_transcript.rb`
- Modify: `acceptance/lib/live_progress_feed.rb`
- Modify: `acceptance/lib/conversation_artifacts.rb`
- Modify: `core_matrix/test/lib/acceptance/turn_runtime_transcript_test.rb`
- Modify: `core_matrix/test/lib/acceptance/live_progress_feed_test.rb`

**Step 1: Write the failing adapter assertions**

Extend the acceptance tests so they prove:

- runtime transcript sections are built from canonical stream entries
- live progress feed entries share the same summary vocabulary
- exact refs remain available for debug joins
- human-visible summaries no longer depend on duplicated helper-specific
  humanization rules

**Step 2: Run the acceptance helper tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/acceptance/turn_runtime_transcript_test.rb test/lib/acceptance/live_progress_feed_test.rb
```

Expected: FAIL because the acceptance helpers still normalize runtime activity
independently.

**Step 3: Replace duplicate normalization with the shared event stream**

Modify the acceptance helpers so they become thin renderers over
`ConversationRuntime::BuildTurnEventStream`:

- `turn_runtime_transcript.rb` should render grouped sections from the shared
  stream
- `live_progress_feed.rb` should emit incremental entries from the same summary
  vocabulary
- `conversation_artifacts.rb` should read the shared fields instead of
  re-deriving its own wording

Do not preserve old helper-only summary builders.

**Step 4: Re-run the helper tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/lib/acceptance/turn_runtime_transcript_test.rb test/lib/acceptance/live_progress_feed_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add acceptance/lib/turn_runtime_transcript.rb acceptance/lib/live_progress_feed.rb acceptance/lib/conversation_artifacts.rb core_matrix/test/lib/acceptance/turn_runtime_transcript_test.rb core_matrix/test/lib/acceptance/live_progress_feed_test.rb
git commit -m "refactor: route acceptance runtime projections through turn event stream"
```

### Task 4: Extend supervision state with semantic runtime focus and recent progress

**Files:**
- Create: `core_matrix/app/services/conversation_supervision/build_runtime_focus_hint.rb`
- Modify: `core_matrix/app/services/conversation_supervision/build_current_turn_todo.rb`
- Modify: `core_matrix/app/services/conversations/update_supervision_state.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_snapshot.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_machine_status.rb`
- Modify: `core_matrix/test/services/conversation_supervision/build_activity_feed_test.rb`
- Modify: `core_matrix/test/requests/app_api/conversation_turn_feeds_controller_test.rb`
- Test: `core_matrix/test/services/conversations/update_supervision_state_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb`

**Step 1: Add failing supervision state tests for runtime focus hints**

Add tests that prove provider-backed turns freeze fields like:

```ruby
{
  "runtime_focus_hint" => {
    "kind" => "command_wait",
    "summary" => "waiting for the test-and-build check in /workspace/game-2048",
    "command_run_id" => "cmd_public_123"
  }
}
```

Also assert that current/recent summaries prefer semantic wording over:

- `Advance provider round N`
- `Run command_run_wait`

Extend the supervision-feed tests so they prove:

- `BuildActivityFeed` remains the canonical current-turn feed for supervision
- `conversation_turn_feeds` still returns turn-feed entries rather than the new
  runtime timeline
- runtime-focus enrichment improves the feed summaries without changing the
  endpoint family

**Step 2: Run the projection tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/conversations/update_supervision_state_test.rb test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb
```

Expected: FAIL because snapshots do not yet freeze semantic runtime focus.

**Step 3: Implement runtime focus hint projection**

Create a projector that derives, when justified:

- active command summary
- active process summary
- host-validation step summary
- semantic waiting reason

Use exact refs for grounding, but expose safe summaries for supervision text.

**Step 4: Thread the new fields through supervision state and snapshots**

Update the supervision projection so:

- persisted `current_focus_summary` can prefer plan item or runtime focus hint
- `recent_progress_summary` can prefer semantic milestones from the runtime
  stream
- machine status freezes `runtime_focus_hint` and related grounding fields
- `BuildActivityFeed` and `conversation_turn_feeds` remain the supervision-feed
  surface instead of becoming the runtime timeline API

Keep `TurnTodoPlan` and `turn_feed` as the plan/feed truth. The runtime focus
hint is an enrichment layer, not a replacement plan domain. Do not add a
schema migration in this follow-up.

**Step 5: Re-run the projection tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/services/conversations/update_supervision_state_test.rb test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb test/services/conversation_supervision/build_activity_feed_test.rb test/requests/app_api/conversation_turn_feeds_controller_test.rb
```

Expected: PASS.

**Step 6: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/services/conversation_supervision/build_runtime_focus_hint.rb core_matrix/app/services/conversation_supervision/build_current_turn_todo.rb core_matrix/app/services/conversations/update_supervision_state.rb core_matrix/app/services/embedded_agents/conversation_supervision/build_snapshot.rb core_matrix/app/services/embedded_agents/conversation_supervision/build_machine_status.rb core_matrix/test/services/conversations/update_supervision_state_test.rb core_matrix/test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb core_matrix/test/services/conversation_supervision/build_activity_feed_test.rb core_matrix/test/requests/app_api/conversation_turn_feeds_controller_test.rb
git commit -m "feat: add semantic runtime focus to supervision snapshots"
```

### Task 5: Rebuild sidechat and summary-model responses on semantic supervision data

**Files:**
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_human_sidechat.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_human_summary.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/responders/summary_model.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/append_message_test.rb`

**Step 1: Add explicit failing sidechat examples**

Update tests so they require wording like:

- `I’m continuing the 2048 app implementation.`
- `Most recently, the test run finished.`
- `I’m waiting for the test-and-build check in /workspace/game-2048 to finish.`

and reject wording like:

- `provider round 6`
- `command_run_wait`
- `process_exec`

**Step 2: Run the sidechat tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb test/services/embedded_agents/conversation_supervision/append_message_test.rb
```

Expected: FAIL because sidechat still consumes low-information summaries.

**Step 3: Replace the current wording logic**

Rebuild the renderers so they answer from semantic supervision fields in this
order:

1. current work
2. most recent meaningful change
3. waiting / blocker reason when relevant
4. next justified step when supported

Remove fallback branches that humanize raw workflow/tool labels into visible
sidechat content.

**Step 4: Re-run the sidechat tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb test/services/embedded_agents/conversation_supervision/append_message_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/services/embedded_agents/conversation_supervision/build_human_sidechat.rb core_matrix/app/services/embedded_agents/conversation_supervision/build_human_summary.rb core_matrix/app/services/embedded_agents/conversation_supervision/responders/summary_model.rb core_matrix/test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb core_matrix/test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb core_matrix/test/services/embedded_agents/conversation_supervision/append_message_test.rb
git commit -m "feat: render supervision replies from semantic runtime summaries"
```

### Task 6: Expose app-facing turn runtime events for the Fenix UI

**Files:**
- Create: `core_matrix/app/controllers/app_api/conversation_turn_runtime_events_controller.rb`
- Modify: `core_matrix/config/routes.rb`
- Test: `core_matrix/test/requests/app_api/conversation_turn_runtime_events_controller_test.rb`

**Step 1: Add a failing request test for the runtime event stream endpoint**

Add a request test for:

```ruby
get app_api_conversation_turn_runtime_events_path(
  conversation_id: fixture.fetch(:conversation).public_id,
  turn_id: fixture.fetch(:turn).public_id
)
```

Assert the payload includes:

- ordered runtime events
- lane labels
- safe summaries
- exact refs for debug usage

**Step 2: Run the request test to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/app_api/conversation_turn_runtime_events_controller_test.rb
```

Expected: FAIL because no app-facing runtime-event endpoint exists yet.

**Step 3: Implement the controller and route**

Expose the canonical turn event stream through an app API endpoint.

The endpoint should:

- return stable `public_id` boundaries only
- preserve exact refs for verbose/debug renderers
- return safe summaries for cowork renderers
- avoid re-deriving summaries in the controller

Keep the existing `conversation_turn_feeds` endpoint untouched except for any
shared helper reuse that preserves its supervision-feed contract.

**Step 4: Re-run the request test to verify it passes**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/requests/app_api/conversation_turn_runtime_events_controller_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/controllers/app_api/conversation_turn_runtime_events_controller.rb core_matrix/config/routes.rb core_matrix/test/requests/app_api/conversation_turn_runtime_events_controller_test.rb
git commit -m "feat: expose turn runtime events for the app ui"
```

### Task 7: Harden the `2048` acceptance gate around semantic supervision and runtime alignment

**Files:**
- Modify: `acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`
- Modify: `acceptance/lib/conversation_artifacts.rb`
- Modify: `core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb`

**Step 1: Add failing acceptance contract assertions**

Update contract coverage so the `2048` bundle fails unless:

- `review/supervision-sidechat.md` avoids `provider round` and raw tool names
- wait-state sidechat mentions a command/process purpose when evidence supports it
- `review/turn-runtime-transcript.md` still preserves the runtime story
- runtime and supervision artifacts agree on the current work narrative without
  requiring identical sentences

**Step 2: Run the contract test to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/fenix_capstone_acceptance_contract_test.rb
```

Expected: FAIL because the acceptance gate does not yet require these stronger
semantic guarantees.

**Step 3: Implement the stronger acceptance gate**

Modify the `2048` scenario and review artifact helpers so they enforce:

- cowork-safe supervision wording
- semantic command/process wait descriptions
- preserved exact refs in debug/runtime artifacts

Do not keep compatibility with the weaker low-information wording.

**Step 4: Re-run the contract test to verify it passes**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/lib/fenix_capstone_acceptance_contract_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb acceptance/lib/conversation_artifacts.rb core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb
git commit -m "test: harden 2048 semantic runtime and supervision gate"
```

### Task 8: Run the integrated verification sweep and close out the follow-up

**Files:**
- Modify as needed from earlier tasks only; do not start new compatibility work

**Step 1: Run the focused feature suite**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/services/conversation_runtime/build_turn_event_stream_test.rb test/services/conversation_runtime/build_safe_activity_summary_test.rb test/lib/acceptance/turn_runtime_transcript_test.rb test/lib/acceptance/live_progress_feed_test.rb test/services/conversations/update_supervision_state_test.rb test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb test/services/conversation_supervision/build_activity_feed_test.rb test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb test/services/embedded_agents/conversation_supervision/append_message_test.rb test/requests/app_api/conversation_turn_feeds_controller_test.rb test/requests/app_api/conversation_turn_runtime_events_controller_test.rb test/lib/fenix_capstone_acceptance_contract_test.rb
```

Expected: PASS.

**Step 2: Run project verification**

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

Expected: PASS.

**Step 3: Run the fresh `2048` acceptance scenario**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

Expected: PASS with:

- high-information supervision sidechat
- semantic command/process wait wording
- preserved verbose/debug command refs
- green `2048` hard gate

**Step 4: Request code review before wrapping up**

Review the final diff against:

- `/Users/jasl/Workspaces/Ruby/cybros/docs/proposed-designs/2026-04-06-fenix-app-ui-contract.md`
- this implementation plan

Fix important findings before closeout.

**Step 5: Commit the closeout changes**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add .
git commit -m "feat: unify fenix runtime and supervision ui projections"
```
