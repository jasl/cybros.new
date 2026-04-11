# CoreMatrix/Fenix Throughput Optimization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce throughput loss and heavy-load latency for the multi-Fenix topology by removing synchronous mailbox waiting, materializing mailbox routing, and separating orchestration from heavy execution queues.

**Architecture:** Reuse the existing workflow wait/resume model instead of inventing a second async execution state machine. First tighten queue topology and mailbox routing, then move `AgentRequestExchange` from in-thread receipt polling to deferred workflow resume.

**Tech Stack:** Ruby on Rails, Solid Queue, PostgreSQL, SQLite, acceptance/perf harness

---

### Task 1: Tighten queue topology for heavy execution vs orchestration

**Files:**
- Modify: `core_matrix/config/runtime_topology.yml`
- Modify: `core_matrix/config/queue.yml`
- Modify: `core_matrix/config/database.yml`
- Modify: `core_matrix/env.sample`
- Test: `core_matrix/test/config/queue_configuration_test.rb`
- Test: `core_matrix/test/config/performance_baseline_test.rb`
- Test: `core_matrix/test/lib/acceptance/perf_workload_contract_test.rb`

**Steps:**
1. Write failing topology/config tests for the new queue split and thread budgets.
2. Run the focused tests to confirm the old topology fails expectations.
3. Implement the new queue families and pool sizing.
4. Run focused tests, then full `core_matrix` verification.

### Task 2: Materialize mailbox delivery routing

**Files:**
- Modify: `core_matrix/app/models/agent_control_mailbox_item.rb`
- Modify: `core_matrix/app/services/agent_control/create_agent_request.rb`
- Modify: `core_matrix/app/services/agent_control/poll.rb`
- Modify: `core_matrix/app/services/resolve_target_runtime.rb`
- Add/Modify migrations as needed under `core_matrix/db/migrate`
- Test: `core_matrix/test/models/agent_control_mailbox_item_test.rb`
- Test: `core_matrix/test/services/agent_control/create_agent_request_test.rb`
- Test: `core_matrix/test/services/agent_control/poll_test.rb`

**Steps:**
1. Write failing tests for mailbox items carrying explicit runtime routing metadata.
2. Run focused tests to confirm `Poll` still depends on dynamic resolution.
3. Implement materialized routing and simplify `Poll` around it.
4. Re-run focused tests and relevant full `core_matrix` suites.

### Task 3: Make program mailbox exchange resumable

**Files:**
- Modify: `core_matrix/app/services/provider_execution/agent_request_exchange.rb`
- Modify: `core_matrix/app/services/provider_execution/prepare_agent_round.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Modify: `core_matrix/app/services/provider_execution/tool_call_runners/agent_mediated.rb`
- Modify: `core_matrix/app/services/agent_control/handle_agent_report.rb`
- Modify: `core_matrix/app/services/agent_control/report.rb`
- Modify: `core_matrix/app/services/workflows/resume_blocked_step.rb`
- Add helpers/services for deferred request persistence/finalization as needed
- Test: `core_matrix/test/services/provider_execution/agent_request_exchange_test.rb`
- Test: `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`
- Test: `core_matrix/test/services/provider_execution/execute_tool_node_test.rb`
- Test: `core_matrix/test/requests/agent_api/execution_delivery_test.rb`
- Test: `core_matrix/test/jobs/workflows/resume_blocked_step_job_test.rb`

**Steps:**
1. Write failing tests for deferred program mailbox requests that release worker threads and resume on terminal report.
2. Run the focused tests to verify the current implementation still blocks synchronously.
3. Implement deferred mailbox exchange, persisted wait context, and report-driven resume/finalization.
4. Run focused tests, then full `core_matrix` verification.

### Task 4: Re-baseline perf harness and docs

**Files:**
- Modify: `acceptance/lib/perf/profile.rb`
- Modify: `acceptance/README.md`
- Modify: `docs/future-plans/2026-04-09-multi-fenix-core-matrix-load-harness-follow-up.md`
- Modify/add acceptance perf tests as needed under `test/acceptance/perf`

**Steps:**
1. Update perf expectations only after the runtime behavior changes are real and verified.
2. Re-run `smoke`, `target_8_fenix`, and `stress`.
3. Refresh docs with the new baselines and remaining follow-up work.

### Task 5: Final review and verification

**Files:**
- Review all touched files

**Steps:**
1. Run `requesting-code-review` style self-review against the whole diff.
2. Fix findings before claiming completion.
3. Run full repository verification:
   - `agents/fenix` verification commands from `AGENTS.md`
   - `core_matrix` verification commands from `AGENTS.md`
   - `core_matrix/vendor/simple_inference` verification from `AGENTS.md`
   - Docker verify for `images/nexus`
   - acceptance perf scripts
4. Only then commit.
