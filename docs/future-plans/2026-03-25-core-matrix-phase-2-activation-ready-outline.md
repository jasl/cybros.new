# Core Matrix Phase 2 Activation-Ready Outline

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans only after this outline is refreshed into `docs/plans` against the activated Phase 2 scope.

**Goal:** Bridge the approved Phase 2 design into an activation-ready execution outline without promoting it early into `docs/plans`.

**Architecture:** `Core Matrix` remains the kernel authority for loop progression, feature gating, capability governance, and recovery. `Fenix` remains the default validation program, including external deployment rotation and agent-program-owned skills, but the final execution-ready task list should still be refreshed after the activation checklist passes.

**Tech Stack:** Rails 8.2, PostgreSQL, Minitest, request and integration tests, `bin/dev`, real LLM provider APIs, Streamable HTTP MCP, `agents/fenix`, real external deployment pairing.

---

## Status

Deferred companion outline for Phase 2.

Use this document to speed up plan promotion later. Do not treat it as the
final active implementation plan.

## Promotion Rule

Before Phase 2 moves into `docs/plans`, refresh this outline against:

- [2026-03-25-core-matrix-phase-2-activation-checklist.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-activation-checklist.md)
- [2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md)
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
- [2026-03-25-fenix-phase-2-validation-and-skills-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-fenix-phase-2-validation-and-skills-design.md)
- [2026-03-25-agent-program-public-api-and-transport-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-agent-program-public-api-and-transport-research-note.md)
- [2026-03-25-core-matrix-agent-execution-delivery-contract-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-agent-execution-delivery-contract-design.md)
- [2026-03-25-core-matrix-workflow-proof-and-mermaid-export-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-workflow-proof-and-mermaid-export-design.md)
- [2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md)

## Formal Task Map

Promote Phase 2 by carrying forward the exact task order from the initial plan:

1. structural gate and scope freeze
2. workflow substrate extensions
3. `AgentTaskRun` and execution contract safety
4. provider-backed turn execution
5. conversation feature policy and stale-work safety
6. wait-state handoff, human interaction, and subagents
7. unified capability governance
8. `Fenix` runtime surface and execution hooks
9. external `Fenix` pairing and deployment rotation
10. Streamable HTTP MCP under governance
11. `Fenix` skills compatibility and operational flows
12. workflow proof export and validation artifacts
13. run verification and manual acceptance

Use the task documents themselves as the detailed execution bodies. This outline
should stay short and promotion-focused.

## Promotion Checks

Before moving anything into `docs/plans`, confirm:

- task order still matches the real codebase
- task boundaries are still non-overlapping
- proof export remains a required acceptance artifact
- `Fenix` validation scenarios still cover bundled, external, rotation, skills,
  tool use, subagents, human interaction, and MCP

## Final Promotion Check

Do not promote this outline into `docs/plans` until:

- the activation checklist passes cleanly
- real provider credentials are ready
- the retained execution-budget and runtime-hook boundary is still accepted
- the chosen `Fenix` runtime shape is concrete
- the third-party skill validation source is confirmed
