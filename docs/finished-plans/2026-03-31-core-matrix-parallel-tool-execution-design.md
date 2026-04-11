# Core Matrix Graph-First Parallel Tool Execution Design

## Status

- Date: 2026-03-31
- Status: implemented
- Depends on:
  - `/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-31-core-matrix-loop-fenix-program-design.md`
  - `/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md`

## Goal

Add parallel tool execution to `Core Matrix` without bypassing the workflow
graph.

The core rule is unchanged:

- no hidden in-memory thread pool inside the provider loop
- no direct parallel execution that is invisible to workflow proof
- all parallelism must first become explicit DAG structure, then be scheduled

## Scope

This follow-up covers only provider-round tool parallelism.

It does not cover:

- speculative execution
- provider-specific partial-result continuation
- dynamic conflict inference from runtime state
- widening browser, process-control, or mutation-heavy tools into the first
  parallel rollout

## Decision Summary

- `Core Matrix` should extend tool definitions with execution metadata.
- The first execution metadata field is `execution_policy.parallel_safe`.
- The default is `false` for every tool.
- The default is also `false` for every MCP tool.
- Parallel execution is enabled only for tools explicitly audited and marked
  safe.
- Provider rounds that return multiple tool calls must materialize a staged
  workflow batch before any tool work starts.
- A stage is parallel only when every tool call in that stage resolves to
  `parallel_safe = true`.
- Stage completion uses the existing workflow batch semantics:
  - `dispatch_mode = parallel`
  - `completion_barrier = wait_all`
- Tool results must be reassembled in original model order before the next
  provider round is prepared.
- MCP widening should happen later through overlay policy, not by relaxing the
  kernel default.

## Implemented Shape

The current repository now implements this design in the following concrete
shape:

- `turn_step` nodes execute exactly one provider round
- provider tool calls materialize as explicit `tool_call` workflow nodes
- each stage fans in through a `barrier_join` node
- the next provider round resumes through a successor `turn_step` node
- prior tool results are rebuilt durably from ordered predecessor `tool_call`
  nodes
- `execution_policy.parallel_safe` is frozen onto tool definitions,
  implementations, and workflow-node bindings
- MCP tools remain `parallel_safe = false` by default
- overlay widening resolves from
  `CapabilitySnapshot.default_config_snapshot["tool_policy_overlays"]`
- the initial audited built-in allowlist contains only `subagent_list`

## Why Graph-First Matters

`Core Matrix` already has workflow-first yield and batch materialization
semantics. The right place to express tool parallelism is therefore the graph,
not the provider loop.

If a provider round returns multiple tool calls and the runtime executes them
concurrently without graph materialization, the system loses:

- durable stage boundaries
- explicit sibling-node proof
- barrier visibility
- replay and retry semantics
- conflict reasoning at the scheduler boundary

The graph must remain the single source of truth for concurrent work.

## Tool Execution Metadata

Tool definitions should grow a small execution policy block.

Initial shape:

```json
{
  "execution_policy": {
    "parallel_safe": false
  }
}
```

Rules:

- absent policy is equivalent to `parallel_safe = false`
- scheduler consumes only the frozen resolved value
- provider execution does not special-case tool names once policy is frozen

This shape is intentionally future-proof. Later follow-up fields may include:

- `mutation_kind`
- `conflict_scope`
- `resource_keys`

The first rollout only activates `parallel_safe`.

## MCP Policy

MCP tools should expose the same execution policy shape, but the kernel default
must remain conservative.

Rules:

- all MCP tools resolve to `parallel_safe = false` by default
- no MCP class is implicitly parallel because it is read-oriented
- internal or trusted MCP tools may be widened later through overlays
- the kernel should not need a code change to reclassify one internal MCP tool

Recommended overlay shape:

```json
{
  "match": {
    "tool_source": "mcp",
    "server_slug": "internal-docs",
    "tool_name": "read_page"
  },
  "execution_policy": {
    "parallel_safe": true
  }
}
```

The overlay is a policy override, not a schema override. It may change
execution metadata, but it must not redefine tool parameters or tool behavior.

## Policy Resolution Order

`Core Matrix` should resolve execution policy in a deterministic order and then
freeze the result into the workflow-facing snapshot.

Recommended order:

1. kernel tool definition defaults
2. tool-source defaults
3. deployment or environment overlays
4. workflow-node-scoped frozen capability snapshot

The scheduler must consume only the frozen value from step 4.

## Provider Round Materialization

Provider rounds remain responsible for asking the model what to do next. They
do not execute parallel work directly.

When a provider response contains tool calls:

1. normalize the tool calls into ordered tool-intent candidates
2. resolve each candidate's frozen execution policy
3. pack candidates into ordered stages
4. materialize those stages as workflow-owned nodes
5. let the scheduler dispatch them
6. wait for the stage barrier
7. aggregate ordered tool results
8. prepare the next provider round

## Stage Packing Rule

The first rollout should use a simple, safe packing rule.

- if a tool call is not `parallel_safe`, it must form its own serial stage
- if consecutive tool calls are all `parallel_safe`, they may be packed into the
  same parallel stage
- the next non-parallel-safe tool call closes the current parallel stage

Example:

```text
provider_round_1
  -> stage_1 parallel: [tool_a, tool_b]
  -> join_1
  -> stage_2 serial: [tool_c]
  -> join_2
  -> provider_round_2
```

This mirrors the conservative batching approach used by existing agent
implementations while keeping the true structure explicit in the workflow DAG.

## Scheduler Rule

The scheduler does not need a new concurrency concept. It should reuse the
existing stage semantics already present in workflow batch materialization.

- `dispatch_mode = parallel` means sibling tool nodes in the same stage may
  execute concurrently
- `completion_barrier = wait_all` means the parent provider flow does not
  re-enter until all sibling tool nodes complete

This keeps the provider loop thin and pushes concurrency ownership to the graph
and scheduler.

## Result Ordering

Parallel execution must not reorder the transcript or the next provider input.

Rules:

- tool nodes may finish in any order
- durable proof records actual completion order
- the aggregated provider-round tool result list must be rebuilt in original
  tool-call order
- the next provider round receives ordered results that match the model's
  original call sequence

This avoids transcript drift and keeps provider behavior deterministic.

## First Rollout Allowlist

The first rollout should whitelist only clearly read-only tools that do not
mutate shared runtime state.

Good initial candidates:

- filesystem read helpers
- search helpers
- page fetch helpers
- explicitly audited read-only agent tools

Explicitly out of scope for the first rollout:

- command execution
- process control
- browser interaction
- skill-backed tools with mutable local context
- MCP tools unless widened by later overlay policy

## Loop Safety

Parallel execution should not depend on `max_rounds` alone for safety.

This follow-up should remain compatible with a later loop-detection layer.

Current guidance:

- keep `loop_policy.max_rounds` as the total round fuse
- do not introduce `max_tool_calls` as a surrogate
- add progress-aware loop detection in a later follow-up

## Acceptance Criteria

This design is complete when:

- tool definitions can express `execution_policy.parallel_safe`
- all tools and all MCP tools default to `false`
- provider rounds with multiple parallel-safe tool calls materialize a workflow
  batch with `dispatch_mode = parallel`
- serial and parallel stages both produce correct proof artifacts
- next-round tool results preserve original call order
- unsafe tools continue to materialize as serial stages
- MCP widening is possible only through overlay policy
