# Runtime Feature Platform Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current ad hoc internal-feature infrastructure with a
shared runtime feature platform that provides schema-first workspace policy,
manifest-driven capability discovery, direct or workflow-backed feature
execution, and embedded fallback execution for feature slices such as
`prompt_compaction` and `title_bootstrap`.

**Architecture:** `core_matrix` will introduce a feature registry, a
schema-first policy layer, a dedicated runtime `feature_contract`, a direct
`execute_feature` control-plane exchange for direct features, and a
workflow-intent materialization path for model-backed features. Feature slices
will then plug into the shared platform by registering their policy schema,
lifecycle rules, runtime capability key, optional consultation mode,
execution mode, orchestrator, and embedded executor.

**Tech Stack:** Ruby on Rails, Active Record, Minitest, JSON Schema, control
plane mailbox contracts, embedded agents/features, `agents/fenix`, EasyTalk or
a product-owned wrapper around it.

---

## Target Outcome

At the end of this plan:

- `workspace.config.features.*` is defined by a schema-first contract layer
- Fenix manifest exposes `feature_contract`
- Core Matrix supports both direct feature invocation and workflow-backed
  feature execution
- the platform can run a direct consultation phase before workflow-backed
  execution when a feature requires runtime guidance
- prompt compaction and title bootstrap use the same platform primitives
- Fenix is contractually required to implement `prompt_compaction`
- `title_bootstrap` remains runtime-optional and embedded-first by default
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
- feature definitions declare `execution_mode`
- feature definitions may declare `consultation_mode`
- feature capability resolution supports both snapshot-frozen and live modes
- `prompt_compaction` is marked runtime-required for Fenix
- `title_bootstrap` remains runtime-optional

**Step 2: Write failing invocation tests**

Add tests that expect:

- `runtime_first` uses runtime when capability is present
- `embedded_only` skips runtime entirely
- `runtime_required` fails when capability is absent
- runtime failure may fall back to embedded when the feature policy allows it
- workflow-backed features materialize workflow work instead of going through
  the direct feature exchange

**Step 3: Extend the Fenix manifest test**

Add failing expectations for:

- top-level `feature_contract`
- required `prompt_compaction` feature capability entry
- `prompt_compaction.consultation_mode = direct_required`
- no requirement that `title_bootstrap` capability be present

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

Use these initial defaults:

- `prompt_compaction.strategy = runtime_first`
- `title_bootstrap.strategy = embedded_only`

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

For this first pass:

- `prompt_compaction` must be present
- `prompt_compaction.consultation_mode = direct_required`
- `prompt_compaction.execution_mode = workflow_intent`
- `title_bootstrap` may be omitted

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

### Task 5: Add The Direct `execute_feature` Control-Plane Contract

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
- consultation-style requests can be issued without materializing workflow work

**Step 2: Implement the Core Matrix exchange**

Add `FeatureRequestExchange` that mirrors the existing agent request exchange
shape without pretending features are tools.

This direct exchange is only for Core Matrix-to-agent feature calls.

Agent-initiated infrastructure queries, such as OpenAI-style input-token
counting for candidate prompt payloads, should use authenticated AgentAPI
resource endpoints instead of `execute_feature`. Those APIs complement static
round-construction guidance but are not implemented through mailbox exchange.
Concrete counting endpoints remain feature-slice work, not platform work.

**Step 3: Implement the Fenix request handler**

Add `Requests::ExecuteFeature` and route mailbox execution accordingly.

Do **not** wire `prompt_compaction` through this path. `prompt_compaction`
will use workflow-intent execution in Task 7.

This task only establishes the direct feature exchange for features that are
actually direct, or for consultation phases that precede workflow-backed
execution.

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

The registry must carry runtime criticality explicitly:

- `prompt_compaction`: `runtime_requirement = required_on_fenix`
- `prompt_compaction`: `consultation_mode = direct_required`
- `title_bootstrap`: `runtime_requirement = optional`

**Step 2: Implement shared invocation**

`RuntimeFeatures::Invoke` should:

- load the registry entry
- resolve policy
- resolve capability
- run direct consultation when the registry entry requires it
- decide direct invocation vs workflow-backed execution vs embedded path
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

### Task 7: Migrate `prompt_compaction` Onto The Platform As A Workflow-Backed Feature

**Files:**
- Create: `agents/fenix/app/services/features/prompt_compaction/respond_to_consultation.rb`
- Create: `agents/fenix/app/services/features/prompt_compaction/execute_node.rb`
- Modify: `agents/fenix/app/services/requests/execute_feature.rb`
- Modify: `agents/fenix/app/services/runtime/manifest/definition_package.rb`
- Create: `agents/fenix/test/services/features/prompt_compaction/respond_to_consultation_test.rb`
- Create: `agents/fenix/test/services/features/prompt_compaction/execute_node_test.rb`
- Modify: `agents/fenix/test/services/runtime/execute_mailbox_item_test.rb`
- Modify: `core_matrix/app/services/provider_execution/prompt_compaction_policy.rb`
- Modify: `core_matrix/app/services/provider_execution/prompt_budget_guard.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Modify: `core_matrix/app/services/provider_execution/persist_turn_step_yield.rb`
- Modify: `core_matrix/app/services/workflows/re_enter_agent.rb`
- Modify: `core_matrix/docs/plans/2026-04-14-prompt-budget-guard-design.md`
- Modify: `core_matrix/docs/plans/2026-04-14-prompt-budget-guard-implementation.md`
- Modify: `core_matrix/test/services/provider_execution/**`

**Step 1: Re-express prompt compaction as a platform slice**

Replace feature-specific policy/capability plumbing with platform calls and a
workflow-backed execution path.

**Step 2: Implement the required Fenix runtime capability**

Implement `agents/fenix` prompt compaction as the first concrete
quality-critical runtime feature.

The algorithm should follow the shared lessons from Claude Code, Codex, and
OpenClaw:

- consume Core Matrix budget diagnostics instead of owning authoritative token
  estimation
- preserve the newest selected user input verbatim
- compact older transcript and imported context first
- prefer trimming or summarizing bulky tool outputs before touching recent user
  context
- return structured compaction guidance during the direct consultation phase
  (`skip`, `compact`, `reject`)
- execute the actual compaction inside the materialized workflow node

**Step 3: Materialize prompt compaction as workflow work**

Update Core Matrix so prompt compaction is represented as workflow work:

- `PromptBudgetGuard` is the sole trigger when preflight detects the request no
  longer fits or reserve quality is at risk
- Core Matrix first consults the runtime for compaction guidance
- if the consultation says to compact, Core Matrix materializes the workflow
  node
- provider-overflow recovery may also trigger the same consultation + node
  insertion once
- the intent materializes a dedicated workflow node
- the workflow node persists compaction artifacts and diagnostics
- `Workflows::ReEnterAgent` returns to the normal agent loop after the node
  completes

**Step 4: Add runtime and embedded executors on the platform side**

Prompt compaction should become a feature orchestrator plus:

- workflow-backed runtime executor
- embedded executor

Embedded execution is still required, but for Fenix it is a degraded fallback,
not the primary quality path.

**Step 5: Remove the internal tool-shaped assumptions**

Prompt compaction should no longer depend on `compact_context` being treated as
an ordinary tool.

Missing `prompt_compaction` support on Fenix should fail manifest/runtime
contract tests rather than being silently accepted as a healthy state.

**Step 6: Run targeted tests and make them green**

Run the prompt-budget slice tests plus platform tests and the new Fenix
feature-executor tests.

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

Keep runtime capability optional and preserve embedded-first default behavior.

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
- `workflow_intent`
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
