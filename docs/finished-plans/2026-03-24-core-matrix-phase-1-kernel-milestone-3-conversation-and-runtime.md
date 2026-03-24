# Core Matrix Kernel Milestone 3: Conversation And Runtime

Use this milestone index together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
4. `docs/future-plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

This milestone owns Task Groups 07-10 and their child tasks:

- [Task Group 07: Rebuild Conversation Tree, Turn Core, And Variant Selection](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-group-07-conversation-and-turn-foundations.md)
- [Task 07.1: Build Conversation Structure](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-07-1-conversation-structure.md)
- [Task 07.2: Build Turn Entry And Override State](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-07-2-turn-entry-and-override-state.md)
- [Task 07.3: Build Rewrite And Variant Operations](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-07-3-rewrite-and-variant-operations.md)
- [Task Group 08: Add Transcript Support Models For Attachments, Imports, Summaries, And Visibility](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-group-08-transcript-support-models.md)
- [Task 08.1: Add Visibility And Attachments](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-08-1-visibility-and-attachments.md)
- [Task 08.2: Add Imports And Summary Segments](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-08-2-imports-and-summary-segments.md)
- [Task Group 09: Rebuild Workflow Core, Context Assembly, And Scheduling Rules](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-group-09-workflow-core-and-scheduling.md)
- [Task 09.1: Build Workflow Graph Foundations](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-09-1-workflow-graph-foundations.md)
- [Task 09.2: Add Scheduler And Wait States](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-09-2-scheduler-and-wait-states.md)
- [Task 09.3: Add Model Selector Resolution](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-09-3-model-selector-resolution.md)
- [Task 09.4: Add Context Assembly And Execution Snapshot](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-09-4-context-assembly-and-execution-snapshot.md)
- [Task Group 10: Add Execution Resources, Conversation Events, Human Interactions, Canonical Variables, And Lease Control](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-group-10-runtime-resources-and-lease-control.md)
- [Task 10.1: Add Workflow Artifacts, Node Events, And Process Runs](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-10-1-artifacts-events-and-process-runs.md)
- [Task 10.2: Add Human Interactions And Conversation Events](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-10-2-human-interactions-and-conversation-events.md)
- [Task 10.3: Add Canonical Variables](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-10-3-canonical-variables.md)
- [Task 10.4: Add Subagents And Leases](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-10-4-subagents-and-leases.md)

Milestone goals:

- build conversation kinds, purposes, archive lifecycle, and turn foundations
- preserve transcript support behavior including attachments, imports, summaries, and visibility overlays
- build turn-scoped workflow DAG execution, model selection, and context assembly
- add runtime resources including processes, subagents, human interactions, canonical variables, conversation events, and leases

Cross-cutting notes:

- this milestone carries the approved automation-conversation base only: `automation` purpose, structured turn-origin metadata, and workflow support for automation-origin turns without a transcript-bearing user message
- this milestone does not implement `AutomationTrigger`, schedule parsing, recurring execution, or webhook ingress
- swarm or multi-agent behavior must remain expressed as workflow DAG fan-out and fan-in through `SubagentRun`, not a separate orchestration aggregate

Execution rules:

- execute the task documents in order
- load only the active execution-unit document during implementation
- treat this file as the milestone ordering index, not as the detailed task body
- apply the shared guardrails and execution-gate audits from the implementation-plan index after every task
- if a child task consults `references/` or external implementations, write the retained conclusion into that task document and any local docs it updates; do not leave only a bare reference path behind

## Completion Record

- status:
  completed on `2026-03-25`
- completed scope:
  - Task Group 07 rebuilt conversation structure, turn core, rewrite, and
    variant selection
  - Task Group 08 rebuilt transcript support models for visibility,
    attachments, imports, and summary segments
  - Task Group 09 rebuilt workflow graph, scheduler, model-selector
    resolution, and execution context assembly
  - Task Group 10 rebuilt runtime resources for processes, human
    interactions, conversation events, canonical variables, subagent
    coordination, and lease control
- verification carry-forward:
  - child tasks completed with targeted tests, broader runtime-regression test
    passes, and behavior-doc alignment before commit
  - Milestone 3 now covers the required conversation-runtime baseline called
    out in the greenfield design, including transcript support, wait states,
    runtime event streams, human interaction resume, canonical variables, and
    explicit lease ownership
