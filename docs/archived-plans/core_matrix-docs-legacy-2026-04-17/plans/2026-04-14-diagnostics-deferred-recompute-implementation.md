# Diagnostics Deferred Recompute Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make diagnostics API reads cache-first and stale-tolerant, enqueue
background recompute when snapshots are missing or stale, and keep debug export
payloads fresh by recomputing diagnostics inside the existing export job.

**Architecture:** Introduce a conversation-scoped freshness probe and a single
conversation-scoped recompute job. The diagnostics controller will stop
synchronously calling recompute services; instead it will read persisted
snapshots, classify the response as `ready` / `stale` / `pending`, enqueue a
background recompute when needed, and return cached data immediately. Debug
export remains freshness-first because it already runs asynchronously.

**Tech Stack:** Ruby on Rails, Active Record, Active Job, Minitest,
conversation diagnostics snapshots, usage/workflow/tool/process/subagent
fact tables.

---

### Task 1: Lock Cache-First Diagnostics Contracts In Request And Export Tests

**Files:**
- Modify: `core_matrix/test/requests/app_api/conversation_diagnostics_test.rb`
- Modify: `core_matrix/test/services/conversation_debug_exports/build_payload_test.rb`
- Create: `core_matrix/test/jobs/conversation_diagnostics/recompute_conversation_snapshot_job_test.rb`

**Step 1: Write failing request tests for pending diagnostics**

Extend `conversation_diagnostics_test.rb` so it expects:

- `GET /diagnostics` returns `diagnostics_status = "pending"` and `snapshot =
  nil` when no conversation snapshot exists
- `GET /diagnostics/turns` returns `diagnostics_status = "pending"` and
  `items = []` when no turn snapshots exist
- both requests enqueue a recompute job instead of creating snapshots

**Step 2: Write failing request tests for stale diagnostics**

Extend `conversation_diagnostics_test.rb` with a stale case:

- create persisted turn/conversation snapshots
- make a newer usage event or workflow fact
- expect the request to return the cached snapshot payload
- expect `diagnostics_status = "stale"`
- expect a recompute job to be enqueued

**Step 3: Write failing recompute job tests**

Create `recompute_conversation_snapshot_job_test.rb` with cases that expect:

- the job recomputes missing turn and conversation snapshots
- rerunning the job updates existing snapshots instead of duplicating them

**Step 4: Write failing debug export freshness test**

Extend `build_payload_test.rb` so it expects debug export to:

- recompute diagnostics even if stored snapshots are missing or stale
- serialize fresh conversation and turn diagnostics payloads

**Step 5: Run the targeted tests and verify they fail for the right reasons**

Run from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/requests/app_api/conversation_diagnostics_test.rb \
  test/services/conversation_debug_exports/build_payload_test.rb \
  test/jobs/conversation_diagnostics/recompute_conversation_snapshot_job_test.rb
```

Expected: failures showing diagnostics requests still recompute synchronously
and no conversation diagnostics recompute job exists yet.

**Step 6: Commit**

```bash
git add \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/conversation_diagnostics_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_debug_exports/build_payload_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/jobs/conversation_diagnostics/recompute_conversation_snapshot_job_test.rb
git commit -m "test: lock diagnostics deferred recompute contracts"
```

### Task 2: Add Freshness Probe And Background Recompute Job

**Files:**
- Create: `core_matrix/app/services/conversation_diagnostics/resolve_snapshot_status.rb`
- Create: `core_matrix/app/jobs/conversation_diagnostics/recompute_conversation_snapshot_job.rb`
- Modify: `core_matrix/test/services/conversation_diagnostics/recompute_conversation_snapshot_test.rb`
- Create: `core_matrix/test/services/conversation_diagnostics/resolve_snapshot_status_test.rb`
- Modify: `core_matrix/config/recurring.yml` only if an explicit recurring hook is needed

**Step 1: Write failing freshness probe tests**

Create `resolve_snapshot_status_test.rb` with cases that expect:

- `pending` when the conversation snapshot is missing
- `pending` when the conversation has turns but turn snapshots are missing
- `stale` when a usage event or workflow fact is newer than the stored snapshot
- `ready` when no newer source facts exist

Use exact fixtures over:

- `UsageEvent`
- `WorkflowRun`
- `AgentTaskRun`
- `ToolInvocation`
- `CommandRun`
- `ProcessRun`
- `SubagentConnection`

**Step 2: Implement the freshness probe**

Add `ResolveSnapshotStatus` that:

- accepts `conversation:`
- loads the stored conversation snapshot and turn snapshot count
- computes a source watermark from cheap indexed `MAX(...)` queries over the
  conversation-scoped fact tables
- returns a small result object with:
  - `status`
  - `conversation_snapshot`
  - `turn_snapshot_count`

Keep it conversation-scoped. Do not add per-turn freshness state in this task.

**Step 3: Add the conversation recompute job**

Create `RecomputeConversationSnapshotJob` that:

- finds the conversation by `id`
- calls `ConversationDiagnostics::RecomputeConversationSnapshot`
- exits cleanly if the conversation was deleted before execution

Keep the job idempotent and avoid extra side effects.

**Step 4: Run the targeted tests and verify they pass**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversation_diagnostics/resolve_snapshot_status_test.rb \
  test/services/conversation_diagnostics/recompute_conversation_snapshot_test.rb \
  test/jobs/conversation_diagnostics/recompute_conversation_snapshot_job_test.rb
```

Expected: the freshness probe classifies `pending` / `stale` / `ready`
correctly and the recompute job refreshes both turn and conversation snapshots.

**Step 5: Commit**

```bash
git add \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_diagnostics/resolve_snapshot_status.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/jobs/conversation_diagnostics/recompute_conversation_snapshot_job.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_diagnostics/resolve_snapshot_status_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_diagnostics/recompute_conversation_snapshot_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/jobs/conversation_diagnostics/recompute_conversation_snapshot_job_test.rb
git commit -m "feat: add diagnostics freshness probe and recompute job"
```

### Task 3: Switch Diagnostics Requests To Cache-Only Reads

**Files:**
- Modify: `core_matrix/app/controllers/app_api/conversations/diagnostics_controller.rb`
- Modify: `core_matrix/test/requests/app_api/conversation_diagnostics_test.rb`

**Step 1: Implement cache-only show**

Update `diagnostics_controller.rb#show` so it:

- calls `ConversationDiagnostics::ResolveSnapshotStatus`
- enqueues `ConversationDiagnostics::RecomputeConversationSnapshotJob` when the
  status is `pending` or `stale`
- serializes the stored conversation snapshot when present
- returns:
  - `diagnostics_status`
  - `snapshot`

Do not call `RecomputeConversationSnapshot` synchronously anymore.

**Step 2: Implement cache-only turns listing**

Update `diagnostics_controller.rb#turns` so it:

- uses the same resolved top-level diagnostics status
- loads stored `TurnDiagnosticsSnapshot` rows only
- returns cached items ordered by turn sequence
- enqueues the recompute job when the status is `pending` or `stale`

**Step 3: Keep response payload shape stable where possible**

Preserve existing snapshot/item fields when a snapshot exists.

Only add:

- `diagnostics_status`

And only change nullability/emptiness for:

- `snapshot`
- `items`

**Step 4: Run the targeted tests and verify they pass**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/requests/app_api/conversation_diagnostics_test.rb \
  test/jobs/conversation_diagnostics/recompute_conversation_snapshot_job_test.rb \
  test/services/conversation_diagnostics/resolve_snapshot_status_test.rb
```

Expected: diagnostics requests stop creating snapshots synchronously, return the
right `diagnostics_status`, and enqueue recompute when needed.

**Step 5: Commit**

```bash
git add \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/conversations/diagnostics_controller.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/conversation_diagnostics_test.rb
git commit -m "feat: make diagnostics reads cache-first"
```

### Task 4: Preserve Fresh Debug Export Payloads

**Files:**
- Modify: `core_matrix/app/services/conversation_debug_exports/build_payload.rb`
- Modify: `core_matrix/test/services/conversation_debug_exports/build_payload_test.rb`

**Step 1: Keep explicit recompute inside debug export**

Do not route debug export through the new cache-only controller behavior.

Instead, make the service behavior explicit:

- recompute diagnostics inside `BuildPayload`
- then serialize the freshly stored snapshots

If the service already does this, simplify the implementation so the intent is
obvious and the test contract is explicit.

**Step 2: Run the targeted tests and verify they pass**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversation_debug_exports/build_payload_test.rb \
  test/services/conversation_diagnostics/recompute_conversation_snapshot_test.rb
```

Expected: debug export still emits fresh diagnostics even when the stored
snapshots were missing or stale before export execution began.

**Step 3: Commit**

```bash
git add \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_debug_exports/build_payload.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_debug_exports/build_payload_test.rb
git commit -m "test: keep debug export diagnostics fresh"
```

### Task 5: Verify End-To-End Behavior And Budgets

**Files:**
- Verify only

**Step 1: Run the focused diagnostics suite**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/requests/app_api/conversation_diagnostics_test.rb \
  test/services/conversation_diagnostics/recompute_turn_snapshot_test.rb \
  test/services/conversation_diagnostics/recompute_conversation_snapshot_test.rb \
  test/services/conversation_debug_exports/build_payload_test.rb \
  test/jobs/conversation_diagnostics/recompute_conversation_snapshot_job_test.rb
```

Expected: all diagnostics and debug export behaviors pass under the new
cache-first contract.

**Step 2: Recheck diagnostics query budgets**

Re-run the existing diagnostics request query-budget assertions.

If the cache-only read path materially reduces SQL, update any plan or audit doc
that currently quotes the old budget.

Do not change unrelated request budgets in this task.

**Step 3: Run the full core_matrix test suite**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test
```

Expected: full suite green with no diagnostics regressions.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: defer diagnostics recompute from read path"
```
