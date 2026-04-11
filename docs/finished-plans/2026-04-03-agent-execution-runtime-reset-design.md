# Agent And Execution Runtime Reset Design

## Status

- Date: 2026-04-03
- Status: proposed and approved for implementation planning

## Goal

Reset the current runtime model so `Conversation` binds only to a logical
agent identity, while each `Turn` freezes the exact agent snapshot and
optional execution runtime used for that turn.

This design intentionally replaces the current assumption that a
conversation is bound to one `AgentDeployment` and one
`ExecutionEnvironment`. The codebase is already at the end of the first full
provider-backed runtime implementation cycle, and the monorepo policy for this
iteration is:

- destructive schema changes are allowed
- migration history may be edited in place
- the database may be dropped and rebuilt
- compatibility shims are not required
- dead code and obsolete documentation should be deleted rather than preserved

## Why The Current Model Is Wrong

The current implementation treats:

- `Conversation.execution_environment`
- `Conversation.agent_deployment`

as the stable runtime identity of an ongoing conversation.

That has proven to be the wrong center of gravity for three reasons:

1. the immutable product identity is the logical agent, not the
   currently running deployment
2. execution capabilities such as code execution, filesystem access, process
   management, or hardware control are optional and turn-scoped, not
   conversation identity
3. the current `AgentDeployment` model is overloaded and simultaneously acts
   as:
   - logical agent snapshot metadata
   - live authenticated runtime connection
   - execution-runtime pairing record

This overloading has already leaked into:

- turn creation
- recovery and retry rules
- control-plane delivery
- capability surface assembly
- attachment projection
- bundled `Fenix` bootstrap

The resulting system is harder to reason about than the intended product.

## Approved Product Constraints

The user-approved target behavior for the reset is:

- `Conversation` must be immutable with respect to the logical agent
- `Conversation` must not own the current execution runtime
- `Turn` must freeze:
  - the chosen agent snapshot
  - the chosen execution runtime when one is used
- `ExecutionRuntime` is optional
- some turns must be able to run with no execution runtime at all
- `ExecutionRuntime` is a program or service that exposes execution-oriented
  tools
- `ExecutionRuntime` is not a synonym for host machine
- both `Agent` and `ExecutionRuntime` need persistent user-facing
  `display_name`
- agent-plane routing is not product identity; it is delivery routing
- if multiple copies of the same agent try to connect, only one may be
  active at a time
- the active program connection must be protected by a session token / lease
- bundled `Fenix` may still implement both agent-plane and execution-plane
  behavior in one appliance, but the product model must not require them to be
  the same thing
- attachment delivery should be on-demand through an execution-plane request
  like `request_attachment`

## New Terminology

### Core Domain Renames

- `AgentInstallation` becomes `Agent`
- `UserAgentBinding` becomes `UserAgentBinding`
- `AgentDeployment` becomes `AgentSnapshot`
- `ExecutionEnvironment` becomes `ExecutionRuntime`

### New Live Connection Models

- `AgentConnection`
  - the single active agent-plane connection for one `Agent`
- `ExecutionRuntimeConnection`
  - the single active execution-plane connection for one `ExecutionRuntime`

### Plane Names

The control-plane enum values should be renamed from:

- `agent` -> `program`
- `environment` -> `execution`

The API namespaces should be renamed from:

- `agent_api` -> `agent_api`
- `environment_api` -> `executor_api`

This keeps naming aligned with the new domain model and avoids mixing
`ExecutionRuntime` with an old `environment` vocabulary.

## New Aggregate Responsibilities

### `Agent`

`Agent` is the logical product identity that a conversation uses.

It owns:

- stable program key
- display name
- installation scope
- visibility and ownership rules
- optional default execution-runtime preference

It does not own:

- live session state
- heartbeat or realtime connectivity
- execution-runtime identity
- current capability snapshot

### `AgentSnapshot`

`AgentSnapshot` is an immutable version/capability snapshot created from
agent-plane handshake data.

It owns:

- protocol version
- SDK version
- program fingerprint or version identity
- immutable capability/tool/profile/config payloads
- governance projection inputs that are now split between
  `AgentDeployment` and `CapabilitySnapshot`

It does not own:

- connection credential
- heartbeat
- link state
- health state
- execution-runtime pairing

`CapabilitySnapshot` should be removed and folded into this aggregate instead
of remaining as a second immutable version layer.

### `ExecutionRuntime`

`ExecutionRuntime` is an optional external execution host that can expose
execution-oriented tools such as:

- command execution
- filesystem tools
- long-lived process management
- browser or device control
- hardware interaction
- attachment materialization for local execution

It owns:

- stable runtime fingerprint
- display name
- runtime kind
- connection metadata
- execution-tool capability metadata

It does not own:

- logical agent identity
- conversation identity
- agent-plane authentication

### `AgentConnection`

`AgentConnection` is the live, authenticated, single-active agent-plane
connection.

It owns:

- connection credential digest
- session token or lease nonce
- liveness and connectivity fields
- session status
- current bound `AgentSnapshot`

It belongs to:

- one `Agent`
- one `AgentSnapshot`

Single-active-session is enforced per `Agent`.

### `ExecutionRuntimeConnection`

`ExecutionRuntimeConnection` is the live, authenticated, single-active execution-plane
connection.

It owns:

- connection credential digest
- session token or lease nonce
- liveness and connectivity fields
- execution-plane status

It belongs to:

- one `ExecutionRuntime`

Single-active-session is enforced per `ExecutionRuntime`.

### `Conversation`

`Conversation` becomes a stable transcript container bound only to the logical
program identity.

It owns:

- workspace and user-facing conversation identity
- lineage and transcript state
- feature policy
- conversation-local mutable state

It belongs to:

- one `Agent`

It must not belong to:

- `AgentSnapshot`
- `ExecutionRuntime`

### `Turn`

`Turn` becomes the frozen runtime contract owner.

It belongs to:

- one `Conversation`
- one `AgentSnapshot`
- zero or one `ExecutionRuntime`

It freezes:

- the exact agent snapshot used
- the exact execution runtime used, when present
- the capability surface derived from those bindings
- the attachment manifest and model-input attachment projection

## Schema Reset

### Rename Tables

- `agent_installations` -> `agents`
- `user_agent_bindings` -> `user_agent_bindings`
- `agent_deployments` -> `agent_snapshots`
- `execution_environments` -> `execution_runtimes`

### Add Tables

- `agent_connections`
- `execution_runtime_connections`

### Remove Columns

From `conversations`:

- `agent_deployment_id`
- `execution_environment_id`

From `agent_snapshots`:

- `execution_runtime_id`
- connection credential digest
- heartbeat state
- realtime link state
- control activity state
- health status
- health metadata
- connection-endpoint ownership fields that exist only for live session use

### Add Columns

To `conversations`:

- `agent_id`

To `turns`:

- `agent_snapshot_id`
- `execution_runtime_id`, nullable

To `agents`:

- `display_name`
- optional `default_execution_runtime_id`, nullable

To `execution_runtimes`:

- `display_name`
- `executor_fingerprint`

### Fold Or Remove Tables

- remove `capability_snapshots`
- migrate immutable handshake payloads onto `agent_snapshots`

## Turn Entry And Default Runtime Selection

`Conversation` no longer provides a current runtime binding.

Every new turn must go through a single application boundary that resolves:

- the active `AgentConnection`
- the selected `ExecutionRuntime`, if any
- the derived capability surface

### Execution Runtime Selection Policy

`Turns::SelectExecutionRuntime` should resolve runtime selection in this order:

1. explicitly requested `execution_runtime_id`
2. previous turn's `execution_runtime_id`
3. `Agent.default_execution_runtime_id`
4. `nil`

Behavior:

- if the result is `nil`, the turn remains valid
- if a runtime is selected, an active `ExecutionRuntimeConnection` must exist
- if the runtime session is missing or stale, turn creation fails closed

### Program Version Selection Policy

`Turns::FreezeProgramVersion` should:

- find the active `AgentConnection` for the conversation's `Agent`
- freeze its current `AgentSnapshot` onto the turn
- reject turn entry when no active program session exists

This replaces the old behavior of reading a conversation-bound deployment.

## Capability Surface Assembly

Capability assembly should become turn-scoped rather than conversation-scoped.

### Inputs

- `Core Matrix` tool catalog
- `ExecutionRuntime` tool catalog, when a runtime is present
- `AgentSnapshot` agent tool catalog

### Precedence

For ordinary tool names:

1. `ExecutionRuntime`
2. `AgentSnapshot`
3. `Core Matrix`

Reserved `core_matrix__*` system tools remain non-overridable.

### Consequences Of No Execution Runtime

If a turn has no execution runtime:

- execution-plane tools do not appear
- command and process tools do not appear
- runtime attachment request tools do not appear
- only core-matrix and agent-plane tools remain

This is the intended behavior for roleplay, support, and other non-execution
agents.

## Attachments

Attachments must stop treating execution delivery as a conversation-level
property.

### Canonical Turn Snapshot

Keep on the turn snapshot:

- `attachment_manifest`
- `model_input_attachments`

Delete from the turn snapshot:

- `runtime_attachment_manifest`

### New Semantics

- `attachment_manifest` is the canonical visible attachment fact set
- `model_input_attachments` remains provider-facing multimodal projection
- execution-runtime access to attachments becomes on-demand

### Execution Attachment Access

Add an execution-plane request such as:

- `request_attachment`

Expected behavior:

- input uses `public_id` values only
- validates that the authenticated `ExecutionRuntimeConnection` belongs to the turn's
  frozen `ExecutionRuntime`
- returns an expiring execution-local handle

I recommend a durable but short-lived access-grant row to support:

- auditing
- expiry
- later revocation if needed

The old `conversation_attachment_upload` capability gate should be removed.
It conflates provider multimodal input with execution delivery and no longer
matches the new model.

## Control Plane And Security

### Authentication

Program-plane requests authenticate `AgentConnection`.

Execution-plane requests authenticate `ExecutionRuntimeConnection`.

No API should authenticate directly as:

- `AgentSnapshot`
- `ExecutionRuntime`

### Single-Active Session

For both session types:

- only one `active` session may exist per logical owner
- opening a replacement session requires explicit replace semantics
- a superseded session becomes stale immediately
- stale sessions receive `409 stale_session` on poll, report, or heartbeat

### Mailbox Routing

Mailbox targeting should separate logical ownership from lease ownership.

Program-plane work:

- new work targets the logical `Agent`
- leased in-flight work belongs to one `AgentConnection`

Execution-plane work:

- new work targets the logical `ExecutionRuntime`
- leased in-flight work belongs to one `ExecutionRuntimeConnection`

This keeps delivery routing out of the product identity layer.

## Recovery Model Reset

The current recovery implementation assumes:

- a conversation-bound deployment
- replacement deployment compatibility inside one execution environment

That model must be deleted.

New recovery rules:

- paused work is owned by the frozen turn binding
- compatibility checks compare:
  - the frozen `AgentSnapshot` capability surface
  - the current active `AgentConnection` version
- retry or resume does not mutate `Conversation`
- retry or resume may create a new turn or new task binding, but it does not
  rebind conversation identity

Waiting reasons should pivot from deployment identity to logical program or
execution owner identity where appropriate.

## Bundled Fenix Implications

Bundled `Fenix` should remain able to act as:

- the agent-plane service
- the execution-plane service

but those are two composable roles, not one domain identity.

Bundled bootstrap must therefore become:

1. register or reconcile bundled `Agent`
2. register or reconcile bundled `ExecutionRuntime`
3. establish bundled defaults or composition policy
4. create user binding against the `Agent`

The bundled appliance may still supply both session types, but the product
must not encode that coincidence in the schema.

## Required Deletions

The following concepts should be removed rather than adapted:

- conversation-scoped deployment switching
- conversation-scoped execution-runtime binding
- deployment-to-execution-runtime ownership
- capability refresh modeled as a conversation aggregate helper
- runtime attachment projection stored on the turn snapshot
- connection credential lifecycle modeled on `AgentSnapshot`

Specifically, these service families are obsolete in the target design:

- `Conversations::SwitchAgentDeployment`
- `Conversations::ValidateAgentDeploymentTarget`
- `Conversations::RefreshRuntimeContract`
- `ExecutionEnvironments::ResolveDeliveryEndpoint`

## Rewrite Sweep Requirement

Implementation is not complete until a repo-wide sweep across both
`core_matrix` and `agents/fenix` finds no remaining old-model assumptions in
code or behavior docs.

The required sweep terms are:

- `AgentInstallation`
- `UserAgentBinding`
- `AgentDeployment`
- `ExecutionEnvironment`
- `agent_api`
- `environment`
- `runtime_plane`
- `conversation.agent_deployment`
- `conversation.execution_environment`
- `conversation_attachment_upload`

The sweep is not just a rename pass. Each hit must be classified as:

- renamed and still valid
- rewritten for the new design
- deleted as obsolete

## Validation Standard

Implementation is only complete when all of these are true:

1. schema reset works from edited migrations and fresh database creation
2. dead services and dead branches from the old design are gone
3. `core_matrix` tests pass
4. `agents/fenix` tests pass
5. behavior docs no longer describe the old model
6. the Fenix provider-backed 2048 capstone acceptance completes under the new
   contract
