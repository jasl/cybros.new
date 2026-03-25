# Core Matrix Phase 2 Milestone 1: Kernel Execution Foundations

Use this milestone index together with:

1. `AGENTS.md`
2. `docs/design/2026-03-25-core-matrix-platform-phases-and-validation-design.md`
3. `docs/design/2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md`
4. `docs/design/2026-03-25-core-matrix-agent-execution-delivery-contract-design.md`
5. `docs/future-plans/2026-03-25-core-matrix-phase-2-milestone-agent-loop-execution.md`
6. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

This milestone owns Tasks 01-05:

- [Task 01: Re-Run Structural Gate And Freeze Scope](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-01-structural-gate-and-scope-freeze.md)
- [Task 02: Extend Workflow Substrate For Yield And Projection](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-02-workflow-substrate-extensions.md)
- [Task 03: Add AgentTaskRun And Execution Contract Safety](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-03-agent-task-run-and-execution-contract-safety.md)
- [Task 04: Add Provider-Backed Turn Execution](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-04-provider-backed-turn-execution.md)
- [Task 05: Enforce Conversation Feature Policy And Stale-Work Safety](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-05-conversation-feature-policy-and-stale-work-safety.md)

Milestone goals:

- refresh the substrate and activation boundary against the landed Phase 1 code
- strengthen workflow-owned execution substrate before broader runtime features
- land a durable claimable execution contract through `AgentTaskRun`
- prove one provider-backed turn path under workflow control
- close the first correctness gap around conversation feature policy and
  stale-work rejection

Execution rules:

- execute the task documents in order
- load only the active task document during implementation
- treat this file as the milestone ordering index, not as the detailed task
  body
- breaking changes are allowed in Phase 2
- no backward-compatibility, backfill, or migration-heavy preservation work is
  required unless it directly reduces current implementation risk
- database reset and `schema.rb` regeneration are acceptable
- each task must update the relevant `core_matrix/docs/behavior/*` documents
  during the same execution unit when durable behavior changes
- Phase 1 substrate is the authority; Milestone 1 should consume it rather than
  rebuild it
- if a task consults `references/` or external implementations, write the
  retained conclusion into the task document and any local docs updated by the
  same execution unit
- if Tasks 01-05 reveal a root-shape issue in the substrate, fix it now rather
  than deferring it into later execution, MCP, or `Fenix` tasks

Milestone 1 completion gate:

- all five tasks are complete
- targeted automated verification for each task passes
- the milestone leaves the kernel with one safe provider-backed loop foundation
  and authoritative stale-work rejection
