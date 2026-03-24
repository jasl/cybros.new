# Core Matrix Kernel Phase 3: Conversation And Runtime

Use this phase index together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

This phase owns Tasks 07-10:

- [Task 07: Rebuild Conversation Tree, Turn Core, And Variant Selection](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-07-conversation-and-turn-foundations.md)
- [Task 08: Add Transcript Support Models For Attachments, Imports, Summaries, And Visibility](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-08-transcript-support-models.md)
- [Task 09: Rebuild Workflow Core, Context Assembly, And Scheduling Rules](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-09-workflow-core-and-scheduling.md)
- [Task 10: Add Execution Resources, Conversation Events, Human Interactions, Canonical Variables, And Lease Control](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-10-runtime-resources-and-lease-control.md)

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

- execute the task documents in order
- load only the active task document during implementation
- treat this file as the phase ordering index, not as the detailed task body
- apply the shared guardrails and phase-gate audits from the implementation-plan index after every task
