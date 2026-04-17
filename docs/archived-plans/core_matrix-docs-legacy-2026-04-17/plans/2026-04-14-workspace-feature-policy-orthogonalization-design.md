# Workspace Feature Policy Orthogonalization Design

## Goal

Correct the configuration and policy layering introduced during title-bootstrap
work so `core_matrix` cleanly separates:

1. runtime default behavior
2. workspace-owned product overrides
3. turn-frozen execution policy

The target behavior is:

- runtime canonical config and workspace config both use a shared
  `features.*` shape
- workspace policy API exposes explicit `features`, not generic `metadata`
- `prompt_compaction` is treated as execution policy and frozen per turn
- `title_bootstrap` is treated as asynchronous conversation-metadata
  post-processing and remains live workspace-controlled
- `Workspace` validation grows into a generic feature-policy container instead
  of accumulating feature-specific branches

## Scope

This correction pass changes six connected areas:

1. move runtime and workspace policy shape from `metadata.*` to `features.*`
2. make workspace policy API project explicit `features`
3. introduce a generic workspace feature schema/normalization layer
4. keep `title_bootstrap` as live-read post-processing over
   `features.title_bootstrap`
5. freeze effective `prompt_compaction` policy into the execution snapshot
6. update prompt-budget-guard and title-bootstrap plans so they build on the
   corrected contract

## Non-Goals

This pass does not:

- implement the prompt-budget guard itself
- add new runtime protocol work in `agents/fenix` beyond config-shape changes
- add compatibility reads for legacy `metadata.title_bootstrap`
- add new workspace policy endpoints
- freeze title-bootstrap policy into the execution snapshot
- redesign unrelated runtime metadata, provider metadata, or agent metadata

This branch already allows destructive contract changes, so this pass should
prefer one clean cutover over compatibility layering.

## Relationship To Existing Work

The branch already landed several accepted-turn and request-path slimming
changes:

- workflow substrate is lazy-materialized for app-facing manual entry
- diagnostics reads are deferred/stale-tolerant
- feed and todo-plan reads are projection-first
- conversation title bootstrap moved into an asynchronous job

That title-bootstrap follow-up also pre-landed a structured `workspaces.config`
field and mirrored the same shape into Fenix canonical config defaults.

The current issue is not that config storage was added. The issue is that the
same nested `metadata.title_bootstrap` path is now trying to represent three
different concerns:

- runtime defaults
- workspace overrides
- execution-time effective behavior

That layering is not precise enough for the next prompt-compaction work.

## Current Baseline

Today the relevant paths are:

- Fenix canonical config defaults:
  - `default_canonical_config.metadata.title_bootstrap`
- workspace-owned overrides:
  - `workspaces.config.metadata.title_bootstrap`
- workspace policy API:
  - `workspace_policy.metadata`
- title-bootstrap resolution:
  - `Conversations::Metadata::TitleBootstrapPolicy`
- execution snapshot:
  - `Workflows::BuildExecutionSnapshot`

Within that baseline:

- `WorkspacePolicyPresenter` returns generic `metadata`
- `WorkspacePolicies::Upsert` accepts generic `metadata`
- `Workspace` hardcodes `title_bootstrap` validation logic directly in the
  model
- `TitleBootstrapPolicy` live-merges workspace config and runtime defaults at
  job execution time
- `BuildExecutionSnapshot` does not freeze any feature policy

This is sufficient for title bootstrap alone, but it is the wrong foundation
for prompt compaction.

## Problem 1: `metadata.*` Is The Wrong Namespace For Product Feature Policy

`metadata` reads as descriptive information. The branch is using it to hold
product behavior switches and strategy selection.

That creates immediate ambiguity:

- runtime defaults now put behavioral policy under `metadata`
- workspace override API presents behavioral policy as `metadata`
- future features must either continue misusing `metadata` or create a second
  shape alongside it

This is the wrong long-term contract. The repo needs one explicit namespace for
workspace/runtime-controlled product features.

## Problem 2: Workspace Policy API Exposes A Generic Container Instead Of A Stable Contract

The current workspace policy endpoint returns and accepts generic `metadata`.

That is serviceable for title bootstrap alone, but it is not a good policy
surface for:

- discoverability
- targeted validation
- future versioning
- prompt-compaction rollout

The client should not have to infer which `metadata` subkeys happen to be
feature policy versus descriptive metadata.

## Problem 3: Workspace Validation Is Already Becoming Feature-Specific

`Workspace` currently hardcodes:

- title-bootstrap modes
- title-bootstrap defaults
- title-bootstrap validation

If prompt compaction follows the same pattern, the model will quickly turn into
a pile of feature-specific branches. The branch needs a generic feature-policy
schema and normalization layer before the next policy-bearing feature lands.

## Problem 4: Execution Policy And Metadata Post-Processing Have Different Freezing Rules

The most important semantic distinction is:

- `prompt_compaction` changes the in-flight execution behavior of a turn
- `title_bootstrap` updates conversation metadata after accepted work already
  exists

Those are not the same class of policy.

`prompt_compaction` must be frozen with the rest of the execution contract,
because changing workspace policy mid-turn must not change provider behavior
for already accepted work.

`title_bootstrap` does not belong in the execution contract. It is a best-effort
post-processing path and can legitimately observe live workspace feature policy
when the job runs.

Using one resolution pattern for both would be incorrect.

## Recommended Direction

### 1. Standardize Runtime And Workspace Policy Shape Under `features.*`

Use the same explicit shape in both places:

```json
{
  "features": {
    "prompt_compaction": {
      "enabled": true,
      "mode": "runtime_first"
    },
    "title_bootstrap": {
      "enabled": true,
      "mode": "runtime_first"
    }
  }
}
```

This makes feature policy clearly distinct from descriptive metadata and gives
future workspace-scoped features a stable home.

### 2. Make Workspace Policy API Expose `features`, Not `metadata`

The workspace policy endpoint should become explicit:

- input: `features`
- output: `features`

`metadata` should disappear from this API surface entirely for this contract.

That gives the product a stable, discoverable policy surface without creating a
new endpoint.

### 3. Add A Generic Workspace Feature Schema Layer

Introduce a small shared layer, for example:

- `WorkspaceFeatures::Schema`
- `WorkspaceFeatures::Resolver`

Responsibilities:

- define system defaults for supported features
- normalize hash shape
- validate feature values
- merge runtime defaults over system defaults
- merge workspace overrides over runtime defaults when needed

`Workspace` should stop owning feature-specific validation branches directly.

### 4. Treat `title_bootstrap` As Live-Read Metadata Post-Processing

`title_bootstrap` should remain a conversation-metadata enhancement path:

- `BootstrapTitleJob` may resolve policy live when it runs
- the job should read:
  - runtime default `features.title_bootstrap`
  - workspace override `features.title_bootstrap`
- the result should not be frozen into `ExecutionContract` or
  `provider_context`

This matches the product semantics:

- accepted work is already durable
- title generation is optional metadata improvement
- workspace policy changes may legitimately affect later metadata upgrades

### 5. Treat `prompt_compaction` As Turn-Frozen Execution Policy

`prompt_compaction` should use the same config surface but a different
resolution boundary:

- defaults come from runtime canonical config under `features.prompt_compaction`
- workspace overrides come from `workspace.config.features.prompt_compaction`
- `BuildExecutionSnapshot` resolves the effective policy once and freezes it
- provider execution later consumes only the frozen policy

Recommended snapshot placement:

- `provider_context.feature_policies.prompt_compaction`

This keeps the turn execution contract deterministic even if workspace policy
changes after acceptance.

### 6. Remove `disabled` As A Mode Value For Prompt Compaction

This correction pass should normalize prompt-compaction shape to:

- `enabled`
- `mode`

and not allow `mode = "disabled"`.

Using both `enabled: false` and `mode: "disabled"` creates two ways to express
the same state and will eventually produce inconsistent callers. The product
should use a single boolean switch plus mode enumeration.

## Data And Policy Ownership Model

After this correction, ownership should be:

### Runtime defaults

Owned by:

- `agent_definition_version.default_canonical_config.features.*`

Meaning:

- the runtime's default product behavior for this agent/runtime pairing

### Workspace overrides

Owned by:

- `workspace.config.features.*`

Meaning:

- workspace-scoped CoreMatrix overrides of runtime defaults

### Turn-frozen effective policy

Owned by:

- `ExecutionContract` / `provider_context.feature_policies.prompt_compaction`

Meaning:

- the exact execution policy for this accepted turn

### Live metadata post-processing policy

Owned by:

- the `title_bootstrap` job-time merge of runtime defaults and workspace
  overrides

Meaning:

- best-effort workspace-controlled behavior for asynchronous conversation
  metadata enhancement

## API Contract

The workspace policy response should become:

```json
{
  "workspace_policy": {
    "workspace_id": "wk_...",
    "agent_id": "ag_...",
    "default_execution_runtime_id": "rt_...",
    "features": {
      "prompt_compaction": {
        "enabled": true,
        "mode": "runtime_first"
      },
      "title_bootstrap": {
        "enabled": true,
        "mode": "runtime_first"
      }
    },
    "available_capabilities": [],
    "disabled_capabilities": [],
    "effective_capabilities": []
  }
}
```

The request contract should mirror the same `features` shape.

## Testing Implications

This correction needs four kinds of tests.

### 1. Workspace policy surface tests

Lock that:

- `features.prompt_compaction` is present
- `features.title_bootstrap` is present
- `metadata.title_bootstrap` no longer exists

### 2. Workspace schema tests

Lock that:

- `workspace.config.features` is a hash
- supported features validate correctly
- invalid `enabled`/`mode` values are rejected

### 3. Title-bootstrap live policy tests

Lock that:

- accepted work enqueues the title-bootstrap job
- changing `workspace.config.features.title_bootstrap` before job execution
  changes whether the job runs

This proves title bootstrap is intentionally live workspace-controlled.

### 4. Prompt-compaction frozen-policy tests

Lock that:

- the effective prompt-compaction policy is frozen during snapshot build
- changing workspace config after snapshot creation does not alter the current
  turn's execution policy

This proves prompt compaction follows execution-contract freezing rules.

## Destructive Cutover Recommendation

Because this branch already allows destructive refactoring:

- do not dual-read `metadata.title_bootstrap`
- do not preserve `workspace_policy.metadata`
- do not backfill compatibility helpers
- rewrite the contract in one pass:
  - runtime defaults
  - workspace policy API
  - workspace validation
  - title-bootstrap resolution
  - prompt-budget-guard docs

This yields the cleanest long-term contract and avoids dragging a temporary
shape into future prompt-compaction work.

## Recommended Order

1. correct runtime and workspace config shape to `features.*`
2. cut workspace policy API from `metadata` to `features`
3. add a shared workspace feature schema/resolver layer
4. rewire title-bootstrap policy to `features.title_bootstrap`
5. update prompt-budget-guard docs and tests to use `features.prompt_compaction`
6. freeze prompt-compaction policy in the execution snapshot when that feature
   is implemented

## Acceptance Criteria

This correction is complete only when:

- no product feature policy is stored under `metadata.*`
- workspace policy API exposes `features`, not `metadata`
- `title_bootstrap` resolves from live `features.title_bootstrap`
- prompt-compaction docs and tests point to `features.prompt_compaction`
- prompt-compaction is explicitly documented as turn-frozen execution policy
- title bootstrap is explicitly documented as asynchronous metadata
  post-processing
