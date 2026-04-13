# Title Bootstrap Feature Slice Follow-Up Design

## Status

`title_bootstrap` is no longer a greenfield feature.

The following behavior already exists in `core_matrix` today:

- new conversations start with an i18n placeholder title
- manual user entry enqueues `Conversations::Metadata::BootstrapTitleJob`
- title bootstrap runs asynchronously and is guarded by an eligibility check
- workspace policy is live-read through `WorkspaceFeatures::Resolver`
- generation is already runtime-first in shape, with embedded and heuristic
  fallback

This document describes only the remaining work needed to migrate that
existing implementation onto the shared runtime feature platform defined in:

- [runtime-feature-platform-design.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-14-runtime-feature-platform-design.md)

## Goal

Finish the `title_bootstrap` migration so the feature uses the same platform
contracts as `prompt_compaction` while preserving its own lifecycle rules:

- live-resolved policy
- live-resolved capability
- best-effort, non-blocking execution
- embedded fallback as a product guarantee

## Already Landed

The migration should treat these as baseline, not as pending work:

1. placeholder title semantics at conversation creation time
2. removal of synchronous title generation from accepted-turn persistence
3. async enqueue through workbench/app entry points
4. `BootstrapTitleJob` and its eligibility gate
5. embedded modeled title generation with heuristic fallback
6. workspace-owned title-bootstrap config

The current code paths include:

- [creation_support.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/creation_support.rb)
- [create_conversation_from_agent.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workbench/create_conversation_from_agent.rb)
- [send_message.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workbench/send_message.rb)
- [bootstrap_title_job.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/jobs/conversations/metadata/bootstrap_title_job.rb)
- [generate_bootstrap_title.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/metadata/generate_bootstrap_title.rb)
- [title_bootstrap_policy.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/metadata/title_bootstrap_policy.rb)
- [runtime_bootstrap_title.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/metadata/runtime_bootstrap_title.rb)
- [embedded_agents/conversation_title/invoke.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/conversation_title/invoke.rb)

## Current Gaps

What remains is not product behavior from scratch. It is contract cleanup and
platform alignment.

### 1. Policy Contract Still Uses Transitional Shape

The current effective policy still resolves an `enabled + mode` shape from
`WorkspaceFeatures::Resolver`.

The target platform shape is:

```json
{
  "features": {
    "title_bootstrap": {
      "strategy": "runtime_first"
    }
  }
}
```

This feature should stop depending on transitional per-feature hash-merging
once the shared schema-first policy layer lands.

### 2. Runtime Capability Is Not Yet A First-Class Feature Capability

The current runtime path only checks whether
`protocol_methods` includes `conversation_title_bootstrap`, then returns `nil`.

That is only a stub compatibility bridge. The long-term contract must be:

- manifest advertises `title_bootstrap` in `feature_contract`
- `core_matrix` resolves live capability through the platform
- runtime execution goes through `execute_feature`

### 3. Embedded Execution Is Still In The Legacy Embedded-Agent Namespace

The current embedded path is implemented under
`EmbeddedAgents::ConversationTitle::Invoke`.

That works today, but the platform direction is to move product-owned runtime
feature fallbacks under a feature-oriented namespace such as:

- `EmbeddedFeatures::TitleBootstrap::Invoke`

The modeled prompt and heuristic helper can be preserved, but the public
invocation boundary should align with the platform.

### 4. The Slice Still Owns Too Much Of Its Own Orchestration

`GenerateBootstrapTitle` currently does all of the following itself:

- reads the live policy
- decides whether runtime is allowed
- probes runtime support
- calls the embedded fallback
- falls through to heuristic fallback

After the platform lands, that orchestration should move to shared feature
invocation. The slice should keep only:

- title-specific input shaping
- title-specific persistence rules
- best-effort semantics

## Target Follow-Up State

After the migration, `title_bootstrap` should look like this:

- policy is defined by the shared schema-first `features.title_bootstrap`
  contract
- capability is resolved from `feature_contract`
- runtime invocation goes through `execute_feature`
- embedded fallback goes through the shared feature platform
- the job remains live-resolved and best-effort

Recommended registry identity:

- `feature_key`: `title_bootstrap`
- `runtime_capability_key`: `title_bootstrap`
- `policy_lifecycle`: `live_resolved`
- `capability_lifecycle`: `live_resolved`
- `default_strategy`: `runtime_first`
- `embedded_executor`: required

## Lifecycle Rules That Must Not Change

The migration should preserve these feature-owned semantics:

- policy is resolved live when the job runs
- capability is resolved live when the job runs
- title bootstrap never blocks accepted-turn correctness
- final failure never becomes a user-facing error state

This feature must not inherit `prompt_compaction`'s snapshot-frozen execution
model.

## Runtime And Embedded Follow-Up Behavior

### Runtime Path

When policy allows runtime execution and live capability resolution advertises
`title_bootstrap`, the job should invoke the shared feature platform.

### Embedded Path

Embedded generation remains mandatory.

The current modeled-title prompt and deterministic heuristic are both useful
and should survive the migration, but the execution boundary should move behind
the platform.

### Runtime Failure Handling

When strategy permits, normalized runtime failures should fall back to embedded
generation.

`runtime_required` should keep the placeholder title rather than silently
crossing into embedded generation.

## Persistence Semantics

The migration should not change persistence truth:

- successful bootstrap writes the upgraded title and `title_source = "bootstrap"`
- no usable title leaves the placeholder title in place
- failure keeps `title_source = "none"`

The existing eligibility gate remains the authority before any write.

## Follow-Up Scope

This follow-up should only cover:

1. policy contract migration to the shared platform shape
2. runtime capability migration to `feature_contract`
3. runtime invocation migration to `execute_feature`
4. embedded executor migration into the feature platform
5. removal of slice-local orchestration glue that the platform replaces

It should not reopen:

- placeholder title behavior
- async enqueue behavior
- accepted-turn slimming
- title bootstrap eligibility semantics

## Testing Focus

Follow-up verification should focus on the delta:

1. live-resolved policy under the new shared policy schema
2. live-resolved capability under `feature_contract`
3. `execute_feature` runtime invocation
4. embedded feature fallback after runtime miss or failure
5. preservation of best-effort, non-blocking title-bootstrap behavior

## Summary

`title_bootstrap` already works as a product feature.

The remaining work is to migrate it cleanly onto the shared runtime feature
platform without regressing the behavior that has already landed.
