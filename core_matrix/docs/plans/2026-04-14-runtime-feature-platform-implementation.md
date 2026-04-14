# Runtime Feature Platform Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

## Goal

Replace the current ad hoc internal-feature infrastructure with a shared
runtime feature platform for direct, runtime-backed product features such as
`title_bootstrap`.

This platform should provide:

- schema-first workspace policy under `features.*`
- manifest-driven runtime capability discovery
- direct `execute_feature` control-plane execution
- shared runtime-vs-embedded orchestration
- feature-owned lifecycle semantics

This plan does **not** implement prompt-compaction execution. Prompt
compaction moves to the request-preparation subsystem described in:

- [2026-04-14-prompt-budget-guard-implementation.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-14-prompt-budget-guard-implementation.md)

## Target Outcome

At the end of this plan:

- `workspace.config.features.*` is defined by a schema-first contract layer
- Fenix manifest exposes `feature_contract`
- Core Matrix supports direct runtime feature invocation through
  `execute_feature`
- Core Matrix supports shared runtime-vs-embedded orchestration
- `title_bootstrap` uses the platform instead of slice-local runtime probing
- internal product features stop being modeled as ordinary tools

## Non-Goals

This plan does not:

- implement prompt-budget guarding
- implement prompt-compaction workflow nodes
- add `POST /agent_api/responses/input_tokens`
- freeze prompt-compaction policy into execution snapshots
- keep backward compatibility with interim internal contracts

## Architecture

The implementation introduces:

- a schema-first runtime-feature policy layer
- a runtime-feature registry
- a manifest `feature_contract`
- capability resolution in `core_matrix`
- direct `execute_feature` exchange
- shared runtime-vs-embedded orchestration
- `title_bootstrap` migration onto the platform

## Tech Stack

Ruby on Rails, Minitest, JSON Schema, EasyTalk or a product-owned wrapper
around it, control-plane mailbox contracts, embedded features, `agents/fenix`.

---

### Task 1: Lock The Runtime-Feature Contracts With Failing Tests

**Files:**
- Create: `core_matrix/test/services/runtime_features/registry_test.rb`
- Create: `core_matrix/test/services/runtime_features/capability_resolver_test.rb`
- Create: `core_matrix/test/services/runtime_features/invoke_test.rb`
- Create: `core_matrix/test/services/runtime_features/feature_request_exchange_test.rb`
- Modify: `agents/fenix/test/integration/runtime_manifest_test.rb`

**Step 1: Write failing registry and capability tests**

Add tests that expect:

- runtime features are centrally registered by key
- unknown runtime feature keys are rejected explicitly
- manifest `feature_contract` is normalized separately from `tool_contract`
- runtime feature definitions declare `execution_mode`
- runtime feature capability resolution supports live-resolved features
- `title_bootstrap` remains runtime-optional

**Step 2: Write failing invocation tests**

Add tests that expect:

- `runtime_first` uses runtime when capability is present
- `embedded_only` skips runtime entirely
- `runtime_required` fails when capability is absent
- normalized runtime failure may fall back to embedded when policy allows

**Step 3: Extend the Fenix manifest test**

Add failing expectations for:

- top-level `feature_contract`
- `title_bootstrap` may be advertised there
- `tool_contract` remains reserved for real tools

**Step 4: Run the targeted tests and verify they fail**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/runtime_features/registry_test.rb \
  test/services/runtime_features/capability_resolver_test.rb \
  test/services/runtime_features/invoke_test.rb \
  test/services/runtime_features/feature_request_exchange_test.rb
```

Then:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/integration/runtime_manifest_test.rb
```

Expected: failures show the shared runtime-feature primitives do not exist yet.

### Task 2: Build The Schema-First `features.*` Policy Layer

**Files:**
- Create: `core_matrix/app/models/runtime_feature_policies/base.rb`
- Create: `core_matrix/app/models/runtime_feature_policies/root_schema.rb`
- Create: `core_matrix/app/models/runtime_feature_policies/registry.rb`
- Create: `core_matrix/app/models/runtime_feature_policies/title_bootstrap_schema.rb`
- Create: `core_matrix/app/models/runtime_feature_policies/prompt_compaction_schema.rb`
- Create: `core_matrix/app/services/runtime_feature_policies/schema_bundle.rb`
- Modify: `core_matrix/app/models/workspace.rb`
- Modify: `core_matrix/app/services/workspace_policies/upsert.rb`
- Modify: `core_matrix/app/services/app_surface/presenters/workspace_policy_presenter.rb`
- Modify: `core_matrix/app/controllers/app_api/workspaces/policies_controller.rb`
- Create: `core_matrix/test/models/runtime_feature_policies/root_schema_test.rb`
- Modify: `core_matrix/test/models/workspace_test.rb`
- Modify: `core_matrix/test/requests/app_api/workspace_policies_test.rb`

**Step 1: Commit to the wrapper boundary**

Choose one of these and keep it inside the policy layer:

- direct `easy_talk` usage behind `RuntimeFeaturePolicies::*`
- a narrowed product-owned wrapper behind the same namespace

Do not expose raw EasyTalk classes outside the policy layer.

**Step 2: Implement root and per-feature schemas**

Define a root schema that bundles:

- `features.title_bootstrap`
- `features.prompt_compaction`

Use the shared strategy enum:

- `disabled`
- `embedded_only`
- `runtime_first`
- `runtime_required`

Use these initial defaults:

- `title_bootstrap.strategy = embedded_only`
- `prompt_compaction.strategy = runtime_first`

This shared settings layer is used by both:

- the runtime feature platform
- the request-preparation subsystem

**Step 3: Replace hand-written workspace validation**

Update workspace policy validation and normalization so they depend on the new
schema layer rather than the hand-written hash validator.

**Step 4: Add schema bundle output**

Expose a reusable schema bundle service for future UI consumers.

**Step 5: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/models/runtime_feature_policies/root_schema_test.rb \
  test/models/workspace_test.rb \
  test/requests/app_api/workspace_policies_test.rb
```

Expected: `features.*` is now validated and projected through a schema-first
contract layer.

### Task 3: Replace `WorkspaceFeatures::*` With Shared Policy Resolution

**Files:**
- Create: `core_matrix/app/services/runtime_features/policy_resolver.rb`
- Modify: `core_matrix/app/services/conversations/metadata/title_bootstrap_policy.rb`
- Modify: `core_matrix/test/services/conversations/metadata/title_bootstrap_policy_test.rb`

**Step 1: Write failing policy-resolution tests**

Add tests that expect:

- `title_bootstrap` policy resolves from the shared policy layer
- `title_bootstrap` remains live-resolved
- slice-local policy merging goes away

**Step 2: Implement shared policy resolution**

Add a shared resolver that:

- merges workspace overrides over runtime defaults over built-in defaults
- validates against the schema-backed policy model
- returns normalized policy objects

**Step 3: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/metadata/title_bootstrap_policy_test.rb
```

Expected: runtime-platform features now read policy through the shared layer.

### Task 4: Add Manifest `feature_contract` And Capability Resolution

**Files:**
- Modify: `agents/fenix/app/services/runtime/manifest/definition_package.rb`
- Modify: `agents/fenix/config/canonical_config.defaults.json`
- Modify: `agents/fenix/config/canonical_config.schema.json`
- Modify: `agents/fenix/test/integration/runtime_manifest_test.rb`
- Modify: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Create: `core_matrix/app/services/runtime_features/capability_resolver.rb`
- Modify: `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Modify: `core_matrix/test/services/runtime_features/capability_resolver_test.rb`

**Step 1: Add `feature_contract` to the manifest**

Update Fenix definition packaging so the manifest publishes a top-level
`feature_contract`.

Keep `tool_contract` for real tools only.

For this pass:

- `title_bootstrap` may be present
- `prompt_compaction` is not part of `feature_contract`

Keep Fenix runtime defaults aligned with the shared settings contract by
ensuring canonical config continues to publish:

- `features.title_bootstrap.strategy = embedded_only`

**Step 2: Implement capability resolution**

Add capability resolution that:

- normalizes `feature_contract`
- resolves live capability for `title_bootstrap`
- keeps the platform independent from `protocol_methods`

**Step 3: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/runtime_features/capability_resolver_test.rb \
  test/services/installations/register_bundled_agent_runtime_test.rb
```

Then:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test test/integration/runtime_manifest_test.rb
```

Expected: runtime-platform capability is now explicit and manifest-driven.

### Task 5: Add The Direct `execute_feature` Control-Plane Contract

**Files:**
- Create: `agents/fenix/app/services/requests/execute_feature.rb`
- Modify: `agents/fenix/test/services/runtime/execute_mailbox_item_test.rb`
- Modify: `core_matrix/app/services/runtime_features/feature_request_exchange.rb`
- Modify: `core_matrix/test/services/runtime_features/feature_request_exchange_test.rb`

**Step 1: Introduce direct runtime-feature exchange**

Implement a dedicated control-plane request for runtime-platform features:

- `execute_feature`

This path should:

- carry `feature_key`
- carry typed request payload
- return typed result payload
- normalize unsupported or failed runtime execution

**Step 2: Keep this path scoped**

Do **not** wire prompt-compaction workflow execution through this path.

This exchange is only for direct runtime-platform features.

**Step 3: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/runtime_features/feature_request_exchange_test.rb
```

Then:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/runtime/execute_mailbox_item_test.rb
```

Expected: direct runtime-feature invocation now exists as a distinct contract.

### Task 6: Register And Orchestrate `title_bootstrap`

**Files:**
- Modify: `core_matrix/app/services/runtime_features/registry.rb`
- Modify: `core_matrix/app/services/runtime_features/invoke.rb`
- Create: `core_matrix/app/services/runtime_features/title_bootstrap/orchestrator.rb`
- Create: `core_matrix/app/services/embedded_features/title_bootstrap/invoke.rb`
- Modify: `core_matrix/test/services/runtime_features/registry_test.rb`
- Modify: `core_matrix/test/services/runtime_features/invoke_test.rb`
- Create or Modify: `core_matrix/test/services/embedded_features/title_bootstrap/invoke_test.rb`

**Step 1: Register the first concrete runtime feature**

Add `title_bootstrap` to the runtime feature registry with:

- `runtime_requirement = optional`
- `policy_lifecycle = live_resolved`
- `capability_lifecycle = live_resolved`
- `execution_mode = direct`
- embedded executor required

**Step 2: Implement shared orchestration**

Ensure the shared invocation path:

- resolves live policy and live capability
- prefers runtime when strategy allows and capability exists
- falls back to embedded when policy allows
- returns normalized result metadata

**Step 3: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/runtime_features/registry_test.rb \
  test/services/runtime_features/invoke_test.rb \
  test/services/embedded_features/title_bootstrap/invoke_test.rb
```

Expected: the platform can execute a concrete runtime feature end to end.

### Task 7: Migrate `title_bootstrap` Onto The Platform

**Files:**
- Modify: `core_matrix/app/services/conversations/metadata/runtime_bootstrap_title.rb`
- Modify: `core_matrix/app/services/conversations/metadata/generate_bootstrap_title.rb`
- Modify: `core_matrix/app/jobs/conversations/metadata/bootstrap_title_job.rb`
- Modify: `core_matrix/test/services/conversations/metadata/runtime_bootstrap_title_test.rb`
- Modify: `core_matrix/test/services/conversations/metadata/generate_bootstrap_title_test.rb`
- Modify: `core_matrix/test/jobs/conversations/metadata/bootstrap_title_job_test.rb`

**Step 1: Remove slice-local runtime probing**

Replace `protocol_methods` and other slice-local capability checks with shared
runtime-feature invocation.

**Step 2: Preserve title-specific semantics**

Keep:

- live resolution
- best-effort behavior
- placeholder preservation
- non-blocking failure handling

**Step 3: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/metadata/runtime_bootstrap_title_test.rb \
  test/services/conversations/metadata/generate_bootstrap_title_test.rb \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb
```

Expected: `title_bootstrap` is now platform-backed without changing product
behavior.

### Task 8: Verify The Platform End To End

**Step 1: Run focused runtime-feature verification**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/runtime_features/registry_test.rb \
  test/services/runtime_features/capability_resolver_test.rb \
  test/services/runtime_features/invoke_test.rb \
  test/services/runtime_features/feature_request_exchange_test.rb \
  test/services/conversations/metadata/title_bootstrap_policy_test.rb \
  test/services/conversations/metadata/runtime_bootstrap_title_test.rb \
  test/services/conversations/metadata/generate_bootstrap_title_test.rb \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb
```

Then:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test \
  test/integration/runtime_manifest_test.rb \
  test/services/runtime/execute_mailbox_item_test.rb
```

**Step 2: Run full `core_matrix` verification**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare
bin/rails test
bin/rails test:system
```

**Step 3: Run acceptance verification if the migration touched acceptance-critical paths**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

Inspect:

- acceptance artifacts relevant to conversation creation and first-turn flows
- resulting database state for placeholder-title and title-source transitions

Expected: runtime-platform infrastructure and `title_bootstrap` behave
correctly, without dragging prompt-compaction execution back into the platform.
