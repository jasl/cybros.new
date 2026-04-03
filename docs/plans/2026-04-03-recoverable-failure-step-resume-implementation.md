# Recoverable Failure Step Resume Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace terminal provider failure semantics with explicit step-level blocked waiting and resume semantics for recoverable failures.

**Architecture:** Introduce explicit failure classification plus a unified blocked-step state transition in `core_matrix`. Recoverable provider, runtime, and contract failures move the active workflow node and turn into `waiting`, then resume through a single step-resume path instead of implicit job retries.

**Tech Stack:** Ruby on Rails, Active Record, Solid Queue, Minitest

---

### Task 1: Add the new waiting reason and turn state

**Files:**
- Modify: `core_matrix/app/models/workflow_run.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/test/models/workflow_run_test.rb`

**Step 1: Add the new enums**

- Add `external_dependency_blocked` to `WorkflowRun.wait_reason_kind`
- Add `waiting` to `Turn.lifecycle_state`

**Step 2: Update validations**

- Keep `WorkflowRun.wait_state_consistency` strict
- Ensure new `Turn#terminal?` still excludes `waiting`

**Step 3: Add model tests**

- Verify `external_dependency_blocked` is accepted
- Verify a waiting turn is non-terminal

### Task 2: Introduce failure classification

**Files:**
- Create: `core_matrix/app/services/provider_execution/failure_classification.rb`
- Create: `core_matrix/test/services/provider_execution/failure_classification_test.rb`

**Step 1: Build a classifier**

- Map `SimpleInference::HTTPError` and transport/runtime errors to:
  - category
  - kind
  - retry strategy
  - whether the result is terminal

**Step 2: Cover the first supported mappings**

- 429 -> `external_dependency_blocked/provider_rate_limited`
- 401/403 -> `external_dependency_blocked/provider_auth_expired`
- 5xx -> `external_dependency_blocked/provider_overloaded`
- connection failures -> `external_dependency_blocked/provider_unreachable`
- insufficient credits/quota messages -> `external_dependency_blocked/provider_credits_exhausted`
- invalid tool/contract errors -> `contract_error/...`
- unknown errors -> `implementation_error/internal_unexpected_error`

### Task 3: Add blocked-step state transitions

**Files:**
- Create: `core_matrix/app/services/workflows/block_node_for_failure.rb`
- Create: `core_matrix/test/services/workflows/block_node_for_failure_test.rb`
- Modify: `core_matrix/app/services/workflows/wait_state.rb`

**Step 1: Implement the service**

- Input:
  - `workflow_node`
  - `failure_category`
  - `failure_kind`
  - `retry_strategy`
  - `next_retry_at`
  - `attempt_no`
  - `max_auto_retries`
  - `last_error_summary`
  - metadata

**Step 2: Apply state transitions**

- terminal path:
  - fail node, turn, workflow
- waiting path:
  - `workflow_node.lifecycle_state = "waiting"`
  - `turn.lifecycle_state = "waiting"`
  - `workflow_run.wait_state = "waiting"`
  - `workflow_run.wait_reason_kind = "retryable_failure"` or `"external_dependency_blocked"`
  - `workflow_run.blocking_resource_type = "WorkflowNode"`
  - `workflow_run.blocking_resource_id = workflow_node.public_id`

**Step 3: Add tests**

- Verify both waiting kinds and terminal fallback

### Task 4: Add blocked-step resume

**Files:**
- Create: `core_matrix/app/services/workflows/resume_blocked_step.rb`
- Create: `core_matrix/test/services/workflows/resume_blocked_step_test.rb`

**Step 1: Implement resume validation**

- Require `workflow_run.waiting?`
- Require `blocking_resource_type == "WorkflowNode"`
- Require the referenced node to exist and be waiting

**Step 2: Restore execution**

- `workflow_run.update!(Workflows::WaitState.ready_attributes)`
- `turn.update!(lifecycle_state: "active")`
- `workflow_node.update!(lifecycle_state: "queued", started_at: nil, finished_at: nil)`
- call `Workflows::DispatchRunnableNodes`

### Task 5: Replace implicit provider retry

**Files:**
- Modify: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Modify: `core_matrix/app/jobs/workflows/execute_node_job.rb`
- Modify: `core_matrix/app/services/provider_execution/persist_turn_step_failure.rb`
- Modify: `core_matrix/test/services/provider_execution/persist_turn_step_failure_test.rb`
- Modify: `core_matrix/test/services/workflows/execute_run_test.rb`

**Step 1: Remove `retry_job` usage**

- Stop rescuing `AdmissionRefused` in `ExecuteNodeJob`

**Step 2: Re-route provider failures**

- `AdmissionRefused` becomes blocked-step waiting instead of `queued + retry_job`
- `RoundRequestFailed` becomes:
  - classified
  - blocked-step waiting or terminal failure

**Step 3: Narrow `PersistTurnStepFailure`**

- Make it the terminal-only path, or replace its callers with the new blocking service

### Task 6: Add due-retry scheduler

**Files:**
- Create: `core_matrix/app/jobs/workflows/resume_due_blocked_nodes_job.rb`
- Create: `core_matrix/test/jobs/workflows/resume_due_blocked_nodes_job_test.rb`

**Step 1: Query due blocked workflow runs**

- `wait_state = waiting`
- `blocking_resource_type = "WorkflowNode"`
- `retry_strategy = automatic`
- `next_retry_at <= Time.current`

**Step 2: Resume**

- Call `Workflows::ResumeBlockedStep`

### Task 7: Preserve existing manual paths

**Files:**
- Modify: `core_matrix/app/models/workflow_wait_snapshot.rb`
- Modify: `core_matrix/app/services/workflows/resume_after_wait_resolution.rb`
- Modify: `core_matrix/test/models/workflow_wait_snapshot_test.rb`

**Step 1: Teach snapshots about the new wait reason**

- Resolve `external_dependency_blocked` through node existence/state
- Do not regress human interaction, subagent barrier, or policy gate behavior

### Task 8: Add request and integration coverage

**Files:**
- Create or modify provider execution and workflow integration tests under `core_matrix/test/services` and `core_matrix/test/e2e`

**Step 1: Add provider recoverability coverage**

- rate limit => waits and can auto-resume
- credits exhausted => waits manual
- auth expired => waits manual
- overloaded/unreachable => waits automatic

**Step 2: Add contract failure coverage**

- invalid contract => `retryable_failure`

**Step 3: Add terminal fallback coverage**

- internal unexpected error => terminal failure

### Task 9: Update docs

**Files:**
- Modify: `core_matrix/docs/behavior/*` as needed
- Modify: `docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md` only if acceptance wording needs blocked-state semantics

**Step 1: Update behavior docs**

- waiting semantics
- recoverable failure semantics
- same-step resume semantics

### Task 10: Verify and iterate

**Files:**
- No code changes by default

**Step 1: Run targeted tests**

- workflow wait state
- provider execution failure handling
- resume blocked step

**Step 2: Run full project verification once implementation stabilizes**

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

**Step 3: Re-run acceptance after OpenRouter credits are restored**

- 2048 checklist
- blocked failure recovery scenario

