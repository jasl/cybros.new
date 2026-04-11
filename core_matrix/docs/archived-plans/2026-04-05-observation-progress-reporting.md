# Observation Progress Reporting Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `ObservationConversation` answer progress questions in user-facing natural language without leaking internal workflow structure, while preserving machine-facing proof and strengthening acceptance coverage.

**Architecture:** Freeze a new semantic `work_context_view` inside the observation bundle snapshot, derive user-facing summaries from the current turn and runtime state, and refactor `BuildHumanSidechat` / `BuildHumanSummary` to narrate from that semantic layer instead of humanizing internal tokens. Tighten the acceptance leak scan so internal workflow vocabulary in human-visible text fails the 2048 artifact checks.

**Tech Stack:** Rails 8.2, Active Record, Minitest, Ruby services under `app/services`, root-level acceptance scenario script

---

### Task 1: Add a semantic work-context builder with red tests first

**Files:**
- Create: `app/services/embedded_agents/conversation_observation/build_work_context_view.rb`
- Create: `test/services/embedded_agents/conversation_observation/build_work_context_view_test.rb`
- Modify: `test/services/embedded_agents/conversation_observation/build_bundle_test.rb`

**Step 1: Write the failing builder tests**

Add focused tests that prove the new builder produces user-facing summaries from
current-turn and runtime evidence without retaining raw transcript text or
internal tokens.

```ruby
test "builds request, waiting, subagent, and next-step summaries without internal token leaks" do
  fixture = build_observation_fixture_for_work_context!

  work_context = EmbeddedAgents::ConversationObservation::BuildWorkContextView.call(
    anchor_turn: fixture.fetch(:current_turn),
    workflow_run: fixture.fetch(:workflow_run),
    workflow_node: fixture.fetch(:workflow_node),
    activity_items: fixture.fetch(:activity_items),
    active_subagent_connections: [fixture.fetch(:subagent_connection)]
  )

  assert_equal "improve the observation progress report for users", work_context.fetch("request_summary")
  assert_equal "waiting", work_context.fetch("work_type")
  assert_equal "I am waiting for a helper task to finish before I can continue.", work_context.fetch("waiting_summary")
  assert_equal "A helper task is still running for this request.", work_context.fetch("subagent_summary")
  assert_equal "Once that result is back, I will continue the main task.", work_context.fetch("next_step_hint")

  combined = work_context.values.compact.join(" ")
  refute_match(/provider_round|tool_|runtime\.|subagent_barrier/i, combined)
  refute_includes combined, fixture.fetch(:current_turn).selected_input_message.content
end
```

Also add a second test proving `next_step_hint` is omitted when the snapshot
does not justify it.

**Step 2: Run the new tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/embedded_agents/conversation_observation/build_work_context_view_test.rb
```

Expected: FAIL because `BuildWorkContextView` does not exist yet.

**Step 3: Write the minimal builder**

Implement `BuildWorkContextView` with a compact public contract:

```ruby
{
  "request_summary" => summarize_request(anchor_turn.selected_input_message&.content),
  "work_type" => classify_work_type(workflow_run:, workflow_node:, activity_items:),
  "current_focus_summary" => current_focus_summary(...),
  "recent_progress_summary" => recent_progress_summary(...),
  "waiting_summary" => waiting_summary(...),
  "subagent_summary" => subagent_summary(...),
  "next_step_hint" => next_step_hint(...)
}.compact
```

Rules:

- summarize the selected input message; do not store the original text
- classify work as one of `research`, `implementation`, `testing`, `waiting`, `completed`, `failed`, `general`
- translate wait reasons into user language
- summarize subagent work in user language
- only set `next_step_hint` when evidence clearly supports it

**Step 4: Run the builder tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/embedded_agents/conversation_observation/build_work_context_view_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add app/services/embedded_agents/conversation_observation/build_work_context_view.rb test/services/embedded_agents/conversation_observation/build_work_context_view_test.rb
git commit -m "feat: add observation work context summaries"
```

### Task 2: Freeze `work_context_view` in the bundle snapshot

**Files:**
- Modify: `app/services/embedded_agents/conversation_observation/build_bundle_snapshot.rb`
- Modify: `app/services/embedded_agents/conversation_observation/build_bundle.rb`
- Modify: `test/services/embedded_agents/conversation_observation/build_bundle_test.rb`

**Step 1: Extend bundle tests first**

Update `build_bundle_test.rb` so the frozen bundle now requires a
`work_context_view` payload and proves it contains only semantic summaries.

```ruby
assert_equal %w[activity_view subagent_view transcript_view work_context_view workflow_view], bundle.keys.sort

work_context = bundle.fetch("work_context_view")
assert_equal "improve the observation progress report for users", work_context.fetch("request_summary")
refute_includes work_context.values.compact.join(" "), "Fix the observation progress report so it reads naturally for users."
refute_match(/provider_round|tool_|runtime\.|subagent_barrier/i, work_context.values.compact.join(" "))
```

**Step 2: Run the bundle test to verify it fails**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/embedded_agents/conversation_observation/build_bundle_test.rb
```

Expected: FAIL because the bundle does not yet include `work_context_view`.

**Step 3: Wire the builder into the snapshot**

Update `BuildBundleSnapshot#call`:

```ruby
{
  "transcript_view" => transcript_view,
  "workflow_view" => workflow_view,
  "activity_view" => activity_view,
  "subagent_view" => subagent_view,
  "work_context_view" => work_context_view,
}
```

Add a private helper:

```ruby
def work_context_view
  EmbeddedAgents::ConversationObservation::BuildWorkContextView.call(
    anchor_turn: @anchor_turn,
    workflow_run: @workflow_run,
    workflow_node: @workflow_node,
    activity_items: activity_events,
    active_subagent_connections: @active_subagent_connections
  )
end
```

Prefer reusing one `activity_events` collection for both `activity_view` and
`work_context_view` so snapshot and semantic narration are derived from the same
frozen evidence.

**Step 4: Run the bundle tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/embedded_agents/conversation_observation/build_bundle_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add app/services/embedded_agents/conversation_observation/build_bundle_snapshot.rb test/services/embedded_agents/conversation_observation/build_bundle_test.rb
git commit -m "feat: freeze observation work context in snapshots"
```

### Task 3: Refactor human narration to use semantic summaries

**Files:**
- Modify: `app/services/embedded_agents/conversation_observation/build_human_sidechat.rb`
- Modify: `app/services/embedded_agents/conversation_observation/build_human_summary.rb`
- Modify: `app/services/embedded_agents/conversation_observation/responders/builtin.rb`
- Modify: `test/services/embedded_agents/conversation_observation/responders/builtin_test.rb`
- Modify: `test/services/embedded_agents/conversation_observation/append_message_test.rb`

**Step 1: Write failing responder tests**

Extend `responders/builtin_test.rb` so progress questions assert human-facing
language and reject internal tokens.

```ruby
test "progress questions use semantic summaries instead of internal workflow tokens" do
  response = EmbeddedAgents::ConversationObservation::RouteResponder.call(...)

  content = response.dig("human_sidechat", "content")
  assert_includes content, "I am working on the observation progress report for this request."
  assert_includes content, "I am waiting for a helper task to finish before I can continue."
  refute_match(/provider_round|tool_|runtime\.|subagent_barrier/i, content)
end

test "next-step questions report a conservative next step only when the snapshot supports it" do
  response = EmbeddedAgents::ConversationObservation::RouteResponder.call(
    ...,
    question: "What will you do next?"
  )

  assert_includes response.dig("human_sidechat", "content"), "Once that result is back, I will continue the main task."
end
```

Add a complementary test proving a snapshot with no clear next step omits that
sentence.

Update `append_message_test.rb` to assert the persisted observer message does
not contain internal workflow vocabulary.

**Step 2: Run the responder tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/embedded_agents/conversation_observation/responders/builtin_test.rb test/services/embedded_agents/conversation_observation/append_message_test.rb
```

Expected: FAIL because the current responder still emits humanized internal
tokens.

**Step 3: Implement the narrator changes**

Refactor `BuildHumanSidechat` so it reads `work_context_view` from
`@observation_bundle` and builds sentences from:

- `current_focus_summary`
- `recent_progress_summary`
- `waiting_summary`
- `subagent_summary`
- `next_step_hint`

Add a `NEXT_STEP_KEYWORDS` / `NEXT_STEP_PHRASES` topic matcher for questions
such as:

```ruby
NEXT_STEP_KEYWORDS = %w[next then upcoming after].freeze
NEXT_STEP_PHRASES = ["what next", "what will you do next", "接下来", "下一步"].freeze
```

Refactor `BuildHumanSummary` to use the same semantic fields so fallback
summaries also avoid internal token leaks.

Keep grounding text, but make it user-facing:

```ruby
"This update is based on the current work state, recent execution progress, and available context."
```

**Step 4: Run the responder tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/embedded_agents/conversation_observation/responders/builtin_test.rb test/services/embedded_agents/conversation_observation/append_message_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add app/services/embedded_agents/conversation_observation/build_human_sidechat.rb app/services/embedded_agents/conversation_observation/build_human_summary.rb app/services/embedded_agents/conversation_observation/responders/builtin.rb test/services/embedded_agents/conversation_observation/responders/builtin_test.rb test/services/embedded_agents/conversation_observation/append_message_test.rb
git commit -m "feat: narrate observation progress in user language"
```

### Task 4: Tighten the acceptance leak scan for internal workflow vocabulary

**Files:**
- Modify: `acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`
- Modify: `core_matrix/test/lib/fresh_start_stack_contract_test.rb`
- Modify: `core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb`

**Step 1: Write failing contract tests**

Add script-contract assertions that the acceptance scenario now treats internal
workflow vocabulary as suspicious in human-visible observation text.

```ruby
test "capstone scenario flags internal workflow tokens in observation sidechat" do
  script = Rails.root.join("../acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb").read

  assert_match(/provider_round/, script)
  assert_match(/tool_/, script)
  assert_match(/runtime\\\./, script)
  assert_match(/subagent_barrier/, script)
end
```

The assertion can be more specific if the final helper uses a named pattern
array or constant; prefer checking the helper contract rather than generic file
text when possible.

**Step 2: Run the contract tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/fresh_start_stack_contract_test.rb test/lib/fenix_capstone_acceptance_contract_test.rb
```

Expected: FAIL because the current leak scan only checks long numbers and UUIDs.

**Step 3: Expand `human_visible_leak_tokens`**

Update the acceptance scenario helper so it catches internal workflow structure
in user-visible observation text. A minimal version is:

```ruby
def suspicious_internal_tokens(text)
  return [] if text.blank?

  patterns = [
    /\bprovider_round(?:_[a-z0-9]+)*\b/i,
    /\btool_[a-z0-9_]+\b/i,
    /\bruntime\.[a-z0-9_.]+\b/i,
    /\bsubagent_barrier\b/i,
    /\bexternal_dependency_blocked\b/i,
    /\bmanual_recovery_required\b/i,
    /\bagent_unavailable\b/i,
  ]

  patterns.flat_map { |pattern| text.scan(pattern) }.uniq
end
```

Keep `public_id_tokens` intact so the scan still catches UUID leaks too.

**Step 4: Run the contract tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/fresh_start_stack_contract_test.rb test/lib/fenix_capstone_acceptance_contract_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb core_matrix/test/lib/fresh_start_stack_contract_test.rb core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb
git commit -m "test: catch observation workflow token leaks"
```

### Task 5: Run verification, inspect artifacts, and finish the branch cleanly

**Files:**
- Inspect: `acceptance/artifacts/*/observation-conversation.md`
- Inspect: `acceptance/artifacts/*/observation-final.json`
- Inspect: `acceptance/artifacts/*/run-summary.json`

**Step 1: Run targeted observation tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/services/embedded_agents/conversation_observation/build_work_context_view_test.rb \
  test/services/embedded_agents/conversation_observation/build_bundle_test.rb \
  test/services/embedded_agents/conversation_observation/responders/builtin_test.rb \
  test/services/embedded_agents/conversation_observation/append_message_test.rb \
  test/lib/fresh_start_stack_contract_test.rb \
  test/lib/fenix_capstone_acceptance_contract_test.rb
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
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
```

Expected: PASS.

**Step 3: Run the 2048 acceptance flow**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

Expected: PASS and produce a fresh artifact directory.

**Step 4: Inspect the observation artifacts**

Verify in the generated `observation-conversation.md` that:

- human sidechat talks about the request and work
- internal terms such as `provider_round_*`, `tool_*`, `runtime.*`, and
  `subagent_barrier` do not appear in human-visible text
- if a next-step sentence appears, it is evidence-backed and conservative

**Step 5: Final cleanup and commit**

If verification or acceptance required small follow-up fixes, commit them with a
focused message after rerunning the affected checks.
