# SolidQueue Topology and Provider Governor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move `core_matrix` and `agents/fenix` onto explicit SolidQueue queue topologies, add provider-level LLM concurrency/throttle governance, and document the 4-core/8GB baseline plus tuning knobs.

**Architecture:** `core_matrix` keeps queue isolation between workflow orchestration, LLM requests, tool calls, and maintenance work. LLM throughput is governed by a new provider governor layer that merges static defaults from `config/llm_catalog.yml` with installation overrides from `ProviderPolicy`, then gates outbound requests before `ProviderExecution::DispatchRequest` calls `HTTPX`. `agents/fenix` migrates from `:async` to `:solid_queue`, splitting pure runtime work from registry-backed process/browser work so the latter can remain pinned to a narrow worker pool.

**Tech Stack:** Rails 8.2, ActiveJob, SolidQueue, PostgreSQL (`core_matrix`), SQLite (`agents/fenix`), HTTPX, `with_advisory_lock`

---

### Task 1: Add Provider Governor Defaults To The Catalog Contract

**Files:**
- Modify: `core_matrix/config/llm_catalog.yml`
- Modify: `core_matrix/app/services/provider_catalog/validate.rb`
- Modify: `core_matrix/app/services/provider_catalog/effective_catalog.rb`
- Test: `core_matrix/test/services/provider_catalog/load_test.rb`
- Test: `core_matrix/test/services/provider_catalog/validate_test.rb`
- Test: `core_matrix/test/services/workflows/resolve_model_selector_test.rb`

**Step 1: Write the failing tests**

Add catalog fixture coverage for:

```ruby
request_governor:
  max_concurrent_requests: 12
  throttle_limit: 600
  throttle_period_seconds: 60
```

and assert:

```ruby
provider = catalog.provider("openai")
assert_equal 12, provider.fetch(:request_governor).fetch(:max_concurrent_requests)
```

**Step 2: Run tests to verify they fail**

Run: `cd core_matrix && bin/rails test test/services/provider_catalog/load_test.rb test/services/provider_catalog/validate_test.rb test/services/workflows/resolve_model_selector_test.rb`

Expected: FAIL because provider definitions do not expose `request_governor`.

**Step 3: Implement the minimal catalog support**

Add provider-level validation in `ProviderCatalog::Validate` and make `EffectiveCatalog` expose a merged provider governor payload:

```ruby
def provider_governor(provider_handle)
  provider_defaults = provider(provider_handle).fetch(:request_governor, {})
  policy = ProviderPolicy.find_by(installation: @installation, provider_handle: provider_handle)

  {
    "max_concurrent_requests" => policy&.max_concurrent_requests || provider_defaults[:max_concurrent_requests],
    "throttle_limit" => policy&.throttle_limit || provider_defaults[:throttle_limit],
    "throttle_period_seconds" => policy&.throttle_period_seconds || provider_defaults[:throttle_period_seconds],
  }.compact
end
```

**Step 4: Run tests to verify they pass**

Run: `cd core_matrix && bin/rails test test/services/provider_catalog/load_test.rb test/services/provider_catalog/validate_test.rb test/services/workflows/resolve_model_selector_test.rb`

Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/config/llm_catalog.yml \
  core_matrix/app/services/provider_catalog/validate.rb \
  core_matrix/app/services/provider_catalog/effective_catalog.rb \
  core_matrix/test/services/provider_catalog/load_test.rb \
  core_matrix/test/services/provider_catalog/validate_test.rb \
  core_matrix/test/services/workflows/resolve_model_selector_test.rb
git commit -m "feat: add provider governor defaults to catalog"
```

### Task 2: Implement Provider Request Governor Admission Control

**Files:**
- Create: `core_matrix/app/services/provider_execution/provider_request_governor.rb`
- Create: `core_matrix/app/services/provider_execution/with_provider_request_lease.rb`
- Create: `core_matrix/test/services/provider_execution/provider_request_governor_test.rb`
- Modify: `core_matrix/app/services/provider_execution/dispatch_request.rb`
- Modify: `core_matrix/test/services/workflows/execute_run_test.rb`
- Modify: `core_matrix/test/support/provider_execution_test_support.rb`

**Step 1: Write the failing tests**

Add tests for three cases:

```ruby
test "admits requests below max_concurrent_requests"
test "returns retry_later when provider concurrency is exhausted"
test "records cooldown when upstream returns 429"
```

**Step 2: Run tests to verify they fail**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/provider_request_governor_test.rb test/services/workflows/execute_run_test.rb`

Expected: FAIL because the governor service and lease wrapper do not exist.

**Step 3: Write minimal implementation**

Implement a short-lived governor using advisory locks for the decision point plus cache-backed counters / cooldowns:

```ruby
decision = ProviderExecution::ProviderRequestGovernor.call(
  installation: workflow_run.installation,
  provider_handle: request_context.provider_handle,
  effective_catalog: effective_catalog
)

raise RetryLater, decision.retry_at if decision.blocked?
```

Wrap outbound dispatch so admitted requests increment in-flight counts in `ensure`:

```ruby
ProviderExecution::WithProviderRequestLease.call(...) do
  build_client.responses(**request)
end
```

**Step 4: Run tests to verify they pass**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/provider_request_governor_test.rb test/services/workflows/execute_run_test.rb`

Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/app/services/provider_execution/provider_request_governor.rb \
  core_matrix/app/services/provider_execution/with_provider_request_lease.rb \
  core_matrix/app/services/provider_execution/dispatch_request.rb \
  core_matrix/test/services/provider_execution/provider_request_governor_test.rb \
  core_matrix/test/services/workflows/execute_run_test.rb \
  core_matrix/test/support/provider_execution_test_support.rb
git commit -m "feat: gate outbound provider requests"
```

### Task 3: Route Core Matrix Jobs Onto Explicit Queues

**Files:**
- Modify: `core_matrix/config/queue.yml`
- Modify: `core_matrix/app/jobs/workflows/execute_node_job.rb`
- Modify: `core_matrix/app/jobs/lineage_stores/garbage_collect_job.rb`
- Modify: `core_matrix/app/services/workflows/dispatch_runnable_nodes.rb`
- Create: `core_matrix/test/jobs/workflows/execute_node_job_test.rb`
- Create: `core_matrix/test/services/workflows/dispatch_runnable_nodes_test.rb`

**Step 1: Write the failing tests**

Add assertions that:

```ruby
assert_enqueued_with(job: Workflows::ExecuteNodeJob, queue: "llm_requests")
assert_enqueued_with(job: Workflows::ExecuteNodeJob, queue: "tool_calls")
assert_equal "maintenance", LineageStores::GarbageCollectJob.queue_name
```

**Step 2: Run tests to verify they fail**

Run: `cd core_matrix && bin/rails test test/jobs/workflows/execute_node_job_test.rb test/services/workflows/dispatch_runnable_nodes_test.rb`

Expected: FAIL because all jobs still use `default`.

**Step 3: Write minimal implementation**

Add queue routing by node type:

```ruby
def queue_name_for(workflow_node)
  case workflow_node.node_type
  when "turn_step" then "llm_requests"
  when "tool_call" then "tool_calls"
  else "workflow_default"
  end
end
```

Update `config/queue.yml` to the 4-core/8GB baseline:

```yml
workers:
  - queues: "llm_requests"
    threads: <%= ENV.fetch("SQ_THREADS_LLM", 8) %>
    processes: <%= ENV.fetch("SQ_PROCESSES_LLM", 1) %>
  - queues: "tool_calls"
    threads: <%= ENV.fetch("SQ_THREADS_TOOLS", 6) %>
    processes: <%= ENV.fetch("SQ_PROCESSES_TOOLS", 1) %>
  - queues: "workflow_default"
    threads: <%= ENV.fetch("SQ_THREADS_WORKFLOW", 3) %>
    processes: <%= ENV.fetch("SQ_PROCESSES_WORKFLOW", 1) %>
  - queues: "maintenance"
    threads: <%= ENV.fetch("SQ_THREADS_MAINTENANCE", 1) %>
    processes: <%= ENV.fetch("SQ_PROCESSES_MAINTENANCE", 1) %>
```

**Step 4: Run tests to verify they pass**

Run: `cd core_matrix && bin/rails test test/jobs/workflows/execute_node_job_test.rb test/services/workflows/dispatch_runnable_nodes_test.rb`

Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/config/queue.yml \
  core_matrix/app/jobs/workflows/execute_node_job.rb \
  core_matrix/app/jobs/lineage_stores/garbage_collect_job.rb \
  core_matrix/app/services/workflows/dispatch_runnable_nodes.rb \
  core_matrix/test/jobs/workflows/execute_node_job_test.rb \
  core_matrix/test/services/workflows/dispatch_runnable_nodes_test.rb
git commit -m "feat: isolate core matrix job queues"
```

### Task 4: Reuse Persistent HTTPX Sessions For LLM Dispatch

**Files:**
- Modify: `core_matrix/vendor/simple_inference/lib/simple_inference/http_adapters/httpx.rb`
- Modify: `core_matrix/app/services/provider_execution/dispatch_request.rb`
- Create: `core_matrix/test/services/provider_execution/dispatch_request_test.rb`

**Step 1: Write the failing tests**

Add a test proving `DispatchRequest` can accept and reuse a shared `HTTPX::Session`-backed adapter.

**Step 2: Run tests to verify they fail**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/dispatch_request_test.rb`

Expected: FAIL because there is no shared-session construction path.

**Step 3: Write minimal implementation**

Build a reusable adapter/session factory, preferring `HTTPX.plugin(:persistent)` and keeping the current API compatible:

```ruby
def self.default_client
  @default_client ||= ::HTTPX.plugin(:persistent)
end
```

**Step 4: Run tests to verify they pass**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/dispatch_request_test.rb`

Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/vendor/simple_inference/lib/simple_inference/http_adapters/httpx.rb \
  core_matrix/app/services/provider_execution/dispatch_request.rb \
  core_matrix/test/services/provider_execution/dispatch_request_test.rb
git commit -m "feat: reuse persistent httpx sessions for llm dispatch"
```

### Task 5: Move Fenix To SolidQueue With Split Runtime Queues

**Files:**
- Modify: `agents/fenix/Gemfile`
- Modify: `agents/fenix/config/application.rb`
- Modify: `agents/fenix/config/environments/development.rb`
- Modify: `agents/fenix/config/environments/production.rb`
- Modify: `agents/fenix/config/database.yml`
- Create: `agents/fenix/config/queue.yml`
- Create: `agents/fenix/db/queue_schema.rb`
- Create: `agents/fenix/db/queue_migrate/.keep`
- Test: `agents/fenix/test/services/fenix/runtime/mailbox_worker_test.rb`

**Step 1: Write the failing tests**

Add assertions that:

```ruby
assert_equal "solid_queue", ActiveJob::Base.queue_adapter_name
assert_enqueued_with(job: RuntimeExecutionJob, queue: "runtime_pure_tools")
```

**Step 2: Run tests to verify they fail**

Run: `cd agents/fenix && bin/rails test test/services/fenix/runtime/mailbox_worker_test.rb`

Expected: FAIL because `fenix` still uses `:async` and has no queue routing.

**Step 3: Write minimal implementation**

Introduce SolidQueue wiring and baseline worker topology:

```yml
workers:
  - queues: "runtime_prepare_round"
    threads: <%= ENV.fetch("SQ_THREADS_PREPARE", 2) %>
    processes: <%= ENV.fetch("SQ_PROCESSES_PREPARE", 1) %>
  - queues: "runtime_pure_tools"
    threads: <%= ENV.fetch("SQ_THREADS_PURE_TOOLS", 6) %>
    processes: <%= ENV.fetch("SQ_PROCESSES_PURE_TOOLS", 1) %>
  - queues: "runtime_process_tools"
    threads: <%= ENV.fetch("SQ_THREADS_PROCESS_TOOLS", 2) %>
    processes: <%= ENV.fetch("SQ_PROCESSES_PROCESS_TOOLS", 1) %>
  - queues: "runtime_control"
    threads: <%= ENV.fetch("SQ_THREADS_RUNTIME_CONTROL", 2) %>
    processes: <%= ENV.fetch("SQ_PROCESSES_RUNTIME_CONTROL", 1) %>
  - queues: "maintenance"
    threads: <%= ENV.fetch("SQ_THREADS_MAINTENANCE", 1) %>
    processes: <%= ENV.fetch("SQ_PROCESSES_MAINTENANCE", 1) %>
```

Use a dedicated queue database file for SQLite:

```yml
queue:
  <<: *default
  database: storage/queue_development.sqlite3
  migrations_paths: db/queue_migrate
```

**Step 4: Run tests to verify they pass**

Run: `cd agents/fenix && bin/rails test test/services/fenix/runtime/mailbox_worker_test.rb`

Expected: PASS

**Step 5: Commit**

```bash
git add agents/fenix/Gemfile \
  agents/fenix/config/application.rb \
  agents/fenix/config/environments/development.rb \
  agents/fenix/config/environments/production.rb \
  agents/fenix/config/database.yml \
  agents/fenix/config/queue.yml \
  agents/fenix/db/queue_schema.rb \
  agents/fenix/db/queue_migrate/.keep \
  agents/fenix/test/services/fenix/runtime/mailbox_worker_test.rb
git commit -m "feat: move fenix onto solid queue"
```

### Task 6: Route Fenix Runtime Work By Execution Type

**Files:**
- Modify: `agents/fenix/app/jobs/runtime_execution_job.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/mailbox_worker.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/execution_topology.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/program_tool_executor.rb`
- Create: `agents/fenix/test/jobs/runtime_execution_job_test.rb`
- Modify: `agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb`

**Step 1: Write the failing tests**

Add tests proving:

```ruby
assert_enqueued_with(job: RuntimeExecutionJob, queue: "runtime_process_tools")
assert_enqueued_with(job: RuntimeExecutionJob, queue: "runtime_prepare_round")
```

and that registry-backed tools remain restricted:

```ruby
assert Fenix::Runtime::ExecutionTopology.registry_backed_queue?("runtime_process_tools")
```

**Step 2: Run tests to verify they fail**

Run: `cd agents/fenix && bin/rails test test/jobs/runtime_execution_job_test.rb test/services/fenix/runtime/execute_assignment_test.rb`

Expected: FAIL because runtime work is not classified into queues yet.

**Step 3: Write minimal implementation**

Route based on mailbox item / tool kind:

```ruby
def queue_name_for(runtime_execution)
  case runtime_execution.runtime_plane
  when "agent_program" then "runtime_prepare_round"
  when "agent"
    registry_backed? ? "runtime_process_tools" : "runtime_pure_tools"
  else
    "runtime_control"
  end
end
```

Update topology checks so registry-backed tools are allowed only on the dedicated queue pool, not only on `:async`.

**Step 4: Run tests to verify they pass**

Run: `cd agents/fenix && bin/rails test test/jobs/runtime_execution_job_test.rb test/services/fenix/runtime/execute_assignment_test.rb`

Expected: PASS

**Step 5: Commit**

```bash
git add agents/fenix/app/jobs/runtime_execution_job.rb \
  agents/fenix/app/services/fenix/runtime/mailbox_worker.rb \
  agents/fenix/app/services/fenix/runtime/execution_topology.rb \
  agents/fenix/app/services/fenix/runtime/execute_assignment.rb \
  agents/fenix/app/services/fenix/runtime/program_tool_executor.rb \
  agents/fenix/test/jobs/runtime_execution_job_test.rb \
  agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb
git commit -m "feat: classify fenix runtime work by queue"
```

### Task 7: Document Baseline And Scaling Knobs

**Files:**
- Create: `docs/operations/queue-topology-and-provider-governor.md`
- Modify: `docs/plans/README.md`
- Modify: `core_matrix/config/queue.yml`
- Modify: `agents/fenix/config/queue.yml`

**Step 1: Write the failing doc checklist**

Create a checklist in the new doc that must answer:

```markdown
- Which queues exist in each app?
- What is the 4-core/8GB baseline?
- Which env vars scale threads/processes?
- How do provider governor defaults interact with ProviderPolicy?
- Which fenix queues must stay narrow because of registry-backed tools?
```

**Step 2: Verify the checklist is currently unmet**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros && rg -n "provider governor|runtime_process_tools|SQ_THREADS_LLM" docs core_matrix/config/queue.yml agents/fenix/config/queue.yml`

Expected: Missing or partial documentation.

**Step 3: Write the minimal documentation**

Document:
- baseline queue topology
- all tuning env vars
- how to scale for 32-core hosts
- why LLM queue width and provider concurrency are separate knobs
- rollout note for registry-backed `fenix` tools

**Step 4: Verify the doc is discoverable**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros && rg -n "queue-topology-and-provider-governor" docs`

Expected: PASS

**Step 5: Commit**

```bash
git add docs/operations/queue-topology-and-provider-governor.md \
  docs/plans/README.md \
  core_matrix/config/queue.yml \
  agents/fenix/config/queue.yml
git commit -m "docs: add queue topology and provider governor guide"
```

### Task 8: Run Focused Verification

**Files:**
- Modify as needed based on failures from earlier tasks

**Step 1: Run core_matrix verification**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/provider_catalog/load_test.rb \
  test/services/provider_catalog/validate_test.rb \
  test/services/provider_execution/provider_request_governor_test.rb \
  test/services/provider_execution/dispatch_request_test.rb \
  test/services/workflows/execute_run_test.rb \
  test/jobs/workflows/execute_node_job_test.rb \
  test/services/workflows/dispatch_runnable_nodes_test.rb
```

Expected: PASS

**Step 2: Run agents/fenix verification**

Run:

```bash
cd agents/fenix
bin/rails test \
  test/services/fenix/runtime/mailbox_worker_test.rb \
  test/jobs/runtime_execution_job_test.rb \
  test/services/fenix/runtime/execute_assignment_test.rb
```

Expected: PASS

**Step 3: Run targeted lint/security checks if queue/config files changed heavily**

Run:

```bash
cd core_matrix && bin/rubocop app/jobs app/services/provider_execution app/services/provider_catalog
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rubocop app/jobs app/services/fenix/runtime config
```

Expected: PASS

**Step 4: Commit any final fixes**

```bash
git add -A
git commit -m "chore: finish queue topology and provider governor rollout"
```
