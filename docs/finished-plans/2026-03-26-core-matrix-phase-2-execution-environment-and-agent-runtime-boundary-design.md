# Core Matrix Phase 2 Design: Execution Environment And Agent Runtime Boundary

Use this design document before starting the next Phase 2 batch that reshapes
runtime ownership, pairing, and capability resolution.

Read together with:

1. `AGENTS.md`
2. `docs/plans/README.md`
3. `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
4. `docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md`
5. `docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md`

## Purpose

Phase 2 Milestone C established mailbox control, runtime pairing, close
semantics, and an initial Fenix runtime surface. During that work, the current
model exposed a structural blur:

- `ProcessRun` and other runtime resources conceptually belong to an execution
  environment
- current routing and pairing still lean heavily on `AgentDeployment`
- current Fenix implementation folds agent logic and environment execution into
  one process

This design resolves that blur by making `ExecutionEnvironment` the stable
owner of runtime resources and by treating `AgentDeployment` as the rotatable
Agent layer attached to that environment.

## Decisions

### 1. `ExecutionEnvironment` Is The Stable Runtime Owner

`ExecutionEnvironment` is a stable aggregate that survives deployment rotation.
It represents a concrete execution surface, regardless of whether that surface
is backed by a sandbox, bare metal host, container, VM, or another runtime
carrier.

`ExecutionEnvironment` owns all runtime-executed resources, including:

- `ProcessRun`
- future shell execution sessions
- future file read and write tool sessions
- future environment-scoped network or tool handles

Runtime resource ownership must always resolve to one `ExecutionEnvironment`.
That ownership does not change when the active agent changes.

### 2. `AgentDeployment` Is The Agent Layer

`AgentDeployment` is not the durable owner of runtime resources.

`AgentDeployment` represents the current paired and rotatable Agent
layer that is attached to an `ExecutionEnvironment`. It is responsible for:

- agent loop behavior
- provider-backed turn execution
- agent-exposed tools
- agent-level capabilities
- deployment versioning and rotation

For the foreseeable product horizon, bundled agents such as Fenix should be
modeled as one runtime process that simultaneously implements:

- `AgentRuntime`
- `ExecutionEnvironmentRuntime`

That bundling is an implementation posture, not a modeling shortcut. The
logical boundary remains explicit even when one process serves both planes.

### 3. `Conversation` Binds To Environment, Then Selects Agent

Each `Conversation` is permanently bound to one `ExecutionEnvironment`.

Within that fixed environment, the conversation may switch its active
`AgentDeployment`. It must not switch to a different environment after
creation. Environment continuity preserves runtime state expectations around:

- file system scope
- process ownership
- environment-side tools
- attachment semantics

Conversation capability is derived from the pair:

- environment capabilities
- active agent deployment capabilities

The effective conversation capability set should be refreshed when:

- the conversation is created
- the active agent deployment changes
- the bound execution environment changes capability due to upgrade or repair

The environment identity remains fixed even when that capability set changes.

### 4. Pairing Produces A Composite Runtime Entry

The product should keep a simple pairing and selection flow. Users should not
have to pick an execution environment first and an agent second.

Pairing should therefore behave as a composite operation:

- resolve or create one stable `ExecutionEnvironment`
- create or rotate one `AgentDeployment` attached to that environment
- publish one product-facing entry that represents the pair

In the foreseeable future, agents should default to
`includes_execution_environment = true`. That means one runtime advertises both
planes together and can be paired in one flow.

`ExecutionEnvironment` reconciliation must key off an explicit stable runtime
identity. That identity is not the deployment release fingerprint.

For this follow-up, the contract should require one installation-local
`environment_fingerprint` value that:

- stays stable across `AgentDeployment` rotation for the same runtime carrier
- changes only when the runtime carrier should be treated as a different
  execution environment
- is published by bundled or external runtimes as part of pairing and
  capability metadata

If a runtime cannot provide `environment_fingerprint`, pairing should fail
rather than guessing from deployment-only metadata.

When a deployment rotates:

- the environment remains the same
- a new `AgentDeployment` becomes active for that environment
- conversations bound to the environment may switch to the new deployment
- runtime-owned resources do not migrate owners

### 5. Protocol Transport May Stay Shared, But Runtime Planes Must Not Blur

The mailbox and MQ transport can continue to reuse the existing agent protocol
shape. However, the logical target of each message must be explicit.

The protocol model now has two planes:

- `agent plane`
- `environment plane`

The agent plane handles:

- turn execution
- workflow callbacks
- agent tools
- agent loop control

The environment plane handles:

- `ProcessRun`
- shell and file execution
- environment resource close and control
- environment capability reporting

The current Fenix runtime may accept both planes over one connection. Even in
that bundled case, the server-side contract must distinguish:

- owner identity
- routing target
- logical runtime plane

### 6. Ownership And Routing Are Separate Concerns

Ownership is determined by `ExecutionEnvironment`.

Delivery may still target the currently online deployment that is acting on
behalf of that environment. This means any routing hint such as
`ExecutionLease.holder_key` must not carry ownership semantics. At most, it is
a delivery hint that identifies the currently reachable runtime endpoint for an
environment.

Close and control routing for a runtime-owned resource should always behave as:

1. resolve the owning `ExecutionEnvironment`
2. resolve the currently reachable runtime endpoint for that environment
3. enqueue environment-plane control
4. if the environment is unreachable, persist pending or degraded close state

The system must not silently fall back to a kernel-local stop path for a
resource that is environment-owned.

### 7. Timeouts Drive Task Quiescence

Lifecycle separation does not replace timeout management. Final task quiescence
must still be governed by timeout policy.

The model distinction is:

- timeout and fence logic determine when active work is considered overdue,
  interrupted, or abandoned
- environment ownership determines where the close request must be executed

So a timed-out task or turn should still resolve closure through
environment-plane control whenever it holds environment-owned resources.

### 8. Tool Conflict Resolution Is Explicit

Tool lookup must no longer be left implicit when capabilities from Core Matrix,
`AgentDeployment`, and `ExecutionEnvironment` overlap.

Reserved Core Matrix system tools must use the `core_matrix__` public-name
prefix and keep `tool_kind = kernel_primitive`.

Those `core_matrix__*` tools do not participate in ordinary collision
resolution.

For all non-`core_matrix__*` tool names, the resolution order is:

1. `ExecutionEnvironment`
2. `AgentDeployment`
3. `CoreMatrix`

This makes the runtime carrier authoritative for shell, file, process, and
other environment-backed operations even if the agent exposes the same
tool name.

Capability publication should materialize the final effective tool manifest so
that UI, orchestration, and runtime execution all observe the same winning
surface.

### 9. Environment Capabilities Are First-Class

`ExecutionEnvironment` needs its own capability model. The first required
capability is whether the environment can support conversation attachment
upload.

That model should also expand to describe environment-native execution
surfaces, such as:

- shell access
- file read and write access
- process spawning and control

Conversation and tool resolution must be based on the combined environment and
agent capability picture rather than a deployment-only view.

Environment capability changes must be able to land independently from agent
deployment rotation. Conversation contract refresh therefore needs to cover two
separate mutation paths:

- active `AgentDeployment` switches within one bound environment
- `ExecutionEnvironment` capability refresh for the same bound environment

## Fenix And Future Agents

Fenix must be adjusted so that its implementation reflects the split between
agent and environment responsibility even if the same process continues to
implement both.

The same posture should apply to future bundled agents until the product has a
clearer interaction model for independently selecting or swapping agent
and execution environment.

The default near-term product assumption is:

- one paired runtime usually bundles both planes
- the model still keeps the planes separate
- later physical separation should extend the same contract rather than replace
  it

## Destructive Migration Posture

This correction is structural and should be treated as a design repair rather
than a compatibility exercise.

The next implementation batch should proceed with an explicitly aggressive
cleanup posture:

- allow breaking changes
- do not preserve compatibility layers
- edit existing migrations in place when that yields a cleaner schema
- reset the database when needed
- regenerate `schema.rb`
- delete stale models, services, tests, and behavior statements that preserve
  superseded ownership semantics

The goal is to restore a clean and internally consistent runtime model for the
rest of Phase 2 and later phases.

## Required Cleanup

The implementation plan derived from this design should include removal or
rewrite of any stale artifact that implies:

- `AgentDeployment` is the owner of `ProcessRun`
- runtime close may bypass mailbox or environment control
- conversation runtime identity is deployment-only
- capability resolution is deployment-only
- tool precedence is unspecified or implicitly Core Matrix first

Documentation, tests, code, and schema should be corrected together so the
repository no longer teaches the superseded model.

## Resulting Architectural Summary

The repository should move to the following mental model:

- `ExecutionEnvironment` is the stable runtime resource owner
- `AgentDeployment` is the rotatable Agent layer on that environment
- `Conversation` binds permanently to one environment and variably to one
  active deployment
- protocol transport may remain shared, but agent plane and environment plane
  are distinct contracts
- timeout logic governs quiescence timing, while environment ownership governs
  where close executes
- environment capabilities and tool precedence are first-class and explicit
