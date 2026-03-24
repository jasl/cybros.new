# Core Matrix Kernel Phase 3: Conversation And Runtime

Use this phase index together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

This phase owns Tasks 07-10:

- [Task 07 Index: Rebuild Conversation Tree, Turn Core, And Variant Selection](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-07-conversation-and-turn-foundations.md)
- [Task 07.1: Build Conversation Structure](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-07-1-conversation-structure.md)
- [Task 07.2: Build Turn Entry And Override State](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-07-2-turn-entry-and-override-state.md)
- [Task 07.3: Build Rewrite And Variant Operations](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-07-3-rewrite-and-variant-operations.md)
- [Task 08 Index: Add Transcript Support Models For Attachments, Imports, Summaries, And Visibility](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-08-transcript-support-models.md)
- [Task 08.1: Add Visibility And Attachments](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-08-1-visibility-and-attachments.md)
- [Task 08.2: Add Imports And Summary Segments](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-08-2-imports-and-summary-segments.md)
- [Task 09 Index: Rebuild Workflow Core, Context Assembly, And Scheduling Rules](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-09-workflow-core-and-scheduling.md)
- [Task 09.1: Build Workflow Graph Foundations](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-09-1-workflow-graph-foundations.md)
- [Task 09.2: Add Scheduler And Wait States](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-09-2-scheduler-and-wait-states.md)
- [Task 09.3: Add Model Selector Resolution](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-09-3-model-selector-resolution.md)
- [Task 09.4: Add Context Assembly And Execution Snapshot](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-09-4-context-assembly-and-execution-snapshot.md)
- [Task 10 Index: Add Execution Resources, Conversation Events, Human Interactions, Canonical Variables, And Lease Control](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-10-runtime-resources-and-lease-control.md)
- [Task 10.1: Add Workflow Artifacts, Node Events, And Process Runs](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-10-1-artifacts-events-and-process-runs.md)
- [Task 10.2: Add Human Interactions And Conversation Events](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-10-2-human-interactions-and-conversation-events.md)
- [Task 10.3: Add Canonical Variables](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-10-3-canonical-variables.md)
- [Task 10.4: Add Subagents And Leases](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-10-4-subagents-and-leases.md)

Phase goals:

- build conversation kinds, purposes, archive lifecycle, and turn foundations
- preserve transcript support behavior including attachments, imports, summaries, and visibility overlays
- build turn-scoped workflow DAG execution, model selection, and context assembly
- add runtime resources including processes, subagents, human interactions, canonical variables, conversation events, and leases

Cross-cutting notes:

- this phase carries the approved automation-conversation base only: `automation` purpose, structured turn-origin metadata, and workflow support for automation-origin turns without a transcript-bearing user message
- this phase does not implement `AutomationTrigger`, schedule parsing, recurring execution, or webhook ingress
- swarm or multi-agent behavior must remain expressed as workflow DAG fan-out and fan-in through `SubagentRun`, not a separate orchestration aggregate

Execution rules:

- execute the task and subtask documents in order
- load only the active execution-unit document during implementation
- treat this file as the phase ordering index, not as the detailed task body
- apply the shared guardrails and phase-gate audits from the implementation-plan index after every task or subtask
