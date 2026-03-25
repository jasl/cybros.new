# Core Matrix Phase 2 Task 04: Add Provider-Backed Turn Execution

Part of `Core Matrix Phase 2 Milestone 1: Kernel Execution Foundations`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-25-core-matrix-agent-execution-delivery-contract-design.md`
3. `docs/research-notes/2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md`
4. `docs/plans/2026-03-25-core-matrix-phase-2-milestone-1-kernel-execution-foundations.md`

Load this file as the detailed execution unit for Task 04. Treat the milestone
file as the ordering index, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the
  consulted source section and the retained conclusion, invariant, or
  intentional difference in this task document or another local document
  updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs,
  carry that conclusion into those docs instead of leaving only a bare
  reference path
- keep reference paths as index pointers only; restate the relevant behavior
  locally so this task remains understandable if the reference later drifts

---

**Files:**
- Modify: `core_matrix/app/services/workflows/create_for_turn.rb`
- Likely create: `core_matrix/app/services/workflows/execute_run.rb`
- Likely create or modify: `core_matrix/app/services/provider_execution/*`
- Modify: `core_matrix/app/models/workflow_run.rb`
- Modify: `core_matrix/app/models/workflow_node.rb`
- Modify: `core_matrix/app/models/agent_task_run.rb`
- Modify: `core_matrix/app/models/provider_usage_event.rb`
- Modify: `core_matrix/app/models/execution_profile_fact.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/vendor/simple_inference/lib/simple_inference/*`
- Modify: `core_matrix/vendor/simple_inference/test/*`
- Create or modify: `core_matrix/test/services/workflows/execute_run_test.rb`
- Create or modify: `core_matrix/test/services/provider_execution/*`
- Create or modify: `core_matrix/test/integration/provider_backed_turn_execution_test.rb`
- Modify: `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- Modify: `core_matrix/docs/behavior/provider-usage-events-and-rollups.md`
- Modify: `core_matrix/docs/behavior/execution-profiling-facts.md`

**Step 1: Write failing service and integration tests**

Cover at least:

- one queued `AgentTaskRun` moving to running and then terminal
- one provider-backed `turn_step` routed through `simple_inference`
- authoritative provider usage persistence after completion
- likely model or model-profile hint exposure
- separation between hard provider ceilings and advisory runtime hints

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix/vendor/simple_inference
bundle exec rake
cd ../..
bin/rails test test/services/workflows/execute_run_test.rb test/services/provider_execution test/integration/provider_backed_turn_execution_test.rb
```

Expected:

- missing executor, provider, or usage-persistence failures

**Step 3: Implement one real provider-backed turn path**

Rules:

- keep prompt building and compaction agent-program-owned
- use `simple_inference` as the shared provider substrate unless a focused
  protocol gap forces a local extension
- one provider-backed path is enough for this task
- persist authoritative provider usage and correlation data
- expose likely-model hints when known
- breaking changes are allowed in Phase 2

**Step 4: Update local behavior docs**

Document exact retained behavior for:

- provider-backed `turn_step` execution under workflow control
- authoritative provider usage capture
- advisory threshold evaluation based on post-run real usage
- hard-limit versus advisory-budget separation

**Step 5: Run the targeted tests**

Run:

```bash
cd core_matrix/vendor/simple_inference
bundle exec rake
cd ../..
bin/rails test test/services/workflows/execute_run_test.rb test/services/provider_execution test/integration/provider_backed_turn_execution_test.rb
```

Expected:

- targeted provider-backed execution tests pass

**Step 6: Run one focused provider smoke in development**

Use the mock provider for fast reruns and one real provider path for a focused
manual smoke if credentials are present.

Expected:

- one provider-backed run reaches terminal state
- provider usage facts are visible in durable records

**Step 7: Commit**

```bash
git -C .. add core_matrix/app/services/workflows/create_for_turn.rb core_matrix/app/services/workflows/execute_run.rb core_matrix/app/services/provider_execution core_matrix/app/models/workflow_run.rb core_matrix/app/models/workflow_node.rb core_matrix/app/models/agent_task_run.rb core_matrix/app/models/provider_usage_event.rb core_matrix/app/models/execution_profile_fact.rb core_matrix/app/services/turns/start_user_turn.rb core_matrix/vendor/simple_inference/lib/simple_inference core_matrix/vendor/simple_inference/test core_matrix/test/services/workflows/execute_run_test.rb core_matrix/test/services/provider_execution core_matrix/test/integration/provider_backed_turn_execution_test.rb core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md core_matrix/docs/behavior/provider-usage-events-and-rollups.md core_matrix/docs/behavior/execution-profiling-facts.md
git -C .. commit -m "feat: add provider-backed turn execution"
```

## Stop Point

Stop after one provider-backed turn path executes under workflow control and
persists authoritative usage.

Do not implement conversation feature policy, human interaction, or MCP in this
task.
