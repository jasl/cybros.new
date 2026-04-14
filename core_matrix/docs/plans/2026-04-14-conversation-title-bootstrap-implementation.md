# Title Bootstrap Feature Slice Follow-Up Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

## Status

This is a follow-up plan, not a greenfield implementation plan.

`title_bootstrap` already has working product behavior in `core_matrix`:

- placeholder conversation titles
- async enqueue after manual user entry
- `BootstrapTitleJob`
- eligibility gating
- workspace policy
- runtime-first shape with embedded and heuristic fallback

This plan covers only the remaining migration work needed to align the existing
slice with the shared runtime feature platform defined in:

- [runtime-feature-platform-design.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-14-runtime-feature-platform-design.md)
- [runtime-feature-platform-implementation.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-14-runtime-feature-platform-implementation.md)

Complete platform Tasks 1 through 6 first. Do not reimplement placeholder
title flow, accepted-turn enqueue, or title-bootstrap eligibility from scratch.

## Goal

Migrate the existing `title_bootstrap` implementation onto the shared runtime
feature platform without changing its product semantics.

## Architecture

The already-landed slice behavior remains in place. The follow-up replaces only
the transitional contracts around it:

- `enabled + mode` policy shape moves to shared `strategy`
- runtime support probing moves from `protocol_methods` to `feature_contract`
- runtime invocation moves from slice-local stubs to `execute_feature`
- embedded execution moves from legacy embedded-agent plumbing to the shared
  embedded-feature boundary

The long-term default should be `features.title_bootstrap.strategy =
embedded_only`. Runtime title generation remains optional rather than quality
critical.

Unlike `prompt_compaction`, this follow-up stays on the direct runtime-feature
path. It does not participate in the request-preparation workflow-node model.

## Tech Stack

Ruby on Rails, Active Record, Active Job, Minitest, workspace feature policy
schema layer, runtime feature registry, Fenix manifest `feature_contract`,
control-plane `execute_feature`, embedded feature executors.

---

## Already Implemented Baseline

These behaviors are already shipped and should be treated as regression
constraints:

- placeholder title at conversation creation
- asynchronous enqueue after first manual user turn
- best-effort job execution
- eligibility gate before title writes
- embedded modeled-title generation
- heuristic last-resort fallback

The follow-up tasks below should only touch the migration delta.

### Task 1: Lock The Migration Delta With Regression Tests

**Files:**
- Modify: `core_matrix/test/services/conversations/metadata/title_bootstrap_policy_test.rb`
- Modify: `core_matrix/test/services/conversations/metadata/runtime_bootstrap_title_test.rb`
- Modify: `core_matrix/test/services/conversations/metadata/generate_bootstrap_title_test.rb`
- Modify: `core_matrix/test/jobs/conversations/metadata/bootstrap_title_job_test.rb`

**Step 1: Add failing policy-shape migration tests**

Add expectations that describe the target platform contract:

- effective title-bootstrap policy resolves from the shared `strategy` shape
- live resolution still applies at job execution time
- the slice no longer depends on `enabled + mode` as its long-term contract

**Step 2: Add failing runtime-capability migration tests**

Extend `runtime_bootstrap_title_test.rb` so it expects:

- runtime support is resolved from `feature_contract`
- `protocol_methods` is no longer the capability source of truth
- runtime invocation is feature-oriented, not slice-local stub logic

**Step 3: Add failing orchestration-boundary tests**

Extend `generate_bootstrap_title_test.rb` and
`bootstrap_title_job_test.rb` so they expect:

- live policy and live capability are resolved through the shared platform
- embedded fallback still occurs when runtime is absent or fails and strategy
  allows it
- `runtime_required` leaves the placeholder title intact without embedded
  fallback

**Step 4: Run the targeted tests and verify they fail**

From `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/metadata/title_bootstrap_policy_test.rb \
  test/services/conversations/metadata/runtime_bootstrap_title_test.rb \
  test/services/conversations/metadata/generate_bootstrap_title_test.rb \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb
```

Expected: failures show the current implementation still depends on the
transitional policy shape, protocol-method capability probing, and slice-local
orchestration.

### Task 2: Migrate The Slice To The Shared Policy Contract

**Files:**
- Modify: `core_matrix/app/services/conversations/metadata/title_bootstrap_policy.rb`
- Modify: `core_matrix/app/services/conversations/metadata/generate_bootstrap_title.rb`
- Modify: `core_matrix/test/services/conversations/metadata/title_bootstrap_policy_test.rb`
- Modify: `core_matrix/test/services/conversations/metadata/generate_bootstrap_title_test.rb`

**Step 1: Replace transitional shape assumptions**

Update the slice so it consumes the platform policy contract:

- `features.title_bootstrap.strategy`

Stop treating `enabled + mode` as the slice-owned long-term API.

**Step 2: Preserve live resolution**

Keep title bootstrap live-resolved at job execution time. Do not freeze policy
into execution snapshots.

**Step 3: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/metadata/title_bootstrap_policy_test.rb \
  test/services/conversations/metadata/generate_bootstrap_title_test.rb
```

Expected: the slice now reads the shared policy contract without regressing its
live-read behavior.

### Task 3: Migrate Runtime Capability And Invocation To The Feature Platform

**Files:**
- Modify: `core_matrix/app/services/conversations/metadata/runtime_bootstrap_title.rb`
- Modify: `core_matrix/app/services/conversations/metadata/generate_bootstrap_title.rb`
- Modify: `core_matrix/test/services/conversations/metadata/runtime_bootstrap_title_test.rb`
- Modify: `core_matrix/test/services/conversations/metadata/generate_bootstrap_title_test.rb`

**Step 1: Replace `protocol_methods` probing**

Update runtime title bootstrap so it no longer checks `protocol_methods` as the
capability source of truth.

Use live capability resolution from the shared feature platform instead.

**Step 2: Route runtime execution through `execute_feature`**

Replace the current runtime stub path with feature-platform invocation for:

- `feature_key = "title_bootstrap"`

Keep the slice-specific shaping of input and normalization of returned title.

**Step 3: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/metadata/runtime_bootstrap_title_test.rb \
  test/services/conversations/metadata/generate_bootstrap_title_test.rb
```

Expected: runtime title generation now uses the shared feature capability and
invocation contracts.

### Task 4: Migrate Embedded Execution To The Shared Feature Boundary

**Files:**
- Create: `core_matrix/app/services/embedded_features/title_bootstrap/invoke.rb`
- Modify: `core_matrix/app/services/conversations/metadata/generate_bootstrap_title.rb`
- Modify: `core_matrix/test/services/conversations/metadata/generate_bootstrap_title_test.rb`
- Create or Modify: `core_matrix/test/services/embedded_features/title_bootstrap/invoke_test.rb`

**Step 1: Preserve the existing embedded behavior**

Carry forward the already-useful behavior from
`EmbeddedAgents::ConversationTitle::Invoke`:

- modeled candidate generation
- normalization and internal-content guard
- heuristic fallback support

**Step 2: Move the public fallback boundary**

Update the slice to depend on the shared embedded-feature executor instead of
the legacy embedded-agent namespace.

The migration may keep shared helper methods or extract them, but the call site
should align with the platform.

**Step 3: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/metadata/generate_bootstrap_title_test.rb \
  test/services/embedded_features/title_bootstrap/invoke_test.rb
```

Expected: embedded fallback now sits behind the platform boundary without
changing title quality or last-resort heuristic behavior.

### Task 5: Remove Slice-Local Orchestration Glue

**Files:**
- Modify: `core_matrix/app/services/conversations/metadata/generate_bootstrap_title.rb`
- Modify: `core_matrix/app/jobs/conversations/metadata/bootstrap_title_job.rb`
- Modify: `core_matrix/test/services/conversations/metadata/generate_bootstrap_title_test.rb`
- Modify: `core_matrix/test/jobs/conversations/metadata/bootstrap_title_job_test.rb`

**Step 1: Collapse orchestration into the shared platform**

After policy, capability, runtime invocation, and embedded fallback all move to
the platform, simplify the slice so it keeps only:

- title-specific input shaping
- eligibility and persistence rules
- best-effort logging and failure semantics

**Step 2: Preserve non-blocking behavior**

Ensure the migration does not change these guarantees:

- no accepted-turn failure
- no visible error state to the user
- placeholder title remains when no usable title is produced

**Step 3: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/metadata/generate_bootstrap_title_test.rb \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb
```

Expected: the slice is now thin and platform-backed while preserving the
already-shipped behavior.

### Task 6: Verify The Follow-Up End To End

**Files:**
- Modify as needed: follow-up docs or tests discovered during cleanup

**Step 1: Run focused slice verification**

From `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/metadata/title_bootstrap_policy_test.rb \
  test/services/conversations/metadata/runtime_bootstrap_title_test.rb \
  test/services/conversations/metadata/generate_bootstrap_title_test.rb \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb \
  test/services/conversations/create_root_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/services/workbench/send_message_test.rb \
  test/requests/app_api/conversations_test.rb \
  test/requests/app_api/conversation_messages_test.rb
```

**Step 2: Run full `core_matrix` verification required by repo policy**

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

**Step 3: Run acceptance verification because this still touches acceptance-critical turn behavior**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

Inspect both:

- acceptance artifacts relevant to conversation creation and first-turn flows
- resulting database state for placeholder-title and title-source transitions

Expected: title bootstrap is fully aligned with the shared runtime feature
platform, while the already-landed product behavior remains intact.
