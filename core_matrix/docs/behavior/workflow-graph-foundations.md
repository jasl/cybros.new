# Workflow Graph Foundations

## Purpose

Task 09.1 introduces the durable workflow graph substrate for one turn.

The workflow graph is modeled as a turn-owned `WorkflowRun` plus append-only
`WorkflowNode` and `WorkflowEdge` rows. It is not a conversation-wide graph and
it is not a reusable template.

## Workflow Run Behavior

- A `Turn` owns exactly one `WorkflowRun`.
- A `Conversation` may accumulate historical workflow runs over time, but v1
  allows only one `active` workflow run in a conversation at once.
- `WorkflowRun` belongs to one installation, one conversation, and one turn.
- Installation and conversation identity must stay aligned across the run and
  its owning turn.
- Supported v1 lifecycle states are:
  - `active`
  - `completed`
  - `failed`
  - `canceled`

## Workflow Node Behavior

- `WorkflowNode` rows belong to one workflow run and are ordered by an
  append-only `ordinal`.
- Node ordinals are unique within a workflow run.
- Node keys are unique within a workflow run and act as mutation-time lookup
  handles.
- Supported v1 decision sources are:
  - `llm`
  - `agent_program`
  - `system`
  - `user`
- Node metadata is stored as structured `jsonb` and must stay a hash.
- Policy-sensitive execution markers are carried explicitly in node metadata,
  for example `metadata["policy_sensitive"]`, rather than inferred later from
  transcript text.

## Workflow Edge Behavior

- `WorkflowEdge` rows belong to one workflow run and connect one `from_node` to
  one `to_node`.
- Both endpoint nodes must belong to the same workflow run as the edge.
- Self-loops are rejected.
- Edge ordinals are ordered per predecessor node, not globally across the whole
  workflow.
- For a given `from_node`, edge ordinals begin at `0` and append upward as new
  edges are added.

## Service Behavior

- `Workflows::CreateForTurn` creates an `active` workflow run and seeds one root
  node at ordinal `0`.
- `Workflows::Mutate` appends nodes and edges to an existing workflow run
  without replacing the run row.
- Node and edge ordinal allocation is serialized at the workflow-run boundary
  so concurrent graph mutations keep append-only ordering without duplicate
  ordinal failures.
- Mutation uses database-scoped workflow queries instead of relying on a cached
  Active Record association on the caller's `workflow_run` instance. This keeps
  repeated mutations consistent even when the same in-memory run object is
  reused across calls.
- After appending edges, mutation walks the full persisted graph and rejects any
  mutation that would make the workflow cyclic.

## Invariants

- one workflow run per turn
- at most one active workflow run per conversation in v1
- workflow nodes and edges remain subordinate to one workflow run
- workflow mutation is append-only for graph structure in this task
- the workflow graph must remain acyclic after every mutation
- explicit node metadata is the durable source for policy-sensitive execution
  markers

## Failure Modes

- creating a second workflow run for the same turn is rejected
- creating a second active workflow run in the same conversation is rejected
- creating a node with a duplicate ordinal or duplicate node key is rejected
- creating an edge that crosses workflow boundaries is rejected
- creating a self-loop edge is rejected
- mutating a workflow in a way that would introduce a cycle raises
  `ActiveRecord::RecordInvalid` on the workflow run
- mutating a workflow with an edge that references a missing node key raises
  `ActiveRecord::RecordInvalid` on the workflow run instead of leaking a raw
  lookup exception

## Rails And Reference Findings

- Local Rails source confirmed that `enum ... validate: true` is the right
  pattern when lifecycle and decision-source values should fail validation on
  `valid?` rather than by immediate assignment-time `ArgumentError`.
- Local Rails guides confirmed the self-referential
  `foreign_key: { to_table: :workflow_nodes }` pattern for `from_node` and
  `to_node` references.
- A narrow Dify sanity check showed Dify primarily persists workflow runs and
  node execution history around a runtime-state engine. Core Matrix intentionally
  keeps the turn-scoped graph structure itself durable in SQL because later
  scheduler, wait-state, and audit tasks need explicit append-only node and edge
  records before execution history is layered on top.
