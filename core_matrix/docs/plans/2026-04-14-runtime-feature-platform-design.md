# Runtime Feature Platform Design

## Goal

Introduce a shared `core_matrix` runtime feature platform for product-owned
features whose execution is:

- policy-driven at the workspace level
- runtime-capability-aware
- optionally runtime-backed
- optionally embedded-backed
- not part of the provider request-preparation critical path

This platform is the long-term home for features such as:

- `title_bootstrap`
- future metadata or post-processing features
- other best-effort or directly-invoked product features

It is **not** the primary execution model for prompt-budget enforcement or
Core Matrix-assisted prompt compaction. Those belong to the dedicated request
preparation subsystem described in:

- [2026-04-14-prompt-budget-guard-design.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-14-prompt-budget-guard-design.md)

## Design Principles

This branch allows intentional breaking changes. The architecture should prefer
clear long-term boundaries over compatibility with interim internal contracts.

Priority order:

1. explicit domain boundaries
2. product correctness and observability
3. coherent long-term contracts
4. implementation cost

## Scope

This platform establishes shared infrastructure for runtime-backed product
features across `core_matrix` and `agents/fenix`.

It includes:

1. schema-first feature-policy contracts under `workspace.config.features.*`
2. runtime feature capability contracts in manifests
3. a shared runtime-feature registry in `core_matrix`
4. direct runtime feature invocation over the control plane
5. shared runtime-vs-embedded orchestration
6. feature-owned lifecycle semantics such as live-resolved vs snapshot-frozen
7. schema publication for future UI consumers

It does **not** include:

- prompt-budget guarding
- provider request assembly
- authoritative dispatch-time token decisions
- workflow-backed prompt compaction
- agent-facing token-counting APIs

Those are request-preparation concerns, even when they reuse the same
`features.*` settings namespace.

## Current Baseline

Useful groundwork already exists:

- `workspace.config.features.*`
- `WorkspaceFeatures::Schema`
- `WorkspaceFeatures::Resolver`
- workspace policy show/update
- canonical config defaults in Fenix
- live-read title-bootstrap policy resolution

The current shape is still transitional because:

1. policy and capability are not modeled as separate contracts
2. runtime capability is still partly inferred from ad hoc surfaces
3. execution and fallback are still partially slice-local
4. the policy schema is hand-written instead of schema-first

## Core Problem

Features such as `title_bootstrap` are not ordinary tools. They have:

- policy
- capability
- execution strategy
- fallback semantics
- lifecycle rules
- feature-specific failure handling

Those concerns should be modeled explicitly. A shared platform avoids each
feature growing its own bespoke runtime probe, invocation path, and fallback
logic.

## Recommended Architecture

### 1. Separate Policy, Capability, And Execution

The platform should model three distinct concerns:

- `policy`
  - what the workspace wants
- `capability`
  - what the current runtime advertises
- `execution`
  - what `core_matrix` decides to invoke for this specific feature call

These should not share the same wire contract.

### 2. Keep `features.*` As The Shared Policy Namespace

The long-term workspace policy shape should remain structured:

```json
{
  "features": {
    "title_bootstrap": {
      "strategy": "embedded_only"
    },
    "prompt_compaction": {
      "strategy": "runtime_first"
    }
  }
}
```

The shared strategy enum should be:

- `disabled`
- `embedded_only`
- `runtime_first`
- `runtime_required`

Important boundary:

- the `features.*` namespace is shared across product-owned subsystems
- the runtime feature platform consumes `features.title_bootstrap`
- the request-preparation subsystem consumes `features.prompt_compaction`

Shared settings do not imply shared execution infrastructure.

### 3. Introduce A Feature Registry

`core_matrix` should own a registry for runtime-platform features.

Each entry should define:

- `feature_key`
- `policy_schema_class`
- `runtime_capability_key`
- `runtime_requirement`
- `policy_lifecycle`
- `capability_lifecycle`
- `execution_mode`
- `orchestrator_class`
- `embedded_executor_class`
- `runtime_failure_policy`
- `result_contract`

Example:

```ruby
RuntimeFeatures::Registry.register(
  key: "title_bootstrap",
  policy_schema: RuntimeFeaturePolicies::TitleBootstrapSchema,
  runtime_capability_key: "title_bootstrap",
  runtime_requirement: :optional,
  policy_lifecycle: :live_resolved,
  capability_lifecycle: :live_resolved,
  execution_mode: :direct,
  orchestrator: RuntimeFeatures::TitleBootstrap::Orchestrator,
  embedded_executor: EmbeddedFeatures::TitleBootstrap::Invoke
)
```

This registry should cover runtime-platform features only. It should not own
provider request-preparation orchestration.

### 4. Publish Policy Schemas As First-Class Artifacts

The policy layer should become schema-first.

Recommended direction:

- one Ruby-side schema definition per feature
- one bundled root schema for `workspace.config.features`
- machine-readable JSON Schema output
- optional UI metadata such as labels, descriptions, and control hints

The current hand-written validator in
[schema.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workspace_features/schema.rb)
is a transitional guard, not the desired final abstraction.

### 5. Use An Internal EasyTalk-Based Schema Wrapper

The `easy_talk` evaluation still points to the right policy-layer direction:

- nested schema composition
- root schema bundle
- extension metadata such as `x-ui`

Recommended adoption:

- expose a narrow product-owned wrapper namespace such as
  `RuntimeFeaturePolicies::*`
- keep `easy_talk` out of unrelated app code
- let the wrapper own JSON Schema publication and metadata conventions

### 6. Add A Dedicated Runtime Feature Contract

Fenix manifest should gain a top-level `feature_contract` for runtime-platform
features.

Each entry should include:

- `feature_key`
- `execution_mode`
- `lifecycle`
- `request_schema`
- `response_schema`
- `implementation_ref`

Example:

```json
{
  "feature_key": "title_bootstrap",
  "execution_mode": "direct",
  "lifecycle": "live",
  "request_schema": { "type": "object" },
  "response_schema": { "type": "object" },
  "implementation_ref": "fenix/title_bootstrap"
}
```

This contract is for direct runtime features. It is not the right home for
prompt-compaction workflow execution.

### 7. Keep Runtime Feature Execution Direct

The runtime feature platform should support direct control-plane execution for
its features.

Recommended transport:

- `execute_feature`

That path is appropriate for:

- best-effort metadata generation
- product-owned runtime helpers that do not reshape the main agent loop
- features whose execution does not need a dedicated workflow node

It is not appropriate for model-backed prompt compaction, because Core Matrix
assistance with compaction must be visible in workflow state.

### 8. Freeze Or Resolve Per Feature, Not Globally

Each runtime-platform feature declares its own lifecycle semantics.

Initial rule:

- `title_bootstrap`
  - policy: `live_resolved`
  - capability: `live_resolved`

The platform must support both:

- snapshot-backed access for future features that need it
- live-resolved access for features like `title_bootstrap`

The platform should not force one rule onto all features.

### 9. Standardize Orchestration And Fallback

Every runtime-platform invocation should go through one shared orchestration
path:

1. resolve effective policy
2. resolve effective capability
3. select runtime vs embedded vs skip
4. invoke the selected path
5. normalize result and failure semantics

The common result shape should include:

- `status`
  - `ok`
  - `skipped`
  - `failed`
- `source`
  - `runtime`
  - `embedded`
  - `none`
- `fallback_used`
- `value`
- `failure`

### 10. Standardize Failure Semantics

The platform should normalize a small set of runtime-feature failure codes,
such as:

- `feature_not_advertised`
- `feature_not_allowed`
- `feature_unsupported`
- `feature_timeout`
- `feature_runtime_error`

Each feature then decides whether these mean:

- skip
- fallback
- fail

For `title_bootstrap`:

- runtime support is optional
- runtime failure is best-effort
- embedded fallback remains the product guarantee
- final failure remains non-blocking

## Platform Components

### Policy Layer

Recommended home:

- `core_matrix/app/models/runtime_feature_policies/**`

Responsibilities:

- define schema classes
- emit JSON Schema bundle
- validate workspace overrides
- expose defaults and UI metadata

This shared layer may still define `features.prompt_compaction`, but that does
not make prompt compaction a runtime-platform feature.

### Registry Layer

Recommended home:

- `core_matrix/app/services/runtime_features/registry.rb`

Responsibilities:

- register runtime-platform feature definitions
- expose lifecycle and orchestration metadata

### Capability Layer

Recommended home:

- `core_matrix/app/services/runtime_features/capability_resolver.rb`

Responsibilities:

- normalize manifest `feature_contract`
- resolve effective runtime capability

### Invocation Layer

Recommended home:

- `core_matrix/app/services/runtime_features/feature_request_exchange.rb`
- `agents/fenix/app/services/requests/execute_feature.rb`

Responsibilities:

- send direct runtime-feature requests
- normalize runtime-feature responses and failures

### Orchestration Layer

Recommended home:

- `core_matrix/app/services/runtime_features/invoke.rb`
- `core_matrix/app/services/runtime_features/base_orchestrator.rb`

Responsibilities:

- apply strategy
- decide runtime vs embedded vs skip
- return normalized result objects

### Embedded Execution Layer

Recommended home:

- `core_matrix/app/services/embedded_features/**`

Responsibilities:

- product-owned fallback behavior
- no runtime dependency
- no provider-loop coupling

## Boundary With Request Preparation

The request-preparation subsystem owns:

- budget envelope production
- `POST /agent_api/responses/input_tokens`
- authoritative dispatch-time token checks
- prompt-compaction consultation
- prompt-compaction workflow nodes
- re-entry after compaction

This boundary matters because the user and system constraints are different:

- runtime-platform features may be direct and best-effort
- Core Matrix-assisted compaction must leave workflow traces and be scheduled
  by the workflow engine

Prompt compaction may still reuse:

- the shared `features.*` policy namespace
- shared schema publication
- shared manifest vocabulary where useful

But it should not be executed as an ordinary runtime feature.

## How `title_bootstrap` Fits

`title_bootstrap` is the first concrete runtime-platform consumer.

It should be:

- metadata-only
- live-resolved
- embedded-only by default
- runtime-optional
- best-effort and non-blocking

Its runtime invocation path should be:

- direct `execute_feature` when runtime execution is allowed and advertised
- embedded fallback otherwise

## Why This Is Better

This split is cleaner than forcing both `prompt_compaction` and
`title_bootstrap` through the same abstraction:

- `title_bootstrap` is a real runtime-platform feature
- `prompt_compaction` is a request-preparation and workflow concern
- the shared `features.*` namespace remains coherent
- direct runtime features stop inheriting prompt-compaction complexity
- prompt compaction stops inheriting direct-feature assumptions

## Likely Future Runtime-Platform Consumers

- conversation summary generation
- intent distillation
- response critique
- lightweight post-processing

## Testing Strategy

The runtime feature platform should be tested at five levels:

1. policy schema bundle generation and validation
2. manifest `feature_contract` parsing and resolution
3. direct `execute_feature` exchange
4. runtime-vs-embedded orchestration results
5. concrete `title_bootstrap` behavior on top of the platform

## Summary

The right long-term move is to keep a real runtime feature platform, but to
scope it honestly.

This platform should own:

- schema-first `features.*` publication
- runtime-platform capability discovery
- direct runtime feature invocation
- runtime-vs-embedded orchestration

It should not own provider request-preparation critical-path behavior.

`title_bootstrap` belongs here.
`prompt_compaction` does not.
