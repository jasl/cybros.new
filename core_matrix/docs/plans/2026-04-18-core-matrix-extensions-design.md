# CoreMatrix Extensions Architecture Design

**Date:** 2026-04-18

**Status:** Approved for implementation planning

## Goal

Refactor CoreMatrix so ingress integrations, embedded agents, and embedded features become first-class extension contracts under `core_matrix/app`, while concrete built-in implementations move into plugin packages that are easy to discover, reason about, and evolve into a future developer ecosystem.

## Context

CoreMatrix currently has three extension-like areas, but they are shaped as service clusters instead of a clear extension system:

- `app/services/ingress_api/*` contains ingress pipeline orchestration and platform-specific logic.
- `app/services/embedded_agents/*` contains built-in agent-like capabilities behind a hard-coded registry.
- `app/services/runtime_features/*` plus `app/services/embedded_features/*` split feature orchestration from built-in fallback execution.

That shape creates several long-term problems:

- Concrete extension implementations are hidden inside `app/services`.
- Host orchestration and plugin-specific behavior are mixed together.
- Platform branching is repeated in controllers, jobs, and dispatchers.
- Bundled capabilities are installed through large configuration hashes instead of discoverable definitions.
- Future contributors must learn internal CoreMatrix service layout before they can add a new ingress or built-in capability.

This redesign intentionally allows breaking changes. Compatibility with the current internal structure is not a goal. Long-term clarity, explicit contracts, and maintainability take priority.

## Confirmed Product Decisions

The following decisions were explicitly confirmed during design review:

- all concrete built-in extensions are packaged as plugins
- `Ingress`, `EmbeddedAgent`, and `EmbeddedFeature` remain host-owned contract categories
- plugins may ship migrations, but only through host-governed loading and naming rules
- plugins may declare gem dependencies, but dependency resolution remains build-time through a single application bundle
- App UI does not become an open-ended plugin page system; plugins contribute settings, pairing, status, and management actions through host-owned surfaces
- `core_matrix_cli` remains a host-owned consumer of public management RPC; it does not need its own plugin system in this phase
- compatibility with the current internal shape is not required
- breaking refactors are acceptable when they improve the long-term design

## Current-State Anchors

The design is anchored to the current CoreMatrix implementation and operator docs at these exact locations:

- hard-coded embedded agent registry: `core_matrix/app/services/embedded_agents/registry.rb:1-14`
- hard-coded runtime feature registry: `core_matrix/app/services/runtime_features/registry.rb:1-38`
- ingress management controller with platform branching and Weixin-specific actions: `core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings_controller.rb:3-245`
- active poller dispatch branching by platform: `core_matrix/app/jobs/channel_connectors/dispatch_active_pollers_job.rb:1-24`
- outbound delivery branching by platform: `core_matrix/app/services/channel_deliveries/dispatch_conversation_output.rb:1-180`
- bundled agent/runtime registration through a large configuration hash: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb:5-220`
- Telegram-specific ingress route plus Weixin-specific management routes: `core_matrix/config/routes.rb:68-150`
- plugin-specific gem currently still declared in the host bundle: `core_matrix/Gemfile:58-64`
- current operator workflows for Telegram and Weixin: `core_matrix/docs/INTEGRATIONS.md:1-145`
- current CLI API still creates ingress bindings by `platform` and calls Weixin-specific routes directly: `core_matrix_cli/lib/core_matrix_cli/core_matrix_api.rb:106-132`
- current CLI setup/status flows still branch by `telegram`, `telegram_webhook`, and `weixin`: `core_matrix_cli/lib/core_matrix_cli/use_cases/setup_telegram_polling.rb:1-18`, `core_matrix_cli/lib/core_matrix_cli/use_cases/setup_telegram_webhook.rb:1-20`, `core_matrix_cli/lib/core_matrix_cli/use_cases/setup_weixin.rb:1-47`, and `core_matrix_cli/lib/core_matrix_cli/use_cases/show_status.rb:3-83`
- monorepo architectural and verification constraints that this work must continue to obey: `AGENTS.md:20-45` and `AGENTS.md:72-81` and `AGENTS.md:120-132`

## Evaluated Approaches

### 1. Directory Promotion Only

Move current code from `app/services/*` into `app/ingresses`, `app/embedded_agents`, and `app/embedded_features` without changing the registration model.

Pros:

- Smallest migration cost
- Lowest short-term implementation risk
- Minimal boot/runtime overhead

Cons:

- Preserves hard-coded registries and platform branching
- Does not create a real plugin system
- Still makes future extension authors learn host internals first

### 2. In-Repo Plugin Packages With Host Contracts

Promote ingress, embedded-agent, and embedded-feature into explicit host contracts, and move concrete built-in implementations into plugin packages loaded through a registry and manifest system.

Pros:

- Best matches the desired future developer ecosystem
- Makes extension entry points obvious
- Keeps host governance centralized
- Can evolve into extracted gems or Rails engines later

Cons:

- Requires a new loader, definition model, and migration rules
- Introduces more boot-time structure than a simple move

### 3. Immediate Rails Engine / Gem Ecosystem

Require third-party-style plugin boundaries immediately using gems or Rails engines.

Pros:

- Highest theoretical openness from day one

Cons:

- Freezes unstable contracts too early
- Adds unnecessary complexity around bundling, load order, migrations, and routing
- Slows down core refactoring before the contracts are proven

## Recommendation

Choose approach 2.

It preserves the practicality of an in-repo refactor while forcing a stable host/plugin shape. It is close in spirit to GitLab's extension seams, but more productized and explicit: plugin packages are first-class, extension points are narrow, and host contracts are intentionally discoverable rather than implied by conventions or monkey patches.

## Architectural Principles

### Plugin Is the Packaging Unit

Every built-in extension is packaged as a plugin. A plugin may contribute zero or more ingresses, embedded agents, and embedded features.

The plugin package is the primary unit of ownership, dependency declaration, migrations, management actions, and documentation.

### Contract Type Is Separate From Packaging

`Ingress`, `EmbeddedAgent`, and `EmbeddedFeature` remain real architectural categories, but they are host-owned contracts, not top-level code ownership buckets for concrete implementations.

This means:

- `app/ingresses`, `app/embedded_agents`, and `app/embedded_features` contain host contracts, registries, dispatchers, and common policies.
- `app/plugins/core/telegram` contains the Telegram plugin package.
- Inside that plugin package, `ingresses/telegram.rb` contributes an ingress definition.

### Host Owns Governance

CoreMatrix continues to own:

- orchestration
- persistence of host entities
- public identifiers
- installation/workspace/resource scoping
- authorization and auditing
- host-visible lifecycle
- runtime policy boundaries

Plugins may contribute behavior, but they do not redefine host semantics.

### No Reverse Ownership

Plugins must not take control of CoreMatrix through monkey patches, `prepend`, implicit callbacks, or arbitrary controller injection. All extension behavior must flow through explicit registries and contract dispatchers.

### Breaking Cleanup Is A Goal

This redesign is not a compatibility bridge. Once host-owned extension contracts and plugin packages are in place, legacy structures should be deleted rather than preserved as permanent shims.

That includes eventual removal or collapse of:

- `app/services/embedded_agents/*`
- `app/services/runtime_features/*`
- `app/services/embedded_features/*`
- platform-specific ingress API controllers and route branches

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

  controllers/
    ingress_api/
      public_endpoints_controller.rb
    app_api/
      workspace_agents/
        ingress_binding_actions_controller.rb

  ingresses/
    ingress_definition.rb
    registry.rb
    endpoint_dispatcher.rb
    management_action_dispatcher.rb
    poller_dispatcher.rb
    delivery_dispatcher.rb
    envelope.rb
    inbound_pipeline/
    management/

  embedded_agents/
    embedded_agent_definition.rb
    registry.rb
    invoke.rb
    result.rb
    errors.rb
    authorization/

  embedded_features/
    embedded_feature_definition.rb
    registry.rb
    invoke.rb
    policy_resolver.rb
    capability_resolver.rb
    runtime_delegate.rb

  plugins/
    core/
      telegram/
        plugin.rb
        gems.rb
        ingresses/
          telegram.rb
        management_actions/
        public_endpoints/
        pollers/
        deliveries/
        models/
        db/migrate/
        docs/
      weixin/
        ...
      conversation_title/
        plugin.rb
        embedded_agents/
          conversation_title.rb
      conversation_supervision/
        plugin.rb
        embedded_agents/
          conversation_supervision.rb
      prompt_compaction/
        plugin.rb
        embedded_features/
          prompt_compaction.rb
```

`config/initializers/extensions.rb` loads and freezes plugin manifests during boot. `config/routes.rb` exposes only host-owned generic routes, never plugin-authored routing DSL.

Because Rails/Zeitwerk would otherwise treat each new `app/*` subtree as an independent autoload root, boot configuration must register explicit namespace mappings for `Extensions`, `Ingresses`, `EmbeddedAgents`, `EmbeddedFeatures`, and `Plugins`. The directory promotion is not safe unless those namespaces are bootstrapped deliberately.

## Plugin Package Model

Each plugin package exposes a short declaration file, for example `plugin.rb`, which registers a plugin manifest with the host.

Each manifest contains:

- stable plugin `id`
- plugin `version`
- short `display_name`
- host contract compatibility requirements
- optional dependency declarations
- declared extension contributions
- management schemas and actions
- optional public endpoint declarations
- optional migration paths
- optional documentation metadata

The loader validates manifests at boot and compiles them into immutable definitions. Runtime dispatch works only against compiled definitions.

## Boot And Load Order

Plugin discovery is deterministic and host-controlled.

Rules:

- plugin entrypoints are discovered from `app/plugins/**/plugin.rb`
- discovery order is lexical and deterministic
- `config/initializers/extensions.rb` loads manifests during application boot
- Zeitwerk namespace roots are explicitly configured so constants resolve from the new `app/extensions`, `app/ingresses`, `app/embedded_agents`, `app/embedded_features`, and `app/plugins` directories without leaking into unintended top-level constants
- the loader validates manifests before any registry is published
- compiled definition registries are frozen after boot
- missing gem dependencies or invalid manifests fail boot loudly instead of degrading silently

This keeps all dynamic behavior at boot time and prevents request-time file scanning or constant guessing.

## Extension Definitions

### IngressDefinition

An ingress definition describes:

- plugin key and ingress key
- binding kind
- supported transport styles (`webhook`, `poller`, or both)
- request verification handler
- inbound normalization handler
- attachment materialization strategy
- delivery adapter
- poller handler, if any
- public endpoints exposed through host-managed routes
- management actions and schemas

### EmbeddedAgentDefinition

An embedded agent definition describes:

- plugin key and agent key
- target schema
- input schema
- options schema
- authorization boundary
- invoke handler
- result schema

### EmbeddedFeatureDefinition

An embedded feature definition describes:

- plugin key and feature key
- policy schema
- capability key
- execution modes supported by the host
- embedded executor handler
- runtime delegation behavior
- result schema

## Unified Host Surface

### Public Ingress Endpoints

Plugins may declare restricted public endpoints, but they do not define arbitrary Rails routing. The host mounts all public ingress endpoints under a fixed namespace, for example:

`/ingress/:plugin_key/bindings/:public_ingress_id/:endpoint_key`

The host dispatcher performs:

- ingress binding lookup
- plugin resolution
- request authentication/verification dispatch
- idempotency enforcement
- audit/event wrapping
- error normalization

Only then does control pass to the plugin endpoint handler.

### Authenticated Management RPC

Plugins do not add arbitrary App API controllers. Instead, they declare `management_actions` that the host exposes through a unified authenticated RPC layer for App UI, CLI, and future automation clients.

The host exposes ingress binding management through a generic action endpoint, for example:

`POST /app_api/workspace_agents/:workspace_agent_id/ingress_bindings/:ingress_binding_id/actions/:action_key`

Binding creation stays host-owned, but creation payloads become plugin-aware:

- `plugin_id`
- `ingress_key`
- initial settings/config payload
- optional initial management action input

For ingress plugins, common actions include:

- `configure`
- `status`
- `start_pairing`
- `pairing_status`
- `confirm_pairing`
- `disconnect`
- `rotate_secret`
- `test_connection`

Each action declares:

- `action_key`
- `input_schema`
- `result_schema`
- `authorization_policy`
- `idempotency_policy`
- `side_effect_level`

This keeps the host surface uniform while still allowing plugin-specific workflows such as QR login, webhook secret rotation, or token validation.

Existing nested ingress management resources such as pairing/session helpers should be collapsed into host-managed action semantics unless a truly generic resource abstraction survives the refactor.

## Data Boundaries

### Host-Owned State

CoreMatrix host models continue to own:

- installations
- workspaces
- agents and agent definition versions
- execution runtimes
- conversations and turns
- ingress bindings as host binding resources
- generic channel/session/delivery relationships when still justified as host abstractions

### Plugin-Owned State

Plugins may store state in:

- host-approved generic extension storage
- plugin-specific tables with plugin-prefixed names

Plugin tables are required for many ingress cases such as:

- OAuth or QR-login state
- external ticket/session mapping
- platform-specific cursors
- platform-specific delivery metadata
- pairing state that is not truly generic

Plugins may reference host entities, but they may not redefine host business semantics.

The initial implementation should keep `IngressBinding` as the host-owned binding resource and should only retain `ChannelConnector`, `ChannelSession`, `ChannelInboundMessage`, and `ChannelDelivery` as host models when their semantics remain genuinely generic after the plugin split. If a structure is mostly platform-owned after extraction, it should move into plugin-owned persistence instead of staying in the host out of inertia.

## Migration Rules

Plugins may ship migrations, but only through host-controlled loading.

Rules:

- each plugin declares its migration path
- host migration loading composes plugin migrations into the application migration flow
- plugin migrations create or modify only plugin-owned tables and indexes by default
- plugin migrations must use plugin-prefixed table/index/document/event names
- plugin migrations must not silently change host core semantics
- any required host schema evolution must be promoted into explicit host-owned migrations

## Gem Dependency Model

Plugins may declare gem dependencies, but gem installation is not dynamic at runtime.

Rules:

- plugin packages can ship `gems.rb` or equivalent bundle fragments
- the root `Gemfile` evaluates plugin dependency fragments into one bundle
- there is still one `Gemfile.lock` for the application
- plugin-owned dependencies should default to `require: false`
- loader validation checks that required gems are present and loadable before activating definitions
- per-tenant or runtime gem installation is forbidden

Cross-plugin infrastructure gems stay in the host bundle. Capability-specific gems move into plugin dependency fragments.

## Lifecycle Model

Plugins have four lifecycle layers:

1. `discovered`
2. `loaded`
3. `enabled_for_host`
4. `active_for_installation_or_resource`

That separation prevents bundle presence from implying tenant availability and prevents plugin loading from implying that a given ingress binding or workspace mount is active.

Initial implementation note:

- all discovered in-repo core plugins are `enabled_for_host` by default after successful boot-time validation
- the explicit `enabled_for_host` lifecycle stage still remains part of the contract so host-level plugin policy can be added later without reshaping the system

For this redesign the activation units are:

- ingress plugin behavior: an `IngressBinding`
- embedded agent behavior: an agent definition and its workspace mount or invocation target
- embedded feature behavior: workspace policy plus runtime/agent capability

## Performance and Complexity Controls

To keep the system maintainable:

- all file scanning and manifest compilation happen only at boot
- runtime dispatch is pure registry lookup
- definition registries are immutable after load
- plugin requests and actions must pass schema validation
- host authorization, auditing, idempotency, and public-id policies remain centralized
- platform-specific branching must not reappear in controllers, jobs, or dispatchers
- plugins may not use monkey patching as their primary integration method

If a proposed extension requires arbitrary pages, arbitrary controllers, or host-core schema ownership changes to function, it should be reconsidered as a first-class CoreMatrix product module rather than forced through the plugin framework.

## Refactor Mapping From Current Code

### Ingress

Current:

- `app/services/ingress_api/*`
- hard-coded Telegram webhook controller
- platform branching inside management controller, poller job, and delivery dispatcher

Target:

- host pipeline and contracts move into `app/ingresses`
- host generic controllers move into `app/controllers/ingress_api/public_endpoints_controller.rb` and `app/controllers/app_api/workspace_agents/ingress_binding_actions_controller.rb`
- Telegram and Weixin become plugin packages under `app/plugins/core/*`
- legacy `telegram` and `telegram_webhook` platform split collapses into one Telegram plugin-backed ingress definition with transport mode selected by binding configuration and management actions
- host-managed endpoint and action dispatch replace platform `case` logic

### Embedded Agents

Current:

- `app/services/embedded_agents/*`
- hard-coded registry

Target:

- host agent contract and registry move into `app/embedded_agents`
- concrete built-in agents become plugin packages
- legacy `app/services/embedded_agents/*` should be deleted or reduced to temporary transition shims during implementation only

### Embedded Features

Current:

- `app/services/runtime_features/*`
- `app/services/embedded_features/*`
- split registry model between runtime and embedded behavior

Target:

- unified host feature system under `app/embedded_features`
- concrete built-in features become plugin packages
- runtime delegation becomes a feature behavior, not a separate architecture silo
- legacy `app/services/runtime_features/*` and `app/services/embedded_features/*` should not survive as permanent ownership centers

### Bundled Agent Provisioning

Current:

- installation bootstrap uses large configuration hashes to describe a bundled agent runtime

Target:

- provisioning resolves plugin definitions and composes definition packages from explicit plugin metadata

## Documentation Deliverables

Implementation should add:

- `core_matrix/AGENTS.md`
- `core_matrix/docs/architecture/extensions.md`
- `core_matrix/docs/extensions/authoring.md`
- `core_matrix/docs/extensions/ingress.md`
- `core_matrix/docs/extensions/embedded-agents.md`
- `core_matrix/docs/extensions/embedded-features.md`
- `core_matrix/docs/extensions/migrations-and-dependencies.md`
- refreshed `core_matrix_cli/README.md` so the CLI continues to document itself as a consumer of host-owned ingress RPC
- refreshed operator-facing docs such as `core_matrix/docs/INTEGRATIONS.md`, `core_matrix/docs/INSTALL.md`, and `core_matrix/docs/ADMIN-QUICK-START-GUIDE.md` so `cmctl` guidance matches the new host-owned RPC surfaces

The root monorepo `AGENTS.md` should only point contributors to `core_matrix/AGENTS.md` for CoreMatrix-specific extension rules.

## Verification And Acceptance

Because this refactor touches ingress, conversation bootstrap, turn entry, and bundled capability provisioning, it must be treated as verification-critical work under `AGENTS.md:32-40`.

Acceptance requires:

- focused contract and regression tests for the new extension framework and migrated plugins
- full `core_matrix` verification commands from `AGENTS.md:72-81`
- the required active verification suite from `AGENTS.md:120-126`
- inspection of produced verification artifacts and relevant database state for business-shape correctness
- confirmation that the targeted host files no longer branch on Telegram/Weixin platform names or hard-coded embedded agent/feature registries

## Explicit Non-Goals

This redesign does not attempt to:

- support runtime gem installation
- preserve the current internal directory layout
- make plugins free to inject arbitrary controllers or pages
- freeze a third-party external gem/engine contract immediately
- preserve every existing generic channel model unchanged if the plugin split shows some of them should become plugin-owned

## Success Criteria

The redesign is successful when:

- new ingress, embedded-agent, and embedded-feature work starts from plugin packages and definitions, not `app/services`
- host code no longer branches on Telegram/Weixin platform names in controllers/jobs/dispatchers
- built-in extensions are discoverable through plugin manifests
- public RPC/UI management is generated from host-governed schemas and actions
- plugin-specific data and gems are declared near the plugin package that owns them
- `core_matrix_cli` remains a working consumer of the host-managed ingress RPC surface without needing its own extension system
- future extraction of a plugin into a gem or engine is evolutionary rather than a second full rewrite
