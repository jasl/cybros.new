# Agent Definition Version And Pairing Session V2 Design

## Goal

Define a cleaner long-term platform model for Core Matrix that supports:

- bundled `Fenix + Nexus`
- `Fenix + BYO runtime` on an independent workstation
- future `BYO agent` growth without locking the platform into today’s
  incidental object boundaries

The design must:

- keep `CoreMatrix` as the orchestration layer and agent kernel
- keep `ExecutionRuntime` as a pairing-based harness provider, not a managed
  container template
- make agent behavior configurable through a structured, schema-driven runtime
  config
- keep local agent-program-static definitions code-owned
- reduce conceptual overlap between definition state, live connection state,
  and frozen turn state
- optimize for a clean base schema rather than compatibility with early-stage
  development data

## Destructive Assumptions

This revision explicitly assumes:

- the project is still early
- development data may be discarded
- old migrations may be rewritten in place
- internal contract compatibility with the current unfinished substrate is not a
  goal

This is not an incremental cleanup plan. It is a target architecture for a
better base schema and cleaner platform semantics.

## Why The Previous Direction Was Not Pure Enough

The prior design improved the current system, but it still inherited too much
from the existing model split.

### 1. `AgentSnapshot` is overloaded

Today `AgentSnapshot` tries to behave like all of the following at once:

- an agent definition version
- a capability contract
- a release identity
- a connection-adjacent runtime target
- a recovery comparison object

That is too much responsibility for one aggregate.

### 2. `AgentEnrollment` is semantically wrong

The current runtime and agent registration flow already behaves like a bounded
multi-step pairing session, but the aggregate name and docs still frame it as
one-time enrollment.

That mismatch makes the model harder to understand than the behavior actually
is.

### 3. Canonical config was still too detached from the definition version

The previous approach introduced a cleaner canonical config concept, but it did
not go far enough in making the agent definition itself a first-class,
versioned object.

The cleaner move is:

- version the agent definition properly
- keep mutable config state separate from that definition
- freeze only the effective execution projection on turns

### 4. Runtime history should be symmetric with agent definition history

Runtime capability history should exist, but as a lightweight version surface,
not as another all-purpose snapshot blob.

## Reference Findings

Anthropic’s Managed Agents documentation remains useful as a structural
reference, not as something to copy literally.

- Claude treats the agent as a reusable, versioned configuration resource with
  first-class fields such as `model`, `system`, `tools`, `skills`,
  `callable_agents`, `description`, and `metadata`. [Agent setup](https://platform.claude.com/docs/en/managed-agents/agent-setup)
- Claude emphasizes the lifecycle of defining the agent, pairing it with an
  environment, running a session, and inspecting events. [Quickstart](https://platform.claude.com/docs/en/managed-agents/quickstart)
- Claude also emphasizes prototyping before code and surfacing equivalent API
  requests. [Onboarding](https://platform.claude.com/docs/en/managed-agents/onboarding)

Core Matrix should align with the useful shape:

- definition
- environment
- execution session
- evented runtime flow

But it should preserve its own deliberate differences:

- multi-provider model catalog and role selectors
- pairing-based execution runtimes
- long-lived conversation/workspace model
- append-only turn freezing and mailbox-first control delivery

### Claude Concept Mapping

The closest current Core Matrix mapping to Claude Managed Agents is:

- Claude `Agent` -> `Agent` plus immutable `AgentDefinitionVersion`
- Claude `Environment` -> logical `ExecutionRuntime` plus append-only
  `ExecutionRuntimeVersion`
- Claude `Session` -> `Conversation` plus turn/workflow execution state
- Claude setup credential flow -> `PairingSession`

`Workspace` is intentionally not the same concept as Claude `Environment`.

At the platform-model layer, `Workspace` is a user/work-context aggregate that
owns:

- user and binding scope
- conversation ownership
- canonical variables
- a default runtime preference

By contrast, the thing that actually carries environment-like execution
identity is `ExecutionRuntimeVersion`, because that is where runtime-defining
content lives:

- capability payload
- tool catalog
- reflected host metadata
- runtime fingerprint

`ExecutionRuntime` is the logical wrapper around that environment-like version
surface:

- owner and visibility
- lifecycle
- current active version
- current active connection

So the correct statement is:

- platform layer: `Environment` maps to `ExecutionRuntime` /
  `ExecutionRuntimeVersion`
- product layer: `Workspace` is a natural place to select, remember, or
  default an environment for the user

This distinction matters because a future managed-workspace feature may own or
provision environments, but that still would not make `Workspace` itself the
environment resource.

## Design Principles

### 1. Separate identity, definition, connection, and frozen execution

The platform should model these as distinct concerns:

- logical identity
- versioned definition
- live connection
- frozen turn-time execution reference

Any aggregate that mixes more than one of those concerns should be treated as a
smell.

### 2. Treat pairing as pairing

If a token drives a bounded multi-step runtime+agent setup flow, it should be a
pairing-session concept, not a one-shot enrollment concept.

### 3. Normalize local authoring into kernel-owned definition versions

Local files remain the authoring source of truth, but Core Matrix should store
the normalized definition version it actually reasons about.

### 4. Keep mutable config state separate from immutable definition versions

Versioned definitions should not be rewritten because a user or workspace
changes override state.

### 5. Freeze the smallest sufficient execution contract

Turns should freeze:

- exact definition version reference
- exact runtime version reference when present
- exact effective config result
- exact resolved selector result

They should not freeze every source blob that led to that result.

### 6. Prefer schema purity over migration compatibility

Early-phase schema cleanup is cheaper than carrying awkward names and mixed
responsibilities for years.

### 7. Keep external boundaries on `public_id` or credentials only

Core Matrix should continue to respect the repository-wide identifier policy:

- external or agent-facing APIs expose `public_id`, not bigint ids
- pairing tokens and connection credentials are credentials, not identifiers
- version resources that may surface in diagnostics or future APIs should carry
  `public_id` from the start

### 8. Prefer loose publishing and strict turn identity

Core Matrix should not adopt a Claude-style, resource-lifecycle-heavy version
discipline for agent or runtime publishing.

The intended policy is:

- new `AgentDefinitionVersion` rows may become active without blocking future
  turns
- new `ExecutionRuntimeVersion` rows may become active without blocking future
  turns
- unfinished turns keep their frozen execution identity
- the kernel must not silently drift an unfinished turn onto an incompatible new
  definition or runtime version
- compatible replacement versions may resume in place or resume with turn
  rebinding
- incompatible drift escalates to explicit recovery rather than silent
  continuation

This is the platform expression of the product choice:

- publishing is intentionally loose
- in-flight execution identity is intentionally strict

## Target Platform Model

### `Agent`

`Agent` remains the logical identity of an agent inside one installation.

Its responsibilities become intentionally small:

- stable logical identity
- visibility and ownership
- lifecycle
- optional runtime preference through `default_execution_runtime_id`
- pointer to the currently active `AgentDefinitionVersion`

`Agent.default_execution_runtime_id` remains an operational preference only. It
is not part of the immutable agent definition.

### `AgentDefinitionVersion`

This replaces the current "definition" role of `AgentSnapshot`.

It is the canonical immutable agent definition version that Core Matrix can
reason about.

It should carry normalized, kernel-meaningful projections such as:

- `installation_id`
- `public_id`
- `definition_fingerprint`
- `program_manifest_fingerprint`
- `protocol_version`
- `sdk_version`
- `prompt_pack_ref`
- `prompt_pack_fingerprint`
- `protocol_methods_document`
- `tool_contract_document`
- `profile_policy_document`
- `canonical_config_schema_document`
- `conversation_override_schema_document`
- `default_canonical_config_document`
- `reflected_surface_document`

This is the object that should feel conceptually closest to Claude’s versioned
agent definition, while still allowing local code-owned authoring.

### `AgentConfigState`

This is the mutable runtime config state for one logical `Agent`.

V1 of this model should keep exactly one config state row per `Agent`.
Workspace-scoped or user-scoped overlays can come later on top of the same
semantics if needed.

It should carry:

- `installation_id`
- `agent_id`
- `public_id`
- `base_agent_definition_version_id`
- `version`
- `override_document`
- `effective_document`
- `content_fingerprint`
- `reconciliation_state`
- `updated_at`

Its purpose is:

- hold mutable override state
- validate against the active definition version’s schema
- produce the effective runtime config used for future turns

### `AgentConnection`

`AgentConnection` remains the live control-plane identity.

It should reference:

- the logical `Agent`
- the active `AgentDefinitionVersion` it is serving

It should not itself become the versioned definition object.

When a new definition version becomes active, a new agent connection may become
active and the older one becomes stale, exactly as today’s rotation contract
already does in spirit.

### `PairingSession`

This replaces the current `AgentEnrollment`.

It is a bounded pairing credential for one logical agent and installation.

It should carry:

- `installation_id`
- `agent_id`
- `public_id`
- `token_digest`
- `issued_at`
- `expires_at`
- `last_used_at`
- `runtime_registered_at`
- `agent_registered_at`
- `closed_at`
- `revoked_at`

It authorizes a bounded sequence of:

- runtime registration or refresh
- agent registration or refresh
- retries until expiry or explicit closure

This name matches the actual workflow and removes the current one-time token
semantic mismatch.

### `ExecutionRuntime`

`ExecutionRuntime` remains the logical harness host identity.

It should stay focused on:

- owner/visibility/lifecycle
- runtime kind
- current active connection
- current active version
- optional use as an agent’s default runtime preference

It is not an agent definition object and it should not absorb agent config
meaning.

### `ExecutionRuntimeVersion`

This is the runtime analogue of `AgentDefinitionVersion`, but intentionally
lighter.

It should be append-only and created only when logical runtime-defining content
changes.

It should carry:

- `installation_id`
- `execution_runtime_id`
- `public_id`
- `version`
- `content_fingerprint`
- `execution_runtime_fingerprint`
- `kind`
- `protocol_version`
- `sdk_version`
- `capability_payload_document`
- `tool_catalog_document`
- optional reflected host metadata document

### `ExecutionRuntimeConnection`

This remains the live execution-runtime-plane identity.

It should reference:

- the logical `ExecutionRuntime`
- the active `ExecutionRuntimeVersion` the runtime is currently serving

### `Turn`

`Turn` becomes the frozen execution reference point for agent and runtime
versioning.

It should freeze:

- `agent_definition_version_id`
- `agent_config_version`
- `agent_config_content_fingerprint`
- `execution_runtime_id` optional
- `execution_runtime_version_id` optional
- `resolved_config_snapshot`
- `resolved_model_selection_snapshot`

It should not depend on a mixed-purpose `AgentSnapshot` aggregate.

### `ExecutionCapabilitySnapshot`

This can remain as a deduplicated frozen execution artifact, but its role
should be narrow:

- turn-level dedupe of visible tool surface and subagent execution facts

It should not be treated as the primary versioned definition object.

## Old To New Mapping

The intended conceptual replacement is:

- `AgentEnrollment` -> `PairingSession`
- `AgentSnapshot` -> `AgentDefinitionVersion`
- mutable canonical config row -> `AgentConfigState`
- current runtime capability state -> `ExecutionRuntimeVersion` plus the mutable
  `ExecutionRuntime` aggregate

This mapping is intentionally destructive. The platform should stop carrying
the old names once the schema is rewritten.

## Local Authoring And Kernel Normalization

### Local agent project remains the authoring source

`agents/fenix` should continue to own authoring-time files such as:

- prompt files and prompt assembly implementation
- profile labels and descriptions
- tool implementation declarations
- config schema
- default runtime config
- reflected/static metadata

### Core Matrix stores the normalized definition version

Core Matrix should not store the entire local project, but it should store the
normalized versioned definition it depends on.

The local runtime or agent registration payload should therefore be treated as a
definition package that can be normalized into an `AgentDefinitionVersion`.

That package should include, directly or by reference:

- `program_manifest_fingerprint`
- `prompt_pack_ref`
- `prompt_pack_fingerprint`
- `protocol_version`
- `sdk_version`
- protocol methods
- tool contract
- profile policy
- canonical config schema
- default canonical config
- reflected surface

Core Matrix may reject malformed or unsupported definition packages at
registration time.

## Agent Config Model

### What belongs in the immutable definition version

The following belong in `AgentDefinitionVersion`:

- the canonical config schema
- the conversation override schema
- the default canonical config
- the definition of role slots and fallback edges
- kernel-visible profile policy
- reflected read-only metadata

### What belongs in mutable config state

The following belong in `AgentConfigState`:

- operator- or system-applied override values
- the current reconciled effective runtime config
- config reconciliation status
- optimistic-locking version

### Canonical config shape

The exact schema may evolve, but it should stay intentionally structured and
kernel-readable.

Suggested runtime-effective shape:

```json
{
  "interactive": {
    "default_profile_key": "main"
  },
  "role_slots": {
    "main": {
      "selector": "role:main",
      "fallback_role_slot": null
    },
    "summary": {
      "selector": "role:summary",
      "fallback_role_slot": "main"
    }
  },
  "profile_runtime_overrides": {
    "main": {
      "role_slot": "main"
    },
    "researcher": {
      "role_slot": "main"
    }
  },
  "subagents": {
    "enabled": true,
    "allow_nested": true,
    "max_depth": 3
  },
  "tool_policy_overlays": [],
  "behavior": {}
}
```

### Reserved conventions

- `main` is the canonical fallback role slot.
- `selector` may point at either:
  - a role selector such as `role:main`
  - an explicit provider/model selector
- `fallback_role_slot` expresses kernel-visible fallback structure.
- profile display text stays in the reflected surface.
- profile policy that affects runtime behavior stays in the normalized
  definition version.

### JSON Schema subset

V1 should support a constrained JSON Schema subset for canonical config.

Supported:

- `type`
- `enum`
- `const`
- `default`
- `title`
- `description`
- `properties`
- `required`
- `additionalProperties`
- `items`
- `$defs`
- local `$ref`
- narrow `oneOf` usage for simple controlled choices

Deferred:

- recursive schemas
- `patternProperties`
- arbitrary `if/then/else`
- deep polymorphic unions that require custom UI logic

### Config reconciliation

When a new `AgentDefinitionVersion` becomes active:

- `AgentConfigState` revalidates its override document against the new schema
- if valid, it recomputes the effective document and advances normally
- if invalid, it preserves the override document but moves into
  `reconciliation_required`
- frozen old turns continue using their pinned config result
- new turns must not start against an invalid unreconciled config state

This is stricter than runtime diagnostics because silent config resets would be
harder to debug than an explicit reconciliation failure.

### Conversation override layer

Conversation-scoped override input remains useful and should stay explicit.

- `Conversation.override_payload` remains the ephemeral per-conversation layer
- that payload must validate against
  `AgentDefinitionVersion.conversation_override_schema_document`
- if no conversation override schema is published, conversation overrides are
  rejected for that definition version
- turn-time effective config resolution becomes:
  - definition default config
  - reconciled `AgentConfigState.effective_document`
  - validated conversation override payload

This keeps mutable operator state and ephemeral conversation-specific state
separate while still producing one frozen turn-time effective config result.

### Future overlays

Workspace-scoped and user-scoped config overlays are intentionally out of scope
for this base cleanup.

The first clean step is:

- one immutable `AgentDefinitionVersion`
- one mutable `AgentConfigState` per logical agent

Later overlay systems can be added on top if product needs them.

## Pairing Flow

The pairing flow should be expressed in terms of `PairingSession`.

### Step 1: issue pairing session

Core Matrix issues a pairing token for one logical agent.

### Step 2: runtime registers or refreshes

The runtime uses the pairing session token to:

- reconcile or create the logical `ExecutionRuntime`
- create or reuse the current `ExecutionRuntimeVersion`
- create the active `ExecutionRuntimeConnection`
- optionally set or refresh `Agent.default_execution_runtime_id`
  as the agent’s runtime preference

### Step 3: agent registers or refreshes

The agent uses the same pairing session token to:

- reconcile or create the current `AgentDefinitionVersion`
- reconcile `AgentConfigState` against that definition
- create the active `AgentConnection`

### Step 4: pairing session closes or expires

The pairing session remains valid until:

- explicit closure
- revocation
- expiry

This matches the actual multi-step workflow instead of pretending it is one
request.

## Runtime Versioning

Runtime versioning should be intentionally lightweight.

It should also remain operationally permissive:

- publishing a new runtime version is allowed
- selecting a new runtime version for future turns is allowed
- paused or active turns remain pinned to their frozen runtime version identity
  until recovery logic proves a compatible continuation path
- runtime version publication must not imply forced migration of in-flight work

### What creates a new runtime version

Create a new `ExecutionRuntimeVersion` only when runtime-defining content
changes:

- `execution_runtime_fingerprint`
- `kind`
- `protocol_version`
- `sdk_version`
- normalized capability payload
- normalized tool catalog

### What must not create a new runtime version

- heartbeat updates
- connection liveness changes
- transient endpoint metadata changes
- operational counters

### Storage model

Large JSON payloads should use deduplicated `JsonDocument` rows.

Runtime version rows should carry:

- scalar identity fields
- document refs
- content fingerprint

The mutable `ExecutionRuntime` row remains the fast read path for current
execution.

## Turn Freezing And Recovery

### Turn entry

When a turn starts, Core Matrix should resolve:

- the active `AgentConnection`
- the `AgentDefinitionVersion` that connection serves
- the current `AgentConfigState`
- the selected `ExecutionRuntime`
- the selected `ExecutionRuntimeVersion` when runtime is present

### What turns freeze

Turns should freeze:

- definition version ref
- config state version ref
- config content fingerprint
- runtime version ref when present
- exact resolved effective config
- exact resolved model selection

This means the platform is strict at turn execution boundaries, not at publish
boundaries.

New agent or runtime versions may become active for future turns without
invalidating the act of publishing itself.

### Recovery semantics

Paused-work recovery and rebind logic should compare frozen:

- agent definition version identity
- effective config fingerprint
- selected runtime version identity when relevant

The platform should no longer need a separate mixed-purpose `AgentSnapshot`
aggregate to answer those questions.

Version drift should therefore be interpreted as a recovery problem, not as a
publish-time prohibition:

- if the frozen execution identity still matches, execution may resume normally
- if a same-logical-agent replacement preserves the frozen capability contract
  and selector semantics, execution may resume with turn rebinding
- if drift is incompatible, execution moves to explicit manual recovery

## Tool Governance And Capability Composition

`RuntimeCapabilityContract` and tool governance should move from
`AgentSnapshot` to `AgentDefinitionVersion`.

That means:

- definition-level tool contract lives on the immutable definition version
- tool governance rows anchor to `AgentDefinitionVersion`
- visible tool surface is composed from:
  - definition-level tool contract
  - runtime-level tool contract
  - Core Matrix reserved tools
  - current config state and profile policy

This keeps definition-time capabilities and turn-time visible tool surfaces
separate and easier to reason about.

## Read Models

No separate `AgentProgramReflection` aggregate is needed in the base design.

The reflected read-only surface belongs on `AgentDefinitionVersion` as one of
its normalized documents.

Recommended reflected fields include:

- `display_name`
- `description`
- `intended_use`
- `example_prompts`
- `profile_summaries`
- `prompt_pack_ref`
- `program_manifest_fingerprint`

This keeps "what the agent is" close to the immutable versioned definition,
which is cleaner than introducing a second reflection aggregate.

## Storage And Performance Trade-Offs

### What should be append-only

- `AgentDefinitionVersion`
- `ExecutionRuntimeVersion`
- turn rows
- turn-owned execution artifacts

### What should be mutable

- `Agent`
- `AgentConfigState`
- `PairingSession`
- `AgentConnection`
- `ExecutionRuntime`
- `ExecutionRuntimeConnection`

### What should use deduplicated documents

- config schema
- default config
- effective config
- tool contracts
- profile policy
- reflected surfaces
- runtime capability payloads
- runtime tool catalogs

### What should not be duplicated per turn

- full definition package payloads
- full runtime capability blobs
- reflected metadata
- config schema sources

The rule is simple:

turns freeze exact execution results and references, not authoring-time source
packages.

## Model Orthogonality Review

After implementation and cleanup, the core model split should be understood as:

- `Agent`: stable logical identity and ownership surface
- `AgentDefinitionVersion`: immutable program definition and advertised
  capability contract
- `AgentConfigState`: mutable kernel-governed override state
- `AgentConnection`: live control-plane connectivity and health
- `PairingSession`: short-lived pairing workflow for registration
- `ExecutionRuntime`: stable execution-environment identity
- `ExecutionRuntimeVersion`: immutable runtime capability/version package
- `ExecutionRuntimeConnection`: live execution-runtime connectivity
- `Turn`: frozen execution identity selection for one unit of work
- `ExecutionContract`: frozen runtime-facing contract for one turn attempt
- `ExecutionCapabilitySnapshot`: deduplicated visible capability surface

This is mostly orthogonal. Two intentional convenience overlaps remain:

- `Agent.published_agent_definition_version` and
  `Agent.current_agent_definition_version`
- `ExecutionRuntime.published_execution_runtime_version` and
  `ExecutionRuntime.current_execution_runtime_version`

Those overlaps are acceptable for now because the product needs both:

- a durable published/default version pointer
- a live connected version pointer

The important rule is that turn entry and recovery must always freeze from the
live connection identity, not from a stale published pointer.

Two simplifications were already applied during implementation:

- `active_*_version` was renamed to `published_*_version` so the durable
  publication/default pointer is clearly distinguished from the live connected
  pointer returned by `current_*_version`
- the old `capability_snapshot_version` / `pinned_capability_snapshot_version`
  concept was removed because it no longer participated in execution identity
  or recovery decisions

## Post-Implementation Audit Follow-Ups

After the `published_*_version` cleanup, the main remaining issues are no
longer schema-level. They are vocabulary and contract-shaping cleanups.

### 1. Snapshot-era alias vocabulary still exists above the version layer

The platform model now uses:

- `definition_package`
- `version_package`
- `profile_policy`
- `canonical_config_schema`
- `default_canonical_config`

But several higher-level contracts still expose compatibility aliases such as:

- `tool_catalog`
- `profile_policy`
- `canonical_config_schema`
- `conversation_override_schema`
- `default_canonical_config`

These aliases still appear in:

- `Runtime::Manifest::PairingManifest` for Fenix
- `RuntimeCapabilityContract`
- acceptance helpers and scenarios

This is not a correctness problem, but it is the next major cleanup if the
goal is a truly uniform vocabulary.

### 2. Pairing sessions remain reusable until expiry or explicit revocation

`PairingSession` currently models a short-lived pairing workflow rather than a
single-use enrollment token. That means:

- repeated runtime registration is allowed while the session remains active
- repeated agent registration is allowed while the session remains active
- the session is not automatically closed when both sides have registered

This is consistent with the current product direction, but it is still a
deliberate policy choice, not an accident. If the product later wants stricter
pairing finalization, it should be implemented explicitly as a lifecycle
policy, not by overloading version registration behavior.

### 3. Verification discipline for `core_matrix`

`core_matrix` test commands already run with Rails worker parallelism. Do not
run two `bin/rails test ...` commands that target `core_matrix` at the same
time from the same checkout, because both commands will race to create the
same `core_matrix_test_*` databases and can produce misleading infrastructure
failures unrelated to application behavior.

## Migration Strategy

This design should be implemented by rewriting the early migration set into a
clean target schema rather than adding compatibility migrations on top of an
unfinished base.

Recommended approach:

- rewrite the early migrations that define agents, runtimes, pairing, and
  turns
- rename tables and models to the new target concepts
- regenerate the database from scratch

After editing migrations, regenerate the schema with:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

This should be treated as a normal and safe workflow for this early-stage
cleanup.

## Non-Goals

This design does not include:

- first-class `callable_agents`
- broader multi-agent ownership or workspace topology changes
- managed environment deployment
- connector/channel product surfaces
- workspace-scoped or user-scoped config overlays
- compatibility with current development data

`callable_agents` in particular should be treated as a separate experimental
branch later because it may affect deeper workspace, conversation, and
ownership structure.

## Success Criteria

This design is successful when:

- `AgentDefinitionVersion` cleanly replaces the definition role of
  `AgentSnapshot`
- `PairingSession` cleanly replaces the semantic role of `AgentEnrollment`
- mutable config state is separated from immutable definition versions
- runtime history exists without introducing a heavyweight new snapshot family
- turns freeze exact version references and effective execution results
- the base schema becomes easier to reason about than the current one
- future schema-driven config UI and future BYO agent support have a cleaner
  foundation
