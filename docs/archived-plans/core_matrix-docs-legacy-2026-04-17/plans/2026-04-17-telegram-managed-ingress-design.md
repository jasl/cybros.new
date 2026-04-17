# Telegram Managed Ingress Design

## Goal

Refactor CoreMatrix Telegram ingress so long polling and webhook are two
independent channel platforms, align the default Telegram operator flow with
OpenClaw-style long polling, and introduce reusable managed-conversation rules
for externally owned conversations without entangling transport concerns with
conversation ownership.

## Outcome Summary

After this design lands:

- `telegram` means Telegram Bot API long polling.
- `telegram_webhook` means explicit Telegram webhook delivery.
- each platform gets its own `IngressBinding`, `ChannelConnector`,
  `ChannelSession`, and isolated conversation reuse boundary
- channel-backed conversations are managed conversations and cannot accept app
  mainline user turns or metadata drift, even while idle
- managed conversations keep explicit safe exits: `fork` and `stop`
- if an archived or deleted channel-managed conversation receives new inbound
  traffic, CoreMatrix creates a fresh root conversation and rebinds the session
- operator session rebinding no longer points a session directly at an existing
  conversation; it creates a new managed fork-like conversation from the chosen
  context and binds the session there
- the reusable managed policy is shared with subagent conversations instead of
  living only in Telegram-specific code

## Constraints From The Existing Code

- `ChannelSession` already defines the conversation reuse boundary by
  `channel_connector + peer_kind + peer_id + normalized_thread_key`.
- `Conversation.entry_policy_payload` already controls who may write to the
  main transcript and is the existing mechanism that blocks subagent
  conversations from user mainline input.
- `Conversation.interaction_lock_state` currently gates generic mutable-state
  helpers such as `WithMutableStateLock`, but those helpers are used by many
  paths that channel-managed conversations must still allow, especially channel
  ingress itself.
- `CreateFork` currently inherits the parent conversation's
  `entry_policy_payload` by default, so a managed conversation would currently
  create another managed child unless the entry policy is explicitly reset.
- `SessionsController#update` currently allows direct rebinding of a
  `ChannelSession` to any retained conversation under the same workspace agent.
- Telegram Bot API transport mode is chosen per bot token, not per CoreMatrix
  binding. A bot token cannot be used for both `getUpdates` and webhook mode at
  the same time.

These constraints drive the audited design below.

## Design Principles

### Transport Orthogonality

Transport is an ingress concern, not a conversation concern.

- `telegram` and `telegram_webhook` are different channel platforms
- each platform owns its own connector config, setup flow, and runtime
- conversation ownership rules stay the same regardless of transport

This keeps the model easy to reason about and avoids one connector carrying
multiple transport modes.

### Protocol Family Versus Platform Key

CoreMatrix needs two identifiers:

- the connector/session platform key:
  - `telegram`
  - `telegram_webhook`
  - `weixin`
- the protocol family carried by the normalized envelope:
  - Telegram envelopes remain `platform = "telegram"`
  - Weixin envelopes remain `platform = "weixin"`

This distinction matters because many normalized message concepts are
Telegram-wire concepts regardless of transport:

- external event keys such as `telegram:update:*`
- external message keys such as `telegram:chat:*`
- attachment download logic
- reply key parsing

The design therefore keeps envelope-level Telegram wire semantics stable while
splitting connector/session platform keys for operational isolation.

### Managed Conversation As Shared Infrastructure

Managed conversation means “the main transcript is externally owned”.

This applies to:

- `SubagentConnection`-owned conversations
- channel-ingress-managed conversations

The shared policy should answer:

- is the conversation externally managed right now?
- which ownership source makes it managed?
- which operations remain allowed?

The implementation should reuse existing conversation primitives and avoid
inventing a new parallel ownership table unless forced by real gaps.

### No New Conversation Lock State By Default

The preferred audited design does **not** introduce a new
`Conversation.interaction_lock_state` enum value.

Reason:

- channel-managed conversations must reject app mainline user turns
- channel-managed conversations must still accept channel ingress turns
- channel-managed conversations must still allow `fork`
- channel-managed conversations must still allow `stop`

`interaction_lock_state` currently feeds generic mutable-state helpers used by
many operations. Overloading it with a new managed lock would force special
exceptions back into the shared lock path and would couple unrelated mutation
semantics.

The preferred split is:

- use `entry_policy_payload` for transcript-entry ownership
- use a shared managed-policy service for metadata and other managed-sensitive
  mutations
- keep `interaction_lock_state` for its current generic lifecycle and access
  semantics unless a broader future lock redesign is justified

This keeps the ownership model more orthogonal and avoids a destructive schema
rewrite that the current refactor does not need.

## Platform Model

### `telegram`

`telegram` becomes the primary Telegram platform and uses long polling.

Connector defaults:

- `platform = "telegram"`
- `driver = "telegram_bot_api"`
- `transport_kind = "poller"`

Configuration:

- requires bot token
- does not require `webhook_base_url`
- may optionally store poll tuning in `config_payload`
- stores poll runtime state such as last processed update id in
  `runtime_state_payload`

Runtime:

- a recurring dispatcher job scans active poller connectors and enqueues the
  correct per-platform poll job
- the per-connector poll job ensures the bot is not in webhook mode, then calls
  `getUpdates`
- poll offset is durable in `runtime_state_payload`
- normalized updates flow through the existing `IngressAPI::ReceiveEvent`
  pipeline with request metadata `source = "telegram_poller"`

### `telegram_webhook`

`telegram_webhook` is the explicit webhook transport.

Connector defaults:

- `platform = "telegram_webhook"`
- `driver = "telegram_bot_api"`
- `transport_kind = "webhook"`

Configuration:

- requires bot token
- requires `webhook_base_url`
- reuses ingress secret handling for
  `X-Telegram-Bot-Api-Secret-Token`

Runtime:

- keeps the existing webhook controller path, verification, normalization, and
  outbound delivery behavior
- request metadata uses `source = "telegram_webhook"`

## Telegram Token Exclusivity

Telegram transport mode is bot-token-global.

That means:

- one bot token cannot be polled while a webhook is set for the same bot
- one bot token also cannot back two independent active webhook bindings, since
  Telegram only stores one webhook target

Therefore CoreMatrix must reject active Telegram-family connector
configurations in the same installation that reuse the same bot token across
multiple active `telegram`/`telegram_webhook` connectors.

Product consequence:

- polling and webhook are independent CoreMatrix channels
- but they must use different Telegram bots if they are expected to run at the
  same time

This is not a CoreMatrix limitation; it is a Telegram Bot API constraint.

## Polling Runtime Design

### Scheduling

The implementation needs an actual scheduler path, not just a per-connector
poll job.

Preferred shape:

- add a recurring dispatch job in `config/recurring.yml`
- the recurring job finds active poller connectors
- it dispatches per-platform poll jobs, reusing existing poller infrastructure
  such as Weixin while adding Telegram polling

This keeps the operational story explicit and testable.

### Concurrency

The polling plan must guard against overlapping polls for the same connector.

At minimum, the per-connector poll job should serialize on the connector row or
equivalent runtime-state lock before it advances polling state. The goal is:

- no duplicate offset advancement races
- no duplicate long-poll workers for the same connector

The audit does not require a new table for this. Connector row locking plus
runtime state is sufficient for the initial design.

## Conversation Ownership Model

### Reuse Boundary

Conversation reuse continues to be defined by `ChannelSession`.

For a given connector:

- same peer and same thread reuse the same `ChannelSession`
- the session points at exactly one current bound `Conversation`
- different connectors do not share sessions or conversations

This means:

- `telegram` polling and `telegram_webhook` remain isolated
- even if the same external Telegram user appears on both connectors, the
  conversations are different because the connector boundary is different

### Managed Determination

Managed state should be derived from ownership sources, not from a new
conversation table.

Preferred derived rules:

- a conversation is subagent-managed when it has a `subagent_connection`
- a conversation is channel-managed while at least one bound
  `ChannelSession` points at it with `binding_state != "unbound"`

This keeps ownership orthogonal to transport implementation details.

### Ownership Projection And Operability

Managed ownership must be visible through a shared computed projection, not only
enforced implicitly in write paths.

Preferred shape:

- derive a single management projection from the shared managed policy service
- expose it through App/API conversation reads and conversation export/debug
  surfaces
- keep it computed from associations and public ids, not stored as a new
  conversation column

Initial projection fields should be conservative and operator-friendly:

- `managed`
- `manager_kind`
- `subagent_connection_id`
- `owner_conversation_id`
- channel session and ingress binding public ids when channel-managed

This gives operators a direct answer to “who currently owns this transcript?”
without coupling transport implementation to the conversation schema.

### Entry Policy Helpers

Managed ownership needs explicit entry-policy helpers.

Preferred helpers:

- an ordinary interactive policy derived from the workspace agent baseline
- a channel-managed policy derived from that baseline but with:
  - `main_transcript = false`
  - `channel_ingress = true`
  - `control = true`
  - `sidecar_query` preserved from the baseline
- a subagent-managed policy for agent-internal ownership

The important rule is that channel-managed entry policy should be derived from
the workspace-agent baseline rather than hard-coded from global defaults,
otherwise managed conversations can accidentally ignore workspace restrictions.

### Centralized Channel-Managed Conversation Creation

Channel-managed conversation creation should not be reimplemented in three
places.

The same creation path should be reused for:

- first approved pairing that creates a session-backed conversation
- archived or deleted session rotation
- operator session rebinding from an existing source conversation

The shared creator/factory should own:

- entry-policy selection for channel-managed conversations
- capability projection reuse from the workspace-agent baseline
- deterministic managed title assignment
- conversation shape choice:
  - fresh root when the channel starts a new transcript
  - managed fork-like child when the operator repairs from an existing source
    conversation

This keeps managed channel bootstrap rules cohesive and reduces drift between
pairing, repair, and lifecycle-rotation paths.

## Managed Conversation Rules

### Blocked Operations

Managed conversations reject operations that would break source-of-truth
alignment:

- app/API main transcript entry
- user metadata edits
- metadata regeneration
- agent-side metadata rewrites
- override or selector mutations that would change future execution behavior
- automatic title bootstrap for channel-managed conversations

### Allowed Operations

Managed conversations still allow:

- channel ingress on channel-managed conversations
- agent-internal turns on subagent-managed conversations
- safe read-only supervision
- `fork`
- `stop`
- lifecycle operations such as archive/delete

### Where The Policy Must Be Applied

The shared managed policy must be enforced in service-layer code, not only in
controllers, because direct service callers already exist.

At minimum the audit expects coverage for:

- `Turns::StartUserTurn` / `Turns::AcceptPendingUserTurn`
- metadata services:
  - `Conversations::Metadata::UserEdit`
  - `Conversations::Metadata::Regenerate`
  - `Conversations::Metadata::AgentUpdate`
  - `Conversations::UpdateOverride`
  - channel-managed title bootstrap guard paths

## Fork Semantics

### User Fork From Managed Conversation

`fork` remains the official “take back control” path.

Behavior:

- the user forks from the managed conversation
- the new fork inherits transcript context and lineage normally
- the new fork restores the ordinary interactive entry policy derived from the
  workspace-agent baseline
- the new fork is not managed unless another ownership source later makes it
  managed
- the original managed conversation remains externally owned

This detail is critical because `CreateFork` currently inherits the parent's
entry policy by default. The implementation must explicitly reset the child
entry policy when the parent is managed.

### Operator Session Rebind

The session repair surface should no longer bind a session directly to an
existing retained conversation.

New behavior:

- the operator chooses a retained source conversation under the same workspace
  agent
- CoreMatrix creates a new managed fork-like conversation from that source
  context
- the session binds to that new managed conversation

Why this is preferable:

- it preserves source context
- it keeps the channel-owned transcript separate from the source conversation
- it avoids turning an arbitrary existing conversation into a channel-owned
  source of truth

This repair path should be implemented as a dedicated operator/application
service, not by reusing `CreateFork` blindly, because the repair surface should
not depend on user-facing branching feature flags or parent mutability checks.

## Archived And Deleted Session Rotation

When inbound traffic resolves an existing `ChannelSession`:

- active retained conversations are reused
- archived conversations cause creation of a fresh root conversation and
  session rebinding
- pending-delete or deleted conversations also cause creation of a fresh root
  conversation and rebinding

`stop` does **not** rotate the conversation by itself.

This keeps IM behavior intuitive and avoids resurrecting a closed transcript.

## Metadata And Title Rules

Managed channel conversations must not enter the ordinary title/summary drift
paths.

Rules:

- set a deterministic title at managed channel conversation creation time
- do not rely on the generic bootstrap-title job for channel-managed
  conversations
- block user, regenerate, and agent metadata update paths for managed
  conversations
- leave summary unset unless a future managed-safe summary rule exists

Initial title examples:

- `Telegram DM @username`
- `Telegram DM 123456789`
- `Telegram Webhook DM @username`
- `Telegram Webhook DM 123456789`

Title source should reuse an existing source enum value such as `agent`; this
refactor does not need a new title-source enum.

## Stop Behavior

Managed conversations keep an explicit stop escape hatch.

Entry points:

- IM `/stop`
- existing app-side conversation control/supervision surfaces

Behavior:

- request interruption through the existing CoreMatrix stop flow
- send an explicit acknowledgement back through the channel
- treat `/stop` as idempotent from the IM surface when practical:
  - if work was interrupted, acknowledge that it stopped
  - if no active work exists, return an explicit already-stopped/no-active-work
    notice instead of a silent rejection

This is a better IM operator experience than returning no delivery for control
commands.

## AppAPI And CLI Shape

App/API:

- creating a polling Telegram binding uses `platform = "telegram"`
- creating a webhook Telegram binding uses `platform = "telegram_webhook"`
- setup payloads differ by platform
- session repair rebinding uses the managed-fork repair path described above

CLI:

- `cmctl ingress telegram setup` configures polling and does not ask for
  webhook base URL
- `cmctl ingress telegram-webhook setup` configures webhook and prints webhook
  material
- readiness/status output distinguishes polling and webhook bindings
- CLI help and docs must explicitly mention that simultaneous polling and
  webhook require different Telegram bot tokens
- CLI help and docs must explicitly mention that polling requires the CoreMatrix
  recurring scheduler and queue worker to be running

## Testing Strategy

Lock behavior with tests at these layers:

1. platform and connector tests
   - `telegram` defaults to poller
   - `telegram_webhook` defaults to webhook
   - active Telegram-family connectors reject duplicated bot tokens
2. polling runtime tests
   - recurring dispatch enqueues eligible poll connectors
   - per-connector poll job clears webhook mode and advances offsets
   - request metadata identifies polling as `telegram_poller`
3. managed policy tests
   - managed conversations reject app mainline input while idle
   - managed conversations reject metadata drift, including agent metadata
     updates
   - app/API and export/debug surfaces expose the computed management
     projection with public ids only
   - user fork from a managed conversation restores ordinary entry policy
4. session lifecycle tests
   - operator session rebinding creates a new managed fork-like conversation
   - archived/deleted managed conversations rotate to a fresh root conversation
5. ingress command tests
   - `/stop` returns a channel acknowledgement
   - repeated `/stop` with no active work produces an explicit stopped/no-op
     response
6. Telegram family integration tests
   - delivery, progress, and attachment paths work for both
     `telegram` and `telegram_webhook`
7. CLI tests
   - polling and webhook setup flows diverge correctly
   - readiness/status output distinguishes both Telegram platforms

## Risks

- If Telegram-family call sites are not swept systematically, code paths that
  branch on `platform == "telegram"` will silently skip `telegram_webhook`.
- If managed policy is only applied at the controller layer, direct service
  callers will bypass it.
- If managed ownership is not projected through read surfaces, operators will
  not be able to tell whether a conversation is managed by a channel or a
  subagent while debugging staging behavior.
- If user forks from a managed conversation without resetting entry policy, the
  fork will stay unintentionally managed.
- If pairing, rebinding, and rotation each create managed conversations
  differently, titles and entry-policy semantics will drift over time.
- If operator session rebinding reuses `CreateFork` directly, feature gates or
  parent mutability checks will make the repair surface unreliable.
- If polling lacks a recurring scheduler or per-connector concurrency guard, a
  configured polling connector will appear valid but not behave reliably.
- If duplicated Telegram bot tokens are allowed across active connectors,
  staging will fail in confusing transport-level ways.

## Recommendation

Implement the refactor as a destructive rename and cleanup:

- `telegram` becomes long polling
- `telegram_webhook` becomes explicit webhook
- managed ownership stays orthogonal to transport
- managed state is derived from ownership sources plus entry policy, not from a
  new conversation schema field

This audited design keeps the transport split simple, keeps managed ownership
reusable across channel and subagent conversations, and avoids unnecessary
Conversation schema churn while still supporting the staging workflow you want.
