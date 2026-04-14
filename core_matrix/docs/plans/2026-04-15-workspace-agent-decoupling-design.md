# Workspace-Agent Decoupling And Revocable Access Design

## Goal

Define the long-term CoreMatrix topology that treats `Workspace` as the user's
top-level personal data space, removes `UserAgentBinding` as a first-class
product abstraction, and models agent access, ingress, and execution through
explicit revocable mounts.

This design intentionally ignores backward compatibility and favors a more
orthogonal core.

## Why Change The Current Shape

The current model mixes several concerns:

- `Workspace` is both a user data space and an agent-bound enablement root
- `UserAgentBinding` is a thin enablement record that overlaps with
  workspace-level ownership
- `Conversation` stores ownership, agent binding, and execution defaults as if
  they were equally durable truths
- ingress is being designed against a topology that is already too coupled

That coupling shows up in several product edge cases:

- a public agent turning private indirectly changes workspace accessibility
- ingress needs to answer whether it depends on `UserAgentBinding`
- runtime defaults live on both `Agent` and `Workspace` even though they are
  really "agent mounted in this user's space" concerns

## Design Principles

1. `Workspace` is a user-owned product space, not an agent mount.
2. Agent entitlement is explicit and revocable.
3. Ownership controls visibility; entitlement controls mutability.
4. Conversation remains the transcript and turn lineage aggregate root.
5. Ingress is an entry surface attached to a mounted agent, not to the raw
   workspace alone.
6. Execution runtime selection belongs to the mounted agent context, not to the
   workspace as a generic concept.

## Recommended Topology

### `Workspace`

`Workspace` becomes the user's top-level personal working space.

Suggested responsibilities:

- owned by one user
- scoped to one installation
- carries user-local configuration and preferences
- does not directly belong to one `Agent`
- does not directly own the default runtime used by one mounted agent

This means a single workspace may later host multiple mounted agents if the
product wants that, but the design does not require immediate multi-agent UI.

### `WorkspaceAgent`

Introduce a new aggregate root representing one agent mounted into one
workspace.

Suggested fields:

- `public_id`
- `installation_id`
- `workspace_id`
- `agent_id`
- optional `default_execution_runtime_id`
- `lifecycle_state`
  - `active`
  - `revoked`
  - `retired`
- optional `revoked_at`
- optional `revoked_reason_kind`
- `capability_policy_payload`
- `entry_policy_payload`

This object replaces the product role currently split across
`UserAgentBinding`, `Workspace.agent_id`, and `Workspace.default_execution_runtime_id`.

### `Conversation`

`Conversation` should belong to `WorkspaceAgent`.

Suggested consequences:

- `workspace_agent_id` becomes the durable entitlement root
- `workspace_id`, `agent_id`, and `user_id` may remain as denormalized read-side
  columns, but no longer represent the primary model edge
- execution defaulting and access control flow through `workspace_agent`

`Conversation` still remains the transcript aggregate root:

- turns
- messages
- attachments
- workflow runs
- feature snapshots

That does not change.

## Access Model

The key change is to separate visibility from mutability.

### Ownership Controls Visibility

If the user owns the workspace, the user can still view the workspace and its
historical conversations.

This preserves the user's historical data even when agent entitlement changes.

### Entitlement Controls Mutability

If the mounted agent is revoked, the user can still open the conversation but
cannot continue interacting with it.

Suggested conversation interaction states:

- `mutable`
- `locked_agent_access_revoked`
- `archived`
- `deleted`

This should be modeled separately from lifecycle/archive/delete state.

## Revocable Agent Access

If a public agent later becomes private, or otherwise stops being available to a
user, CoreMatrix should not delete historical conversations.

Instead:

- the relevant `WorkspaceAgent` moves to `revoked`
- conversations under that mount remain visible
- those conversations become locked for new interaction
- related ingress bindings become disabled
- related automation entry should stop scheduling new work

Suggested revoke reasons:

- `agent_visibility_revoked`
- `owner_revoked`
- `agent_retired`

## Capability And Entry Policy

The current `Conversation.addressability` model is too narrow for the future.

Long-term recommendation:

- remove `Conversation.addressability`
- replace it with explicit entry policy

Suggested entry-policy dimensions:

- `app_ui`
- `channel_ingress`
- `agent_internal`
- `automation`

Each source can be `allow` or `deny`.

Capability policy should move up to `WorkspaceAgent`, because that is where
"this user using this agent in this space" actually lives.

Suggested model:

- `WorkspaceAgent.capability_policy_payload`
  - default allowed conversation features
  - default UI/control capabilities
- `Conversation`
  - snapshots or overrides those defaults when created

This gives double protection for IM:

- ingress source can be denied by entry policy
- incompatible interactive features can be disabled by capability policy

## Execution Runtime Model

`ExecutionRuntime` remains the execution target resource.

Long-term resolution order should be:

1. ingress-specific override
2. `WorkspaceAgent.default_execution_runtime`
3. `Agent.default_execution_runtime`

`Workspace.default_execution_runtime` should be removed from the core path,
because runtime preference is not a generic workspace concern. It is a mounted
agent concern.

## Ingress Topology

Long-term ingress should attach to the mounted agent, not directly to the old
workspace-agent coupled shape.

Recommended model:

### `ChannelConnector`

Transport credential and live transport state.

Suggested responsibilities:

- Telegram bot token state
- Weixin login state
- poll cursors
- credential rotation state

### `IngressBinding`

User-managed entry route bound to one `WorkspaceAgent` and one connector.

Suggested fields:

- `public_id`
- `workspace_agent_id`
- `channel_connector_id`
- `public_ingress_id`
- `secret_digest`
- `lifecycle_state`
- `disabled_at`
- `disabled_reason_kind`
- `entry_policy_payload`

Suggested disable reasons:

- `user_disabled`
- `agent_access_revoked`
- `execution_runtime_unavailable`
- `credentials_invalid`

### `ChannelSession`

External peer/thread bound to one conversation.

### `ChannelInboundMessage`

Immutable normalized inbound fact.

### `ChannelDelivery`

Immutable outbound delivery fact.

## `UserAgentBinding` In The Ideal State

`UserAgentBinding` should be removed.

Its current role is mostly:

- enablement record for one user-agent pair
- light preference holder

That role is better expressed by `WorkspaceAgent`, which is both more concrete
and more useful to the product.

If a lightweight preference aggregate is still needed later, it should either:

- live on `WorkspaceAgent`, or
- become a clearly named `AgentPreference` aggregate

It should not remain as an ambiguous parallel enablement model.

## Product Semantics After Revocation

Recommended rule:

- conversations stay visible
- conversations become read-only
- app can still show transcript and attachments
- app cannot send new turns
- ingress cannot create new turns
- automation cannot create new work on revoked mounts

This is the most explainable product behavior:

- user history is preserved
- revoked access is enforced
- no hidden deletion happens

## Migration Intent

Because this design intentionally allows destructive changes, it should be
implemented as a topology refactor, not a compatibility layer.

Recommended intent:

- create `WorkspaceAgent`
- re-anchor conversation ownership and execution defaults there
- remove `UserAgentBinding`
- remove `Workspace.agent_id`
- remove `Workspace.default_execution_runtime_id`
- replace `Conversation.addressability`
- redesign ingress around `IngressBinding`

## Recommendation

This design should be treated as the preferred long-term prerequisite before
expanding Telegram/Weixin ingress deeply.

If adopted, the existing ingress design should be rebased on:

- `WorkspaceAgent` instead of the current workspace-agent coupling
- `IngressBinding` instead of endpoint-as-everything
- explicit read-only lock semantics after entitlement revocation

## Summary

The ideal future shape is:

- `Workspace` = user's durable personal data space
- `WorkspaceAgent` = revocable mounted agent context
- `Conversation` = transcript aggregate under one mounted agent
- `IngressBinding` = external entry route
- `ChannelConnector` = transport credentials/state

That is more orthogonal, more explicit about revocable access, and healthier
than continuing to evolve the current `UserAgentBinding + agent-bound Workspace`
topology.
