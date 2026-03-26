# Core Matrix Phase 2 Task: Execution Environment Runtime Boundary Follow-Up

Part of `Core Matrix Phase 2: Agent Loop Execution`.

This is a `Milestone C` follow-up task. It executes after `Task C4` and before
later Phase 2 breadth tasks.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/README.md`
3. `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
4. `docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md`
5. `docs/plans/2026-03-26-core-matrix-phase-2-execution-environment-and-agent-runtime-boundary-design.md`
6. `docs/plans/2026-03-26-core-matrix-phase-2-plan-execution-environment-runtime-boundary.md`
7. `docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md`
8. `docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md`

## Purpose

Repair the runtime ownership boundary exposed by Milestone C so that:

- `ExecutionEnvironment` is the stable owner of runtime resources
- `AgentDeployment` is the rotatable Agent Program layer on that environment
- runtime pairing and mailbox control keep owner identity separate from the
  current delivery endpoint
- bundled runtimes such as `Fenix` expose explicit agent and environment planes
  even when one process serves both

## Scope

### In Scope

- environment-first runtime lineage
- stable `environment_fingerprint` contract for pairing and reconciliation
- conversation binding to one `ExecutionEnvironment`
- conversation-level agent switching within one bound environment
- environment capability refresh independent of deployment rotation
- environment-first tool precedence with reserved `core_matrix__*` system tools
- canonical plan and design cleanup so unattended execution reads one coherent
  authority chain

### Out Of Scope

- later Phase 2 breadth tasks beyond the runtime-boundary correction
- Web UI productization
- independent user-facing environment selection UX

## Required Outcomes

- `ProcessRun` and future environment-backed tools are unambiguously
  `ExecutionEnvironment`-owned
- `ExecutionEnvironment` reconciliation uses a stable installation-local
  `environment_fingerprint` and never guesses from deployment-only metadata
- mailbox control routes by environment owner and resolves the active delivery
  endpoint separately
- conversation capability and attachment policy refresh on both:
  - active deployment switch
  - environment capability change
- capability publication exposes explicit `agent_plane`,
  `environment_plane`, and `effective_tool_catalog`
- `core_matrix__*` system tools remain kernel-owned and outside ordinary name
  collision rules
- the follow-up remains inside the existing Phase 2 protocol E2E harness

## Verification

The detailed execution steps, test order, and commit boundaries live in:

- [2026-03-26-core-matrix-phase-2-plan-execution-environment-runtime-boundary.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-plan-execution-environment-runtime-boundary.md)

At minimum, verification must include:

- model tests for environment ownership and conversation binding
- pairing tests for stable environment reuse across deployment rotation
- conversation mutation tests for active deployment switching
- environment capability refresh tests independent of deployment rotation
- mailbox control and protocol E2E tests for environment-owner routing
- Fenix manifest and runtime tests for dual-plane publication and handling

## Stop Point

Stop after the follow-up design is fully reflected in schema, runtime protocol,
pairing, capability composition, tests, and authoritative Phase 2
documentation.
