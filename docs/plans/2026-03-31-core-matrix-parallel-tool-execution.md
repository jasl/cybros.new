# Core Matrix Graph-First Parallel Tool Execution Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add graph-first parallel tool execution to `core_matrix` by extending
tool definitions with frozen execution metadata, materializing parallel-safe
tool batches as workflow stages, and preserving ordered tool-result re-entry
into the next provider round.

**Architecture:** `Core Matrix` stays graph-first. Provider rounds only
normalize model tool calls and hand them to workflow batch materialization.
Scheduler-visible stages are derived from frozen `execution_policy`
metadata. The first rollout only activates `execution_policy.parallel_safe`,
defaults every tool and every MCP tool to `false`, and enables a small audited
whitelist.

**Tech Stack:** Ruby on Rails, Minitest, workflow DAG materialization,
provider execution services, tool binding snapshots, JSON capability payloads.

---

## Task 1: Freeze Tool Execution Policy In The Capability Snapshot

**Files:**
- Modify: `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- Modify: `core_matrix/app/services/tool_bindings/freeze_for_workflow_node.rb`
- Modify: `core_matrix/app/models/tool_binding.rb`
- Test: `core_matrix/test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb`
- Test: `core_matrix/test/services/tool_bindings/freeze_for_workflow_node_test.rb`
- Test: `core_matrix/test/models/tool_binding_test.rb`

**Step 1: Write the failing tests**

Add assertions that every frozen tool entry carries an `execution_policy`
object and that `parallel_safe` defaults to `false`.

**Step 2: Run the focused tests and confirm they fail**

Run: `cd core_matrix && bin/rails test test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb test/services/tool_bindings/freeze_for_workflow_node_test.rb test/models/tool_binding_test.rb`

Expected: FAIL because frozen tool catalogs do not yet include execution policy.

**Step 3: Implement the minimal policy shape**

Extend the effective tool catalog and frozen binding payloads to persist:

```json
{
  "execution_policy": {
    "parallel_safe": false
  }
}
```

**Step 4: Re-run the focused tests**

Run: `cd core_matrix && bin/rails test test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb test/services/tool_bindings/freeze_for_workflow_node_test.rb test/models/tool_binding_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb core_matrix/app/services/tool_bindings/freeze_for_workflow_node.rb core_matrix/app/models/tool_binding.rb core_matrix/test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb core_matrix/test/services/tool_bindings/freeze_for_workflow_node_test.rb core_matrix/test/models/tool_binding_test.rb
git commit -m "feat: freeze tool execution policy metadata"
```

## Task 2: Add MCP Policy Overlay Resolution

**Files:**
- Create: `core_matrix/app/services/runtime_capabilities/resolve_tool_execution_policy.rb`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- Modify: `core_matrix/app/models/agent_deployment.rb`
- Test: `core_matrix/test/services/runtime_capabilities/resolve_tool_execution_policy_test.rb`
- Test: `core_matrix/test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb`

**Step 1: Write the failing tests**

Cover:

- built-in tools default to `parallel_safe = false`
- MCP tools default to `parallel_safe = false`
- an overlay can mark a matched MCP tool as `parallel_safe = true`
- unmatched MCP tools remain `false`

**Step 2: Run the focused tests and confirm the resolver is missing**

Run: `cd core_matrix && bin/rails test test/services/runtime_capabilities/resolve_tool_execution_policy_test.rb test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb`

Expected: FAIL because no resolver or overlay merge exists.

**Step 3: Implement the resolver**

Resolve policy in this order:

1. tool definition default
2. source default
3. deployment overlay

Keep the first rollout limited to `parallel_safe`.

**Step 4: Re-run the focused tests**

Run: `cd core_matrix && bin/rails test test/services/runtime_capabilities/resolve_tool_execution_policy_test.rb test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/runtime_capabilities/resolve_tool_execution_policy.rb core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb core_matrix/app/models/agent_deployment.rb core_matrix/test/services/runtime_capabilities/resolve_tool_execution_policy_test.rb core_matrix/test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb
git commit -m "feat: add tool execution policy overlays"
```

## Task 3: Materialize Provider Tool Calls Into Workflow Stages

**Files:**
- Create: `core_matrix/app/services/provider_execution/build_tool_execution_batch.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Modify: `core_matrix/app/services/provider_execution/normalize_provider_response.rb`
- Test: `core_matrix/test/services/provider_execution/build_tool_execution_batch_test.rb`
- Test: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`
- Test: `core_matrix/test/services/provider_execution/normalize_provider_response_test.rb`

**Step 1: Write the failing tests**

Cover:

- one non-parallel tool call produces one serial stage
- consecutive parallel-safe tool calls produce one parallel stage
- a non-parallel-safe call splits the batch into separate stages
- original tool-call order is preserved in the manifest

**Step 2: Run the focused tests and confirm batching is absent**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/build_tool_execution_batch_test.rb test/services/provider_execution/execute_round_loop_test.rb test/services/provider_execution/normalize_provider_response_test.rb`

Expected: FAIL because provider execution still treats tool calls as a flat list.

**Step 3: Implement stage packing**

Pack normalized tool calls into ordered stages using frozen
`execution_policy.parallel_safe`.

Map them to existing workflow batch semantics:

- one unsafe call -> serial stage
- consecutive safe calls -> parallel stage
- every stage -> `wait_all`

**Step 4: Re-run the focused tests**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/build_tool_execution_batch_test.rb test/services/provider_execution/execute_round_loop_test.rb test/services/provider_execution/normalize_provider_response_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/provider_execution/build_tool_execution_batch.rb core_matrix/app/services/provider_execution/execute_round_loop.rb core_matrix/app/services/provider_execution/normalize_provider_response.rb core_matrix/test/services/provider_execution/build_tool_execution_batch_test.rb core_matrix/test/services/provider_execution/execute_round_loop_test.rb core_matrix/test/services/provider_execution/normalize_provider_response_test.rb
git commit -m "feat: materialize provider tool calls into workflow stages"
```

## Task 4: Route Parallel Stages Through Workflow Batch Materialization

**Files:**
- Modify: `core_matrix/app/services/workflows/intent_batch_materialization.rb`
- Modify: `core_matrix/app/services/provider_execution/route_tool_call.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Test: `core_matrix/test/services/workflows/intent_batch_materialization_test.rb`
- Test: `core_matrix/test/services/provider_execution/route_tool_call_test.rb`
- Test: `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`

**Step 1: Write the failing tests**

Add coverage showing that:

- parallel-safe sibling tool calls become a `dispatch_mode = parallel` stage
- the stage produces a `wait_all` barrier artifact
- execution resumes only after all sibling nodes complete

**Step 2: Run the focused tests and confirm provider tools are not yet graph-first**

Run: `cd core_matrix && bin/rails test test/services/workflows/intent_batch_materialization_test.rb test/services/provider_execution/route_tool_call_test.rb test/services/provider_execution/execute_turn_step_test.rb`

Expected: FAIL because tool execution is not yet fully expressed through
workflow stage materialization.

**Step 3: Reuse the existing workflow batch semantics**

Do not add a new concurrency mechanism. Reuse:

- `dispatch_mode = parallel`
- `completion_barrier = wait_all`

Make provider tool execution consume those existing semantics.

**Step 4: Re-run the focused tests**

Run: `cd core_matrix && bin/rails test test/services/workflows/intent_batch_materialization_test.rb test/services/provider_execution/route_tool_call_test.rb test/services/provider_execution/execute_turn_step_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/workflows/intent_batch_materialization.rb core_matrix/app/services/provider_execution/route_tool_call.rb core_matrix/app/services/provider_execution/execute_turn_step.rb core_matrix/test/services/workflows/intent_batch_materialization_test.rb core_matrix/test/services/provider_execution/route_tool_call_test.rb core_matrix/test/services/provider_execution/execute_turn_step_test.rb
git commit -m "feat: execute tool stages through workflow barriers"
```

## Task 5: Preserve Original Tool Result Order Across Parallel Completion

**Files:**
- Create: `core_matrix/app/services/provider_execution/aggregate_tool_stage_results.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Test: `core_matrix/test/services/provider_execution/aggregate_tool_stage_results_test.rb`
- Test: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`

**Step 1: Write the failing tests**

Cover one stage where tool completion order differs from model call order and
assert that the next provider input still reflects original call order.

**Step 2: Run the focused tests and confirm ordering logic is missing**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/aggregate_tool_stage_results_test.rb test/services/provider_execution/execute_round_loop_test.rb`

Expected: FAIL because completion order currently drives aggregation.

**Step 3: Implement ordered aggregation**

Aggregate by original normalized tool-call sequence, not completion order.

**Step 4: Re-run the focused tests**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/aggregate_tool_stage_results_test.rb test/services/provider_execution/execute_round_loop_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/provider_execution/aggregate_tool_stage_results.rb core_matrix/app/services/provider_execution/execute_round_loop.rb core_matrix/test/services/provider_execution/aggregate_tool_stage_results_test.rb core_matrix/test/services/provider_execution/execute_round_loop_test.rb
git commit -m "fix: preserve provider tool result ordering"
```

## Task 6: Add The First Audited Allowlist

**Files:**
- Modify: `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- Modify: `core_matrix/app/services/provider_execution/route_tool_call.rb`
- Test: `core_matrix/test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb`
- Test: `core_matrix/test/services/provider_execution/route_tool_call_test.rb`
- Doc: `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-31-core-matrix-parallel-tool-execution-design.md`

**Step 1: Write the failing tests**

Add assertions for a minimal audited allowlist:

- selected read-only tools resolve to `parallel_safe = true`
- command, browser, process-control, and MCP tools remain `false`

**Step 2: Run the focused tests and confirm the allowlist does not exist**

Run: `cd core_matrix && bin/rails test test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb test/services/provider_execution/route_tool_call_test.rb`

Expected: FAIL because every tool still resolves to the same policy.

**Step 3: Implement the first audited allowlist**

Keep it intentionally small and document each included tool family.

**Step 4: Re-run the focused tests**

Run: `cd core_matrix && bin/rails test test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb test/services/provider_execution/route_tool_call_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb core_matrix/app/services/provider_execution/route_tool_call.rb core_matrix/test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb core_matrix/test/services/provider_execution/route_tool_call_test.rb docs/plans/2026-03-31-core-matrix-parallel-tool-execution-design.md
git commit -m "feat: add initial parallel-safe tool allowlist"
```

## Task 7: Verification And Proof

**Files:**
- Test: `core_matrix/test/integration/provider_backed_turn_execution_test.rb`
- Test: `core_matrix/test/integration/human_interaction_and_subagent_flow_test.rb`
- Test: `core_matrix/test/queries/workflows/proof_export_query_test.rb`
- Doc: update any acceptance or proof docs created by this follow-up

**Step 1: Run the focused integration and proof tests**

Run: `cd core_matrix && bin/rails test test/integration/provider_backed_turn_execution_test.rb test/integration/human_interaction_and_subagent_flow_test.rb test/queries/workflows/proof_export_query_test.rb`

Expected: PASS with explicit proof of parallel stages and wait barriers.

**Step 2: Run the project verification matrix**

Run:

```bash
cd core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
```

Expected: PASS.

**Step 3: Commit**

```bash
git add core_matrix/test/integration/provider_backed_turn_execution_test.rb core_matrix/test/integration/human_interaction_and_subagent_flow_test.rb core_matrix/test/queries/workflows/proof_export_query_test.rb
git commit -m "test: verify graph-first parallel tool execution"
```
