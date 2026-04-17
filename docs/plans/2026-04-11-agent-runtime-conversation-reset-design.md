# Agent Runtime Conversation Reset Design

## Status

- Date: 2026-04-11
- Status: superseded by `/Users/jasl/Workspaces/Ruby/cybros/docs/archived-plans/core_matrix-docs-legacy-2026-04-17/plans/2026-04-12-agent-canonical-config-and-runtime-pairing-design.md`; terminology normalized here for consistency with the implemented model

## Goal

Reset the current CoreMatrix/Fenix/Nexus architecture so the monorepo models a
single reusable `Agent`, a single reusable `ExecutionRuntime`, and a
user-facing `Conversation`, with `Turn` freezing the exact runtime snapshots used
for execution and audit.

This round is intentionally destructive:

- compatibility is not required
- migration history may be edited in place
- databases may be dropped and rebuilt
- dead names, files, and APIs should be deleted instead of shimmed

## Why The Current Model Is Wrong

The current codebase still carries a transitional split based on the earlier
`Agent` / `ExecutionRuntime` vocabulary even though the implementation is
already mid-migration toward:

- `Agent`
- `AgentDefinitionVersion`
- `ExecutionRuntime`
- `AgentConnection`
- `ExecutionRuntimeConnection`
- `Conversation`

That model already improved on the earlier agent-definition/environment design, but
it still preserves two incorrect assumptions:

1. the kernel still thinks in terms of a product-specific "agent" and an
   attached executor instead of a reusable `Agent` plus reusable
   `ExecutionRuntime`
2. `Fenix` and `Nexus` still preserve the old bundled-runtime assumption where
   one appliance can present both agent-plane and execution-plane identity at
   once

This leaks into:

- registration payloads
- pairing manifests
- default binding and onboarding
- control-plane routing
- capability assembly
- API naming
- docs and acceptance narratives

The result is harder to reason about than either Claude Managed Agents or the
desired CoreMatrix product model.

## Approved Product Constraints

The approved target behavior for this reset is:

- CoreMatrix models a single reusable `Agent`
- CoreMatrix models a single reusable `ExecutionRuntime`
- a user-facing thread is a `Conversation`
- `Turn` freezes the exact `AgentDefinitionVersion` and execution-runtime contract used
  for that turn
- the system records actual runtime snapshots for audit, but does not attempt
  a full release-management product around snapshots
- `Fenix` becomes the pure agent decision layer
- `Nexus` becomes the single execution runtime appliance
- `Nexus` may internally compose modules later, but CoreMatrix does not model
  runtime-module composition in this round
- skills are logically selected by the agent, but skill packages, scripts, and
  resources live in the runtime because they are filesystem-backed assets
- memory strategy belongs to the agent, but the current filesystem-backed
  memory store lives in the runtime
- tool precedence is `ExecutionRuntime > Agent > CoreMatrix`
- CoreMatrix reserved tool names and reserved namespaces are never overridable
- an agent may mask CoreMatrix tools from its visible set even when those tools
  remain stable kernel capabilities

## Naming

### New Core Domain Names

- `Agent` becomes `Agent`
- `AgentDefinitionVersion` becomes `AgentDefinitionVersion`
- `ExecutionRuntime` becomes `ExecutionRuntime`
- `AgentConnection` becomes `AgentConnection`
- `ExecutionRuntimeConnection` becomes `ExecutionRuntimeConnection`
- `Conversation` stays `Conversation`

`Turn` stays `Turn`.

### Runtime Naming Choice

The design intentionally does **not** use `Environment` as the main aggregate
name because it would collide semantically with:

- Rails `config/environment.rb`
- Rails `config/environments/*`
- existing `Shared::Environment` namespaces in `Fenix` and `Nexus`

The design also does **not** use bare `Runtime` as the aggregate name because
the codebase already uses `Runtime` namespaces for the live
control-loop appliance layer.

`ExecutionRuntime` is the approved aggregate name.

## Aggregate Responsibilities

### `Agent`

`Agent` is the reusable logical assistant identity.

It owns:

- stable key
- display name
- installation scope
- visibility and ownership rules
- default execution runtime preference
- onboarding defaults

It does not own:

- live connection state
- execution resources
- filesystem-backed skill assets
- filesystem-backed memory storage

### `AgentDefinitionVersion`

`AgentDefinitionVersion` is an immutable audit snapshot of the agent-plane capability
contract that was actually used for execution.

It owns:

- fingerprint
- protocol version
- SDK version
- protocol methods
- agent-owned tool catalog
- profile policy
- canonical config schema
- conversation override schema
- default canonical config

It does not own:

- release-management semantics
- executor/runtime identity
- live connection state

### `ExecutionRuntime`

`ExecutionRuntime` is the reusable execution appliance used by conversations and
turns.

It owns:

- stable fingerprint
- display name
- runtime kind
- connection metadata
- default pairing metadata

It does not own:

- agent identity
- agent prompt logic
- workflow orchestration

### Runtime Freeze

The approved target model is that each turn freezes both the selected
`AgentDefinitionVersion` and the execution-runtime surface used for the turn.

In the current implementation, that runtime-side freeze is carried by the
execution contract stack (`ExecutionCapabilitySnapshot`,
`ExecutionContextSnapshot`, and `ExecutionContract`) together with the selected
`ExecutionRuntime`. This round keeps that structure while renaming the durable
runtime aggregate itself to `ExecutionRuntime`.

### `Conversation`

`Conversation` is the user-facing long-lived thread container.

It owns:

- workspace and user-facing identity
- lineage and transcript state
- conversation feature policy
- mutable state and metadata
- logical binding to one `Agent`
- logical binding to one `ExecutionRuntime`

It does not own:

- frozen runtime snapshots
- live connection credentials

### `Turn`

`Turn` is the frozen runtime contract owner.

It owns:

- one `Conversation`
- one `AgentDefinitionVersion`
- one frozen execution-runtime contract
- resolved visible tool surface
- resolved config and model snapshots
- execution identity used for audit and recovery

### `AgentConnection`

`AgentConnection` is the live authenticated connection for one `Agent`.

It owns:

- connection credential digest
- connection token digest
- liveness and health fields
- currently connected `AgentDefinitionVersion`

Single-active-connection is enforced per `Agent`.

### `ExecutionRuntimeConnection`

`ExecutionRuntimeConnection` is the live authenticated connection for one
`ExecutionRuntime`.

It owns:

- connection credential digest
- connection token digest
- liveness and health fields
- currently connected `ExecutionRuntime`

Single-active-connection is enforced per `ExecutionRuntime`.

## Tool Ownership And Priority

### Ownership

- CoreMatrix owns orchestration and reserved governance tools
- `Agent` owns prompt logic, skill-selection policy, memory-selection policy,
  and agent-owned tools
- `ExecutionRuntime` owns runtime tools, runtime-owned context materialization,
  skill package storage, skill file reads, skill scripts/resources, and the
  current filesystem-backed memory store

### Priority

The effective tool surface is resolved in this order:

1. `ExecutionRuntime`
2. `Agent`
3. `CoreMatrix`

CoreMatrix reserved tool names are exempt from that priority rule. They must be
namespaced or otherwise reserved so that:

- external runtimes cannot override them
- agents cannot override them

An agent may still mask CoreMatrix tools from visible use by profile or
whitelist policy.

## Skill And Memory Boundary

This round intentionally uses a split boundary:

- skills are logically an agent capability
- skill packages are physically runtime assets
- memory strategy is logically an agent capability
- filesystem-backed memory storage is physically a runtime capability

The runtime therefore materializes:

- skill package file access
- skill resource reads
- script/resource execution prerequisites
- current workspace-backed memory payloads

The agent decides:

- which skills to activate
- which memory slices to request
- how to interpret the returned context

## Registration And Control Flow

### Agent Registration

`Fenix` registers as an `Agent` only.

It submits:

- agent key and display name
- agent fingerprint
- agent-plane protocol methods
- agent-owned tool catalog
- profile/config snapshots

CoreMatrix creates or reuses:

- `Agent`
- `AgentDefinitionVersion`
- `AgentConnection`

### Execution Runtime Registration

`Nexus` registers as an `ExecutionRuntime` only.

It submits:

- runtime fingerprint
- runtime display name
- runtime capability payload
- runtime tool catalog
- runtime-owned context contract

CoreMatrix creates or reuses:

- `ExecutionRuntime`
- `ExecutionRuntimeConnection`

### Conversation Creation

A new `Conversation` binds:

- one `Agent`
- one `ExecutionRuntime`

Those are logical bindings only.

### Turn Freezing

When a new `Turn` starts:

1. CoreMatrix resolves the `Conversation` agent/runtime pair
2. CoreMatrix resolves the current active `AgentConnection` and
   `ExecutionRuntimeConnection`
3. CoreMatrix freezes the pointed `AgentDefinitionVersion` plus the execution-runtime
   surface through the execution contract snapshot stack
4. CoreMatrix resolves the effective tool surface using the approved priority
   rules
5. the turn executes only against those frozen snapshots

## Context Materialization Flow

The current round flow becomes:

1. `Fenix` decides which skills and memory slices it wants
2. CoreMatrix asks `Nexus` to materialize the runtime-owned context bundle
3. `Nexus` returns:
   - skill context
   - memory context
   - other runtime-owned context fragments
4. `Fenix` assembles final round instructions from those returned materials

## API And Path Design

The API surface should become:

- `agent_api/*`
  - agent registration
  - agent health/heartbeat
  - agent control reports
  - agent-owned tool execution
- `execution_runtime_api/*`
  - runtime registration
  - runtime health/heartbeat
  - runtime control reports
  - runtime-owned resource APIs

The older bundled assumption where the agent registration payload can also
smuggle execution-runtime identity is removed.

## Codebase Reorganization

### `core_matrix`

Keeps:

- orchestration
- scheduling
- audit and snapshot freezing
- conversation/turn/workflow state
- tool governance
- onboarding and default binding

### `agents/fenix`

Keeps:

- prompts
- round preparation
- profile and policy logic
- skill-selection logic
- memory-selection logic
- agent-owned tools
- agent registration manifest

Removes:

- exec/process/browser/web runtime executors
- runtime-owned skill package storage
- runtime-owned memory storage

### `execution_runtimes/nexus`

Keeps:

- runtime manifest
- runtime control loop
- exec/process/browser/web tooling
- runtime-owned skill package repository
- runtime-owned memory store
- filesystem/workspace context materialization

Removes:

- copied `Fenix` agent namespace and prompts
- bundled dual-identity manifest assumptions

## Error Handling

### Registration Failures

Reject registration immediately when:

- fingerprint is blank
- schema is invalid
- reserved CoreMatrix tool names are overridden
- required contract payloads are missing

### Turn Start Failures

Reject turn start immediately when:

- conversation has no bound agent or execution runtime
- no active agent connection exists
- no active execution runtime connection exists
- frozen snapshot resolution fails
- reserved tool override is attempted

When the runtime is unavailable, historical conversations remain readable but new
turns fail with an explicit unavailable state.

## Validation Gate

This work is not complete until all of the following are re-run under the new
model:

- `core_matrix` verification commands from `AGENTS.md`
- `agents/fenix` verification commands from `AGENTS.md`
- `execution_runtimes/nexus` verification commands matching the copied Rails app shape
- repo-wide sweeps proving old bundled-runtime terminology is gone
- end-to-end acceptance for:
  - separate agent registration
  - separate runtime registration
  - default `Fenix + Nexus` onboarding
  - turn freezing of both snapshots
  - runtime-owned skill and memory context
  - runtime disconnection failure behavior
