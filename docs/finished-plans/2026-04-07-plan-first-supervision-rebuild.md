# Plan-First Supervision Rebuild Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild runtime and supervision so human-visible progress is anchored to persisted turn todo plans, with optional coarse fallback when no plan update exists, and add replayable supervision evaluation dumps to avoid full `2048` reruns during every iteration.

**Architecture:** Treat this as breaking cleanup. Remove the current heuristic path that infers product semantics from runtime details. `Core Matrix` should own safe reusable conversation context, generic runtime evidence, prompt payload construction, and replay dumps, while the `Agent` remains responsible only for the optional `turn_todo_plan_update` interface.

**Tech Stack:** Ruby, Rails service objects, Active Record, Minitest, JSON/public-id payloads, acceptance helpers, replayable artifact dumps

**Execution Notes:**
- Continue on the current branch: `codex/turn-todo-supervision`.
- Breaking cleanup is allowed. Delete or replace the current heuristic path instead of preserving compatibility.
- `turn_todo_plan_update` is optional. If it is absent, supervision must fall back to coarse runtime/lifecycle wording without inventing business semantics.
- Run Rails commands from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`.
- Run `git add` and `git commit` from `/Users/jasl/Workspaces/Ruby/cybros`.
- Use `test-driven-development`, `layered-rails`, `rails-active-record-patterns`, `verification-before-completion`, `systematic-debugging`, and `requesting-code-review` during implementation.
- Prefer replaying supervision from dumped evaluation bundles while iterating. Reserve full `2048` reruns for milestone checks and the final pass.

---

### Task 1: Lock in the new contract with failing tests

**Files:**
- Create: `core_matrix/test/services/conversation_supervision/build_context_snippets_test.rb`
- Create: `core_matrix/test/services/conversation_supervision/build_runtime_evidence_test.rb`
- Modify: `core_matrix/test/services/conversation_supervision/build_current_turn_todo_test.rb`
- Modify: `core_matrix/test/services/conversations/update_supervision_state_test.rb`
- Modify: `core_matrix/test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb`
- Modify: `core_matrix/test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb`
- Modify: `core_matrix/test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb`
- Modify: `core_matrix/test/lib/acceptance/conversation_artifacts_test.rb`

**Step 1: Add failing tests for context snippets**

Write tests for a new builder that consumes `Conversations::ContextProjection`
and emits safe reusable snippets such as:

```ruby
{
  "message_id" => "msg_public_123",
  "turn_id" => "turn_public_123",
  "role" => "user",
  "slot" => "input",
  "excerpt" => "Please make supervision plan-first and stop guessing from npm commands.",
  "keywords" => %w[make supervision plan first stop guessing npm commands]
}
```

Assert the builder does not emit benchmark-specific template summaries such as:

- `Context already references the 2048 acceptance flow.`
- `Context already references adding tests.`

**Step 2: Add failing tests for generic runtime evidence**

Write tests for a new runtime evidence builder that reports generic facts such
as:

```ruby
{
  "active_command" => {
    "command_run_public_id" => "cmd_public_123",
    "cwd" => "/workspace/game-2048",
    "command_preview" => "npm test && npm run build",
    "lifecycle_state" => "running"
  }
}
```

Assert it does not emit business guesses such as:

- `the React app`
- `game files`
- `the test-and-build check`

and does not special-case `npm install -g`.

**Step 3: Add failing plan-first supervision tests**

Update the supervision tests so they require:

- active plan item title is the primary current-work anchor when a plan exists
- recent progress prefers plan transition feed over runtime wording
- no-plan fallback remains coarse and generic
- `provider round`, `command_run_wait`, `React 2048 game`, `game files`, and
  package-manager-specific wording do not appear in default sidechat/status

**Step 4: Add a failing artifact test for replay dumps**

Extend `AcceptanceConversationArtifactsTest` so acceptance artifacts must write
one replayable supervision bundle containing:

- frozen machine status
- canonical plan view
- recent plan transitions
- context snippets
- runtime evidence
- question set

**Step 5: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/conversation_supervision/build_context_snippets_test.rb test/services/conversation_supervision/build_runtime_evidence_test.rb test/services/conversation_supervision/build_current_turn_todo_test.rb test/services/conversations/update_supervision_state_test.rb test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb test/lib/acceptance/conversation_artifacts_test.rb
```

Expected: FAIL because the current supervision stack still depends on heuristic
context summaries, heuristic runtime wording, and business-coupled fallback.

**Step 6: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/test/services/conversation_supervision/build_context_snippets_test.rb core_matrix/test/services/conversation_supervision/build_runtime_evidence_test.rb core_matrix/test/services/conversation_supervision/build_current_turn_todo_test.rb core_matrix/test/services/conversations/update_supervision_state_test.rb core_matrix/test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb core_matrix/test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb core_matrix/test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb core_matrix/test/lib/acceptance/conversation_artifacts_test.rb
git commit -m "test: require plan-first supervision contract"
```

### Task 2: Replace synthetic context facts with reusable context snippets

**Files:**
- Create: `core_matrix/app/services/conversation_supervision/build_context_snippets.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_snapshot.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_human_summary.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_human_sidechat.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/responders/summary_model.rb`
- Test: `core_matrix/test/services/conversation_supervision/build_context_snippets_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb`

**Step 1: Implement the pure context-snippet builder**

Create a service that converts the recent `Conversations::ContextProjection`
window into bounded snippets with:

- `message_id`
- `turn_id`
- `role`
- `slot`
- `excerpt`
- `keywords`

Do not generate sentence-level template summaries.

**Step 2: Replace `conversation_context_view.facts` with `context_snippets`**

Update snapshot bundling so the supervision payload carries reusable snippets
instead of heuristic facts.

**Step 3: Update human-summary and summary-model consumers**

Change the responder stack so it consumes snippets as supporting context only.
Do not let the context builder itself decide the business meaning.

**Step 4: Run the focused tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/conversation_supervision/build_context_snippets_test.rb test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/services/conversation_supervision/build_context_snippets.rb core_matrix/app/services/embedded_agents/conversation_supervision/build_snapshot.rb core_matrix/app/services/embedded_agents/conversation_supervision/build_human_summary.rb core_matrix/app/services/embedded_agents/conversation_supervision/build_human_sidechat.rb core_matrix/app/services/embedded_agents/conversation_supervision/responders/summary_model.rb core_matrix/test/services/conversation_supervision/build_context_snippets_test.rb core_matrix/test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb core_matrix/test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb
git commit -m "refactor: replace heuristic context facts with snippets"
```

### Task 3: Replace business-coupled runtime summaries with generic runtime evidence

**Files:**
- Create: `core_matrix/app/services/conversation_supervision/build_runtime_evidence.rb`
- Delete: `core_matrix/app/services/conversation_supervision/build_runtime_focus_hint.rb`
- Modify: `core_matrix/app/services/conversation_runtime/build_safe_activity_summary.rb`
- Modify: `core_matrix/app/services/conversations/update_supervision_state.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_machine_status.rb`
- Test: `core_matrix/test/services/conversation_supervision/build_runtime_evidence_test.rb`
- Test: `core_matrix/test/services/conversations/update_supervision_state_test.rb`

**Step 1: Implement the runtime evidence builder**

Create a service that emits generic evidence fields such as:

```ruby
{
  "active_command" => {
    "command_run_public_id" => command_run.public_id,
    "cwd" => "/workspace/game-2048",
    "command_preview" => "npm test && npm run build",
    "lifecycle_state" => "running"
  },
  "active_process" => nil,
  "recent_failure" => nil,
  "workflow_wait_state" => "waiting"
}
```

**Step 2: Downgrade `BuildSafeActivitySummary` to generic wording only**

Keep it only if needed for transcript/feed rendering, and rewrite it so it can
say at most things like:

- `Ran a shell command in /workspace/game-2048`
- `A process is still running in /workspace/game-2048`

Remove business-specific and package-manager-specific meaning.

**Step 3: Replace `runtime_focus_hint` with `runtime_evidence`**

Update supervision state and machine-status payloads so responders receive
generic runtime evidence instead of pre-humanized runtime focus text.

**Step 4: Run the focused tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/conversation_supervision/build_runtime_evidence_test.rb test/services/conversations/update_supervision_state_test.rb test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/services/conversation_supervision/build_runtime_evidence.rb core_matrix/app/services/conversation_runtime/build_safe_activity_summary.rb core_matrix/app/services/conversations/update_supervision_state.rb core_matrix/app/services/embedded_agents/conversation_supervision/build_machine_status.rb core_matrix/test/services/conversation_supervision/build_runtime_evidence_test.rb core_matrix/test/services/conversations/update_supervision_state_test.rb core_matrix/test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb core_matrix/test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb
git rm core_matrix/app/services/conversation_supervision/build_runtime_focus_hint.rb
git commit -m "refactor: replace runtime focus hints with runtime evidence"
```

### Task 4: Make persisted turn todo plans the only semantic supervision anchor

**Files:**
- Modify: `core_matrix/app/services/conversation_supervision/build_current_turn_todo.rb`
- Modify: `core_matrix/app/services/turn_todo_plans/build_feed_changeset.rb`
- Modify: `core_matrix/app/services/conversations/update_supervision_state.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_snapshot.rb`
- Modify: `core_matrix/test/services/conversation_supervision/build_current_turn_todo_test.rb`
- Modify: `core_matrix/test/services/conversations/update_supervision_state_test.rb`
- Modify: `core_matrix/test/requests/app_api/conversation_turn_todo_plans_controller_test.rb`
- Modify: `core_matrix/test/requests/app_api/conversation_turn_feeds_controller_test.rb`

**Step 1: Remove workflow-node-derived pseudo-plan semantics**

Update `BuildCurrentTurnTodo` so it does not synthesize business-looking plan
items from workflow nodes when no persisted `TurnTodoPlan` exists.

The new rule is:

- if persisted plan exists, use it
- otherwise return no semantic plan and let supervision use coarse fallback

**Step 2: Strengthen plan transition feed**

Adjust `TurnTodoPlans::BuildFeedChangeset` so recent plan transitions are the
canonical source for:

- current item started
- current item completed
- current item failed
- current item blocked

These summaries should be derived only from plan item titles.

**Step 3: Rebuild supervision-state derivation**

Set the persisted fields by this precedence:

- `current_focus_summary`: active plan item title, else coarse fallback
- `recent_progress_summary`: recent plan transition summary, else generic runtime
  completion evidence
- `waiting_summary`: runtime evidence only when the overall state is waiting or
  blocked

**Step 4: Run the focused tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/conversation_supervision/build_current_turn_todo_test.rb test/services/conversations/update_supervision_state_test.rb test/requests/app_api/conversation_turn_todo_plans_controller_test.rb test/requests/app_api/conversation_turn_feeds_controller_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/services/conversation_supervision/build_current_turn_todo.rb core_matrix/app/services/turn_todo_plans/build_feed_changeset.rb core_matrix/app/services/conversations/update_supervision_state.rb core_matrix/app/services/embedded_agents/conversation_supervision/build_snapshot.rb core_matrix/test/services/conversation_supervision/build_current_turn_todo_test.rb core_matrix/test/services/conversations/update_supervision_state_test.rb core_matrix/test/requests/app_api/conversation_turn_todo_plans_controller_test.rb core_matrix/test/requests/app_api/conversation_turn_feeds_controller_test.rb
git commit -m "refactor: make persisted plans the supervision anchor"
```

### Task 5: Rebuild builtin and model responders around canonical supervision payloads

**Files:**
- Create: `core_matrix/app/services/embedded_agents/conversation_supervision/responders/build_prompt_payload.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_human_summary.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_human_sidechat.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/responders/summary_model.rb`
- Modify: `core_matrix/test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb`
- Modify: `core_matrix/test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb`

**Step 1: Add a shared prompt-payload builder**

Create one service that freezes the responder input shape:

- `overall_state`
- `request_summary`
- `primary_turn_todo_plan`
- `recent_plan_transitions`
- `context_snippets`
- `runtime_evidence`
- `blocked_summary`
- `next_step_hint`

**Step 2: Rewrite builtin responder precedence**

Change builtin summary generation so it follows the same semantic ladder as the
model path:

- active plan item
- recent plan transitions
- context snippets for subject nouns only
- runtime evidence for wait/block/fallback only

**Step 3: Rewrite summary-model system prompt and user payload**

Adopt the absorbed prompt principles from Codex and Claude:

- answer only from frozen canonical payload
- respond in a single tool-free turn
- prefer plan semantics
- use runtime evidence only for justification
- never mention internal ids, workflow labels, providers, or tool names

**Step 4: Run the focused responder tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb test/services/embedded_agents/conversation_supervision/append_message_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/services/embedded_agents/conversation_supervision/responders/build_prompt_payload.rb core_matrix/app/services/embedded_agents/conversation_supervision/build_human_summary.rb core_matrix/app/services/embedded_agents/conversation_supervision/build_human_sidechat.rb core_matrix/app/services/embedded_agents/conversation_supervision/responders/summary_model.rb core_matrix/test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb core_matrix/test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb core_matrix/test/services/embedded_agents/conversation_supervision/append_message_test.rb
git commit -m "refactor: rebuild supervision responders around canonical payloads"
```

### Task 6: Add replayable supervision evaluation dumps and offline replay tooling

**Files:**
- Create: `acceptance/lib/supervision_eval_replay.rb`
- Create: `acceptance/bin/replay_supervision_eval.sh`
- Modify: `acceptance/lib/conversation_artifacts.rb`
- Modify: `acceptance/lib/turn_runtime_transcript.rb`
- Modify: `acceptance/lib/live_progress_feed.rb`
- Modify: `core_matrix/test/lib/acceptance/conversation_artifacts_test.rb`
- Create: `core_matrix/test/lib/acceptance/supervision_eval_replay_test.rb`

**Step 1: Add a replayable evaluation bundle export**

Extend artifact generation so each fresh run writes a JSON bundle such as:

- `review/supervision-eval-bundle.json`

containing:

- machine status
- primary plan
- recent plan transitions
- context snippets
- runtime evidence
- canned sidechat questions
- expected contract flags

**Step 2: Add an offline replay runner**

Create a helper and shell entry point that:

- reads the exported bundle
- reruns builtin/model supervision renderers against it
- rewrites the review markdown files
- reruns supervision contract assertions without a fresh `2048` run

**Step 3: Update transcript/feed helpers to consume canonical payloads**

Make acceptance rendering helpers read plan transitions and generic runtime
evidence from the dumped bundle instead of re-deriving their own special-case
wording.

**Step 4: Run the focused acceptance-helper tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/acceptance/conversation_artifacts_test.rb test/lib/acceptance/supervision_eval_replay_test.rb test/lib/acceptance/turn_runtime_transcript_test.rb test/lib/acceptance/live_progress_feed_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add acceptance/lib/supervision_eval_replay.rb acceptance/bin/replay_supervision_eval.sh acceptance/lib/conversation_artifacts.rb acceptance/lib/turn_runtime_transcript.rb acceptance/lib/live_progress_feed.rb core_matrix/test/lib/acceptance/conversation_artifacts_test.rb core_matrix/test/lib/acceptance/supervision_eval_replay_test.rb core_matrix/test/lib/acceptance/turn_runtime_transcript_test.rb core_matrix/test/lib/acceptance/live_progress_feed_test.rb
git commit -m "feat: add replayable supervision evaluation dumps"
```

### Task 7: Rewire the `2048` acceptance gate around the new canonical payloads

**Files:**
- Modify: `acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`
- Modify: `core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb`
- Modify: `core_matrix/test/lib/fresh_start_stack_contract_test.rb`

**Step 1: Add failing gate assertions for the new contract**

Require the final bundle to prove:

- supervision uses persisted plan semantics when present
- no human-visible supervision wording depends on `provider round`,
  `command_run_wait`, `React app`, `game files`, or package-manager-specific
  labels
- replay bundle exists and is complete

**Step 2: Use replay during local iteration**

Run one fresh acceptance only after the previous tasks are integrated:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

If the gate fails, use:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/replay_supervision_eval.sh /absolute/path/to/review/supervision-eval-bundle.json
```

Expected: replay reproduces supervision wording and contract failures without a
new full benchmark run.

**Step 3: Tighten the final gate once replay passes**

Update the scenario assertions so the final green run requires the new
plan-first supervision contract.

**Step 4: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb core_matrix/test/lib/fresh_start_stack_contract_test.rb
git commit -m "test: enforce plan-first supervision acceptance contract"
```

### Task 8: Run full verification, complete one fresh acceptance, and request code review

**Files:**
- Modify as needed: any failing files discovered during verification
- Review: all files touched in Tasks 1-7

**Step 1: Run the full project verification suite**

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

**Step 2: Run one fresh full `2048` acceptance**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

Expected: PASS with a fresh final artifact bundle and replayable supervision
evaluation dump.

**Step 3: If anything fails unexpectedly, switch to `systematic-debugging`**

Do not patch blindly. Capture:

- failing assertion
- dumped supervision bundle path
- exact runtime evidence
- exact plan view

Use replay first when the failure is in supervision wording.

**Step 4: Run `requesting-code-review` before final wrap-up**

Review for:

- residual business-coupled heuristics
- hidden package-manager or framework assumptions
- drift between builtin and model responder precedence
- replay bundle completeness

**Step 5: Commit the final cleanups**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add acceptance core_matrix
git commit -m "feat: complete plan-first supervision rebuild"
```

**Step 6: Record final evidence in the handoff**

Include:

- final artifact path
- replay bundle path
- full verification commands run
- any remaining non-blocking limitations

## Reference Alignment Checklist

Before implementation starts, verify that the design and code changes absorb
these principles:

- Codex: plan updates are first-class app-facing events
- Codex: checklist progress is durable and sufficient without extra semantic
  agent interfaces
- Claude: current todo is the strongest current-work anchor
- Claude: sidechat-style replies are derived from safe reusable main-thread
  context, not from raw runtime internals
- Both: runtime evidence remains available, but is not the primary semantic
  source

If any task introduces a new agent-side semantic interface beyond
`turn_todo_plan_update`, stop and rewrite the task before implementing it.
