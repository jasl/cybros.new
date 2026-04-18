# CoreMatrix Packages, Conversation Surfaces, and Capabilities Design

## Context

The current codebase has two different architectural problems at the same time.

First, the extension seams are split by historical implementation shape rather than by stable product concepts:

- `embedded_agents` is a tiny keyed invoke registry at `core_matrix/app/services/embedded_agents/invoke.rb:1-58`
- `runtime_features` is another keyed invoke registry plus backend selection at `core_matrix/app/services/runtime_features/invoke.rb:1-40`
- `embedded_features` is a third local execution path, and `title_bootstrap` already bridges across those seams by calling `EmbeddedAgents::Invoke` from inside `EmbeddedFeatures::TitleBootstrap::Invoke` at `core_matrix/app/services/embedded_features/title_bootstrap/invoke.rb:1-64`
- the current feature registry literally stores both `orchestrator_class` and `embedded_executor_class`, which is a strong signal that the system wants one capability contract with multiple backends, not separate architectural categories; see `core_matrix/app/services/runtime_features/registry.rb:1-38`

Second, the host ingress model is still shaped around channel history instead of a real external interaction contract:

- platform branching still lives in the App API controller at `core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings_controller.rb:3-246`
- poller dispatch still branches on platform at `core_matrix/app/jobs/channel_connectors/dispatch_active_pollers_job.rb:1-24`
- outbound delivery still branches on platform at `core_matrix/app/services/channel_deliveries/dispatch_conversation_output.rb:1-180`
- routes still expose Telegram- and Weixin-specific paths at `core_matrix/config/routes.rb:64-148`
- CLI calls still create ingress bindings by `platform` and then call Weixin-specific routes directly at `core_matrix_cli/lib/core_matrix_cli/core_matrix_api.rb:106-133`

The persistence model carries the same historical shape:

- `ChannelConnector` still hard-codes `telegram`, `telegram_webhook`, and `weixin` into the host model at `core_matrix/app/models/channel_connector.rb:1-104`
- `ChannelSession` is the current host mapping between an external boundary and a conversation, but it is still expressed as a platform-specific channel construct at `core_matrix/app/models/channel_session.rb:1-108`
- `IngressBinding` is already close to the right host resource, but it is still tied to `kind = "channel"` and to channel-owned associations at `core_matrix/app/models/ingress_binding.rb:1-99`

Bundled provisioning is also still host-owned by a large configuration hash instead of by explicit extension metadata; see `core_matrix/app/services/installations/register_bundled_agent_runtime.rb:5-260`.

The user has explicitly said this refactor may be breaking, does not need compatibility, and should optimize for long-term clarity, low runtime overhead, and pluginization.

## Design Goal

Replace the current three-family extension shape:

- `ingresses`
- `embedded_agents`
- `embedded_features` plus `runtime_features`

with a smaller, more orthogonal host kernel:

- `conversation_surfaces`
- `capabilities`

while keeping `plugin packages` as the only packaging and ownership unit.

This design assumes:

- `conversation` is a working-memory container, not a user record
- external users may be unregistered
- shared surfaces such as Telegram groups must work
- generic webhook-driven SaaS integrations should be first-class and should serve as the simplest architecture probe
- plugin loading must not make the hot path meaningfully heavier than the current code

## Evaluated Approaches

### 1. Directory Promotion Only

Move existing code out of `app/services/*` into better-named directories, but keep the current contract families and host data model.

Pros:

- smallest code delta
- lowest immediate migration risk
- minimal boot-time change

Cons:

- preserves the wrong abstraction split
- keeps `channel_*` history in the host
- still leaves extension authors learning implementation accidents first

### 2. Previous Three-Family Plugin Design

Keep `ingresses`, `embedded_agents`, and `embedded_features` as first-class host contract families, but package all concrete implementations as plugins.

Pros:

- already much better than today
- creates explicit plugin packages
- removes most controller/job branching

Cons:

- still bakes a dubious split into the public architecture
- keeps two nearly identical invocation systems alive
- makes future “external conversation surface” work fit under an IM-shaped name

### 3. Packages + Conversation Surfaces + Capabilities

Recommended.

Pros:

- matches the product concepts more directly
- reduces the host kernel to two orthogonal extension families
- gives a natural place for Telegram, Weixin, webhook SaaS, and embedded support/chat widgets
- collapses `embedded_agents`, `runtime_features`, and `embedded_features` into one capability system with selectable backends
- lets the host delete more `channel_*` history instead of rebranding it

Cons:

- more destructive than the previous plan
- requires rewriting the host schema, not just moving files
- forces the CLI and App API to adopt new resource names

## Core Principles

### Plugin Package Is The Only Packaging Unit

Every built-in extension ships as a plugin package under `app/plugins/*`.

A plugin package owns:

- dependency fragments
- migrations
- documentation
- one or more `conversation_surfaces`
- one or more `capabilities`

The host does not care whether a behavior came from a built-in package or a future external package. It only consumes compiled definitions.

### Conversation Surface Is The User Interaction Contract

A conversation surface is any package-contributed entry point that brings user interaction into CoreMatrix and binds it to conversation working memory.

It is not limited to IM platforms.

Examples:

- Telegram DM
- Telegram group
- Weixin polling account
- a generic SaaS webhook sender
- an embedded support widget inside another app

The common trait is not “chat platform”; it is “surface that sends external interaction into a CoreMatrix conversation.”

### Capability Is The Reusable Execution Contract

A capability is a host-visible unit of behavior that can be invoked with normalized target/input/options and that can choose from one or more execution backends.

This replaces:

- `embedded_agents`
- `runtime_features`
- `embedded_features`

The important distinction is no longer “agent vs feature,” but:

- what schema the capability accepts
- what target it operates on
- what authorization it needs
- what backend strategy it uses

### Conversation Is Working Memory, Not Identity

The host must keep these concepts separate:

- `subject`
  who is interacting
- `thread`
  where the interaction is happening
- `conversation`
  the working-memory container CoreMatrix uses for accumulation and execution

A conversation surface definition decides how a surface maps normalized subject/thread claims into a conversation scope.

### Host Owns Governance, Not Business Semantics

CoreMatrix continues to own:

- orchestration
- persistence of host entities
- public identifiers
- authorization
- auditing
- lifecycle
- runtime policy enforcement

Plugin packages contribute behavior, but they do not redefine host semantics.

Per the monorepo boundary in `AGENTS.md`, prompt-heavy and business-semantic logic should still trend toward the Agent or ExecutionRuntime side over time. The capability system must therefore support package-local embedded handlers now while remaining able to point at agent-owned or runtime-owned implementations later.

### Breaking Cleanup Is Required

This redesign is not a compatibility exercise.

If a legacy host abstraction exists only because the old architecture happened to create it, it should be deleted instead of preserved under a new name.

## Target Directory Shape

```text
core_matrix/app/
  extensions/
    loader.rb
    registry.rb
    manifest.rb
    manifest_validator.rb
    dependency_resolver.rb
    definition_index.rb
    conversation_surfaces/
      surface_definition.rb
      registry.rb
      envelope.rb
      scope_key.rb
      receive_event.rb
      create_or_bind_conversation.rb
      materialize_turn_entry.rb
      attach_materialized_attachments.rb
      endpoint_dispatcher.rb
      management_action_dispatcher.rb
      poller_dispatcher.rb
      delivery_dispatcher.rb
      middleware/
      preprocessors/
    capabilities/
      capability_definition.rb
      registry.rb
      invoke.rb
      result.rb
      backend_selector.rb
      runtime_exchange.rb

  controllers/
    conversation_surfaces/
      public_endpoints_controller.rb
    app_api/
      workspace_agents/
        surface_bindings_controller.rb
        surface_binding_actions_controller.rb

  jobs/
    conversation_surfaces/
      dispatch_active_pollers_job.rb

  models/
    surface_binding.rb
    conversation_scope_binding.rb
    surface_event_receipt.rb
    surface_delivery_attempt.rb

  plugins/
    core/
      webhook_inbox/
        plugin.rb
        gems.rb
        conversation_surfaces/
          webhook_inbox.rb
        public_endpoints/
          events.rb
        management_actions/
          configure.rb
          status.rb
          rotate_secret.rb
        deliveries/
          post_callback.rb
        docs/
      telegram/
        plugin.rb
        gems.rb
        conversation_surfaces/
          telegram.rb
        public_endpoints/
        pollers/
        deliveries/
        management_actions/
      weixin/
        plugin.rb
        gems.rb
        conversation_surfaces/
          weixin.rb
        pollers/
        deliveries/
        management_actions/
        lib/
        models/
        db/migrate/
      conversation_title/
        plugin.rb
        capabilities/
          conversation_title.rb
      conversation_supervision/
        plugin.rb
        capabilities/
          conversation_supervision.rb
      title_bootstrap/
        plugin.rb
        capabilities/
          title_bootstrap.rb
      prompt_compaction/
        plugin.rb
        capabilities/
          prompt_compaction.rb
```

`config/initializers/extensions.rb` loads and freezes package manifests during boot. `config/routes.rb` exposes only host-owned generic routes.

Because Rails/Zeitwerk would otherwise treat each `app/*` subtree as an independent autoload root, boot configuration must explicitly map:

- `app/extensions/**` to `Extensions::*`
- `app/plugins/**` to `Plugins::*`

If package-private helpers live under package-local `lib/`, boot configuration must also collapse `app/plugins/*/*/lib` so `app/plugins/core/weixin/lib/client.rb` resolves as `Plugins::Core::Weixin::Client` rather than `Plugins::Core::Weixin::Lib::Client`.

No request-time constant guessing is allowed.

## Package Manifest Model

Each package exposes a short `plugin.rb` declaration that registers a manifest with the host.

Each manifest contains:

- `id`
- `version`
- `dependencies`
- optional declarative `gems.rb`
- optional migration paths
- declared `conversation_surfaces`
- declared `capabilities`
- management schemas/actions
- optional public endpoint declarations
- optional documentation metadata

The loader validates manifests at boot and compiles them into immutable definitions. Runtime dispatch works only against compiled definitions.

Package-private support code that exists only to implement one package, such as API clients, normalizers, pollers, token stores, or QR-login helpers, should live inside that package rather than under the app-global `lib/`. For example, Weixin support code should move under `app/plugins/core/weixin/lib/*`, with the package-local `lib` directory collapsed so the constants still live directly under the Weixin package namespace. The app-global `lib/` should be reserved for genuinely shared cross-package or cross-project code.

## Conversation Surface Contract

A conversation surface definition describes:

- package key and surface key
- binding kind
- supported ingress transports for the current phase: `webhook` and/or `poller`
- supported outbound delivery styles for the current phase: `push_delivery` and/or `callback_delivery`
- request verification handler
- inbound normalization handler
- external subject resolver
- external thread resolver
- conversation scope policy
- activation policy for shared surfaces
- attachment materialization strategy
- outbound delivery adapter
- poller handler, if any
- public endpoints exposed through host-managed routes
- management actions and schemas

Future synchronous or streaming response transports are explicitly out of scope for the first implementation. The design should leave room for them, but the host should not claim support before the transport path exists.

### External Subjects And Shared Threads

The normalized surface envelope should carry explicit claims for:

- `subject_ref`
  The external actor sending the event.
- `thread_ref`
  The external shared surface where the event happened.
- `participant_role`
  Optional role hints such as member, admin, bot, guest, or system.
- `visibility`
  Direct, shared, topic-scoped, or another host-approved value.
- `activation_reason`
  Why the agent should respond in a shared surface, such as explicit mention, reply-to-agent, or configured auto-respond policy.

This is necessary for:

- Telegram groups where unfamiliar participants can ask the agent after the bot is added
- embedded support/chat surfaces where the end user is not a CoreMatrix account
- generic webhook senders that identify subjects and threads by external business IDs

### Conversation Scope Policy

The surface definition chooses how the host maps normalized claims to conversation working memory.

Supported strategies should include:

- `subject`
- `thread`
- `subject_in_thread`
- `explicit_session`

The host should derive one stable `scope_key` per normalized event and use that key for indexed lookup. This keeps the hot path to one deterministic key computation plus one indexed query/upsert rather than a pile of plugin-specific branching.

## Capability Contract

A capability definition describes:

- package key and capability key
- target schema
- input schema
- options schema
- optional policy schema
- authorization boundary
- backend strategy
- optional embedded handler
- optional runtime capability key
- optional agent reference
- result schema

This contract intentionally separates “what the capability is” from “how it executes.”

Examples:

- `conversation_title`
  a capability whose current implementation may remain package-local but whose long-term ownership could move toward the Agent layer
- `title_bootstrap`
  a capability with an embedded fallback and optional delegated path
- `prompt_compaction`
  a capability that may prefer runtime delegation but still expose an embedded fallback

## Unified Host Surface

### Public Surface Endpoints

Packages may declare restricted public endpoints, but they do not define arbitrary Rails routing.

The host mounts public endpoints under a fixed namespace, for example:

`/surfaces/:package_key/bindings/:public_surface_id/:endpoint_key`

The host dispatcher performs:

- binding lookup
- package resolution
- request verification
- idempotency enforcement
- audit/event wrapping
- error normalization

Only then does control pass to the package handler.

### Authenticated Management RPC

Packages do not add arbitrary App API controllers.

Instead, the host exposes generic binding management through a unified action endpoint, for example:

`POST /app_api/workspace_agents/:workspace_agent_id/surface_bindings/:surface_binding_id/actions/:action_key`

Binding creation stays host-owned, but creation payloads become package-aware:

- `package_id`
- `surface_key`
- initial settings payload
- optional initial management action input

Common actions include:

- `configure`
- `status`
- `rotate_secret`
- `test_connection`
- `start_pairing`
- `pairing_status`
- `disconnect`

This keeps App UI and CLI generic while still allowing package-specific workflows.

## Host Persistence Model

### Host-Owned Models

The first implementation should replace the current ingress/channel host schema with four generic models:

- `SurfaceBinding`
  The host-owned binding resource. This replaces `IngressBinding` plus the active connector concept.
- `ConversationScopeBinding`
  The mapping between a normalized surface scope and a conversation working-memory container. This replaces `ChannelSession`.
- `SurfaceEventReceipt`
  Generic idempotency and inbound audit data when the host needs to remember processed external events.
- `SurfaceDeliveryAttempt`
  Generic outbound delivery audit data if the host can still describe outbound attempts in a surface-neutral way.

The host continues to own:

- installations
- workspaces
- agents and agent definition versions
- execution runtimes
- conversations and turns
- binding resources
- public identifiers

### Plugin-Owned State

Plugin packages own:

- pairing state
- OAuth or QR-login state
- poll cursors
- external ticket/session state
- package-specific delivery metadata
- any package-specific records that stop being genuinely generic once the legacy channel shell is removed

If `SurfaceDeliveryAttempt` or `SurfaceEventReceipt` turns out not to be genuinely generic during implementation, they should also move into package-owned persistence instead of remaining in the host out of inertia.

## Migration Strategy

This redesign should use destructive migration rewriting rather than compatibility migrations.

Specifically:

- rewrite the current host ingress/channel migrations in place
- regenerate `db/schema.rb` from scratch
- keep plugin-owned migrations inside plugin packages

For `core_matrix`, the rebuild flow must follow the repo rule in `AGENTS.md`:

`rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset`

This is appropriate here because the user explicitly does not want compatibility preserved and because the old schema encodes the wrong host abstractions.

## Gem Dependency Model

Plugin packages may declare gem dependencies, but gem installation is not dynamic at runtime.

Rules:

- packages may ship declarative `gems.rb` fragments, but those fragments should register dependency metadata through a host helper DSL rather than calling Bundler's `gem` DSL directly
- the root `Gemfile` loads package fragments into a host-owned dependency registry, normalizes declarations, groups them by gem name, and emits one final Bundler declaration per resolved gem
- the app still has one `Gemfile.lock`
- package-owned dependencies default to `require: false`
- if two packages declare the same gem with identical normalized requirements and options, the host collapses the duplicate and records both owning packages for diagnostics
- if two packages declare the same gem with compatible source and loader options, the host merges the unique version requirement strings into one final Bundler declaration and leaves satisfiability to Bundler
- if two packages declare the same gem with conflicting source or non-version loader options, bundle setup fails with an explicit host error before Bundler resolution continues
- package fragments must stay data-oriented and deterministic; arbitrary imperative Gemfile logic inside package fragments is forbidden
- boot validation checks that required gems are present before activating definitions
- per-tenant or runtime gem installation is forbidden

This is one place where CoreMatrix should be stricter than a naive `eval_gemfile` design. A direct multi-fragment `eval_gemfile` setup would surface duplicate dependency warnings and make ownership harder to reason about. The host should own deduplication and conflict reporting so package-local dependency declarations stay readable without increasing bundle noise. To keep overhead low, the first implementation should not try to compute semver intersections across package fragments. It should only normalize declarations, merge unique version requirements for the same gem, and let Bundler decide whether the combined constraints are solvable.

Because `Gemfile` executes before Rails autoloading exists, the package gem DSL must live in a plain Ruby helper that `Gemfile` can `require_relative` directly. It should not depend on `app/extensions/*` code.

## Lifecycle Model

Packages have four lifecycle layers:

1. `discovered`
2. `loaded`
3. `enabled_for_host`
4. `active_for_installation_or_resource`

Activation units are:

- `SurfaceBinding` for conversation-surface behavior
- invocation target plus policy/runtime context for capability behavior

Initially, all discovered in-repo core packages are `enabled_for_host` by default after successful boot-time validation.

## Generic Webhook Package

The first implementation should include a core package such as `webhook_inbox`.

Why:

- it validates the new conversation-surface architecture without IM-specific assumptions
- it is easier to exercise from tests and local scripts than Telegram or Weixin
- it gives the host a normal SaaS-style webhook surface immediately

Recommended first-phase behavior:

- secret-authenticated inbound webhook endpoint
- canonical JSON payload contract containing external event id, subject, thread, message payload, attachments, and metadata
- asynchronous outbound delivery through a configured callback URL
- management actions for `configure`, `status`, and `rotate_secret`

This package should be treated as the architecture probe for the new surface kernel.

## Performance and Overhead Controls

The redesign should not make the hot path meaningfully heavier than today.

Rules:

- all package scanning and manifest compilation happen only at boot
- compiled registries are immutable after boot
- runtime dispatch is one registry lookup plus one handler call
- schema validation happens at package boundaries, not repeatedly through the full call chain
- conversation resolution is one deterministic `scope_key` derivation plus indexed lookup/upsert
- no request-time filesystem scanning or string-based constant guessing
- no platform branching in controllers, jobs, or dispatchers

This design should be lighter than the previous three-family plan because:

- one capability invoke path replaces the current overlapping `embedded_agents` and `runtime_features` systems
- `channel_*` host history is deleted rather than rewrapped
- a generic webhook package prevents the host kernel from overfitting to IM-specific shapes

## Legacy Terminology Boundary

The old architecture vocabulary:

- `ingress`
- `IngressBinding`
- `ChannelConnector`
- `ChannelSession`
- `ChannelPairingRequest`
- `ChannelInboundMessage`
- `ChannelDelivery`
- `embedded_agents`
- `embedded_features`
- `runtime_features`

should be treated as migration-only terminology.

After the refactor is complete:

- active code should use `conversation_surfaces`, `surface_bindings`, and `capabilities`
- active operator and contributor docs should use the new vocabulary
- CLI help and README examples should expose a `surface` command family rather than an `ingress` command family
- the old terms may survive only inside archived/historical material such as old plans, archived docs, or explicit migration commentary

## Refactor Mapping From Current Code

### Conversation Surfaces

Current:

- `app/services/ingress_api/*`
- `IngressBinding`
- `ChannelConnector`
- `ChannelSession`
- `ChannelInboundMessage`
- `ChannelDelivery`
- platform-specific routes, controllers, jobs, and dispatchers

Target:

- host conversation-surface kernel under `app/extensions/conversation_surfaces`
- generic host endpoints and management RPC
- `SurfaceBinding`, `ConversationScopeBinding`, `SurfaceEventReceipt`, and optionally `SurfaceDeliveryAttempt`
- concrete Telegram, Weixin, and webhook behavior packaged under `app/plugins/core/*`

### Capabilities

Current:

- `app/services/embedded_agents/*`
- `app/services/runtime_features/*`
- `app/services/embedded_features/*`

Target:

- unified host capability kernel under `app/extensions/capabilities`
- concrete built-in capabilities packaged under `app/plugins/core/*`
- current agent-like and feature-like behavior represented as capability definitions with backend strategies

### Bundled Provisioning

Current:

- large host configuration hash for bundled runtime and feature contracts

Target:

- provisioning composes from package definitions and capability metadata

## Documentation Deliverables

Implementation should add or refresh:

- `core_matrix/AGENTS.md`
- `core_matrix/docs/architecture/extensions.md`
- `core_matrix/docs/extensions/packages.md`
- `core_matrix/docs/extensions/conversation-surfaces.md`
- `core_matrix/docs/extensions/capabilities.md`
- `core_matrix/docs/extensions/migrations-and-dependencies.md`
- `core_matrix/docs/INTEGRATIONS.md`
- `core_matrix/docs/INSTALL.md`
- `core_matrix/docs/ADMIN-QUICK-START-GUIDE.md`
- `core_matrix_cli/README.md`

The root monorepo `AGENTS.md` should only point contributors to `core_matrix/AGENTS.md` for CoreMatrix-specific package and surface rules.

## Explicit Non-Goals

This redesign does not attempt to:

- preserve the old ingress/channel schema
- preserve old App API or CLI route names
- support runtime gem installation
- open arbitrary plugin pages or arbitrary plugin controllers
- claim synchronous or streaming response transport before the host implements it
- keep prompt-heavy business semantics in CoreMatrix forever if they belong in the Agent layer

## Success Criteria

The redesign is successful when:

- new external interaction work starts from a conversation-surface package, not from `app/services/ingress_api`
- new agent/feature work starts from a capability package, not from `embedded_agents` or `runtime_features`
- `conversation` remains a working-memory container, not a disguised user record
- host code no longer branches on Telegram/Weixin platform names in controllers, jobs, or dispatchers
- the generic webhook package works as the simplest first-class conversation surface
- plugin-specific data and gems are declared near the package that owns them
- `core_matrix_cli` remains a working consumer of generic host-managed surface RPC without gaining its own extension system
- active code, active docs, and CLI help no longer present the legacy ingress/channel/embedded/runtime vocabulary as the live architecture
- boot-time complexity increases, but hot-path overhead stays flat or improves
