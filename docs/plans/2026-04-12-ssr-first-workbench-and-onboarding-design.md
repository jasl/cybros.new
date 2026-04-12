# SSR-First Workbench And Onboarding Design

**Date:** 2026-04-12

## Goal

Define the first real Web product surface for `core_matrix` using an
SSR-first hybrid architecture that supports:

- a cowork-style end-user workbench
- an admin console for private-installation operators
- document-driven onboarding for `Agent` and `ExecutionRuntime`
- future migration to a fully separated frontend without changing product
  semantics

## Scope

This design applies to:

- `core_matrix` Web product architecture
- app-facing API boundaries and realtime event contracts
- workbench and admin information architecture
- onboarding flows for `Agent` and `ExecutionRuntime`
- guide-driven manual acceptance expectations

This design does not apply to:

- the internal machine control protocol between `core_matrix` and
  `agents/fenix`
- the internal machine control protocol between `core_matrix` and
  `execution_runtimes/nexus`
- implementation-level CSS, component, or controller details
- the final choice of frontend framework after the SSR-first phase

## Product Constraints

The approved product constraints are:

- end users never interact directly with `Agent` or `ExecutionRuntime`
  machine-control surfaces
- `agent_api` stays machine-facing
- `execution_runtime_api` stays machine-facing
- browser and future custom apps use `app_api` plus realtime subscriptions
- the SSR Web client should authenticate through same-origin session cookies
  protected by CSRF, while non-browser app clients may continue using
  bearer-style session tokens until a dedicated client-token model is added
- the first Web product should be SSR-first, but the product API must remain
  reusable by a future SPA, desktop app, or custom agent-specific app
- onboarding flows for `Agent` and `ExecutionRuntime` must be documented in
  `guides` and manually accepted by following the published steps

## Architectural Recommendation

The approved approach is `SSR-first hybrid`.

`core_matrix` remains the single Web host and exposes:

- Rails-rendered page shells
- typed app-facing APIs
- realtime event subscriptions

The browser uses:

- SSR for initial page load, navigation shell, auth/session state, and admin
  forms
- Turbo/Stimulus-style progressive enhancement for dynamic sections
- realtime updates for long-running conversation and onboarding activity

This is preferred over a full frontend/backend split because:

- `core_matrix` already owns the durable app-facing read models and
  supervision concepts
- the admin console is form-heavy and operational rather than highly visual
- the workbench needs event-driven updates more than client-side routing
- the product semantics are still evolving and should not be frozen behind an
  extra frontend/backend split yet

## Implementation Sequencing

The approved rollout order is intentionally split into three parts.

### Phase 1: Foundation Reset

Do all structural and destructive adjustments first, before any serious UI
implementation.

This phase includes:

- separating human-facing `app_api` foundations from machine-facing
  `agent_api` and `execution_runtime_api`
- replacing `PairingSession` with a neutral `OnboardingSession`
- removing eager default workspace creation
- adding user-authenticated realtime foundations

The purpose of this phase is to stop future UI and API work from building on
the wrong seams.

### Phase 2: App Surface

Build and stabilize the workspace-first app-facing surface next.

This phase includes:

- app-surface policies, queries, and presenters
- workspace-first workbench read models and actions
- admin-facing onboarding and installation resources
- transport-neutral app-facing realtime event contracts

The goal of this phase is to make `app_api` the true product contract before
HTML becomes the primary expression of behavior.

### Phase 3: SSR UI

Build the Rails SSR workbench/admin product only after the first two phases
are stable enough to support iteration.

This phase includes:

- login/setup/admin HTML flows
- the cowork workbench UI
- the admin onboarding UI
- guide publication and manual acceptance

This sequencing is deliberate. UI work is expected to iterate heavily and
should sit on top of already-correct boundaries rather than forcing those
boundaries to move underneath it.

## Existing Frontend Baseline

The current `core_matrix` frontend baseline is already sufficient for the
first product phase and should be treated as the approved implementation base.

Current `core_matrix/package.json` already includes:

- `@hotwired/turbo-rails`
- `@hotwired/stimulus`
- `@rails/request.js`
- `tailwindcss`
- `daisyui`
- `tailwindcss-motion`
- `@iconify-json/lucide` and `@iconify/tailwind4`

Implementation should reuse this stack rather than introducing a second UI
framework or a separate component system.

In particular:

- do not add React, Vue, or another SPA framework for this phase
- do not add a second CSS framework
- prefer server-rendered HTML, Turbo navigation, and focused Stimulus
  controllers over client-heavy page orchestration
- use Tailwind and daisyUI as the primary styling vocabulary for the SSR-first
  client

## UI Product References

The approved product references for layout and interaction are:

- Codex
- ChatGPT

These references should guide:

- a left navigation rail for agent/workspace/conversation access
- a dominant center transcript/composer column
- a secondary right-side context lane for plan, activity, and approvals
- tight, keyboard-friendly, productivity-first spacing
- status chips and activity summaries that read as product language rather
  than machine internals

The goal is not literal cloning. The goal is a similarly legible,
work-focused shell for long-running agent work.

## Rails SSR Reference

`references/original/references/fizzy` is the approved Rails SSR reference for
technical implementation style.

Relevant lessons to absorb from `fizzy`:

- keep Rails views as the primary page-rendering layer
- use Turbo/Stimulus as enhancement, not as a hidden SPA runtime
- prefer many small, focused Stimulus controllers over one large client
  application object
- keep layout structure and navigation in server-rendered templates
- let HTML-first flows remain understandable without deep client-side state

## Product Surface Layers

`core_matrix` should be treated as three explicit layers:

1. `Domain / Orchestration`
   - conversations
   - turns
   - supervision
   - agent/runtime pairing
   - audit and execution governance
2. `App Surface`
   - stable app-facing read models
   - stable app-facing user/admin actions
   - stable realtime event vocabulary
3. `Web Shell`
   - Rails routes, controllers, views
   - Turbo/Stimulus behavior
   - HTML presentation for the SSR-first client

The Web Shell is only one client of the App Surface. Future custom apps should
consume the same `app_api` contracts and realtime event model rather than
reaching into machine control endpoints.

## Hard Boundary Rules

- Do not expose `agent_api/*` directly to browsers or future custom apps.
- Do not expose `execution_runtime_api/*` directly to browsers or future
  custom apps.
- Do not leak `poll/report` semantics into the app-facing product API.
- Use `public_id` at every app-facing boundary.
- HTML controllers should render from shared presenters/serializers instead of
  page-specific ad hoc JSON.
- Realtime events and REST read models must share the same resource naming and
  field vocabulary.
- Preserve separate machine/runtime streams and app-facing streams; browser
  clients should subscribe only to app-facing realtime channels.

## App-Surface Authorization Model

Authorization for the product surface should be single-sourced.

### Layer Responsibilities

- controllers and channels
  - authenticate the caller
  - parse request params
  - resolve `public_id` references into records
- app-surface policies
  - make the actual product authorization decision for end-user and operator
    actions
  - decide whether a user may view, mutate, or subscribe to a given product
    resource
- services and domain objects
  - enforce business invariants such as lifecycle, idempotency, stale report
    rejection, and machine-resource ownership
  - record audit attribution where an `actor` is required

### Hard Rule

Do not implement the same end-user/operator authorization twice in both the
app surface and downstream services.

That means:

- app-facing controllers and channels should not hand-roll authorization
  against `current_user`
- app-facing controllers and channels should not directly call
  `ResourceVisibility::Usability` once app-surface policies exist
- domain/application services may still accept `actor` for audit or provenance,
  but should not re-evaluate app-surface user access unless the service itself
  is the app-surface action object

### Migration Guidance

Existing authorization helpers such as `ResourceVisibility::Usability` and the
conversation-supervision authority objects may remain implementation details,
but they should be wrapped by explicit app-surface policies so the product
surface has one place to reason about access.

## Product Resource Model

### Core Relationship Model

The approved user-facing relationship model is:

- `Agent has many Workspaces`
- `Workspace has many Conversations`

`Conversation` should not be modeled as the direct first-level container under
an end-user-visible `Agent`.

### Why Workspace Is Required

`Workspace` is the durable work container analogous to a project/work area.
It gives the user a stable place to return to, while `Conversation` remains a
thread inside that place.

This lets the product support:

- multiple threads under one work area
- stable runtime and policy defaults at the workspace layer
- future workspace-level tools, artifacts, and visibility rules

### Execution Runtime Selection

The current product decision is intentionally narrow:

- `workspace` provides the default `execution_runtime`
- the first turn of a newly created conversation may explicitly override that
  runtime
- once the conversation exists, ordinary conversation message APIs must not
  switch the runtime
- runtime version refresh within the same runtime identity remains an internal
  execution concern, not a user-facing handoff flow

This means conversation runtime selection is treated as a creation-time choice,
not a mutable thread setting.

Agent visibility and agent launchability are intentionally separate concerns:

- users may still see an agent and its home/workspace surfaces even if the
  agent default runtime is currently unavailable
- launchability is evaluated only when starting a conversation
- an explicit first-turn runtime override can therefore make an otherwise
  visible-but-not-launchable agent usable for that conversation

### Runtime Handoff Is Deferred

Conversation-to-runtime handoff is approved as future work, not as a Phase 2
or Phase 3 gap in the current implementation.

For now:

- any follow-up `execution_runtime_id` on message-send APIs should return a
  product-facing error
- the error should make it explicit that runtime handoff is not implemented
  yet
- the system should not silently reinterpret follow-up runtime changes as a
  cheap metadata swap

The design assumption is that real handoff will likely require durable
conversation locking, execution-context reconciliation, and recovery-safe state
transitions rather than a simple row update.

## Default Workspace Policy

Each user-usable `Agent` should expose one default workspace entry point.

However, the system should not eagerly create a real workspace row for every
possible user-agent combination.

The approved policy is `lazy materialization`.

### Lazy Materialization

The UI should behave as if the default workspace already exists, but the
backend only materializes the real `Workspace` record when the user performs a
first substantive action such as:

- sending the first message
- explicitly starting the workspace
- uploading an initial attachment

### Product Behavior

For the user:

- the agent appears immediately usable
- the default workspace appears in the UI immediately
- no explicit "create workspace first" step is shown

For the backend:

- the app surface may return a `default_workspace_ref`
- that ref may be `virtual` until first use
- the first conversation-creating action may atomically materialize the
  workspace and create the conversation

### UX Rule

Do not surface internal terms such as `virtual workspace` or
`materialization` in the user UI. Use product language such as:

- `Start working`
- `Your first conversation will set up this workspace`

## App API Direction

The app-facing API should be resource-oriented with explicit user/admin
actions, not a generic RPC façade.

### Workbench Read Models

Approved read-model families:

- `agent_home`
- `workspace`
- `conversation`
- `conversation_transcript`
- `turn_todo_plan`
- `turn_runtime_event`
- `supervision_session`
- `approval_request`
- `export_request`

### Workbench Actions

Approved action families:

- `send_message`
- `create_conversation`
- `branch_conversation`
- `rename_conversation`
- `resolve_approval`
- `start_supervision_session`
- `close_supervision_session`

These actions should appear as explicit app-facing operations rather than
leaking internal workflow verbs.

### Admin Read Models

Approved admin-facing resource families:

- `installation`
- `agent`
- `agent_release`
- `execution_runtime`
- `runtime_host`
- `llm_provider`
- `onboarding_session`
- `audit_entry`

Approved user-facing configuration families:

- `workspace_policy`

### Admin Actions

Approved admin-facing action families:

- `create_agent_onboarding_session`
- `create_runtime_onboarding_session`
- `rotate_agent_credential`
- `rotate_runtime_credential`
- `update_llm_provider`
- `authorize_codex_subscription`
- `revoke_codex_subscription_authorization`
- `request_llm_provider_connection_test`

Approved user-facing configuration actions:

- `update_workspace_policy`

## Suggested App API Shape

Illustrative examples, not final route lock-in:

### Workbench

- `GET /app_api/agents`
- `GET /app_api/agents/:agent_id/home`
- `GET /app_api/agents/:agent_id/workspaces`
- `GET /app_api/agents/:agent_id/workspaces/:workspace_id`
- `GET /app_api/agents/:agent_id/workspaces/:workspace_id/conversations`
- `POST /app_api/conversations`
  - if no `workspace_id` is supplied, the system uses the agent default
    workspace and materializes it on first use if needed
- `GET /app_api/conversations/:conversation_id/transcript`
- `GET /app_api/conversations/:conversation_id/todo_plan`
- `GET /app_api/conversations/:conversation_id/turns/:turn_id/runtime_events`
- `POST /app_api/conversations/:conversation_id/supervision_sessions`
- `POST /app_api/conversations/:conversation_id/supervision_sessions/:id/messages`
- `POST /app_api/approval_requests/:id/resolve`

### Admin

- `GET /app_api/admin/installation`
- `GET /app_api/admin/agents`
- `POST /app_api/admin/agents/onboarding_sessions`
- `GET /app_api/admin/agents/:id`
- `POST /app_api/admin/agents/:id/rotate_credential`
- `GET /app_api/admin/execution_runtimes`
- `POST /app_api/admin/execution_runtimes/onboarding_sessions`
- `GET /app_api/admin/execution_runtimes/:id`
- `POST /app_api/admin/execution_runtimes/:id/rotate_credential`
- `GET /app_api/admin/llm_providers`
- `GET /app_api/admin/llm_providers/:provider`
- `PATCH /app_api/admin/llm_providers/:provider`
- `PATCH /app_api/admin/llm_providers/:provider/credential`
- `PATCH /app_api/admin/llm_providers/:provider/policy`
- `PATCH /app_api/admin/llm_providers/:provider/entitlements`
- `GET /app_api/admin/llm_providers/codex_subscription/authorization`
- `POST /app_api/admin/llm_providers/codex_subscription/authorization`
- `DELETE /app_api/admin/llm_providers/codex_subscription/authorization`
- `GET /app_api/admin/llm_providers/codex_subscription/authorization/callback`
- `POST /app_api/admin/llm_providers/:provider/test_connection`
- `GET /app_api/admin/audit_entries`

### User Workspace Settings

- `GET /app_api/workspaces/:workspace_id/policy`
- `PATCH /app_api/workspaces/:workspace_id/policy`

## Batch C Resource Decisions

The Batch C contract questions are resolved.

### `llm_providers`

`llm_providers` is the approved admin resource family. It is keyed by the
provider handle from the effective provider catalog, not by database primary
key.

The resource is a composite of:

- catalog-backed provider definition from `ProviderCatalog::Snapshot`
- installation-scoped overlay records for credentials, policy, and
  entitlements

Approved rules:

- the provider resource exists even when no overlay rows exist yet
- overlay records should be lazy-created on first write
- each provider is soft-limited to one credentials record for now
- no API may return raw API keys, OAuth tokens, or other plaintext secrets
- connection tests are asynchronous and only the latest result needs to be
  retained
- `codex_subscription` uses specialized OAuth actions inside the same
  resource family rather than a parallel top-level resource
- `codex_subscription` authorization is served by
  `AppAPI::Admin::LLMProviders::CodexSubscription::AuthorizationsController`
- if `codex_subscription` is disabled in the effective provider catalog, the
  authorization routes return `404`
- OAuth-backed providers remain `enabled=true` even when reauthorization is
  required; the resource should instead expose `reauthorization_required=true`
  and `usable=false`
- OAuth credential refresh should happen automatically on demand before model
  requests use an expired token
- Ruby constants should use the `LLMProviders` namespace to match the `LLM`
  acronym inflection, while Rails file and directory paths remain
  `llm_providers/*`

Implementation note:

- `llm_providers` needs an installation-scoped latest connection-test record
  so the resource can expose asynchronous test status without inventing
  history semantics
- OAuth-backed providers such as `codex_subscription` need a transient
  authorization-session/state carrier distinct from the stored
  `ProviderCredential`
- `ProviderCredential` should keep API-key style credentials in `secret`, but
  add dedicated encrypted OAuth columns such as `access_token` and
  `refresh_token`
- OAuth expiry and lifecycle timestamps such as `expires_at`,
  `last_refreshed_at`, and `refresh_failed_at` may remain plaintext
- `ProviderCredential.metadata` should remain non-sensitive and must not hold
  raw tokens
- OAuth callbacks should terminate inside `core_matrix`, resolve the
  authorization `state`, and then write the resulting credential record

### `workspace_policies`

`workspace_policies` is not an admin resource.

It belongs to the end-user app surface because workspaces are owner-private
and this resource expresses user-controlled workspace settings rather than
installation-wide administration.

Approved rules:

- the resource shape is `workspace settings + deny-only capability overlay`
- the agent metadata defines the maximum available capability set
- the workspace policy may only disable capabilities, never add new ones
- effective capabilities are `available_capabilities - disabled_capabilities`
- policy changes affect only newly created conversations, not existing ones
- `Fenix` should disable `regenerate` and `swipe` at the agent capability
  baseline

Implementation note:

- `workspace_policies` needs a workspace-scoped persisted overlay rather than
  an admin-only read model
- new conversation creation must project the workspace policy into the new
  conversation's capability policy state
- the product still needs a canonical end-user capability vocabulary for
  entries such as `regenerate`, `swipe`, `supervision`, and `control`

### `audit_entries`

`audit_entries` remains an admin resource, but its meaning is intentionally
narrow:

- read-only human operation audit stream
- focused on `who did what to what, and when`
- excludes diagnostic/system event streams for now
- includes human actors only, not background or machine-generated events

## Realtime Event Model

Realtime is approved as a product requirement for:

- active conversation work
- plan updates
- runtime activity summaries
- approvals
- onboarding progress

Transport may begin with ActionCable, but event naming and payload shape should
remain transport-neutral so the system can later move to SSE or a dedicated
frontend gateway without changing product semantics.

The implementation should preserve a separate raw runtime stream for existing
publication or machine-adjacent consumers and project a distinct app-facing
stream for the workbench.

### Event Envelope

Recommended shape:

```json
{
  "event_type": "turn.runtime_event.appended",
  "resource_type": "conversation_turn_runtime_event",
  "resource_id": "trev_public_123",
  "conversation_id": "conv_public_123",
  "turn_id": "turn_public_123",
  "sequence": 42,
  "occurred_at": "2026-04-12T10:00:00Z",
  "payload": {
    "summary": "Started the preview server in /workspace/foo"
  }
}
```

### Approved Event Families

- `conversation.updated`
- `transcript.item.appended`
- `turn.started`
- `turn.completed`
- `turn.runtime_event.appended`
- `turn.todo_plan.updated`
- `approval_request.created`
- `approval_request.resolved`
- `supervision_session.updated`
- `onboarding_session.updated`
- `agent.updated`
- `execution_runtime.updated`

Do not use internal workflow node names, `provider_round_*`, `poll/report`, or
machine-control labels as browser event types.

## Acceptance Strategy

`acceptance` should be treated as product-facing end-to-end verification where
that makes sense, not merely as a service-driver harness.

### Product Acceptance Scope

After Phase 2 is complete:

- end-user workbench acceptance should drive `app_api` and app-facing realtime
  contracts
- admin/operator acceptance should drive `app_api/admin/*` and
  `onboarding_session` flows
- machine-protocol acceptance should continue to hit `agent_api` and
  `execution_runtime_api` directly

### Helper Boundary

Acceptance helpers should be split by boundary:

- app-surface helpers
  - authenticate with human session tokens
  - call `app_api`
  - subscribe to app-facing realtime channels/events
- machine helpers
  - authenticate with machine credentials
  - call `agent_api` / `execution_runtime_api`

The stabilized pattern is:

- end-user/operator acceptance authenticates with human session tokens and
  drives `app_api`
- machine protocol acceptance continues to authenticate with machine
  credentials and hit `agent_api` / `execution_runtime_api`

### Observation Rule

Direct database reads, logs, console output, and runtime transcripts remain
valid observation tools for acceptance, diagnosis, and proof collection.
They should not remain the primary action driver for end-user or operator flows
once the corresponding app-surface endpoints exist.

## Contract-Debt Cleanup Priority

Before broadening Phase 2 to more admin resources or app-facing UI consumers,
the product surface should clear the most obvious contract debt that would
otherwise distort later decisions.

### Priority Cleanup Areas

- remove duplicate end-user authorization from app-facing supervision flows
- unify remaining `app_api` endpoints on `MethodResponse`
- finish the already-approved `llm_providers`, `workspace_policies`, and
  `audit_entries` surfaces on top of their resolved contracts

### Why This Is Higher Priority Than More Breadth

These debts are not cosmetic.

- duplicate supervision authorization makes it unclear whether the product
  surface or downstream services are the real policy source
- mixed response shapes make future SSR UI and acceptance helpers consume an
  unstable API
- the provider/workspace/audit resources must land on top of the approved
  surface contracts before implementation breadth continues

The approved implementation order is therefore:

1. stabilize the contracts
2. continue the rest of Phase 2 breadth
3. only then move on to SSR UI

## UI Design Extraction

The detailed Phase 3 UI design has been extracted into:

- `docs/plans/2026-04-13-ssr-ui-and-guides-design.md`

That document now owns:

- workbench information architecture
- admin console information architecture
- guide-driven onboarding UX
- UI-specific verification criteria
- the project-level scope-first route/controller rule as it applies to HTML

This document remains the source of truth for the non-UI architecture and the
product/API constraints that the UI must build on.
