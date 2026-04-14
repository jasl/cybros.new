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
7. Mainline turns, sidecar questions, control commands, and artifact exchange
   are separate interaction surfaces and should not be collapsed into one
   transcript path.

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

### App Surface Consequences

The current app surface still assumes an agent-centric default-workspace flow:

- `/app_api/agents/:agent_id/home`
- `/app_api/agents/:agent_id/workspaces`
- `default_workspace_ref`
- conversation launch that starts from `agent_id` and optionally materializes a
  default workspace on first use

That shape does not fit the post-refactor topology.

After this destructive refactor:

- the browser/app management root should be `Workspace` plus nested
  `WorkspaceAgent`
- the old virtual default-workspace reference should be removed instead of
  preserved as a compatibility shim
- interactive launch and later message-send entry should resolve through a
  concrete `workspace_agent_id`
- app-facing visibility should show owned workspaces even when one mounted
  agent becomes revoked

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
- replace it with explicit entry policy plus separate interaction locking

The coarse source list `app_ui / channel_ingress / agent_internal / automation`
is not enough for the current product shape. The mounted policy should use
surface-scoped keys directly.

Capability policy should move up to `WorkspaceAgent`, because that is where
"this user using this agent in this space" actually lives.

Suggested model:

- `WorkspaceAgent.capability_policy_payload`
  - default allowed conversation features
  - default UI/control capabilities
- `Conversation`
  - snapshots or overrides those defaults when created
  - can narrow them further for child-conversation or channel-specific cases

This gives double protection for IM:

- ingress source can be denied by entry policy
- incompatible interactive features can be disabled by capability policy

Long-term, `entry_policy` should distinguish at least these interaction
surfaces:

- `main_transcript`
- `sidecar_query`
- `control`
- `artifact_ingress`
- `channel_ingress`
- `agent_internal`
- `automation`

That lets CoreMatrix express policies such as:

- app UI may open the main transcript, but IM may only use sidecar/control
- IM may be allowed to stop or report, but not fork or branch
- generated artifacts may still be deliverable even when a conversation is
  locked for normal dialogue
- subagent child conversations may allow only `agent_internal` while denying
  owner or channel transcript entry

This last rule is the required replacement for today's
`Conversation.addressability = agent_addressable` behavior. Removing
`addressability` must not collapse the agent-internal child-conversation
boundary into the same mutable surface used by the owner or IM ingress.

## Operational Sidecars, Commands, And Progress

CoreMatrix should model several operator-facing interaction surfaces that do
not all mutate the main transcript.

### Main Transcript

This is the ordinary conversation turn path.

- user/app input
- channel-ingress input
- selected input/output lineage
- workflow bootstrap and replay semantics

When the main transcript is shared by multiple external senders, follow-up
behavior must remain sender-scoped:

- the mounted conversation may still be a shared conversation
- same-sender follow-ups may steer or merge into that sender's active work
- cross-sender follow-ups must never steer another sender's active turn and
  should queue as later work instead

### Sidecar Query

This is a read-oriented question surface over the current conversation context.

The first IM-driven example should be `/btw`, borrowed from Claude-style chat:

- `/btw <question>`
- answers a one-off question about the main conversation context
- does not append a new user turn to the main transcript
- should be backed by the same supervision/sidecar substrate already used for
  `ConversationSupervision`

`/report` is a specialized sidecar query:

- it asks for the current work state, progress, blockers, or next steps
- it should prefer supervision/runtime evidence over asking the main agent to
  summarize itself from scratch

### Control

This is an imperative surface, not ordinary chat.

Examples:

- `/stop`
- future `/resume`
- future `/retry`

These should route through bounded control requests instead of being interpreted
as normal conversation content.

For shared channel conversations, control authority should also be sender-scoped
by default:

- the same external sender may stop or control its own active work
- a different external sender must not gain implicit authority over another
  sender's in-flight work just by sharing the conversation surface

### Regeneration

`/regenerate` is compatible with IM conceptually, but it is still a mutation of
the conversation's selected output state rather than an ordinary sidecar query.

The long-term design should treat it as:

- gated by capability policy
- allowed only when the mounted agent and target conversation remain mutable
- backed by an explicit conversation action surface, not by pretending it is a
  fresh user turn

### Progress Surfaces

Progress delivery should also be modeled separately from the final transcript.

CoreMatrix should support three distinct outward-facing progress modes:

- `preview_stream`
  - editable preview text when the transport supports edits or drafts
- `status_progress`
  - coarse progress cards/messages, typing indicators, report snapshots
- `final_delivery`
  - final text, files, images, and other deliverables

The mounted-agent and ingress policy model should therefore be able to express
what a given connector can do, instead of assuming every surface is a text
turn.

Command handling should also be extensible by construction. Long-term, command
support should not stay embedded inside one ingress preprocessor. Prefer an
explicit dispatcher boundary such as:

- `IngressCommands::Parse`
- `IngressCommands::Authorize`
- `IngressCommands::Dispatch`

That keeps future commands such as `/resume`, `/new`, or transport-specific
helpers from bloating the ordinary chat-batching path.

## Artifact Ingress And Egress

CoreMatrix already has `MessageAttachment` as its storage primitive, but it
lacks a first-class shared artifact-ingress surface.

Long-term, artifact exchange should be treated as a product capability in its
own right:

- app users can upload a file into a conversation
- runtimes can attach a generated local file to an output message
- IM delivery can project those attachments back to Telegram/Weixin as native
  media/file sends
- acceptance and other external consumers can treat conversation attachments as
  the final delivery boundary instead of scraping runtime-local working
  directories

This should not be modeled as transport-specific glue. The shared shape should
be:

- conversation-owned attachment storage remains `MessageAttachment`
- the stored file lives in Rails Active Storage regardless of whether it was
  uploaded by a human or published by a runtime-generated output
- published attachments should carry an explicit publication role such as:
  - `primary_deliverable`
  - `source_bundle`
  - `preview`
  - `evidence`
- a mounted-agent or conversation policy decides whether artifact ingress is
  allowed
- artifact ingress is also governed by a configurable maximum byte size
  (`max_bytes`), with a default product limit of 100 MB
- artifact ingress is also governed by a configurable maximum attachment count
  (`max_count`), with a default product limit of 10 attachments per publish
  operation
- ingress/outbound connectors only translate attachments to platform-specific
  transport formats

Hard boundary rules:

- App uploads, runtime-published local files, and inbound IM attachments must
  all pass through the same artifact-ingress byte-size policy before creating a
  `MessageAttachment`
- the conversation/storage limit and the transport delivery limit are separate
- the effective publish limit is the smallest applicable conversation or mount
  policy limit
- the effective publish count limit is the smallest applicable conversation or
  mount policy limit
- an artifact that exceeds the publish limit must be rejected before blob
  attachment and must not appear as a partial transcript attachment row
- an artifact batch that exceeds the publish count limit must be rejected
  before attachment rows are created
- a stored conversation attachment may still exceed a specific transport's
  outbound limit; in that case the attachment remains in the conversation, but
  the connector must fall back to a non-native delivery strategy

Default delivery strategy should be explicit:

- images should be sent as native media when the transport supports it
- non-image files smaller than 1 MB should be sent as native attachments when
  the transport supports it
- other files should default to a short-lived signed download URL backed by
  Active Storage

This is especially important for:

- generated webpages or HTML bundles
- generated documents and reports
- generated images
- later richer media outputs

For deployable web projects, the primary delivered artifact should normally be
the built distribution payload rather than the raw working directory. For
example, a Vite-based project should prefer its `dist/` bundle as the final
attachment, with source code or workspace archives treated as optional
secondary artifacts.

Artifact publication also does not need to be fused into the same turn that did
the work. A healthy long-term model should allow:

- one turn to produce or revise the work in-place
- a later export/publish action or follow-up turn to package and attach the
  final artifact to the conversation

That separation is especially useful for acceptance-grade flows such as the
2048 capstone, where downstream automation should be able to download the
published artifact from the conversation transcript through app-facing APIs,
unpack it locally, and verify it without depending on runtime-private
filesystem paths.

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
