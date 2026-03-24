# Core Matrix Phase 2 Activation Checklist

## Status

Deferred activation checklist for the next platform phase.

Use this document immediately before promoting any Phase 2 material from
`docs/future-plans` into `docs/plans`.

## Purpose

Phase 2 should begin only when the substrate is truly closed, the next-phase
execution target is explicit, and the real-environment validation path is
actually available.

This checklist exists to prevent:

- starting Phase 2 on top of unresolved substrate shape problems
- activating a plan without a real validation target
- widening Phase 2 scope beyond loop execution
- pretending real manual validation is available when it is not

## Activation Rule

Phase 2 is activatable only when every gate in this checklist is marked
`pass`.

If any gate is `fail` or `unknown`, do not move a Phase 2 plan into
`docs/plans`.

## Gate 1: Phase 1 Closure

Confirm all of the following:

- the active substrate batch in `docs/plans` is complete
- its required verification and manual-validation work is complete
- the phase-one structural gate has been re-run at the end of the batch
- any root-shape corrections discovered by that gate were handled before phase
  closure
- phase-one behavior docs match the landed code

Required evidence:

- completed phase-one verification record
- final phase-one structural-gate decision note
- clean mapping between landed code and `core_matrix/docs/behavior/`

## Gate 2: No Unresolved Root-Shape Ambiguity

Confirm there is no remaining ambiguity about the ownership roots or insertion
points that Phase 2 depends on.

At minimum, confirm the real codebase has a clear durable home for:

- workflow execution progression
- invocation attempts and failure lineage
- capability binding and availability state
- feature-policy snapshots on running work
- runtime resources for human interaction and subagents
- recovery-time decisions and audit links

Stop if any expected Phase 2 object still implies a likely schema rewrite to:

- `Conversation`
- `Turn`
- `WorkflowRun`
- `WorkflowNode`
- `AgentDeployment`
- capability-snapshot lineage

## Gate 3: Scope Lock

Confirm the team is activating the intended Phase 2 only.

Phase 2 must stay limited to:

- real agent-loop execution
- unified capability governance
- conversation feature-policy enforcement
- real human-interaction and subagent execution
- Fenix-based real-environment validation

Phase 2 must not absorb:

- Web UI productization
- workspace-owned trigger and delivery infrastructure
- IM, PWA, or desktop clients
- extension or plugin packaging

If an item from those later phases is required, record why. Then either:

- prove it is actually a missing loop prerequisite and amend design first
- or defer it back out and keep Phase 2 narrow

## Gate 4: Terminology And Design Alignment

Confirm the active design baseline is still coherent and accepted.

At minimum, re-read and confirm alignment with:

- [2026-03-24-core-matrix-kernel-greenfield-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md)
- [2026-03-24-core-matrix-kernel-phase-shaping-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-24-core-matrix-kernel-phase-shaping-design.md)
- [2026-03-25-core-matrix-platform-phases-and-validation-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-platform-phases-and-validation-design.md)

Explicitly confirm that the following terms still mean the same thing across
the active docs:

- `capability`
- `tool`
- `feature`
- `policy`
- `decision_source`
- `composer completion`

Also confirm alignment with the focused `Fenix` design and research notes:

- [2026-03-25-fenix-phase-2-validation-and-skills-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-fenix-phase-2-validation-and-skills-design.md)
- [2026-03-25-fenix-skills-and-agent-skills-spec-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-fenix-skills-and-agent-skills-spec-research-note.md)
- [2026-03-25-fenix-deployment-rotation-and-discourse-operations-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-fenix-deployment-rotation-and-discourse-operations-research-note.md)

If terminology drift is found, correct the design docs before activation.

## Gate 5: Fenix Validation Target Is Concrete

Do not activate Phase 2 with a vague promise to "test it later".

Before activation, define the exact Fenix validation slices that must pass:

- one default assistant conversation flow
- one coding-assistant flow
- one office-assistance flow
- one independently paired external `Fenix` flow
- one same-installation deployment rotation flow
- one explicit downgrade flow
- one built-in system skill that deploys another agent
- one third-party skill-install-and-use flow, ideally using
  [obra/superpowers](https://github.com/obra/superpowers)
- one real tool-call flow
- one real subagent flow
- one real human-interaction flow
- one outage or drift recovery flow

Each slice must name:

- the user-visible scenario
- the expected kernel behavior
- the expected agent-program behavior
- the manual validation path

If these slices are not concrete, Phase 2 is not ready.

## Gate 6: Real-Environment Validation Prerequisites

Confirm the real validation environment is ready before planning starts.

Required prerequisites:

- `bin/dev` boots the relevant local services
- at least one real LLM API credential is available
- at least one real provider path is available to `core_matrix`
- at least one external capability path is available for tool validation
  through MCP or an agent-program-exposed tool surface
- the bundled `Fenix` runtime can be started and connected
- an independently started external `Fenix` runtime can be enrolled and paired
- a same-installation second `Fenix` deployment path exists for cutover testing
- a human operator path exists for manual human-interaction validation
- a reachable third-party skill source exists for install-and-use validation,
  ideally [obra/superpowers](https://github.com/obra/superpowers)

If any of these are missing, either fix the environment first or explicitly
hold Phase 2.

## Gate 7: Capability-Governance Readiness

Confirm the activation plan has a clear target for unified capability
governance.

At minimum, the next execution plan must explicitly cover:

- `ToolDefinition`
- `ToolImplementation`
- `ImplementationSource`
- `ToolBinding`
- `ToolInvocation`
- override policy
- whitelist-only policy
- reserved-prefix handling
- availability and supervision state

If the promoted plan still talks about a "minimal bridge" without naming these
objects or policies, rewrite it before activation.

## Gate 8: Conversation Feature-Policy Readiness

Confirm the next execution plan treats feature gating as kernel execution
behavior, not UI configuration.

At minimum, the promoted plan must say how it will:

- persist enabled conversation features
- freeze feature-policy snapshots on running work
- reject disabled kernel behaviors deterministically
- prevent dead-end automation runs caused by disallowed human interaction

Initial features that must be accounted for:

- `human_interaction`
- `tool_invocation`
- `message_attachments`
- `conversation_branching`
- `conversation_archival`

## Gate 9: Manual Checklist Readiness

Before activation, define how the manual checklist will change.

Required outcome:

- a planned update path for `docs/checklists`
- explicit real-environment scenarios for tools, subagents, human interaction,
  recovery, external pairing, deployment rotation, and skills
- a rule that no Phase 2 claim is complete without matching checklist evidence

If the checklist delta is still fuzzy, Phase 2 is not ready.

## Gate 10: Promotion Output Is Defined

Before promoting Phase 2 into `docs/plans`, confirm exactly what will be
created.

Minimum expected output:

- one refreshed Phase 2 implementation plan under `docs/plans`
- exact task ordering based on the real post-phase-one codebase
- exact file paths, test commands, and commit cadence
- clear first task for re-running the structural gate against landed code

Do not promote the current initial plan verbatim. Refresh it first.

## Stop Conditions

Do not activate Phase 2 if any of the following are true:

- Phase 1 still has unresolved structural-gate concerns
- the next-phase scope has expanded into Web UI or triggers
- Fenix validation slices are still vague
- real provider or capability validation paths are unavailable
- the codebase shape materially differs from the assumptions in the initial
  plan

## Activation Record

When this checklist passes, create a short activation note that records:

- the date
- who reviewed activation
- which documents were used
- which real validation paths are available
- the exact Phase 2 plan file promoted into `docs/plans`

That note may live in the promoted plan header or in a short companion document.
