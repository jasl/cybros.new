# Runtime Feature Platform Design

## Goal

Introduce a shared `core_matrix` feature platform for product-owned runtime
features that need all of the following:

- workspace-level policy
- runtime capability discovery
- feature-specific execution modes such as direct control-plane calls vs
  workflow-backed execution
- runtime-first execution or runtime-authored workflow participation with
  embedded fallback
- feature-specific lifecycle rules such as snapshot-frozen vs live-read
- future schema publication for UI or external tooling

The first two feature slices on top of this platform are:

- `prompt_compaction`
- `title_bootstrap`

## Design Principles

This design assumes the current branch allows intentional breaking changes and
does not optimize for compatibility with interim contracts.

Priority order:

1. coherent long-term architecture
2. explicit domain boundaries
3. product correctness and recoverability
4. implementation cost

That means this design prefers replacing ad hoc partial abstractions instead of
layering more compatibility logic on top of them.

## Scope

This pass establishes a reusable platform for feature orchestration across
`core_matrix` and `agents/fenix`.

It includes:

1. structured feature policy schemas
2. runtime feature capability contracts in manifests
3. a shared feature registry in `core_matrix`
4. direct runtime feature invocation over the control plane where appropriate
5. intent-backed workflow-node execution for model-backed features
6. embedded fallback execution
7. feature-owned lifecycle semantics
8. schema publication for future UI consumers

It explicitly covers `prompt_compaction` and `title_bootstrap` as the first
consumers.

## Non-Goals

This pass does not:

- keep backward compatibility with the current internal feature-as-tool
  contract
- preserve `enabled + mode` as the long-term policy shape
- keep `WorkspaceFeatures::Schema` as the final abstraction
- make every feature snapshot-frozen
- require every feature to be runtime-capable
- solve all future settings/configuration needs in one move

## Current Baseline

Today the codebase already has useful groundwork:

- `workspace.config.features.*`
- `WorkspaceFeatures::Schema`
- `WorkspaceFeatures::Resolver`
- workspace policy show/update
- canonical config defaults in Fenix
- `provider_context.feature_policies.prompt_compaction`

But the current shape is still transitional.

The main issues are:

1. policy and capability are still mixed conceptually
2. internal feature execution is still modeled as agent tool execution
3. feature lifecycle behavior is implemented ad hoc per feature
4. the policy schema is hand-written Ruby hash validation rather than a
   first-class schema artifact
5. there is no shared execution contract that distinguishes direct feature
   calls from workflow-backed feature execution

## Core Problem

`prompt_compaction` and `title_bootstrap` are not ordinary tools.

They are product features with:

- policy
- capability
- orchestration
- fallback
- lifecycle semantics
- feature-specific failure handling

Treating them as simple booleans plus a couple of service objects creates
duplicated orchestration logic and blurs the boundary between:

- user/model-visible tools
- internal product-owned features

The platform should make that boundary explicit.

## Recommended Architecture

### 1. Separate Policy, Capability, And Execution

The platform should model three distinct concepts:

- `policy`
  - what the workspace wants
- `capability`
  - what the current runtime/agent implementation can do
- `execution`
  - what `core_matrix` decides to invoke for this particular feature

These must not share the same contract.

### 2. Replace `enabled + mode` With Structured Strategy Policies

The long-term policy shape should become:

```json
{
  "features": {
    "prompt_compaction": {
      "strategy": "runtime_first"
    },
    "title_bootstrap": {
      "strategy": "embedded_only"
    }
  }
}
```

Recommended common strategy enum:

- `disabled`
- `embedded_only`
- `runtime_first`
- `runtime_required`

This removes invalid mixed states such as:

- `enabled = false` plus `mode = runtime_first`

Feature-specific schemas may later add additional fields under the same feature
node, but the strategy contract should be shared.

### 3. Introduce A Feature Registry

`core_matrix` should own a registry describing each supported feature.

Each registry entry should define:

- `feature_key`
- `policy_schema_class`
- `runtime_capability_key`
- `runtime_requirement`
- `consultation_mode`
- `execution_mode`
- `policy_lifecycle`
- `capability_lifecycle`
- `orchestrator_class`
- `embedded_executor_class`
- `runtime_failure_policy`
- `result_contract`

This keeps feature-specific behavior explicit while centralizing the platform
rules.

Example shape:

```ruby
RuntimeFeatures::Registry.register(
  key: "prompt_compaction",
  policy_schema: RuntimeFeatures::Policies::PromptCompaction,
  runtime_capability_key: "prompt_compaction",
  runtime_requirement: :required_on_fenix,
  consultation_mode: :direct_required,
  execution_mode: :workflow_intent,
  policy_lifecycle: :snapshot_frozen,
  capability_lifecycle: :snapshot_frozen,
  orchestrator: RuntimeFeatures::PromptCompaction::Orchestrator,
  embedded_executor: EmbeddedFeatures::PromptCompaction::Invoke
)
```

### 4. Publish Policy Schemas As First-Class Artifacts

The policy layer should become schema-first.

The current hand-written validator in
[schema.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workspace_features/schema.rb)
is good as a transitional guard, but it is not the right final abstraction for
long-lived product settings that must eventually drive UI.

The platform should expose:

- one Ruby-side schema definition per feature
- one bundled root schema for `workspace.config.features`
- machine-readable JSON Schema output
- optional UI metadata such as grouping, labels, controls, and help text

### 5. Use An Internal EasyTalk-Based Schema Layer

The prior research note already pointed at `easy_talk` as the better candidate
once `core_matrix` needs schema-first settings publication:
[research note](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-24-core-matrix-structured-json-contracts-research-note.md).

The Tavern Kit reference confirms the useful pattern:

- product-specific wrapper layer
- nested schema composition
- root schema bundle
- `x-ui` and similar extension metadata

Recommended adoption approach:

- do **not** spread raw `EasyTalk::*` usage across unrelated app code
- do introduce a narrow internal wrapper, for example
  `CoreMatrix::SchemaContracts` or `RuntimeFeatures::PolicySchemas`
- that wrapper may depend on `easy_talk` directly or vendor a narrowed subset,
  but the rest of the app should depend only on the product wrapper

This keeps the platform in control of:

- naming
- schema extensions
- JSON Schema publication
- future UI bundle format

### 6. Add A Dedicated Runtime Feature Contract

Fenix manifest should gain a new top-level `feature_contract` instead of
continuing to advertise internal product features through `tool_contract`.

Each feature entry should include:

- `feature_key`
- `consultation_mode`
- `execution_mode`
- `lifecycle`
- `consultation_schema`
- `intent_schema`
- `artifact_schema`
- `implementation_ref`

Example:

```json
{
  "feature_key": "prompt_compaction",
  "consultation_mode": "direct_required",
  "execution_mode": "workflow_intent",
  "lifecycle": "turn_scoped",
  "consultation_schema": { "type": "object" },
  "intent_schema": { "type": "object" },
  "artifact_schema": { "type": "object" },
  "implementation_ref": "fenix/prompt_compaction"
}
```

This is a cleaner fit than pretending internal compaction is a normal agent
tool.

### 7. Add Dedicated Feature Execution Paths

The platform should not force every feature through the same transport.

It should support two execution paths plus an optional consultation hook:

1. direct feature execution
   - for non-LLM or non-loop-shaping features
   - modeled through `execute_feature`
2. intent-backed workflow execution
   - for model-backed features that should appear as workflow nodes and re-enter
     the agent loop after completion
   - modeled through yielded feature intents plus workflow-node materialization

This keeps the control-plane model honest:

- tools are tools
- direct features are direct features
- workflow-backed features are workflow-backed features

Some features may also require a direct consultation phase before execution:

- Core Matrix remains the authoritative trigger
- runtime is asked whether and how the feature should proceed
- Core Matrix then decides whether to materialize workflow work

For the initial slices:

- `prompt_compaction` must use `workflow_intent`
- `prompt_compaction` should also expose a direct consultation hook
- `title_bootstrap` may use direct feature execution or embedded execution

### 8. Freeze Or Resolve Per Feature, Not Globally

The platform must not force one lifecycle rule onto all features.

Each feature declares its own policy and capability lifecycle.

Recommended initial rules:

- `prompt_compaction`
  - policy: `snapshot_frozen`
  - capability: `snapshot_frozen`
- `title_bootstrap`
  - policy: `live_resolved`
  - capability: `live_resolved`

That means the platform must support both:

- execution-snapshot-backed resolution
- live runtime resolution at invocation time

### 9. Standardize Orchestration And Fallback

Every feature invocation should go through one orchestration path:

1. resolve effective policy
2. resolve effective capability
3. run consultation when the feature requires it
4. select direct invocation vs workflow-backed execution vs embedded path
5. invoke or materialize the selected path
6. fall back to embedded according to feature policy
7. return a typed result object with source, execution mode, and status

The platform must still allow per-feature runtime criticality:

- some features are genuinely runtime-optional
- some features are runtime-required for specific runtimes such as Fenix

That requirement must be explicit in the registry and enforced by manifest
tests and bundled-runtime registration, not left as convention.

The common result shape should include:

- `status`
  - `ok`
  - `skipped`
  - `failed`
- `source`
  - `runtime`
  - `embedded`
  - `none`
- `execution_mode`
  - `direct`
  - `workflow`
  - `none`
- `fallback_used`
- `value`
- `failure`

### 10. Unify Failure Semantics

The platform should standardize a small set of runtime feature failure codes,
for example:

- `feature_not_advertised`
- `feature_not_allowed`
- `feature_unsupported`
- `feature_timeout`
- `feature_runtime_error`

Each feature then decides whether these mean:

- skip
- fallback
- fail the calling workflow

For example:

- `prompt_compaction`
  - on Fenix, missing advertised capability is a contract failure, not a
    healthy steady state
  - runtime execution failure may still fall back once for resilience
  - repeated failure may become a turn failure
- `title_bootstrap`
  - runtime support is optional
  - `feature_unsupported` means fallback or skip according to strategy
  - final failure is still best-effort and non-blocking

## Platform Components

### Policy Layer

Recommended home:

- `core_matrix/app/models/runtime_feature_policies/**`
  or
- `core_matrix/lib/core_matrix/schema_contracts/**`

Responsibilities:

- define schema classes
- emit JSON Schema bundle
- validate workspace overrides
- expose defaults and UI metadata

### Registry Layer

Recommended home:

- `core_matrix/app/services/runtime_features/registry.rb`

Responsibilities:

- register feature definitions
- expose lifecycle/capability/orchestrator metadata

### Capability Layer

Recommended home:

- `core_matrix/app/services/runtime_features/capability_contract.rb`
- `core_matrix/app/services/runtime_features/capability_resolver.rb`

Responsibilities:

- normalize manifest `feature_contract`
- project frozen capability snapshots when required
- resolve live capabilities when required

### Invocation Layer

Recommended home:

- `core_matrix/app/services/runtime_features/feature_request_exchange.rb`
- `agents/fenix/app/services/requests/execute_feature.rb`

Responsibilities:

- send and receive feature control-plane requests
- normalize runtime results and failures
- support consultation-style direct requests for workflow-backed features when
  the platform requires runtime guidance before materializing workflow work

### Shared Advisory APIs

Some agent-facing infrastructure queries should remain Core Matrix-owned instead
of being reimplemented per runtime.

The first concrete example is input-token counting for prompt construction:

- a static per-round budget envelope delivered during prompt construction
- an OpenAI-style input-token counting API exposed to agents over the
  authenticated AgentAPI
  surface
- backed by Core Matrix token estimation and reserve logic
- reusable outside the `prompt_compaction` slice
- non-mutating and non-authoritative for final dispatch

This keeps heavy tokenizer and budgeting infrastructure in Core Matrix while
still giving specialized agents a way to proactively manage context.

The two surfaces should be distinct:

- `budget envelope`
  - delivered with round-construction context
  - includes selected model identity plus recommended and hard prompt-input
    budget targets
  - intended for up-front drafting guidance
- `input-token counting API`
  - invoked on demand with a concrete candidate provider-visible `input`
    payload
  - returns recalculated token diagnostics for that candidate
  - intended for dynamic refinement while drafting

Neither surface replaces the final dispatch-time guard.

These agent-initiated counting APIs should not be modeled as mailbox work or as
Core Matrix-to-agent `execute_feature` calls. They are agent-initiated,
authenticated AgentAPI requests.

### Workflow Intent Layer

Recommended home:

- `core_matrix/app/services/provider_execution/persist_turn_step_yield.rb`
- `core_matrix/app/services/workflows/re_enter_agent.rb`
- `core_matrix/app/services/runtime_features/intent_materializer.rb`

Responsibilities:

- accept runtime-authored workflow intents only for features that permit them
- synthesize feature intents from Core Matrix guards or platform orchestrators
  when the feature is Core Matrix-triggered
- materialize workflow nodes and artifacts
- resume normal agent execution after the feature node completes

### Orchestration Layer

Recommended home:

- `core_matrix/app/services/runtime_features/invoke.rb`
- `core_matrix/app/services/runtime_features/base_orchestrator.rb`

Responsibilities:

- apply strategy
- decide runtime vs embedded
- apply fallback rules
- return typed results

### Embedded Execution Layer

Recommended home:

- `core_matrix/app/services/embedded_features/**`

Responsibilities:

- product-owned fallback behavior
- no runtime dependency
- no protocol dependency

## How The First Two Features Fit

### `prompt_compaction`

Platform-specific characteristics:

- execution-critical
- snapshot-frozen
- runtime-first by default
- runtime capability required for Fenix
- Core Matrix is the sole trigger
- direct consultation before workflow insertion
- workflow-backed execution
- embedded fallback required
- may produce turn failure if compaction cannot recover the request

`prompt_compaction` is the one feature in this initial platform that should be
treated as quality-critical for the primary agent runtime. For Fenix, the
runtime capability must exist and be validated as part of the runtime contract.
The authoritative budget check belongs to Core Matrix, not the runtime agent.
When Core Matrix detects that compaction is advisable or required, it should
ask the runtime for compaction guidance, then insert a workflow node if the
decision is to compact. If compaction requires an LLM call, that call should
appear as a workflow node, not as an invisible synchronous control-plane side
effect. Embedded compaction remains valuable, but only as a degraded fallback
or for non-Fenix runtimes.

### `title_bootstrap`

Platform-specific characteristics:

- metadata-only
- live-resolved
- embedded-only by default
- runtime capability optional
- embedded fallback required
- final failure is best-effort and non-blocking

## Why This Is Better Than The Current Incremental Plan

This version is more expensive, but materially cleaner:

- feature policy becomes a real product contract
- UI schema publication becomes natural instead of bolted on later
- runtime capability becomes separate from tool visibility
- feature lifecycle becomes explicit instead of implicit
- prompt compaction and title bootstrap stop inventing parallel orchestration
  logic
- future features can reuse the same platform

Likely future consumers:

- conversation summary generation
- intent distillation
- response critique
- safety post-processing
- export summarization

## Testing Strategy

The platform should be tested at five levels:

1. policy schema bundle generation and validation
2. manifest `feature_contract` parsing and freezing
3. direct `execute_feature` exchange where relevant
4. workflow-intent materialization and re-entry behavior
5. feature-slice behavior for prompt compaction and title bootstrap

## Summary

The right long-term move is not to keep polishing feature-specific service
stacks. It is to establish a real runtime feature platform where:

- policy is schema-first
- capability is manifest-driven
- execution is explicitly orchestrated
- lifecycle is owned per feature
- embedded fallback is a first-class product capability

`easy_talk` is a good fit for the policy-schema layer inside this platform.
It is not the platform itself.
