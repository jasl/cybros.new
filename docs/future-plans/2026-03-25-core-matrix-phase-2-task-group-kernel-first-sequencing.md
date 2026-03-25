# Core Matrix Phase 2 Task Group: Kernel-First Sequencing

## Status

Deferred focused task-group note for the earliest `Core Matrix` slices inside
Phase 2.

This document does not replace the full Phase 2 initial plan. It narrows one
question only: in what order should the kernel-owned execution work land so the
phase can activate cleanly without letting `Fenix` or MCP breadth drive the
wrong implementation order.

## Purpose

Use this document to:

- define the recommended early sequencing for Phase 2 kernel work
- reduce risk before broader `Fenix` validation and skills work expands
- keep execution correctness, concurrency safety, and recovery semantics ahead
  of product-surface breadth

## Why A Kernel-First Sequence Is Necessary

The approved Phase 2 scope is already broad enough to sprawl:

- real loop execution
- durable execution delivery
- capability governance
- conversation feature policy
- human interaction and subagents
- external `Fenix` pairing and deployment rotation
- skills validation

That is acceptable as a phase boundary, but it is not a safe implementation
order.

The first activation slice should prove the kernel can:

- own one durable claimed execution at a time
- reject stale, duplicate, or superseded execution reports safely
- keep newer conversation tail state authoritative
- move into and out of kernel-owned wait states deterministically

Only after those invariants are real should Phase 2 widen into MCP breadth,
deployment rotation, and richer `Fenix` skill behavior.

## Sequencing Principles

1. Land execution authority before capability breadth.
2. Land stale-work and lease-safety rules before real external runtime
   validation.
3. Land wait-state handoff before richer human-interaction or subagent product
   flows.
4. Freeze tool bindings at `AgentTaskRun` creation before adding more governed
   capability sources.
5. Treat `Fenix` as the first consumer of a stable contract, not as the place
   where that contract is discovered ad hoc.

## Recommended Early Sequence

### Slice A: Claimable Execution Resource And Contract Tests

Primary outcome:

- `AgentTaskRun` exists as the claimable runtime resource for Phase 2
- `execution_claim / execution_lease_heartbeat / execution_progress /
  execution_complete / execution_fail` exist as a tested contract surface
- single-owner lease acquisition, stale-lease rejection, duplicate terminal
  delivery, and fast-terminal behavior are all covered in tests

This slice should not yet prove full provider execution. It should prove the
durable control surface.

Likely areas:

- `core_matrix/app/models/agent_task_run.rb`
- `core_matrix/app/controllers/agent_api/executions_controller.rb`
- `core_matrix/app/services/leases/*`
- `core_matrix/test/requests/agent_api/*`
- `core_matrix/test/services/leases/*`

### Slice B: Provider-Backed Turn Execution

Primary outcome:

- one `turn_step` can move from queued to running to terminal under workflow
  control
- provider execution routes through `simple_inference`
- result ingestion updates workflow state and audit-friendly execution records
- authoritative provider usage is persisted and can drive later advisory
  compaction-threshold evaluation

This slice should still stay narrow:

- one provider-backed path
- no broad tool matrix yet
- no MCP yet

Likely areas:

- `core_matrix/app/services/workflows/*`
- `core_matrix/app/services/provider_execution/*`
- `core_matrix/vendor/simple_inference/lib/simple_inference/*`
- `core_matrix/test/services/workflows/*`
- `core_matrix/test/integration/*`

### Slice C: Conversation Policy And Stale-Work Safety

Primary outcome:

- `Conversation.during_generation_input_policy` is real
- `reject / restart / queue` semantics are enforced
- `tail_guard` or equivalent stale-work protection is carried into execution
- older queued or superseded work can no longer commit transcript-affecting
  output as if it were current

This slice closes the most dangerous correctness gap before real multi-turn
validation expands.

Likely areas:

- `core_matrix/app/models/conversation.rb`
- `core_matrix/app/models/turn.rb`
- `core_matrix/app/models/workflow_run.rb`
- `core_matrix/app/services/turns/*`
- `core_matrix/test/services/turns/*`
- `core_matrix/test/integration/*`

### Slice D: Wait-State Handoff, Human Interaction, And Subagents

Primary outcome:

- runtime execution can request a kernel-owned wait transition through a
  canonical payload such as `wait_transition_requested`
- human interaction and subagent coordination both drive structured workflow
  wait state rather than runtime-local pause state
- resume and retry paths preserve lease and recovery semantics

This slice proves the waiting model before external runtime product flows get
more ambitious.

Likely areas:

- `core_matrix/app/services/human_interactions/*`
- `core_matrix/app/services/subagents/*`
- `core_matrix/app/services/workflows/manual_resume.rb`
- `core_matrix/app/services/workflows/manual_retry.rb`
- `core_matrix/test/services/human_interactions/*`
- `core_matrix/test/services/subagents/*`
- `core_matrix/test/services/leases/*`

### Slice E: Base Capability Governance For Kernel And Agent Tools

Primary outcome:

- `ToolDefinition`, `ToolImplementation`, `ToolBinding`, and `ToolInvocation`
  are real enough to govern one kernel or agent-program tool path
- binding freeze happens when `AgentTaskRun` is created from the current
  execution snapshot
- retries within one attempt keep the same binding unless recovery opens a new
  attempt

This slice should prove the governance shape before MCP is added as another
transport and failure mode.

Likely areas:

- `core_matrix/app/models/capability_snapshot.rb`
- `core_matrix/app/models/*` for tool-governance objects
- `core_matrix/app/services/agent_deployments/*`
- `core_matrix/test/requests/agent_api/*`
- `core_matrix/test/services/agent_deployments/*`

### Slice F: Streamable HTTP MCP Under The Same Governance Model

Primary outcome:

- one Streamable HTTP MCP-backed capability works through the same governance,
  supervision, and invocation-history model
- MCP session and transport failures enter the same retry, wait, or recovery
  semantics already proven for the base execution model

This should come after the base tool-governance shape is already real.

Likely areas:

- `core_matrix/app/services/mcp/*`
- `core_matrix/test/services/mcp/*`
- `core_matrix/test/requests/agent_api/*`

## Fenix Dependency Rules

`Fenix` work should consume this sequence rather than redefine it.

Recommended dependency boundaries:

- `Fenix` runtime endpoints may begin once Slice A stabilizes the contract
- real provider-backed `Fenix` loop validation should wait until Slice B
- multi-turn and stale-work validation should wait until Slice C
- real human-interaction and subagent `Fenix` flows should wait until Slice D
- broader tool and MCP validation should wait until Slice E and Slice F

## Promotion Guidance

When Phase 2 eventually moves into `docs/plans`, the first active plan should
either:

- use this slice order directly
- or explain exactly why a different order is now safer against the real
  post-phase-one codebase

Do not activate Phase 2 with a plan that starts from MCP breadth, `Fenix`
skills, or deployment rotation before the kernel slices above are explicit.

## Related Documents

- [2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md)
- [2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md)
- [2026-03-25-core-matrix-phase-2-activation-ready-outline.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-activation-ready-outline.md)
- [2026-03-25-core-matrix-agent-execution-delivery-contract-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-agent-execution-delivery-contract-design.md)
- [2026-03-25-core-matrix-platform-phases-and-validation-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-platform-phases-and-validation-design.md)
