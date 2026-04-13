# Workspace Feature Policy Orthogonalization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Correct the runtime/workspace/execution-policy contract by moving
feature policy to `features.*`, exposing explicit workspace `features`,
keeping title bootstrap as live metadata post-processing, and preparing prompt
compaction to freeze effective policy per turn.

**Architecture:** This is a destructive cutover. `metadata.title_bootstrap`
will be removed from both Fenix canonical config and CoreMatrix workspace
policy. `Workspace` will gain a shared feature-schema layer, workspace policy
API will expose `features`, and title-bootstrap resolution will switch to
`features.title_bootstrap`. Prompt-compaction docs/tests will be updated to use
`features.prompt_compaction`, while the actual freezing work lands later with
the prompt-budget guard implementation.

**Tech Stack:** Ruby on Rails, Active Record, Minitest, JSON schema-style hash
validation, Fenix canonical config, CoreMatrix workspace policy API, docs in
`docs/plans`.

---

### Task 1: Lock The New `features` Contract Before Rewiring Production Code

**Files:**
- Modify: `core_matrix/test/models/workspace_test.rb`
- Modify: `core_matrix/test/requests/app_api/workspace_policies_test.rb`
- Modify: `core_matrix/test/services/conversations/metadata/title_bootstrap_policy_test.rb`
- Modify: `core_matrix/test/services/conversations/metadata/generate_bootstrap_title_test.rb`
- Modify: `core_matrix/test/jobs/conversations/metadata/bootstrap_title_job_test.rb`
- Modify: `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Modify: `agents/fenix/test/integration/runtime_manifest_test.rb`

**Step 1: Write failing workspace policy surface tests**

Update request tests so they expect:

- `workspace_policy.features.prompt_compaction`
- `workspace_policy.features.title_bootstrap`
- no `workspace_policy.metadata`

Also update request-update tests so they submit `features`, not `metadata`.

**Step 2: Write failing workspace model tests**

Update `workspace_test.rb` so it expects:

- `workspace.config["features"]` to be the feature container
- `workspace.feature_config("title_bootstrap")`
- `workspace.feature_config("prompt_compaction")`
- invalid `features.*` values to be rejected

Do not keep any assertion on `metadata.title_bootstrap`.

**Step 3: Write failing title-bootstrap policy tests**

Update title-bootstrap policy/job tests so they expect:

- policy resolution from `features.title_bootstrap`
- a live workspace policy change before job execution to affect whether the job
  upgrades the title

This locks the intended live-read semantics for title bootstrap.

**Step 4: Write failing runtime-default config tests**

Update the Fenix manifest and bundled-runtime registration tests so they expect:

- `default_canonical_config.features.title_bootstrap`
- `default_canonical_config.features.prompt_compaction`

Remove assertions against `metadata.title_bootstrap`.

**Step 5: Run the targeted tests and verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/integration/runtime_manifest_test.rb
```

Then run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/models/workspace_test.rb \
  test/requests/app_api/workspace_policies_test.rb \
  test/services/conversations/metadata/title_bootstrap_policy_test.rb \
  test/services/conversations/metadata/generate_bootstrap_title_test.rb \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb \
  test/services/installations/register_bundled_agent_runtime_test.rb
```

Expected: failures showing production code still projects `metadata` and still
reads `metadata.title_bootstrap`.

### Task 2: Cut Runtime Defaults And Workspace Policy Shape To `features.*`

**Files:**
- Modify: `agents/fenix/config/canonical_config.defaults.json`
- Modify: `agents/fenix/config/canonical_config.schema.json`
- Modify: `agents/fenix/test/integration/runtime_manifest_test.rb`
- Modify: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Modify: `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Modify: `core_matrix/test/test_helper.rb`

**Step 1: Move Fenix defaults from `metadata` to `features`**

Rewrite canonical config defaults/schema so they define:

- `features.title_bootstrap`
- `features.prompt_compaction`

For `prompt_compaction`, use:

- `enabled`
- `mode`

Do not allow `mode = "disabled"`.

**Step 2: Update bundled-runtime registration and fixtures**

Make sure `RegisterBundledAgentRuntime` and shared helpers persist the same
`features.*` shape into `default_canonical_config`.

There should be no silent fallback to the old `metadata` path anywhere in
registration or test setup.

**Step 3: Run the targeted tests and verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/integration/runtime_manifest_test.rb
```

Then run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/installations/register_bundled_agent_runtime_test.rb
```

Expected: runtime defaults now expose `features.*` only.

**Step 4: Commit**

```bash
git add \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/config/canonical_config.defaults.json \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/config/canonical_config.schema.json \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/runtime_manifest_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/installations/register_bundled_agent_runtime.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/test_helper.rb
git commit -m "refactor: move runtime feature defaults under features"
```

### Task 3: Add A Generic Workspace Feature Schema Layer

**Files:**
- Create: `core_matrix/app/services/workspace_features/schema.rb`
- Create: `core_matrix/app/services/workspace_features/resolver.rb`
- Modify: `core_matrix/app/models/workspace.rb`
- Modify: `core_matrix/test/models/workspace_test.rb`

**Step 1: Introduce shared defaults and validation**

Implement a small shared schema layer that:

- defines supported feature defaults
- normalizes arbitrary hashes into string-keyed feature hashes
- validates `enabled` and `mode`
- rejects unsupported mode values early

Use named constants so both workspace validation and policy resolution share
one source of truth.

**Step 2: Rework `Workspace` to use the shared schema**

Update `Workspace` so it exposes:

- `features_config`
- `feature_config(name)`
- generic `features_config_must_be_valid`

Remove feature-specific `title_bootstrap` validation branches and helpers.

Keep `config` as the persisted JSONB container, but stop treating `metadata` as
its policy root.

**Step 3: Run the targeted tests and verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test test/models/workspace_test.rb
```

Expected: workspace model now validates a generic `features` container and no
test references `metadata.title_bootstrap`.

**Step 4: Commit**

```bash
git add \
  app/services/workspace_features/schema.rb \
  app/services/workspace_features/resolver.rb \
  app/models/workspace.rb \
  test/models/workspace_test.rb
git commit -m "refactor: add shared workspace feature schema"
```

### Task 4: Cut Workspace Policy API From `metadata` To `features`

**Files:**
- Modify: `core_matrix/app/services/workspace_policies/upsert.rb`
- Modify: `core_matrix/app/services/app_surface/presenters/workspace_policy_presenter.rb`
- Modify: `core_matrix/app/controllers/app_api/workspaces/policies_controller.rb`
- Modify: `core_matrix/test/requests/app_api/workspace_policies_test.rb`

**Step 1: Update request/controller contract**

Make the controller:

- accept `features`
- preserve old fields unrelated to feature policy
- stop accepting `metadata`

This is a destructive cutover. Reject old callers through test updates rather
than compatibility logic.

**Step 2: Update presenter contract**

Make `WorkspacePolicyPresenter` return:

- `features`

and remove `metadata` from the presented payload.

**Step 3: Update upsert logic**

Make `WorkspacePolicies::Upsert`:

- accept `features:`
- normalize/validate through `WorkspaceFeatures::Schema`
- merge into `workspace.config["features"]`

Do not keep special-case `validate_title_bootstrap_config!`.

**Step 4: Run the targeted tests and verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test test/requests/app_api/workspace_policies_test.rb
```

Expected: workspace policy API is now explicit and only uses `features`.

**Step 5: Commit**

```bash
git add \
  app/services/workspace_policies/upsert.rb \
  app/services/app_surface/presenters/workspace_policy_presenter.rb \
  app/controllers/app_api/workspaces/policies_controller.rb \
  test/requests/app_api/workspace_policies_test.rb
git commit -m "refactor: expose workspace features policy explicitly"
```

### Task 5: Rewire Title Bootstrap To `features.title_bootstrap`

**Files:**
- Modify: `core_matrix/app/services/conversations/metadata/title_bootstrap_policy.rb`
- Modify: `core_matrix/app/services/conversations/metadata/generate_bootstrap_title.rb`
- Modify: `core_matrix/app/jobs/conversations/metadata/bootstrap_title_job.rb`
- Modify: `core_matrix/test/services/conversations/metadata/title_bootstrap_policy_test.rb`
- Modify: `core_matrix/test/services/conversations/metadata/generate_bootstrap_title_test.rb`
- Modify: `core_matrix/test/jobs/conversations/metadata/bootstrap_title_job_test.rb`

**Step 1: Resolve title-bootstrap policy from `features`**

Change `TitleBootstrapPolicy` so it reads:

- workspace override from `workspace.config.features.title_bootstrap`
- runtime default from
  `agent_definition_version.default_canonical_config.features.title_bootstrap`

Keep the resolution live at job execution time.

**Step 2: Lock the intended live-read semantics**

Add or update tests so they prove:

- changing workspace title-bootstrap policy before job execution changes job
  behavior
- no execution snapshot is consulted for title-bootstrap policy

This makes the metadata-post-processing boundary explicit.

**Step 3: Run the targeted tests and verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/metadata/title_bootstrap_policy_test.rb \
  test/services/conversations/metadata/generate_bootstrap_title_test.rb \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb
```

Expected: title bootstrap now resolves only from `features.title_bootstrap`.

**Step 4: Commit**

```bash
git add \
  app/services/conversations/metadata/title_bootstrap_policy.rb \
  app/services/conversations/metadata/generate_bootstrap_title.rb \
  app/jobs/conversations/metadata/bootstrap_title_job.rb \
  test/services/conversations/metadata/title_bootstrap_policy_test.rb \
  test/services/conversations/metadata/generate_bootstrap_title_test.rb \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb
git commit -m "refactor: resolve title bootstrap from workspace features"
```

### Task 6: Update Prompt-Compaction Contract Docs And Freeze Tests

**Files:**
- Modify: `core_matrix/docs/plans/2026-04-14-prompt-budget-guard-design.md`
- Modify: `core_matrix/docs/plans/2026-04-14-prompt-budget-guard-implementation.md`
- Modify: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Create: `core_matrix/app/services/provider_execution/prompt_compaction_policy.rb`

**Step 1: Correct the prompt-compaction contract in docs**

Update both prompt-budget-guard documents so they state:

- runtime defaults live under `features.prompt_compaction`
- workspace overrides live under `workspace.config.features.prompt_compaction`
- effective policy is frozen into the execution snapshot
- `enabled: false` is the only disable switch

Remove any remaining mention of `metadata.prompt_compaction` or
`mode = "disabled"`.

**Step 2: Write failing snapshot-freeze tests**

Update `build_execution_snapshot_test.rb` so it expects:

- effective prompt-compaction policy is included in the snapshot/provider
  context
- workspace config changes after snapshot creation do not affect the already
  frozen policy

These tests should fail until actual snapshot freezing is implemented.

**Step 3: Add the shared prompt-compaction policy resolver stub**

Introduce `ProviderExecution::PromptCompactionPolicy` as the shared place for:

- default normalization
- workspace override resolution
- runtime-default merge

This task may stop at the resolver and failing freeze tests if the branch wants
to keep the actual prompt-budget guard implementation separate.

**Step 4: Run the targeted tests and verify status**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test test/services/workflows/build_execution_snapshot_test.rb
```

Expected:

- if this task only lands docs plus failing tests, failures should be exactly
  about missing frozen prompt-compaction policy
- if the branch chooses to implement the freeze immediately, the test should
  pass and the implementation should be folded into this task

**Step 5: Commit**

If this task lands only docs and failing tests:

```bash
git add \
  docs/plans/2026-04-14-prompt-budget-guard-design.md \
  docs/plans/2026-04-14-prompt-budget-guard-implementation.md \
  test/services/workflows/build_execution_snapshot_test.rb \
  app/services/provider_execution/prompt_compaction_policy.rb
git commit -m "test: lock frozen prompt compaction policy contract"
```

If the branch also lands the snapshot freeze implementation now, adjust the
commit message accordingly.

### Task 7: Full Verification

**Files:**
- Verify only

**Step 1: Prepare test databases**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails db:test:prepare
```

**Step 2: Run product verifications**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails test
bin/rails test:system
```

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails test
```

Expected: both projects remain green with the new `features.*` contract.

**Step 3: Final commit if Task 6 implemented more than docs/tests**

If Task 6 included the actual snapshot-freeze implementation, commit any
remaining production changes with a focused message.

**Step 4: Document residual risk**

Before closing, explicitly note whether:

- prompt-compaction freezing has actually landed, or
- only the corrected contract and failing tests were put in place for the next
  prompt-budget-guard pass

This branch must not leave that ambiguity unstated.
