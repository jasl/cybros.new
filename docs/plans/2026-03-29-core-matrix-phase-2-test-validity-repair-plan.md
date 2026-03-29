# Core Matrix Phase 2 Test Validity Repair Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restore trust that the Phase 2 automated suite describes real protocol behavior instead of just preserving the current refactor shape.

**Architecture:** Keep the existing L0 and L1 state-oriented coverage, but close the missing L2 `Protocol E2E` gaps on top of the current harness instead of building a second end-to-end stack. Remove or rewrite tests that are actively misleading: placeholder browser checks that do not represent any Phase 2 contract, and white-box structural assertions that fail on refactor without proving a user-visible regression.

**Tech Stack:** Ruby on Rails (`core_matrix`, `agents/fenix`), Minitest, `ActionDispatch::IntegrationTest`, Action Cable test helpers, shared JSON contract fixtures, Phase 2 planning docs

---

## Execution Rules

- Treat the [Phase 2 test strategy design](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-phase-2-test-strategy-design.md) as the source of truth for required verification layers and minimum `Protocol E2E` scenarios.
- Extend the existing `core_matrix/test/e2e/protocol/*` harness. Do not create a parallel browser stack or a second protocol stack with different semantics.
- Prefer black-box assertions on mailbox envelopes, lifecycle state, durable close fields, and public ids over assertions about handler classes, validators, or private dispatch structure.
- Keep `public_id` semantics at external and agent-facing boundaries in every new test.
- Use TDD for every task: add the missing scenario first, confirm the failure or missing support, then make the smallest production or harness change required.
- Commit after each task with the suggested message or a tighter equivalent.

## Audit Baseline

Fresh verification before writing this plan:

- `cd core_matrix && bin/rails test`
- `cd core_matrix && bin/rails db:test:prepare test:system`
- `cd agents/fenix && bundle exec rails test`
- `cd /Users/jasl/Workspaces/Ruby/cybros && ruby test/monorepo_dev_environment_test.rb`

Observed state:

- `core_matrix` unit/integration/request/E2E suite passes
- `core_matrix` system suite passes but only contains a placeholder home-page test
- `agents/fenix` suite passes but is mostly local runtime and shared-contract coverage
- the highest-confidence gap is missing L2 proof for retry, timeout, detached-tail, and MCP/network close paths

### Task 1: Fill The Missing Delivery And Idempotency Protocol E2E Scenarios

**Files:**
- Modify: `core_matrix/test/e2e/protocol/mailbox_delivery_e2e_test.rb`
- Modify: `core_matrix/test/support/fake_agent_runtime_harness.rb`
- Modify: `core_matrix/test/support/controllable_clock.rb`
- Inspect if failing: `core_matrix/app/services/agent_control/report.rb`
- Inspect if failing: `core_matrix/app/services/agent_control/poll.rb`

**Step 1: Write the failing tests**

Add explicit `Protocol E2E` cases for:

- `poll`-only assignment, progress, and completion
- duplicate `execution_complete` idempotency in the same realistic round-trip
- identical observable envelope semantics when the runtime starts in `poll` mode without ever opening a `WebSocket`

Example skeleton:

```ruby
test "poll-only execution assignment progresses to completion with one coherent mailbox lifecycle" do
  context = build_agent_control_context!
  harness = FakeAgentRuntimeHarness.new(
    test_case: self,
    deployment: context[:deployment],
    machine_credential: context[:machine_credential]
  )
  scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)

  first_poll = harness.poll!
  assignment = first_poll.fetch("mailbox_items").fetch(0)

  started = harness.report!(
    method_id: "execution_started",
    protocol_message_id: "poll-start-#{next_test_sequence}",
    mailbox_item_id: assignment.fetch("item_id"),
    agent_task_run_id: scenario.fetch(:agent_task_run).public_id,
    logical_work_id: scenario.fetch(:agent_task_run).logical_work_id,
    attempt_no: scenario.fetch(:agent_task_run).attempt_no,
    expected_duration_seconds: 15
  )

  completed = harness.report!(
    method_id: "execution_complete",
    protocol_message_id: "poll-complete-#{next_test_sequence}",
    mailbox_item_id: assignment.fetch("item_id"),
    agent_task_run_id: scenario.fetch(:agent_task_run).public_id,
    logical_work_id: scenario.fetch(:agent_task_run).logical_work_id,
    attempt_no: scenario.fetch(:agent_task_run).attempt_no,
    terminal_payload: { "output" => "done" }
  )

  assert_equal 200, started.fetch("http_status")
  assert_equal 200, completed.fetch("http_status")
  assert_equal "completed", scenario.fetch(:agent_task_run).reload.lifecycle_state
end
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd core_matrix
bin/rails test test/e2e/protocol/mailbox_delivery_e2e_test.rb
```

Expected: FAIL because the new `poll`-only and duplicate-terminal golden paths are not currently expressed at the `Protocol E2E` layer.

**Step 3: Write the minimal implementation**

Only if the new tests expose a real gap:

- add small harness helpers for `poll`-only completion and repeated terminal reports
- keep all behavior routed through the real `/agent_api/control/poll` and `/agent_api/control/report` endpoints
- if a production bug appears, fix it in the current poll/report path instead of adding a test-only shim

**Step 4: Run test to verify it passes**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/test/e2e/protocol/mailbox_delivery_e2e_test.rb \
  core_matrix/test/support/fake_agent_runtime_harness.rb \
  core_matrix/test/support/controllable_clock.rb
git commit -m "test: add poll-only and duplicate terminal protocol e2e coverage"
```

### Task 2: Add Retry Semantics Protocol E2E Instead Of Leaving Retry At L0 And L1

**Files:**
- Create: `core_matrix/test/e2e/protocol/retry_semantics_e2e_test.rb`
- Modify: `core_matrix/test/support/fake_agent_runtime_harness.rb`
- Modify: `core_matrix/test/support/controllable_clock.rb`
- Inspect if failing: `core_matrix/app/services/workflows/step_retry.rb`
- Inspect if failing: `core_matrix/app/services/agent_control/report.rb`
- Inspect if failing: `core_matrix/app/services/conversations/request_turn_interrupt.rb`
- Inspect if failing: `core_matrix/app/services/agent_control/poll.rb`

**Step 1: Write the failing tests**

Add end-to-end cases for all missing retry golden paths:

- retryable `execution_fail` moves the workflow into `retryable_failure`
- `step_retry` creates a new attempt inside the same turn and workflow
- `turn_interrupt` fences queued retry work before it can be redelivered
- close work outranks queued retry work

Example skeleton:

```ruby
test "retryable execution failure moves workflow into retryable_failure and step retry stays inside the same turn" do
  context = build_agent_control_context!
  harness = FakeAgentRuntimeHarness.new(
    test_case: self,
    deployment: context[:deployment],
    machine_credential: context[:machine_credential]
  )
  scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
  assignment = harness.poll!.fetch("mailbox_items").fetch(0)

  harness.report!(
    method_id: "execution_started",
    protocol_message_id: "retry-start-#{next_test_sequence}",
    mailbox_item_id: assignment.fetch("item_id"),
    agent_task_run_id: scenario.fetch(:agent_task_run).public_id,
    logical_work_id: scenario.fetch(:agent_task_run).logical_work_id,
    attempt_no: scenario.fetch(:agent_task_run).attempt_no,
    expected_duration_seconds: 30
  )

  failed = harness.report!(
    method_id: "execution_fail",
    protocol_message_id: "retry-fail-#{next_test_sequence}",
    mailbox_item_id: assignment.fetch("item_id"),
    agent_task_run_id: scenario.fetch(:agent_task_run).public_id,
    logical_work_id: scenario.fetch(:agent_task_run).logical_work_id,
    attempt_no: scenario.fetch(:agent_task_run).attempt_no,
    terminal_payload: {
      "retryable" => true,
      "retry_scope" => "step",
      "failure_kind" => "tool_failure",
      "last_error_summary" => "exit status 1"
    }
  )

  assert_equal 200, failed.fetch("http_status")
  assert_equal "retryable_failure", context[:workflow_run].reload.wait_reason_kind
end
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd core_matrix
bin/rails test test/e2e/protocol/retry_semantics_e2e_test.rb
```

Expected: FAIL because these scenarios currently exist only in request or service tests, not in `Protocol E2E`.

**Step 3: Write the minimal implementation**

If any scenario fails beyond missing test support:

- fix the real retry lifecycle in `StepRetry`, `RequestTurnInterrupt`, `Poll`, or `Report`
- keep retry identity anchored to `logical_work_id`, `attempt_no`, the current turn, and the current workflow
- do not add a second retry stack or a test-only branch

**Step 4: Run test to verify it passes**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/test/e2e/protocol/retry_semantics_e2e_test.rb \
  core_matrix/test/support/fake_agent_runtime_harness.rb \
  core_matrix/test/support/controllable_clock.rb
git commit -m "test: add retry semantics protocol e2e coverage"
```

### Task 3: Prove Detached Tail And Lineage Blocking Behavior At The Protocol E2E Layer

**Files:**
- Modify: `core_matrix/test/e2e/protocol/conversation_close_e2e_test.rb`
- Inspect if failing: `core_matrix/app/services/conversations/request_close.rb`
- Inspect if failing: `core_matrix/app/services/conversations/request_turn_interrupt.rb`
- Inspect if failing: `core_matrix/app/services/conversations/finalize_deletion.rb`
- Inspect if failing: `core_matrix/app/services/conversations/purge_deleted.rb`

**Step 1: Write the failing tests**

Extend close/disposal `Protocol E2E` coverage with:

- plain `turn_interrupt` clears only the mainline stop barrier and does not stop detached background processes
- ancestor purge remains blocked while descendant lineage still exists
- delete keeps retained child conversations while still requesting detached background close asynchronously

Example skeleton:

```ruby
test "turn interrupt clears the mainline only and leaves detached background work running" do
  context = build_agent_control_context!
  harness = FakeAgentRuntimeHarness.new(
    test_case: self,
    deployment: context[:deployment],
    machine_credential: context[:machine_credential]
  )
  background_service = create_process_run!(
    workflow_node: context[:workflow_node],
    execution_environment: context[:execution_environment],
    kind: "background_service",
    timeout_seconds: nil
  )
  Leases::Acquire.call(
    leased_resource: background_service,
    holder_key: context[:deployment].public_id,
    heartbeat_timeout_seconds: 30
  )

  Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.current)

  assert_equal "open", background_service.reload.close_state
  assert background_service.running?
  assert_empty harness.poll!.fetch("mailbox_items").select { |item| item.dig("payload", "resource_id") == background_service.public_id }
end
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd core_matrix
bin/rails test test/e2e/protocol/conversation_close_e2e_test.rb
```

Expected: FAIL because the current E2E file covers archive and delete golden paths, but not the detached-tail and lineage-blocker cases required by the strategy.

**Step 3: Write the minimal implementation**

If the new tests expose product drift:

- keep detached background behavior anchored to the existing close-operation model
- keep retained-child and descendant-lineage blocking routed through the current purge and close services
- do not special-case these paths in the test harness

**Step 4: Run test to verify it passes**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/test/e2e/protocol/conversation_close_e2e_test.rb
git commit -m "test: add detached tail and lineage close e2e coverage"
```

### Task 4: Add Deterministic Timeout And MCP Or Long-Lived Connection Protocol E2E

**Files:**
- Create: `core_matrix/test/e2e/protocol/mcp_close_e2e_test.rb`
- Create: `core_matrix/test/support/fake_mcp_runtime.rb`
- Create: `core_matrix/test/support/fake_external_process_runner.rb`
- Modify: `core_matrix/test/support/fake_agent_runtime_harness.rb`
- Modify: `core_matrix/test/support/controllable_clock.rb`
- Modify: `core_matrix/test/e2e/protocol/process_close_escalation_e2e_test.rb`
- Inspect if failing: `core_matrix/app/services/agent_control/report.rb`
- Inspect if failing: `core_matrix/app/services/conversations/request_turn_interrupt.rb`
- Inspect if failing: `core_matrix/app/services/conversations/reconcile_close_operation.rb`

**Step 1: Write the failing tests**

Add deterministic deadline-based and connection-close cases for:

- graceful close deadline expiring into forced close
- forced close still failing and recording `residual_abandoned`
- in-flight MCP or long-lived network work being canceled or aborted with a durable terminal outcome

Example skeleton:

```ruby
test "in-flight mcp work closes durably when the turn is interrupted" do
  context = build_agent_control_context!
  clock = ControllableClock.new(self)
  harness = FakeAgentRuntimeHarness.new(
    test_case: self,
    deployment: context[:deployment],
    machine_credential: context[:machine_credential]
  )
  runtime = FakeMcpRuntime.start_for!(context: context)

  Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.current)
  clock.advance!(61.seconds)

  close_report = runtime.report_closed!(harness: harness, close_outcome_kind: "forced")

  assert_equal 200, close_report.fetch("http_status")
  assert_equal "closed", runtime.resource.reload.close_state
end
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd core_matrix
bin/rails test \
  test/e2e/protocol/process_close_escalation_e2e_test.rb \
  test/e2e/protocol/mcp_close_e2e_test.rb
```

Expected: FAIL because the current support surface does not yet prove timeout progression or MCP/network closure end to end.

**Step 3: Write the minimal implementation**

Only add the smallest support and product changes needed:

- use `ControllableClock` for deterministic deadline advancement
- add fake MCP and external-process helpers only as thin wrappers around existing close APIs
- keep all terminal state changes flowing through the real close-report path

**Step 4: Run test to verify it passes**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/test/e2e/protocol/process_close_escalation_e2e_test.rb \
  core_matrix/test/e2e/protocol/mcp_close_e2e_test.rb \
  core_matrix/test/support/fake_mcp_runtime.rb \
  core_matrix/test/support/fake_external_process_runner.rb \
  core_matrix/test/support/fake_agent_runtime_harness.rb \
  core_matrix/test/support/controllable_clock.rb
git commit -m "test: add timeout and mcp close protocol e2e coverage"
```

### Task 5: Remove The Misleading Placeholder System Test

**Files:**
- Delete: `core_matrix/test/system/home_page_test.rb`
- Optionally create if a real smoke contract exists: `core_matrix/test/requests/root_smoke_test.rb`

**Step 1: Write the replacement smoke test only if the root route has a real product contract**

If there is a real root-route contract, add a request-level smoke check:

```ruby
test "root route responds successfully" do
  get "/"

  assert_response :success
end
```

If there is no real root-route contract beyond scaffold output, skip the replacement and delete the placeholder test.

**Step 2: Run verification**

Run:

```bash
cd core_matrix
bin/rails test:system
bin/rails test test/requests/root_smoke_test.rb
```

Expected:

- `test:system` no longer reports placeholder coverage
- the replacement request smoke passes only if a real contract exists

**Step 3: Write the minimal implementation**

- delete the placeholder browser assertion
- do not replace it with another UI assertion unless it describes an actual Phase 2 contract

**Step 4: Run the verification again**

Run the same commands and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/test/system/home_page_test.rb core_matrix/test/requests/root_smoke_test.rb
git commit -m "test: remove placeholder system coverage"
```

### Task 6: Replace Structural White-Box Tests With Public-Behavior Coverage

**Files:**
- Modify: `core_matrix/test/services/agent_control/report_test.rb`
- Modify: `core_matrix/test/requests/agent_api/execution_delivery_test.rb`
- Modify: `core_matrix/test/requests/agent_api/resource_close_test.rb`

**Step 1: Write the black-box replacements**

Add or strengthen behavior tests that prove:

- `execution_progress` and `execution_complete` mutate durable state correctly through the public report API
- stale attempts are rejected through the same public path
- close acknowledgement and close terminalization update mailbox and resource state durably

Then delete or downgrade tests that only assert:

- which handler class a method maps to
- that a check “lives in a dedicated validator”
- that the dispatcher was called in a specific internal shape

Example replacement:

```ruby
test "execution report public api rejects stale attempts without mutating progress" do
  context = build_agent_control_context!
  scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context, attempt_no: 2)
  AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

  result = AgentControl::Report.call(
    deployment: context[:deployment],
    method_id: "execution_progress",
    protocol_message_id: "stale-progress-#{next_test_sequence}",
    mailbox_item_id: scenario.fetch(:mailbox_item).public_id,
    agent_task_run_id: scenario.fetch(:agent_task_run).public_id,
    logical_work_id: scenario.fetch(:agent_task_run).logical_work_id,
    attempt_no: 1,
    progress_payload: { "state" => "late" }
  )

  assert_equal "stale", result.code
  assert_equal({}, scenario.fetch(:agent_task_run).reload.progress_payload)
end
```

**Step 2: Run tests to verify the old low-signal checks are still the only coverage**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/agent_control/report_test.rb \
  test/requests/agent_api/execution_delivery_test.rb \
  test/requests/agent_api/resource_close_test.rb
```

Expected: PASS before deletion, then temporary FAIL while replacing the structural checks with behavior checks.

**Step 3: Write the minimal implementation**

- keep transactional rollback tests that prove durable behavior
- delete structural assertions once an equivalent public-behavior assertion exists
- do not keep both if the structural version adds no new product signal

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/test/services/agent_control/report_test.rb \
  core_matrix/test/requests/agent_api/execution_delivery_test.rb \
  core_matrix/test/requests/agent_api/resource_close_test.rb
git commit -m "test: prefer public behavior over report internals"
```

### Task 7: Add A Monorepo Contract Smoke For The Core Matrix To Fenix Loop

**Files:**
- Modify: `core_matrix/test/services/agent_control/create_execution_assignment_test.rb`
- Modify: `agents/fenix/test/integration/runtime_flow_test.rb`
- Create: `test/phase2_fenix_contract_smoke_test.rb`

**Step 1: Write the failing smoke test**

Add a root-level contract smoke that:

- loads the shared `core_matrix` execution assignment fixture
- verifies `core_matrix` still serializes that envelope shape
- verifies `agents/fenix` still parses and prepares the same envelope successfully

The test does not need to boot both Rails apps, but it must prove the two sides consume the same contract in one automated path.

Example skeleton:

```ruby
def test_core_matrix_and_fenix_accept_the_same_phase2_assignment_fixture
  fixture = JSON.parse(
    File.read(File.join(__dir__, "..", "shared", "fixtures", "contracts", "core_matrix_fenix_execution_assignment_v1.json"))
  )

  prepared = Fenix::Context::BuildExecutionContext.call(mailbox_item: fixture)

  assert_equal "subagent_step", prepared.fetch("kind")
  assert_equal "gpt-5.4", prepared.dig("model_context", "model_ref")
end
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ruby test/phase2_fenix_contract_smoke_test.rb
```

Expected: FAIL until the root-level smoke has the correct load path and shared contract assertions.

**Step 3: Write the minimal implementation**

- keep the fixture authoritative
- do not invent a second contract fixture for the same assignment envelope
- if the fixture exposes drift, fix the serializer or parser, not the smoke test

**Step 4: Run test to verify it passes**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/test/services/agent_control/create_execution_assignment_test.rb \
  agents/fenix/test/integration/runtime_flow_test.rb \
  test/phase2_fenix_contract_smoke_test.rb
git commit -m "test: add monorepo fenix contract smoke"
```

## Final Verification

After all tasks land, run the full batch:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test
bin/rails db:test:prepare test:system

cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bundle exec rails test

cd /Users/jasl/Workspaces/Ruby/cybros
ruby test/monorepo_dev_environment_test.rb
ruby test/phase2_fenix_contract_smoke_test.rb
```

Expected:

- `core_matrix` stays green with materially stronger `Protocol E2E`
- `system` no longer reports placeholder confidence
- `agents/fenix` still accepts the shared assignment contract
- the root-level smoke proves both sides still agree on the Phase 2 envelope
