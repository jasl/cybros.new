# Core Matrix Phase 2 Destructive Naming Alignment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the highest-confidence Phase 2 naming drift in `core_matrix` without preserving compatibility layers.

**Architecture:** Rewrite the original migrations in place, regenerate `db/schema.rb` from a clean database, and update all Ruby/docs/tests to use one canonical term per concept. Focus first on names that currently mean two different things or that diverge between docs and code.

**Tech Stack:** Ruby on Rails, Active Record migrations, Minitest, PostgreSQL

---

### Task 1: Align control-plane protocol message identifiers

**Files:**
- Modify: `db/migrate/20260326113000_add_agent_control_contract.rb`
- Modify: `app/models/agent_control_mailbox_item.rb`
- Modify: `app/models/agent_control_report_receipt.rb`
- Modify: control-plane services, requests, serializers, and tests that read/write `message_id`
- Modify: `docs/behavior/agent-runtime-resource-apis.md`

**Step 1: Write the failing test**

Update an existing mailbox/report test to expect `protocol_message_id` instead of `message_id`.

**Step 2: Run test to verify it fails**

Run the smallest affected test file and confirm it fails because the old name is still present.

**Step 3: Write minimal implementation**

Rename the database columns, model validations, query keys, serializer keys, and docs from `message_id` to `protocol_message_id` for control-plane mailbox/report records only.

**Step 4: Run test to verify it passes**

Re-run the same focused test file and confirm it passes.

### Task 2: Align `AgentTaskRun` provenance and discriminator naming

**Files:**
- Modify: `db/migrate/20260324090034_create_process_runs.rb` only if needed for shared terminology
- Modify: `db/migrate/20260326100000_extend_workflow_substrate.rb`
- Modify: `app/models/agent_task_run.rb`
- Modify: workflow/subagent/agent-control services and tests that use `task_kind` or `requested_by_turn`
- Modify: docs that still describe `AgentTaskRun(kind = ...)` while code uses `task_kind`

**Step 1: Write the failing test**

Update an existing `AgentTaskRun` model/service test to expect `kind` and `origin_turn`.

**Step 2: Run test to verify it fails**

Run the targeted test file and confirm the failure is due to the old names.

**Step 3: Write minimal implementation**

Rename `agent_task_runs.task_kind` to `kind` and `requested_by_turn_id` to `origin_turn_id`, then update associations, service arguments, JSON payload keys where they represent the persisted contract, and behavior docs.

**Step 4: Run test to verify it passes**

Re-run the targeted test file and confirm it passes.

### Task 3: Regenerate schema and repair dependent fixtures/docs

**Files:**
- Modify: `db/schema.rb`
- Modify: test helpers/fixtures/factories that still emit old keys
- Modify: behavior docs that still mention old names

**Step 1: Reset database artifacts**

Run a destructive reset so the rewritten migrations define the new schema from scratch.

**Step 2: Regenerate schema**

Run `bin/rails db:drop db:create db:schema:load` or the equivalent test-safe reset path and confirm `db/schema.rb` only contains the new names.

**Step 3: Repair dependent callers**

Update any remaining broken tests, helper methods, or docs that still reference the old names.

### Task 4: Verify the renamed contracts end to end

**Files:**
- Test: focused model/service/integration files for agent control, workflows, and subagent connections

**Step 1: Run focused red/green checks**

Run the changed test files first to validate the rename surface quickly.

**Step 2: Run project verification**

Run the relevant `core_matrix` verification commands that are practical for this rename batch.

**Step 3: Review residual naming drift**

Search for the old identifiers and confirm only intentional unrelated meanings remain.
