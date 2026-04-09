# Fenix Agent/Executor Role Separation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reorganize `agents/fenix` around explicit `Agent`, `Executor`, and `Shared` runtime roles without losing behavior, breaking contracts, or changing the external Fenix product surface.

**Architecture:** Replace the historical `Fenix::Runtime` center with three role-owned namespaces and hard one-way dependencies. Migrate shared transport/protocol foundations first, then move agent-owned behavior, then executor-owned behavior, then rewire entry points, tests, and docs so the new structure is the only live one.

**Tech Stack:** Ruby on Rails, Solid Queue, SQLite, acceptance harness, Docker runtime images

---

### Task 1: Establish shared foundations and dependency guardrails

**Files:**
- Modify: `agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/control_client.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/payload_context.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/workspace_env_overlay.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/owned_resource_registry.rb`
- Add: `agents/fenix/app/services/fenix/shared/**/*`
- Test: `agents/fenix/test/integration/runtime_manifest_test.rb`
- Test: `agents/fenix/test/services/fenix/runtime/payload_context_test.rb`
- Test: `agents/fenix/test/services/fenix/runtime/workspace_env_overlay_test.rb`
- Add/Modify: role-boundary tests under `agents/fenix/test/services/fenix/shared`

**Steps:**
1. Write failing tests for the new shared namespace and dependency rules.
2. Run the focused shared tests to confirm the current layout still depends on `Fenix::Runtime`.
3. Move shared protocol, control-plane, environment, and value-object responsibilities into `Fenix::Shared`.
4. Make the new file layout Zeitwerk-correct so namespace ownership and file ownership match.
5. Add boundary coverage that prevents `Shared` from referencing `Agent` or `Executor`.
6. Re-run focused tests, then `agents/fenix` full verification.

### Task 2: Move agent-program behavior into `Fenix::Agent`

**Files:**
- Modify: `agents/fenix/app/services/fenix/runtime/prepare_round.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/execute_program_tool.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/execute_conversation_control_request.rb`
- Modify: `agents/fenix/app/services/fenix/prompts/**/*`
- Modify: `agents/fenix/app/services/fenix/memory/**/*`
- Modify: `agents/fenix/app/services/fenix/skills/**/*`
- Modify: `agents/fenix/app/services/fenix/hooks/**/*`
- Add: `agents/fenix/app/services/fenix/agent/**/*`
- Test: `agents/fenix/test/services/fenix/runtime/prepare_round_test.rb`
- Test: `agents/fenix/test/services/fenix/runtime/execute_program_tool_test.rb`
- Test: `agents/fenix/test/services/fenix/runtime/execute_mailbox_item_test.rb`
- Test: `agents/fenix/test/services/fenix/skills/**/*`
- Add/Modify: tests under `agents/fenix/test/services/fenix/agent`

**Steps:**
1. Write failing tests that expect agent-program requests to resolve through `Fenix::Agent`.
2. Run focused tests to confirm the old `Runtime` ownership is still active.
3. Move agent-owned services, hooks, prompts, memory, and skills into `Fenix::Agent`.
4. Remove direct agent references to executor-specific implementation classes.
5. Rehome tests into `test/services/fenix/agent` as ownership moves.
6. Re-run focused tests, then full `agents/fenix` verification.

### Task 3: Move executor-program behavior into `Fenix::Executor`

**Files:**
- Modify: `agents/fenix/app/services/fenix/runtime/system_tool_registry.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/tool_executors/**/*`
- Modify: `agents/fenix/app/services/fenix/processes/**/*`
- Modify: `agents/fenix/app/services/fenix/browser/**/*`
- Add: `agents/fenix/app/services/fenix/executor/**/*`
- Test: `agents/fenix/test/services/fenix/runtime/system_tool_registry_test.rb`
- Test: `agents/fenix/test/services/fenix/runtime/program_tool_executor_test.rb`
- Test: `agents/fenix/test/services/fenix/processes/**/*`
- Test: `agents/fenix/test/services/fenix/browser/**/*`
- Add/Modify: tests under `agents/fenix/test/services/fenix/executor`

**Steps:**
1. Write failing tests that expect executor tool catalog and executor resource lifecycles to resolve through `Fenix::Executor`.
2. Run focused tests to prove the old runtime namespace still owns executor logic.
3. Move system tool registry, command/process/browser executors, and owned resource management into `Fenix::Executor`.
4. Add boundary coverage preventing executor code from referencing prompts, memory, or skills.
5. Rehome tests into `test/services/fenix/executor` as ownership moves.
6. Re-run focused tests, then full `agents/fenix` verification.

### Task 4: Rewire mailbox routing, jobs, and manifests to the new ownership model

**Files:**
- Modify: `agents/fenix/app/services/fenix/runtime/mailbox_worker.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/execute_mailbox_item.rb`
- Modify: `agents/fenix/app/jobs/fenix/runtime/mailbox_execution_job.rb`
- Modify: `agents/fenix/app/controllers/runtime/manifests_controller.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/assignments/dispatch_mode.rb`
- Modify: acceptance/runtime helpers as needed under `acceptance/`
- Test: `agents/fenix/test/services/fenix/runtime/mailbox_worker_test.rb`
- Test: `agents/fenix/test/services/fenix/runtime/execute_mailbox_item_test.rb`
- Test: `agents/fenix/test/services/fenix/runtime/mailbox_execution_job_test.rb`
- Test: `agents/fenix/test/integration/runtime_manifest_test.rb`
- Test: relevant acceptance contract tests under `core_matrix/test/lib/acceptance`

**Steps:**
1. Write failing tests for role-aware mailbox routing and manifest assembly.
2. Run the focused tests to show the old runtime router still mixes agent and executor ownership.
3. Replace the old runtime-centered dispatch with `Shared` routing into `Agent` and `Executor`.
4. Remove the old `Fenix::Runtime` implementation paths instead of leaving compatibility wrappers.
5. Re-run focused tests, then `agents/fenix` and targeted `core_matrix` acceptance-contract suites.

### Task 5: Restructure tests and docs to match the role boundaries

**Files:**
- Modify/create: `agents/fenix/test/services/fenix/agent/**/*`
- Modify/create: `agents/fenix/test/services/fenix/executor/**/*`
- Modify/create: `agents/fenix/test/services/fenix/shared/**/*`
- Modify: `agents/fenix/README.md`
- Modify: runtime/design docs under `docs/plans`, `docs/finished-plans/fenix`, or `docs/future-plans` as needed
- Modify: `docs/plans/README.md`

**Steps:**
1. Move or rewrite tests so their directory layout matches `Agent`, `Executor`, and `Shared`.
2. Remove stale docs that still describe Fenix as a single `Runtime` implementation bucket.
3. Verify all new docs describe the same ownership and dependency rules as the code.
4. Run focused structure checks to ensure no live implementation remains under the old `runtime` bucket except intentionally shared routing pieces.
5. Run `git diff --check` and focused doc/structure sanity checks.

### Task 6: Full repository verification, architecture review, and commit

**Files:**
- Review all touched files across `agents/fenix`, `acceptance`, and any touched root docs

**Steps:**
1. Run a full self-review focused on:
   - dependency direction
   - mailbox ownership
   - manifest ownership
   - unchanged functional behavior
2. Fix any review findings before claiming completion.
3. Run full verification:
   - `agents/fenix` verification commands from `AGENTS.md`
   - relevant `core_matrix` acceptance-contract tests affected by Fenix runtime ownership
   - acceptance scenarios covering bundled runtime, external runtime, skills, process close, and load harness
   - Docker verify for `images/nexus`
4. Only after everything passes, commit the rewrite.
