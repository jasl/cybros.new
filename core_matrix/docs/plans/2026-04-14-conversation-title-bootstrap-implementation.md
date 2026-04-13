# Conversation Title Bootstrap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move conversation title bootstrap out of the accepted-turn request
path by introducing an i18n placeholder title, asynchronous title-bootstrap
jobs, workspace-owned title-bootstrap config, and an embedded fallback title
agent.

**Architecture:** New conversations will persist an i18n placeholder title with
`title_source = "none"`. Manual user turn acceptance will stop synchronously
calling `Conversations::Metadata::BootstrapTitle` and will instead enqueue a
new `BootstrapTitleJob`. That job will resolve effective title-bootstrap policy
from `workspace.config` over runtime canonical config defaults, attempt
runtime-first title generation when available, fall back to an embedded title
agent, and finally fall back to the deterministic first-line heuristic.

**Tech Stack:** Ruby on Rails, Active Record, Minitest, Active Job, I18n,
embedded agents, workspace policy API, optional Fenix canonical config.

---

### Task 1: Lock Placeholder Title And Async Enqueue Contracts Before Rewiring

**Files:**
- Modify: `core_matrix/test/services/turns/accept_pending_user_turn_test.rb`
- Modify: `core_matrix/test/services/turns/start_user_turn_test.rb`
- Modify: `core_matrix/test/services/workbench/create_conversation_from_agent_test.rb`
- Modify: `core_matrix/test/services/workbench/send_message_test.rb`
- Modify: `core_matrix/test/requests/app_api/conversations_test.rb`
- Modify: `core_matrix/test/requests/app_api/conversation_messages_test.rb`

**Step 1: Write failing accepted-turn tests**

Update the generic turn-service tests so they expect:

- no synchronous `title_source = "bootstrap"` after manual user entry
- the conversation title remains the placeholder title immediately after
  `Turns::AcceptPendingUserTurn` or `Turns::StartUserTurn`
- generic turn services do **not** enqueue
  `Conversations::Metadata::BootstrapTitleJob`

Keep the existing pending workflow bootstrap assertions intact.

**Step 2: Write failing app-facing request tests**

Update the request tests so they expect:

- `POST /app_api/conversations` returns the placeholder conversation title
- `POST /app_api/conversations/:id/messages` preserves the current title
  without synchronously bootstrapping a new one
- app-facing/workbench entry points enqueue
  `Conversations::Metadata::BootstrapTitleJob` with
  `[conversation.public_id, turn.public_id]`
- mutation responses still expose `execution_status`, `accepted_at`, and
  `request_summary`

**Step 3: Run targeted tests and verify they fail**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/turns/accept_pending_user_turn_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/services/workbench/send_message_test.rb \
  test/requests/app_api/conversations_test.rb \
  test/requests/app_api/conversation_messages_test.rb
```

Expected: failures showing manual user entry still synchronously sets bootstrap
title metadata and does not enqueue the new title-bootstrap job.

### Task 2: Add The I18n Placeholder Title At Conversation Creation

**Files:**
- Modify: `core_matrix/app/services/conversations/creation_support.rb`
- Modify: `core_matrix/app/services/conversations/create_root.rb`
- Modify: `core_matrix/config/locales/en.yml`
- Create: `core_matrix/config/locales/zh-CN.yml`
- Modify: `core_matrix/test/services/conversations/create_root_test.rb`
- Modify: `core_matrix/test/models/conversation_test.rb`

**Step 1: Write failing create-root and model tests**

Extend the tests so they expect:

- new root conversations persist the placeholder title immediately
- `title_source` remains `"none"`
- `title_lock_state` remains `"unlocked"`

Also add a locale-backed expectation instead of hardcoding the placeholder text
in the test setup.

**Step 2: Add the i18n key and creation-time default**

Add locale entries:

- `conversations.defaults.untitled_title` in `en.yml`
- the corresponding `zh-CN` translation file entry

Update conversation creation so new conversations write the placeholder title
on create without changing `title_source`.

**Step 3: Run the targeted tests and verify they pass**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/create_root_test.rb \
  test/models/conversation_test.rb
```

Expected: newly created conversations now always have the placeholder title
with unchanged title-source semantics.

**Step 4: Commit**

```bash
git add \
  config/locales/en.yml \
  config/locales/zh-CN.yml \
  app/services/conversations/creation_support.rb \
  app/services/conversations/create_root.rb \
  test/services/conversations/create_root_test.rb \
  test/models/conversation_test.rb
git commit -m "feat: add placeholder conversation title"
```

### Task 3: Add Structured Workspace Config For Title Bootstrap

**Files:**
- Modify: `core_matrix/db/migrate/20260324090012_create_workspaces.rb`
- Modify: `core_matrix/db/schema.rb`
- Modify: `core_matrix/app/models/workspace.rb`
- Modify: `core_matrix/app/services/workspace_policies/upsert.rb`
- Modify: `core_matrix/app/services/app_surface/presenters/workspace_policy_presenter.rb`
- Modify: `core_matrix/app/controllers/app_api/workspaces/policies_controller.rb`
- Modify: `core_matrix/test/models/workspace_test.rb`
- Modify: `core_matrix/test/requests/app_api/workspace_policies_test.rb`
- Modify: `core_matrix/test/test_helper.rb`

**Step 1: Write failing workspace policy tests**

Extend workspace model and request tests so they expect:

- `workspaces.config` exists and is a hash
- `workspace_policy.features.title_bootstrap.enabled`
- `workspace_policy.features.title_bootstrap.mode`
- invalid title-bootstrap modes are rejected

Use the existing workspace policy endpoint instead of inventing a new API
surface.

**Step 2: Add `config` to `workspaces` and validate the shape**

Because this branch allows destructive migration edits, fold the new `config`
JSONB column directly into `20260324090012_create_workspaces.rb`.

Update `Workspace` so:

- `config` always validates as a hash
- title-bootstrap config normalization is centralized

Keep the shape generic so prompt-budget-guard can extend the same field later.

**Step 3: Wire policy upsert and presenter support**

Update:

- `WorkspacePolicies::Upsert`
- `WorkspacePolicyPresenter`
- `AppAPI::Workspaces::PoliciesController`

so the title-bootstrap policy can be shown and updated through the existing
policy endpoint.

Use these defaults when config is absent:

- `enabled: true`
- `mode: "runtime_first"`

**Step 4: Update test helpers**

Make shared workspace creation helpers produce a valid empty `config` hash by
default so later tests do not depend on silent fallback behavior.

**Step 5: Run the targeted tests and verify they pass**

Run:

```bash
bin/rails db:drop
rm db/schema.rb
bin/rails db:create
bin/rails db:migrate
bin/rails db:reset
bin/rails db:test:prepare
PARALLEL_WORKERS=1 bin/rails test \
  test/models/workspace_test.rb \
  test/requests/app_api/workspace_policies_test.rb
```

Expected: workspace policy round-trips the structured title-bootstrap config
and validates bad values correctly.

**Step 6: Commit**

```bash
git add \
  db/migrate/20260324090012_create_workspaces.rb \
  db/schema.rb \
  app/models/workspace.rb \
  app/services/workspace_policies/upsert.rb \
  app/services/app_surface/presenters/workspace_policy_presenter.rb \
  app/controllers/app_api/workspaces/policies_controller.rb \
  test/models/workspace_test.rb \
  test/requests/app_api/workspace_policies_test.rb \
  test/test_helper.rb
git commit -m "feat: add workspace title bootstrap policy"
```

### Task 4: Reserve Runtime Defaults In Fenix Canonical Config

**Files:**
- Modify: `agents/fenix/config/canonical_config.defaults.json`
- Modify: `agents/fenix/config/canonical_config.schema.json`
- Modify: `agents/fenix/test/integration/runtime_manifest_test.rb`
- Modify: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Modify: `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`

**Step 1: Write failing config-roundtrip tests**

Extend the Fenix manifest test and bundled runtime registration test so they
expect:

- `features.title_bootstrap.enabled`
- `features.title_bootstrap.mode`

to exist in the canonical config defaults and round-trip through bundled agent
registration.

**Step 2: Add the reserved canonical config shape**

Update the Fenix schema/defaults to include:

- `features.title_bootstrap.enabled`
- `features.title_bootstrap.mode`

with defaults aligned to the product direction:

- enabled
- `runtime_first`

Do not add runtime implementation behavior in this task.

**Step 3: Keep `core_matrix` bundled registration in sync**

Update bundled runtime registration fixtures so the packaged definition/config
shape round-trips the new metadata defaults.

**Step 4: Run the targeted tests and verify they pass**

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

Expected: the reserved runtime config shape is exposed, but no runtime title
generation behavior is required yet.

**Step 5: Commit**

```bash
git add \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/config/canonical_config.defaults.json \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/config/canonical_config.schema.json \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/runtime_manifest_test.rb \
  app/services/installations/register_bundled_agent_runtime.rb \
  test/services/installations/register_bundled_agent_runtime_test.rb
git commit -m "feat: reserve runtime title bootstrap config"
```

### Task 5: Add The Embedded Title Agent And Policy Resolution

**Files:**
- Create: `core_matrix/app/services/embedded_agents/conversation_title/invoke.rb`
- Modify: `core_matrix/app/services/embedded_agents/registry.rb`
- Create: `core_matrix/app/services/conversations/metadata/title_bootstrap_policy.rb`
- Create: `core_matrix/app/services/conversations/metadata/generate_bootstrap_title.rb`
- Create: `core_matrix/test/services/embedded_agents/conversation_title/invoke_test.rb`
- Create: `core_matrix/test/services/conversations/metadata/title_bootstrap_policy_test.rb`
- Create: `core_matrix/test/services/conversations/metadata/generate_bootstrap_title_test.rb`

**Step 1: Write failing policy and embedded-agent tests**

Add tests that expect:

- workspace config overrides agent canonical defaults
- the built-in fallback default is `enabled: true`, `mode: runtime_first`
- the embedded title agent returns a single candidate title
- embedded title generation falls back to the deterministic heuristic when the
  modeled path is unavailable

**Step 2: Implement policy resolution**

Add `TitleBootstrapPolicy` that resolves:

1. `workspace.config.features.title_bootstrap`
2. runtime canonical config default
3. built-in fallback

Normalize invalid or missing values early.

**Step 3: Implement the embedded title generator**

Add a dedicated embedded agent and small orchestration service that:

- accepts conversation + message context
- uses a short, title-specific prompt
- keeps output single-line and under 80 characters
- falls back to the deterministic first-line heuristic when the modeled path is
  unavailable or returns unusable content

Keep the current heuristic logic reusable rather than duplicating title
derivation in multiple places.

**Step 4: Run the targeted tests and verify they pass**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/embedded_agents/conversation_title/invoke_test.rb \
  test/services/conversations/metadata/title_bootstrap_policy_test.rb \
  test/services/conversations/metadata/generate_bootstrap_title_test.rb
```

Expected: policy resolution and embedded fallback title generation are now
covered and green.

**Step 5: Commit**

```bash
git add \
  app/services/embedded_agents/conversation_title/invoke.rb \
  app/services/embedded_agents/registry.rb \
  app/services/conversations/metadata/title_bootstrap_policy.rb \
  app/services/conversations/metadata/generate_bootstrap_title.rb \
  test/services/embedded_agents/conversation_title/invoke_test.rb \
  test/services/conversations/metadata/title_bootstrap_policy_test.rb \
  test/services/conversations/metadata/generate_bootstrap_title_test.rb
git commit -m "feat: add embedded conversation title bootstrap"
```

### Task 6: Add The Async Bootstrap Job And Remove Synchronous Title Writes

**Files:**
- Create: `core_matrix/app/jobs/conversations/metadata/bootstrap_title_job.rb`
- Modify: `core_matrix/app/services/turns/accept_pending_user_turn.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/app/services/workbench/create_conversation_from_agent.rb`
- Modify: `core_matrix/app/services/workbench/send_message.rb`
- Modify: `core_matrix/app/services/conversations/metadata/bootstrap_title.rb`
- Modify: `core_matrix/test/services/turns/accept_pending_user_turn_test.rb`
- Modify: `core_matrix/test/services/turns/start_user_turn_test.rb`
- Modify: `core_matrix/test/services/workbench/create_conversation_from_agent_test.rb`
- Modify: `core_matrix/test/services/workbench/send_message_test.rb`
- Create: `core_matrix/test/jobs/conversations/metadata/bootstrap_title_job_test.rb`
- Modify: `core_matrix/test/services/conversations/metadata/bootstrap_title_test.rb`

**Step 1: Write failing job tests**

Create `bootstrap_title_job_test.rb` with cases for:

- first manual user turn upgrades the placeholder title asynchronously
- later turns do not overwrite an existing title
- user-locked titles are preserved
- ineligible conversations remain unchanged

**Step 2: Remove synchronous title bootstrap from turn acceptance**

Delete the synchronous `Conversations::Metadata::BootstrapTitle.call(...)`
invocations from:

- `Turns::AcceptPendingUserTurn`
- `Turns::StartUserTurn`

Keep all other turn-entry behavior unchanged.

**Step 3: Enqueue the async job from manual user-entry surfaces**

After successful manual user turn acceptance, enqueue
`Conversations::Metadata::BootstrapTitleJob` with public ids needed to reload:

- `conversation.public_id`
- `turn.public_id`

Do this from the app-facing/workbench entry points, not from generic turn
services used by unrelated non-manual paths.

**Step 4: Rework `BootstrapTitle` into a deterministic fallback helper**

Update `Conversations::Metadata::BootstrapTitle` so it becomes the reusable
last-resort heuristic used by:

- the embedded title generator
- the async bootstrap job

It should no longer represent the primary synchronous path.

**Step 5: Implement the job gate and persistence rules**

Inside the job:

- reload conversation and target turn
- find the selected input message or first manual user message
- lock the conversation
- ensure:
  - title is still the placeholder
  - `title_source == "none"`
  - `title_lock_state == "unlocked"`
  - the turn is still the first manual user turn
- resolve the effective title-bootstrap policy
- try runtime-first if policy allows and runtime support exists
- otherwise fall back to the embedded generator
- persist only when the title is still eligible

If generation fails, leave the placeholder title unchanged and log the failure.

**Step 6: Run the targeted tests and verify they pass**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/turns/accept_pending_user_turn_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/services/workbench/send_message_test.rb \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb \
  test/services/conversations/metadata/bootstrap_title_test.rb
```

Expected: accepted-turn paths stay light, the job is enqueued, and title
bootstrap upgrades happen asynchronously.

**Step 7: Commit**

```bash
git add \
  app/jobs/conversations/metadata/bootstrap_title_job.rb \
  app/services/turns/accept_pending_user_turn.rb \
  app/services/turns/start_user_turn.rb \
  app/services/workbench/create_conversation_from_agent.rb \
  app/services/workbench/send_message.rb \
  app/services/conversations/metadata/bootstrap_title.rb \
  test/services/turns/accept_pending_user_turn_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/services/workbench/send_message_test.rb \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb \
  test/services/conversations/metadata/bootstrap_title_test.rb
git commit -m "feat: bootstrap conversation titles asynchronously"
```

### Task 7: Add Optional Runtime-First Attempt Without Making It Mandatory

**Files:**
- Create: `core_matrix/app/services/conversations/metadata/runtime_bootstrap_title.rb`
- Modify: `core_matrix/app/services/conversations/metadata/generate_bootstrap_title.rb`
- Modify: `core_matrix/test/services/conversations/metadata/generate_bootstrap_title_test.rb`
- Create: `core_matrix/test/services/conversations/metadata/runtime_bootstrap_title_test.rb`

**Step 1: Write failing runtime-attempt tests**

Add tests that expect:

- `runtime_first` mode tries the runtime path first
- mailbox work is attempted only when the frozen capability snapshot advertises
  the runtime title tool
- missing runtime support does not fail the overall title bootstrap
- `unsupported_tool` from the agent request path does not fail the overall
  title bootstrap
- runtime failure falls back to embedded generation

Keep these tests narrowly scoped so this pass does not force any concrete Fenix
implementation.

**Step 2: Implement a capability probe plus graceful fallback over the existing mailbox contract**

Add a small runtime strategy service that can:

- inspect the frozen agent capability snapshot / tool surface for the current
  turn or conversation context
- decide whether runtime title bootstrap is supported by checking for a
  dedicated agent-owned title tool in that frozen surface
- use the existing `execute_tool` mailbox path when the tool is present
- return `nil` or a failure result without raising when the capability is
  absent
- treat `unsupported_tool`, timeout, and request failure as graceful fallback
  cases rather than terminal errors

Do not invent a second feature-support protocol for this pass. The runtime
path should reuse the existing manifest/tool-contract + `execute_tool`
contract. The core requirement is that the orchestration path stays
runtime-first when possible and safely falls back otherwise.

**Step 3: Run the targeted tests and verify they pass**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/metadata/runtime_bootstrap_title_test.rb \
  test/services/conversations/metadata/generate_bootstrap_title_test.rb
```

Expected: runtime-first mode is optional and failure-tolerant.

### Task 8: Update Export Fallbacks And Final Verification

**Files:**
- Modify: `core_matrix/app/services/conversation_exports/render_transcript_html.rb`
- Modify: `core_matrix/app/services/conversation_exports/render_transcript_markdown.rb`
- Modify: `core_matrix/test/services/conversation_exports/build_manifest_test.rb`
- Modify: `core_matrix/test/services/conversation_exports/build_conversation_payload_test.rb`
- Modify as needed: `core_matrix/test/requests/app_api/conversations/metadata_test.rb`

**Step 1: Centralize placeholder-title expectations**

Update export/read tests so they understand the new distinction:

- placeholder title with `title_source = "none"`
- asynchronously bootstrapped title with `title_source = "bootstrap"`

Where exports currently hardcode `"Untitled conversation"`, switch them to the
same I18n-backed fallback logic or shared helper used by the product.

**Step 2: Run focused metadata/export verification**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/requests/app_api/conversations/metadata_test.rb \
  test/services/conversation_exports/build_manifest_test.rb \
  test/services/conversation_exports/build_conversation_payload_test.rb \
  test/services/conversations/metadata/bootstrap_title_test.rb \
  test/services/conversations/metadata/generate_field_test.rb \
  test/services/conversations/metadata/regenerate_test.rb \
  test/services/conversations/metadata/agent_update_test.rb \
  test/services/conversations/metadata/user_edit_test.rb
```

Expected: metadata and export surfaces now reflect the placeholder-versus-
bootstrap distinction correctly.

**Step 3: Run broad verification**

Run from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
bin/rails db:test:prepare
PARALLEL_WORKERS=1 bin/rails test \
  test/services/turns/accept_pending_user_turn_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/services/workbench/send_message_test.rb \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb \
  test/services/conversations/metadata/bootstrap_title_test.rb \
  test/services/conversations/metadata/generate_bootstrap_title_test.rb \
  test/services/embedded_agents/conversation_title/invoke_test.rb \
  test/requests/app_api/conversations_test.rb \
  test/requests/app_api/conversation_messages_test.rb \
  test/requests/app_api/workspace_policies_test.rb \
  test/models/workspace_test.rb
```

Then run:

```bash
bin/rails test
bin/rubocop -f github
```

Expected: all targeted suites and the full Rails test suite pass, and RuboCop
stays green for the touched files.

### Task 9: Optional Follow-Up If Fenix Summary-Title Is Implemented

**Files:**
- Modify as needed: `agents/fenix/app/**`
- Modify as needed: `agents/fenix/test/**`
- Modify as needed: `core_matrix/app/services/conversations/metadata/runtime_bootstrap_title.rb`
- Modify as needed: `core_matrix/test/services/conversations/metadata/runtime_bootstrap_title_test.rb`

**Step 1: Only proceed if runtime implementation is explicitly desired**

This task is optional in this pass.

If runtime summary-title is not implemented yet, stop after Task 8.

**Step 2: Add the narrow runtime capability**

If desired, implement a very small Fenix-side title-summary capability that:

- is advertised explicitly in the Fenix `tool_contract`
- is executed through `Requests::ExecuteTool`
- accepts first user message / light transcript context
- returns a candidate title only
- follows the canonical config defaults already added in Task 4

If the capability is declared but not actually implemented, Fenix should return
the normal agent-tool failure payload such as `unsupported_tool`; `core_matrix`
should already interpret that as a fallback signal rather than a fatal title
bootstrap failure.

**Step 3: Re-run cross-repo verification**

Run the relevant Fenix tests plus the `core_matrix` runtime-fallback tests
again.

Expected: runtime-first mode now uses a real runtime title path when available,
but embedded fallback still protects the product.
