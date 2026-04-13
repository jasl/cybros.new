# Runtime Feature Platform Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current ad hoc internal-feature infrastructure with a
shared runtime feature platform that provides schema-first workspace policy,
manifest-driven capability discovery, explicit runtime feature invocation, and
embedded fallback execution for feature slices such as `prompt_compaction` and
`title_bootstrap`.

**Architecture:** `core_matrix` will introduce a feature registry, a
schema-first policy layer, a dedicated runtime `feature_contract`, and a new
`execute_feature` control-plane exchange. Feature slices will then plug into
the shared platform by registering their policy schema, lifecycle rules,
runtime capability key, orchestrator, and embedded executor.

**Tech Stack:** Ruby on Rails, Active Record, Minitest, JSON Schema, control
plane mailbox contracts, embedded agents/features, `agents/fenix`, EasyTalk or
a product-owned wrapper around it.

---

## Target Outcome

At the end of this plan:

- `workspace.config.features.*` is defined by a schema-first contract layer
- Fenix manifest exposes `feature_contract`
- Core Matrix invokes internal runtime features through `execute_feature`
- prompt compaction and title bootstrap use the same platform primitives
- internal product features are no longer modeled as ordinary tools

---

### Task 1: Lock The Platform Contracts Before Rewiring Existing Features

**Files:**
- Create: `core_matrix/test/services/runtime_features/registry_test.rb`
- Create: `core_matrix/test/services/runtime_features/capability_resolver_test.rb`
- Create: `core_matrix/test/services/runtime_features/invoke_test.rb`
- Create: `core_matrix/test/services/runtime_features/feature_request_exchange_test.rb`
- Modify: `agents/fenix/test/integration/runtime_manifest_test.rb`

**Step 1: Write failing registry and capability tests**

Add tests that expect:

- feature definitions are centrally registered by key
- unknown feature keys are rejected explicitly
- manifest `feature_contract` entries are normalized separately from
  `tool_contract`
- feature capability resolution supports both snapshot-frozen and live modes

**Step 2: Write failing invocation tests**

Add tests that expect:

- `runtime_first` uses runtime when capability is present
- `embedded_only` skips runtime entirely
- `runtime_required` fails when capability is absent
- runtime failure may fall back to embedded when the feature policy allows it

**Step 3: Extend the Fenix manifest test**

Add failing expectations for:

- top-level `feature_contract`
- `prompt_compaction` feature capability entry
- any reserved `title_bootstrap` capability entry if declared in this phase

**Step 4: Run the targeted tests and verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/runtime_features/registry_test.rb \
  test/services/runtime_features/capability_resolver_test.rb \
  test/services/runtime_features/invoke_test.rb \
  test/services/runtime_features/feature_request_exchange_test.rb
```

Then run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/integration/runtime_manifest_test.rb
```

Expected: failures show the platform primitives and new manifest surface do not
exist yet.

### Task 2: Build The Schema-First Feature Policy Layer

**Files:**
- Create: `core_matrix/app/models/runtime_feature_policies/base.rb`
- Create: `core_matrix/app/models/runtime_feature_policies/root_schema.rb`
- Create: `core_matrix/app/models/runtime_feature_policies/registry.rb`
- Create: `core_matrix/app/models/runtime_feature_policies/prompt_compaction_schema.rb`
- Create: `core_matrix/app/models/runtime_feature_policies/title_bootstrap_schema.rb`
- Create: `core_matrix/app/services/runtime_feature_policies/schema_bundle.rb`
- Modify: `core_matrix/app/models/workspace.rb`
- Modify: `core_matrix/app/services/workspace_policies/upsert.rb`
- Modify: `core_matrix/app/services/app_surface/presenters/workspace_policy_presenter.rb`
- Modify: `core_matrix/app/controllers/app_api/workspaces/policies_controller.rb`
- Create: `core_matrix/test/models/runtime_feature_policies/root_schema_test.rb`
- Modify: `core_matrix/test/models/workspace_test.rb`
- Modify: `core_matrix/test/requests/app_api/workspace_policies_test.rb`

**Step 1: Decide the wrapper boundary**

Choose one of these and commit to it in code:

- direct `easy_talk` usage behind `RuntimeFeaturePolicies::*`
- vendored narrowed subset behind the same namespace

Do not expose raw EasyTalk classes outside the policy layer.

**Step 2: Implement root and per-feature schemas**

Define a root schema that bundles:

- `features.prompt_compaction`
- `features.title_bootstrap`

Use the shared strategy enum:

- `disabled`
- `embedded_only`
- `runtime_first`
- `runtime_required`

Attach UI-oriented metadata through schema extensions instead of hardcoding UI
shape in controller/presenter code.

**Step 3: Replace hand-written workspace validation**

Update workspace policy validation and normalization so they depend on the new
policy schema layer rather than the current hand-written hash validator.

**Step 4: Add schema bundle output**

Expose a reusable schema bundle service for future UI consumers. The initial
delivery may be internal-only, but the bundle must exist as a first-class
artifact.

**Step 5: Run the targeted tests and make them green**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/models/runtime_feature_policies/root_schema_test.rb \
  test/models/workspace_test.rb \
  test/requests/app_api/workspace_policies_test.rb
```

Expected: workspace feature policies are now validated and projected through a
schema-first contract layer.

### Task 3: Replace `WorkspaceFeatures::*` With Registry-Backed Policy Resolution

**Files:**
- Create: `core_matrix/app/services/runtime_features/policy_resolver.rb`
- Create: `core_matrix/app/services/runtime_features/policy_snapshot.rb`
- Modify: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `core_matrix/app/services/conversations/metadata/title_bootstrap_policy.rb`
- Modify: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Modify: `core_matrix/test/services/conversations/metadata/title_bootstrap_policy_test.rb`

**Step 1: Write failing lifecycle tests**

Add tests that expect:

- `prompt_compaction` policy is frozen into execution snapshot
- `title_bootstrap` policy is resolved live
- both rely on the shared platform resolver rather than feature-specific merge
  logic

**Step 2: Implement policy resolution**

Add a shared policy resolver that:

- merges workspace overrides over runtime defaults over built-in defaults
- validates against the schema-backed policy model
- returns typed or normalized policy objects

**Step 3: Implement lifecycle-aware policy access**

Add a small abstraction for:

- snapshot-frozen policy lookup
- live-resolved policy lookup

Then update existing feature-specific callers to depend on it.

**Step 4: Run targeted tests and make them green**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/conversations/metadata/title_bootstrap_policy_test.rb
```

Expected: the platform now owns policy resolution semantics.

### Task 4: Add Manifest `feature_contract` And Capability Resolution

**Files:**
- Modify: `agents/fenix/app/services/runtime/manifest/definition_package.rb`
- Modify: `agents/fenix/config/canonical_config.defaults.json`
- Modify: `agents/fenix/config/canonical_config.schema.json`
- Modify: `agents/fenix/test/integration/runtime_manifest_test.rb`
- Modify: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Modify: `core_matrix/app/services/tool_bindings/project_capability_snapshot.rb`
- Create: `core_matrix/app/services/runtime_features/capability_snapshot.rb`
- Create: `core_matrix/app/services/runtime_features/capability_resolver.rb`
- Modify: `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Modify: `core_matrix/test/services/runtime_features/capability_resolver_test.rb`

**Step 1: Add `feature_contract` to the manifest**

Update Fenix definition packaging so the manifest publishes a top-level
`feature_contract`.

Keep `tool_contract` for real tools only.

**Step 2: Freeze feature capabilities where required**

Add capability snapshot support in Core Matrix for snapshot-frozen features.

`prompt_compaction` should move to frozen capability projection.

**Step 3: Support live capability resolution**

Add a live capability resolver for best-effort metadata features such as
`title_bootstrap`.

**Step 4: Run targeted tests and make them green**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/integration/runtime_manifest_test.rb
```

Then run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/installations/register_bundled_agent_runtime_test.rb \
  test/services/runtime_features/capability_resolver_test.rb
```

Expected: feature capabilities are now a first-class manifest concept.

### Task 5: Add The `execute_feature` Control-Plane Contract

**Files:**
- Create: `core_matrix/app/services/runtime_features/feature_request_exchange.rb`
- Modify: `core_matrix/app/services/agent_control/create_agent_request.rb`
- Modify: `core_matrix/app/services/agent_control/serialize_mailbox_items.rb`
- Create: `agents/fenix/app/services/requests/execute_feature.rb`
- Modify: `agents/fenix/app/services/runtime/execute_mailbox_item.rb`
- Modify: `agents/fenix/test/services/runtime/execute_mailbox_item_test.rb`
- Modify: `core_matrix/test/services/runtime_features/feature_request_exchange_test.rb`

**Step 1: Write failing mailbox contract tests**

Add tests that expect:

- `execute_feature` is a distinct request kind
- feature request payloads carry `feature_key`, input payload, and context
- terminal reports normalize feature result vs feature failure cleanly

**Step 2: Implement the Core Matrix exchange**

Add `FeatureRequestExchange` that mirrors the existing agent request exchange
shape without pretending features are tools.

**Step 3: Implement the Fenix request handler**

Add `Requests::ExecuteFeature` and route mailbox execution accordingly.

**Step 4: Run targeted tests and make them green**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/runtime_features/feature_request_exchange_test.rb
```

Then run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/runtime/execute_mailbox_item_test.rb
```

Expected: internal runtime features now have a dedicated control-plane path.

### Task 6: Build The Shared Feature Orchestration Layer

**Files:**
- Create: `core_matrix/app/services/runtime_features/registry.rb`
- Create: `core_matrix/app/services/runtime_features/invoke.rb`
- Create: `core_matrix/app/services/runtime_features/base_orchestrator.rb`
- Create: `core_matrix/app/services/runtime_features/result.rb`
- Create: `core_matrix/app/services/embedded_features/base.rb`
- Modify: `core_matrix/test/services/runtime_features/registry_test.rb`
- Modify: `core_matrix/test/services/runtime_features/invoke_test.rb`

**Step 1: Implement the registry**

Register the initial feature slices:

- `prompt_compaction`
- `title_bootstrap`

**Step 2: Implement shared invocation**

`RuntimeFeatures::Invoke` should:

- load the registry entry
- resolve policy
- resolve capability
- decide runtime vs embedded path
- handle fallback
- return a typed result object

**Step 3: Standardize fallback semantics**

Normalize runtime-side failures into platform failure codes and decide:

- skip
- fallback
- fail

through orchestrator policy rather than ad hoc rescue logic in every feature.

**Step 4: Run targeted tests and make them green**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/runtime_features/registry_test.rb \
  test/services/runtime_features/invoke_test.rb
```

Expected: the platform can now invoke any registered feature consistently.

### Task 7: Migrate `prompt_compaction` Onto The Platform

**Files:**
- Modify: `core_matrix/app/services/provider_execution/prompt_compaction_policy.rb`
- Modify: `core_matrix/app/services/provider_execution/prompt_budget_guard.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Modify: `core_matrix/docs/plans/2026-04-14-prompt-budget-guard-design.md`
- Modify: `core_matrix/docs/plans/2026-04-14-prompt-budget-guard-implementation.md`
- Modify: `core_matrix/test/services/provider_execution/**`

**Step 1: Re-express prompt compaction as a platform slice**

Replace feature-specific policy/capability plumbing with platform calls.

**Step 2: Add runtime and embedded executors**

Prompt compaction should become a feature orchestrator plus:

- runtime executor
- embedded executor

**Step 3: Remove the internal tool-shaped assumptions**

Prompt compaction should no longer depend on `compact_context` being treated as
an ordinary tool.

**Step 4: Run targeted tests and make them green**

Run the prompt-budget slice tests plus platform tests.

Expected: prompt compaction now depends on shared platform primitives only.

### Task 8: Migrate `title_bootstrap` Onto The Platform

**Files:**
- Modify: `core_matrix/app/services/conversations/metadata/generate_bootstrap_title.rb`
- Modify: `core_matrix/app/services/conversations/metadata/runtime_bootstrap_title.rb`
- Modify: `core_matrix/app/jobs/conversations/metadata/bootstrap_title_job.rb`
- Modify: `core_matrix/docs/plans/2026-04-14-conversation-title-bootstrap-design.md`
- Modify: `core_matrix/docs/plans/2026-04-14-conversation-title-bootstrap-implementation.md`
- Modify: `core_matrix/test/services/conversations/metadata/**`
- Modify: `core_matrix/test/jobs/conversations/metadata/bootstrap_title_job_test.rb`

**Step 1: Re-express title bootstrap as a platform slice**

Replace feature-specific policy/capability probing with shared platform
resolution.

**Step 2: Preserve live lifecycle semantics**

Make sure title bootstrap uses the shared platform while still resolving live
policy and live capability at job execution time.

**Step 3: Run targeted tests and make them green**

Run the title-bootstrap slice tests plus platform tests.

Expected: title bootstrap uses the same platform without inheriting prompt
compaction’s snapshot-frozen semantics.

### Task 9: Remove Legacy Internal-Feature Paths And Verify End-To-End

**Files:**
- Modify as needed: legacy `WorkspaceFeatures::*` services
- Modify as needed: legacy feature-specific runtime-tool plumbing
- Modify: relevant docs under `core_matrix/docs/plans/`

**Step 1: Remove or retire legacy abstractions**

Delete or collapse transitional code that is superseded by the new platform.

**Step 2: Run focused verification**

Run the platform tests, prompt-budget slice tests, and title-bootstrap slice
tests together.

**Step 3: Run full verification required by repo policy**

From `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare
bin/rails test
bin/rails test:system
```

If Fenix code changed:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare
bin/rails test
```

Then from the repo root:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

Expected:

- platform tests pass
- prompt compaction and title bootstrap both pass on top of the new platform
- acceptance-critical turn behavior remains correct

### Task 10: Finalize Documentation

**Files:**
- Modify: `core_matrix/docs/plans/2026-04-14-runtime-feature-platform-design.md`
- Modify: `core_matrix/docs/plans/2026-04-14-runtime-feature-platform-implementation.md`
- Modify: platform-dependent feature-slice docs as needed

**Step 1: Reconcile plan vs shipped code**

If naming changed during implementation, update all planning docs to match the
final platform vocabulary consistently:

- `feature_contract`
- `execute_feature`
- policy schema namespace
- lifecycle names
- strategy enum

**Step 2: Commit**

```bash
git add \
  core_matrix/docs/plans/2026-04-14-runtime-feature-platform-design.md \
  core_matrix/docs/plans/2026-04-14-runtime-feature-platform-implementation.md \
  core_matrix/docs/plans/2026-04-14-prompt-budget-guard-design.md \
  core_matrix/docs/plans/2026-04-14-prompt-budget-guard-implementation.md \
  core_matrix/docs/plans/2026-04-14-conversation-title-bootstrap-design.md \
  core_matrix/docs/plans/2026-04-14-conversation-title-bootstrap-implementation.md
git commit -m "docs: introduce runtime feature platform plans"
```
