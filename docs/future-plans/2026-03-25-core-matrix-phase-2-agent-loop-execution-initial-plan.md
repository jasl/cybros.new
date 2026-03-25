# Core Matrix Phase 2 Agent Loop Execution Initial Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans only after this plan is promoted into `docs/plans` and refreshed against the post-phase-one codebase.

**Goal:** Turn the phase-one substrate into a real Core Matrix agent loop that works with `Fenix`, real providers, real tools, real recovery behavior, deployment rotation, and real manual validation.

**Architecture:** Phase 2 keeps the kernel authoritative. Core Matrix owns loop progression, workflow execution, feature gating, capability governance, and recovery semantics; `Fenix` and other agent programs may supply domain behavior, external capability implementations, and agent-program-owned skills, but durable side effects still flow back through kernel workflows. This initial plan remains pre-activation until a refreshed activation pass confirms the post-phase-one codebase and real validation environment.

**Tech Stack:** Rails 8.2, PostgreSQL, Active Storage, Minitest, request and integration tests, `bin/dev`, real LLM provider APIs, Streamable HTTP MCP, bundled `agents/fenix`.

---

## Status

This is a future-phase initial plan, not an active execution plan.

Phase 2 may take breaking changes freely:

- no backward-compatibility work is required for pre-phase-two experimental
  state
- no backfill or legacy-shape migration is required by default
- resetting the database is acceptable
- regenerating `schema.rb` is acceptable

Keep it in `docs/future-plans` until:

- the completed phase-one substrate batch has been re-read against the current
  codebase
- the structural-gate review is closed
- the actual post-phase-one file layout is known

When those conditions are true, rewrite this plan into `docs/plans` with exact
task ordering and file paths.

Before promotion, run:

- [2026-03-25-core-matrix-phase-2-milestone-agent-loop-execution.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-milestone-agent-loop-execution.md)
- [2026-03-25-core-matrix-phase-2-activation-checklist.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-activation-checklist.md)
- [2026-03-25-core-matrix-phase-2-activation-ready-outline.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-activation-ready-outline.md)
- [2026-03-25-core-matrix-phase-2-task-group-kernel-first-sequencing.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-group-kernel-first-sequencing.md)
- [2026-03-25-core-matrix-phase-2-task-structural-gate-and-scope-freeze.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-structural-gate-and-scope-freeze.md)
- [2026-03-25-core-matrix-phase-2-task-workflow-substrate-extensions.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-workflow-substrate-extensions.md)
- [2026-03-25-core-matrix-phase-2-task-agent-task-run-and-execution-contract-safety.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-agent-task-run-and-execution-contract-safety.md)
- [2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md)
- [2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md)
- [2026-03-25-core-matrix-phase-2-task-wait-state-human-interaction-and-subagents.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-wait-state-human-interaction-and-subagents.md)
- [2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md)
- [2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md)
- [2026-03-25-core-matrix-phase-2-task-external-fenix-pairing-and-deployment-rotation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-external-fenix-pairing-and-deployment-rotation.md)
- [2026-03-25-core-matrix-phase-2-task-streamable-http-mcp-under-governance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-streamable-http-mcp-under-governance.md)
- [2026-03-25-core-matrix-phase-2-task-fenix-skills-compatibility-and-operational-flows.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-fenix-skills-compatibility-and-operational-flows.md)
- [2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md)
- [2026-03-25-core-matrix-phase-2-task-run-verification-and-manual-acceptance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-run-verification-and-manual-acceptance.md)
- [2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md)
- [2026-03-25-core-matrix-workflow-proof-and-mermaid-export-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-workflow-proof-and-mermaid-export-design.md)
- [2026-03-25-agent-program-public-api-and-transport-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-agent-program-public-api-and-transport-research-note.md)
- [2026-03-25-core-matrix-agent-execution-delivery-contract-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-agent-execution-delivery-contract-design.md)
- [2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md)

## Preconditions

Before activation, confirm all of the following:

1. phase one has landed the workflow, runtime-resource, protocol, and recovery
   substrate it promised
2. the phase-one structural gate has either closed cleanly or produced explicit
   design corrections
3. `Fenix` is still the default bundled validation program for the next phase
4. at least one independently started external `Fenix` deployment path remains
   available for pairing validation
5. at least one mock provider path, one real provider path, and one real
   external capability path remain available for manual validation
6. a third-party skill source is available for manual validation, ideally
   [obra/superpowers](https://github.com/obra/superpowers)
7. `db:seed` can materialize the current real-provider credential baseline from
   the available `.env` secrets, including the OpenRouter path when present

## Formal Execution Units

Execute Phase 2 through these focused task documents, in dependency order:

1. [2026-03-25-core-matrix-phase-2-task-structural-gate-and-scope-freeze.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-structural-gate-and-scope-freeze.md)
   Confirms the landed Phase 1 substrate still supports the approved Phase 2
   shape and freezes scope before any implementation begins.
2. [2026-03-25-core-matrix-phase-2-task-workflow-substrate-extensions.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-workflow-substrate-extensions.md)
   Extends workflow-owned storage for yield, barrier, successor, and
   presentation metadata.
3. [2026-03-25-core-matrix-phase-2-task-agent-task-run-and-execution-contract-safety.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-agent-task-run-and-execution-contract-safety.md)
   Adds `AgentTaskRun` plus durable claim, heartbeat, progress, and terminal
   safety semantics.
4. [2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md)
   Proves one real provider-backed `turn_step` under workflow control.
5. [2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md)
   Makes feature gating and stale-work rejection authoritative kernel behavior.
6. [2026-03-25-core-matrix-phase-2-task-wait-state-human-interaction-and-subagents.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-wait-state-human-interaction-and-subagents.md)
   Proves wait handoff, human interaction, subagent orchestration, and
   resume or retry semantics.
7. [2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md)
   Lands unified tool-governance objects, policies, and binding freeze rules.
8. [2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md)
   Gives `Fenix` a real runtime surface, retained hooks, and estimation
   helpers.
9. [2026-03-25-core-matrix-phase-2-task-external-fenix-pairing-and-deployment-rotation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-external-fenix-pairing-and-deployment-rotation.md)
   Validates external pairing plus same-installation upgrade and downgrade
   rotation.
10. [2026-03-25-core-matrix-phase-2-task-streamable-http-mcp-under-governance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-streamable-http-mcp-under-governance.md)
    Adds one real Streamable HTTP MCP capability path under the unified
    governance model.
11. [2026-03-25-core-matrix-phase-2-task-fenix-skills-compatibility-and-operational-flows.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-fenix-skills-compatibility-and-operational-flows.md)
    Proves the system and third-party skill surface for `Fenix`.
12. [2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md)
    Builds the formal proof-export path and committed artifact package rules.
13. [2026-03-25-core-matrix-phase-2-task-run-verification-and-manual-acceptance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-run-verification-and-manual-acceptance.md)
    Runs the required automated verification, real-environment validation, and
    proof artifact capture.

## Dependency Notes

- Tasks 2 through 7 are the kernel-first substrate and execution path.
- Task 8 starts only after the execution contract and one provider-backed path
  are stable.
- Task 9 depends on Task 8 plus the kernel-side deployment and recovery
  contract.
- Task 10 depends on Task 7 and one usable `Fenix` runtime path.
- Task 11 depends on Task 8 and Task 9.
- Task 12 may start after Task 2 lands and should finish before Task 13.
- Task 13 is the final acceptance gate and should be last.

## Out Of Scope

Do not widen this phase into:

- Web UI productization
- workspace-owned trigger and delivery infrastructure
- IM, PWA, or desktop surfaces
- extension and plugin packaging
- kernel-owned prompt building
- kernel-owned universal compaction or summarization
- a `Fenix` self-update daemon or plugin marketplace

## Promotion Rule

Before promotion, the next planning pass should:

1. refresh this document against the actual codebase
2. keep the task order and file-path assumptions above in sync with the real
   codebase
3. move the execution-ready version into `docs/plans`
