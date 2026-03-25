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
- what export query shape should look like
- where acceptance proof artifacts should live and how they should be named
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

## Exporter Object Model

Phase 2 should keep the exporter split into one read path and small rendering
services instead of one database-heavy blob.

Recommended shape:

- `Workflows::ProofExportQuery`
  - lives under `core_matrix/app/queries/workflows/`
  - reads one `WorkflowRun` proof bundle with eager-loaded workflow rows and
    selected event snippets
- `Workflows::Visualization::MermaidExporter`
  - lives under `core_matrix/app/services/workflows/visualization/`
  - accepts the query result bundle and returns Mermaid text only
- `Workflows::Visualization::ProofRecordRenderer`
  - lives under `core_matrix/app/services/workflows/visualization/`
  - accepts the same bundle plus operator-supplied scenario metadata and
    returns `proof.md` content

The query result should behave like an immutable proof bundle rather than a
live Active Record graph. Minimum contents:

- one workflow-run header
- ordered workflow nodes
- workflow edges
- selected event snippets or summaries keyed by node
- optional blocking-resource summaries for wait or resume scenarios

This split keeps the read path testable, keeps Mermaid rendering deterministic,
and avoids hiding SQL inside presentation code.

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

Recommended markdown shape:

```md
# <Scenario Title>

- Date: YYYY-MM-DD
- Environment: bin/dev
- Workspace: <workspace id or slug>
- Conversation: <conversation id>
- WorkflowRun: <workflow run id>
- Provider or Model Path: <provider/model ref>
- Node Count: <n>
- Edge Count: <n>
- Mermaid Artifact: ./run-<workflow-run-id>.mmd

## Expected Shape

- yield point: <short note>
- blocking barrier: <short note or none>
- successor agent step: <short note>
- presentation-policy note: <short note>

## Operator Notes

<brief observation of whether the graph matched the design>
```

The proof record should stay short. Its job is to make the raw artifact set
easy to review, not to duplicate the full transcript or runtime log.

## Manual Export Entry Point

Phase 2 should use the existing `script/manual/` convention for operator-facing
validation helpers.

Recommended entry point:

- `core_matrix/script/manual/workflow_proof_export.rb`

Recommended behavior:

- accept one explicit `workflow_run_id`
- accept one scenario slug or title
- accept one output directory
- write one Mermaid file for that workflow run
- create `proof.md` when absent, or update it only through an explicit flag

Recommended command shape:

```bash
cd core_matrix
ruby script/manual/workflow_proof_export.rb export \
  --workflow-run-id=<workflow_run_id> \
  --scenario=<scenario_slug> \
  --out=../docs/reports/phase-2/YYYY-MM-DD-<scenario-slug>
```

Recommended operational rules:

- refuse to overwrite existing artifacts unless `--force` is passed
- allow repeated runs against the same scenario directory by writing one
  `run-<workflow-run-id>.mmd` file per workflow run
- keep the command thin; query and rendering logic belong in application code,
  not in the script itself

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

## Export Query Shape

Phase 2 should not treat proof export as ad hoc controller logic.

Recommended shape:

- one query object or export loader rooted at `WorkflowRun`
- one bounded eager load for `WorkflowNode` rows in stable execution order
- one bounded eager load for workflow edges
- one bounded eager load for selected `WorkflowNodeEvent` summaries or
  precomputed event snippets
- optional eager load for workflow-owned blocking-resource refs when a proof
  scenario needs them

The exporter should avoid:

- joining transcript tables just to build node labels
- per-node follow-up lookups for event summaries
- graph reconstruction logic hidden in controller code

Suggested Phase 2 query object names:

- `Workflows::ProofExportQuery` for the core bundle loader
- optional follow-up extraction helpers only if one query becomes unwieldy

Suggested Phase 2 service names:

- `Workflows::Visualization::MermaidExporter`
- `Workflows::Visualization::ProofRecordRenderer`

Reasonable read-facing fields to denormalize or cache on workflow-owned rows
for this exporter include:

- `conversation_id`
- `turn_id`
- `presentation_policy`
- blocking-resource kind or id summary
- batch or yield marker refs
- stable node ordering keys

The exporter should prefer one predictable read path over clever SQL.

## Artifact Location And Naming

Phase 2 should distinguish temporary debug exports from acceptance artifacts.

Recommended rule:

- temporary local exports may live under `tmp/`
- acceptance proof artifacts should live under `docs/reports/phase-2/`

Recommended package layout:

- `docs/reports/phase-2/YYYY-MM-DD-<scenario-slug>/proof.md`
- `docs/reports/phase-2/YYYY-MM-DD-<scenario-slug>/run-<workflow-run-id>.mmd`
- `docs/reports/phase-2/YYYY-MM-DD-<scenario-slug>/run-<workflow-run-id>-2.mmd`
  when one scenario intentionally captures more than one run

Naming guidance:

- use one directory per proof scenario or proof batch
- keep scenario slugs short and human-readable
- use stable workflow-run identifiers in Mermaid file names
- do not treat machine-only temp paths as formal acceptance evidence
- prefer committed `proof.md` plus one-or-more `run-*.mmd` files over custom
  binary formats or mixed log dumps

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
- [2026-03-25-core-matrix-phase-2-milestone-agent-loop-execution.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-milestone-agent-loop-execution.md)
- [2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md)
