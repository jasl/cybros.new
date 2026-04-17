# Live Supervision Sidechat Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a dedicated hybrid acceptance scenario that verifies supervision
sidechat during an active/waiting turn through app_api, while keeping the 2048
capstone focused on export/review completeness.

**Architecture:** Acceptance will gain app_api wrappers for supervision session
and message endpoints. A new hybrid acceptance scenario will deterministically
create a waiting workflow through internal setup, then interrogate it through
app_api supervision endpoints and export the resulting sidechat transcript.

**Tech Stack:** Ruby on Rails, Minitest, acceptance scenarios, app_api
supervision endpoints, debug export.

---

### Task 1: Add Failing Acceptance Contracts For A Live Sidechat Scenario

**Files:**
- Modify: `core_matrix/test/lib/acceptance/active_suite_contract_test.rb`
- Modify: `acceptance/lib/active_suite.rb`
- Create: `acceptance/scenarios/live_supervision_sidechat_validation.rb`

**Step 1: Register a new active scenario**

Add a new active scenario entry for:

- `acceptance/scenarios/live_supervision_sidechat_validation.rb`

Register it as `hybrid_app_api` with a reason that explains:

- app_api supervision endpoints exist
- deterministic waiting-work setup still has no product surface

**Step 2: Run the active suite contract test red**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test test/lib/acceptance/active_suite_contract_test.rb
```

Expected: failure because the new scenario file/metadata is not complete yet.

### Task 2: Add App API Acceptance Helpers For Supervision Session And Messages

**Files:**
- Modify: `acceptance/lib/manual_support.rb`
- Modify: `core_matrix/test/lib/acceptance/manual_support_test.rb`

**Step 1: Write failing helper tests**

Extend `manual_support_test.rb` for three new helpers:

- `app_api_create_conversation_supervision_session!`
- `app_api_append_conversation_supervision_message!`
- `app_api_conversation_supervision_messages!`

The tests should verify the wrappers hit the correct paths and preserve payload
shapes.

**Step 2: Implement the helpers**

Add app_api wrappers that call:

- `POST /app_api/conversations/:conversation_id/supervision_sessions`
- `POST /app_api/conversations/:conversation_id/supervision_sessions/:id/messages`
- `GET /app_api/conversations/:conversation_id/supervision_sessions/:id/messages`

Do not route this new scenario through the old internal acceptance helpers.

**Step 3: Run helper tests green**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test test/lib/acceptance/manual_support_test.rb
```

### Task 3: Implement The Live Sidechat Acceptance Scenario

**Files:**
- Create: `acceptance/scenarios/live_supervision_sidechat_validation.rb`
- Modify: `acceptance/lib/active_suite.rb`

**Step 1: Build a deterministic waiting turn**

Model the setup after the existing deterministic wait scenarios, using internal
workflow substrate only to establish:

- a live retained conversation
- an active turn
- a waiting workflow run
- a stable blocker such as `human_interaction`

The scenario should not rely on transient timing from a real provider run.

**Step 2: Use app_api supervision endpoints while the turn is still live**

Inside the scenario:

- issue an app_api session token
- create a supervision session with
  `app_api_create_conversation_supervision_session!`
- append a message such as:
  - `What are you waiting on right now?`
  - or `What are you doing right now and what changed most recently?`
- list the session transcript through app_api

**Step 3: Assert live-progress semantics**

The scenario should assert:

- `machine_status.overall_state` is `waiting` or another in-flight state
- the human sidechat content refers to current waiting/progress semantics
- the response does not collapse into a purely terminal summary
- the transcript contains both user and supervisor messages
- the target conversation transcript remains untouched

**Step 4: Write result JSON**

The scenario result should include:

- conversation / turn / workflow ids
- supervision session id
- expected vs observed conversation state
- sidechat content
- message roles
- export path

### Task 4: Export The Live Sidechat Transcript And Prove It Survives

**Files:**
- Modify: `acceptance/scenarios/live_supervision_sidechat_validation.rb`
- Modify as needed: `core_matrix/test/services/conversation_debug_exports/build_payload_test.rb`
- Modify as needed: `core_matrix/test/services/conversation_debug_exports/write_zip_bundle_test.rb`
- Modify as needed: `test/acceptance/capstone_review_artifacts_test.rb`

**Step 1: Request debug export before resolving the wait**

The scenario should download debug export while the workflow is still waiting.

**Step 2: Assert export payload content**

Verify:

- `conversation_supervision_sessions.json` contains the created session
- `conversation_supervision_messages.json` contains both messages
- the supervisor content matches the sidechat response

**Step 3: Persist evidence files**

Write:

- `evidence/conversation-supervision-session.json`
- `evidence/conversation-supervision-probe.json`
- `evidence/conversation-debug-export.json`

### Task 5: Keep Capstone Narrow And Non-Regressive

**Files:**
- Modify as needed: `acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`
- Modify as needed: `acceptance/lib/capstone_review_artifacts.rb`
- Modify as needed: `test/acceptance/capstone_review_artifacts_test.rb`

**Step 1: Confirm the capstone remains a post-turn artifact probe**

Do not change the capstone into a timing-sensitive in-flight supervision test.

Only make adjustments if needed to keep:

- transcript export
- supervision transcript review
- debug export supervision transcript sections

stable after the new scenario lands.

**Step 2: Run capstone-focused tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ruby test/acceptance/capstone_review_artifacts_test.rb
```

### Task 6: Run Focused Acceptance And Regression Coverage

**Files:**
- Modify as needed:
  - `core_matrix/test/lib/acceptance/active_suite_contract_test.rb`
  - `core_matrix/test/lib/acceptance/manual_support_test.rb`
  - `core_matrix/test/services/conversation_debug_exports/build_payload_test.rb`
  - `core_matrix/test/services/conversation_debug_exports/write_zip_bundle_test.rb`
  - `core_matrix/test/requests/app_api/conversation_supervision_sessions_test.rb`
  - `core_matrix/test/requests/app_api/conversation_supervision_messages_test.rb`
  - `core_matrix/test/services/embedded_agents/conversation_supervision/append_message_test.rb`

**Step 1: Run the focused suite**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/lib/acceptance/active_suite_contract_test.rb \
  test/lib/acceptance/manual_support_test.rb \
  test/services/conversation_debug_exports/build_payload_test.rb \
  test/services/conversation_debug_exports/write_zip_bundle_test.rb \
  test/requests/app_api/conversation_supervision_sessions_test.rb \
  test/requests/app_api/conversation_supervision_messages_test.rb \
  test/services/embedded_agents/conversation_supervision/append_message_test.rb
```

Expected: focused green coverage for the new app_api acceptance boundary and
export path.

### Task 7: Run Full Verification And Final Acceptance

**Files:**
- No planned code changes in this task

**Step 1: Run full `core_matrix` verification**

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

**Step 2: Run full active acceptance including 2048 capstone**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

**Step 3: Manually inspect artifacts and database state**

Inspect:

- the new live-sidechat scenario artifact for in-flight sidechat evidence
- the latest 2048 capstone artifact for transcript/review completeness
- database rows for:
  - `Conversation`
  - `Turn`
  - `WorkflowRun`
  - `ConversationSupervisionSession`
  - `ConversationSupervisionMessage`

Confirm:

- live-sidechat scenario captured an in-flight waiting/progress answer
- capstone still exports transcript and supervision transcript review
- business state shapes remain correct

### Task 8: Commit And Document Outcome

**Files:**
- Update as needed:
  - `core_matrix/docs/behavior/conversation-supervision-and-control.md`
  - this design doc
  - this implementation doc

**Step 1: Update behavior docs if the acceptance contract changed**

If the new scenario clarifies an acceptance-level contract not already stated in
behavior docs, document it.

**Step 2: Commit only after full verification is green**

Commit the final implementation once:

- focused tests are green
- full `core_matrix` verification is green
- active acceptance and 2048 capstone are green
- artifact and database checks are complete
