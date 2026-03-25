# Core Matrix Workflow Proof And Mermaid Export Design

## Status

Approved focused design note for Phase 2 workflow proof artifacts.

This document narrows one question only: how Phase 2 should export workflow
execution into Mermaid and proof records so manual validation has durable,
inspectable evidence.

## Purpose

Use this document to define:

- why workflow Mermaid export is a Phase 2 acceptance artifact
- what the exporter should and should not render
- what a proof record must contain
- how exporter read paths should stay query-efficient

## Decision Summary

- Workflow Mermaid export is part of Phase 2 acceptance, not an optional debug
  convenience.
- Manual validation should produce both a human-readable proof record and raw
  Mermaid artifacts for selected runs.
- The exporter should render `WorkflowRun`, `WorkflowNode`, and workflow edges,
  plus selected summaries from `WorkflowNodeEvent`.
- The exporter should not render every event as a graph node.
- Proof artifacts should make yield, wait, resume, and bounded parallelism easy
  to inspect.
- Export read paths should follow the same query-efficiency rules as the rest
  of the kernel: bounded eager loading, no N+1 traversal, and no fragile
  graph-reconstruction SQL.

## Why Phase 2 Needs Proof Artifacts

Phase 2 is proving that workflow is the real execution model, not just an
internal implementation detail.

That means manual validation needs evidence strong enough to answer:

- did yield and resume really materialize as workflow execution
- did blocking resources create the expected wait boundaries
- did successor agent steps appear where they should
- did bounded parallel subagent stages produce the intended join shape
- did internal-only versus trackable or user-projectable nodes appear as
  expected

Logs alone are not enough. Graph-shaped proof is the right artifact for this
phase.

## Export Scope

The exporter should start from one `WorkflowRun`.

Minimum rendered objects:

- `WorkflowNode`
- workflow edges
- selected node-local summaries derived from `WorkflowNodeEvent`

Minimum node label content:

- workflow node kind
- state
- short semantic label when available
- `presentation_policy` when relevant to the proof scenario

Useful optional summaries:

- blocking resource type or ref
- yield or intent-batch marker
- join or barrier hint

The exporter should avoid:

- full transcript content
- dumping every `WorkflowNodeEvent` as its own graph node
- mixing workflow proof with UI projection rendering

## Proof Record Shape

Each proof record should include at least:

- scenario name
- run count or run index
- execution date
- environment
- model ref or provider path when relevant
- workflow or conversation identifiers
- workflow node and edge counts
- Mermaid file path
- short operator note

Recommended artifact package:

- one raw `.mmd` file per exported workflow run
- one proof markdown record summarizing the scenarios and artifact paths

## Phase 2 Minimum Proof Scenarios

The proof set should include at least:

- persistent compaction materialized through workflow execution
- non-blocking best-effort title update
- bounded parallel `subagent_spawn` under `wait_all`
- one wait and resume path such as human interaction or equivalent blocking
  resource

Each scenario should make the workflow shape legible enough to confirm:

- where the yielding agent step stopped
- which nodes materialized from kernel-governed intentions
- whether a blocking barrier occurred
- where the successor agent step resumed

## Query-Efficiency Rules

The exporter is a proof surface, but it still should not get a free pass on
read-path quality.

Rules:

- exporter reads should use bounded eager loading and explicit query objects
- exporter reads should not depend on N+1 traversal through nodes, edges, or
  events
- redundant read-facing fields such as `conversation_id`, `turn_id`,
  `presentation_policy`, or blocking-resource summary refs may be used when
  that keeps the proof query simple
- graph reconstruction should prefer stable workflow tables and precomputed
  summaries instead of clever SQL that is hard to maintain

## Interaction With Presentation Policy

Proof export should respect `presentation_policy`, but not hide too much.

Recommended Phase 2 behavior:

- include `internal_only` nodes in proof export by default, because proof needs
  to verify kernel behavior even when the eventual UI would hide that node
- visually mark `presentation_policy` in node labels when it matters to the
  scenario
- keep future UI filtering separate from proof export filtering

## Phase 2 Non-Goals

This design does not require Phase 2 to ship:

- a browser-native graph viewer
- a live-updating graph UI
- a general-purpose workflow analytics suite
- arbitrary graph-diff tooling across runs

Phase 2 only needs reliable export and proof artifacts.

## Reference Index

These local references informed the pattern, but they are not the source of
truth:

- [/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/dag/visualization/mermaid_exporter.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/lib/dag/visualization/mermaid_exporter.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/docs/reports/2026-03-16-agent-root-workspace-proof.md](/Users/jasl/Workspaces/Ruby/cybros/references/original/cybros/docs/reports/2026-03-16-agent-root-workspace-proof.md)

## Related Documents

- [2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md)
- [2026-03-25-core-matrix-phase-2-agent-loop-execution-follow-up.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-agent-loop-execution-follow-up.md)
- [2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md)
