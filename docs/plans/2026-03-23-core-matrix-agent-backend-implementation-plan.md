# CoreMatrix Agent Backend Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the backend-only agent foundation in `core_matrix`, covering migrations, models, backend tests, and the first service layer without entering any UI/runtime follow-up work.

**Architecture:** Follow the conversation-tree plus append-only transcript plus per-turn workflow DAG design. Keep the current slice strictly inside backend/domain concerns in `core_matrix`; do not implement controllers, channels, views, JavaScript UI, background job orchestration, or provider/runtime adapters in this plan.

**Tech Stack:** Rails 8.2 defaults, PostgreSQL, Active Storage, Minitest.

---

## Source Documents

Read in this order before each phase:

1. `docs/plans/2026-03-23-greenfield-agent-implementation-index.md`
2. `docs/plans/2026-03-23-greenfield-agent-conversation-tree-turn-dag-design.md`
3. `docs/plans/2026-03-23-greenfield-agent-rails-bootstrap.md`
4. `docs/plans/2026-03-23-greenfield-agent-v1-backend-blueprint.md`

Do not use `docs/plans/2026-03-23-core-matrix-agent-ui-runtime-follow-up.md` during this plan.

## Phase Gates

Do not advance to the next phase until the current phase satisfies both audits:

1. Audit pass 1: missing fields, indexes, foreign keys, constraints, associations, enums, service boundaries, or test scenarios
2. Audit pass 2: conflicts with source documents, Rails convention mistakes, naming mistakes, association inference mistakes, migration ordering problems, or test gaps

If either audit finds an issue, fix it in the same phase and repeat both audits.

### Task 1: Phase 0 Baseline Lock

**Files:**
- Verify: `core_matrix/package.json`
- Verify: `core_matrix/db/migrate/20260322213202_create_active_storage_tables.active_storage.rb`
- Verify: `core_matrix/db/schema.rb`
- Verify: `core_matrix/app/models/concerns/.keep`
- Verify: `core_matrix/app/services/.keep`
- Verify: `core_matrix/app/queries/.keep`
- Verify: `core_matrix/test/services/.keep`
- Verify: `core_matrix/test/queries/.keep`
- Verify: `core_matrix/test/support/.keep`

**Steps:**
1. Re-read the implementation index and bootstrap baseline sections.
2. Verify Active Storage is already installed and schema-backed.
3. Verify lint/security/test baseline commands are green enough to start backend work.
4. Record Phase 0 completion and audits before creating any new domain migration.

### Task 2: Phase 1A Tree And Transcript Migrations

**Files:**
- Create: `core_matrix/db/migrate/*_create_agents.rb`
- Create: `core_matrix/db/migrate/*_create_conversations.rb`
- Create: `core_matrix/db/migrate/*_create_conversation_closures.rb`
- Create: `core_matrix/db/migrate/*_create_conversation_turns.rb`
- Create: `core_matrix/db/migrate/*_create_conversation_messages.rb`
- Create: `core_matrix/db/migrate/*_add_turn_message_foreign_keys.rb`
- Create: `core_matrix/db/migrate/*_create_conversation_message_visibilities.rb`
- Create: `core_matrix/db/migrate/*_create_message_attachments.rb`
- Create: `core_matrix/db/migrate/*_create_conversation_imports.rb`
- Create: `core_matrix/db/migrate/*_create_conversation_summary_segments.rb`

**Steps:**
1. Copy the migration structure from the backend blueprint, not from memory.
2. Keep all status/kind/role columns string-backed and `null: false` where specified.
3. Apply all indexes and aliased/self-referential foreign keys exactly as documented.
4. Run `bin/rails db:migrate` only after the whole Phase 1 batch is present.

### Task 3: Phase 1B Workflow, Resource, And Projection Migrations

**Files:**
- Create: `core_matrix/db/migrate/*_create_turn_workflows.rb`
- Create: `core_matrix/db/migrate/*_create_workflow_nodes.rb`
- Create: `core_matrix/db/migrate/*_add_turn_workflow_terminal_fk.rb`
- Create: `core_matrix/db/migrate/*_create_workflow_edges.rb`
- Create: `core_matrix/db/migrate/*_create_workflow_node_events.rb`
- Create: `core_matrix/db/migrate/*_create_workflow_artifacts.rb`
- Create: `core_matrix/db/migrate/*_create_subagent_runs.rb`
- Create: `core_matrix/db/migrate/*_create_process_runs.rb`
- Create: `core_matrix/db/migrate/*_create_approval_requests.rb`
- Create: `core_matrix/db/migrate/*_create_execution_leases.rb`
- Create: `core_matrix/db/migrate/*_create_conversation_drafts.rb`
- Create: `core_matrix/db/migrate/*_create_tool_permission_grants.rb`
- Create: `core_matrix/db/migrate/*_create_workspace_documents.rb`
- Create: `core_matrix/db/migrate/*_create_workspace_document_revisions.rb`
- Create: `core_matrix/db/migrate/*_add_workspace_documents_latest_revision_fk.rb`
- Create: `core_matrix/db/migrate/*_create_tool_call_facts.rb`
- Create: `core_matrix/db/migrate/*_add_conversation_managed_subagent_fk.rb`

**Steps:**
1. Continue the migration sequence without inserting model or service files.
2. Preserve the documented order of create-table migrations before late foreign keys.
3. Keep JSON payload columns and counters aligned with blueprint defaults.
4. Apply schema only after both Phase 1A and Phase 1B migration files exist.

### Task 4: Phase 1C Schema Apply And Phase Audit

**Files:**
- Modify: `core_matrix/db/schema.rb`

**Steps:**
1. Run `bin/rails db:migrate`.
2. Run targeted schema verification commands.
3. Audit pass 1 against bootstrap + blueprint migration lists.
4. Audit pass 2 against Rails conventions and migration ordering.
5. Stop and report Phase 1 before creating model files.

### Task 5: Phase 2 Models And Shared Support

**Files:**
- Create: `core_matrix/app/models/concerns/has_public_id.rb`
- Create: `core_matrix/app/models/*.rb` for all domain models from the blueprint
- Create: `core_matrix/test/support/record_builders.rb`
- Modify: `core_matrix/test/test_helper.rb`

**Steps:**
1. Add the shared concern first.
2. Add all model associations, enums, validations, attachments, scopes, and helper predicates from the blueprint.
3. Keep orchestration out of models; use models for state and domain rules only.
4. Run the two audits before any model test file is written.

### Task 6: Phase 3 Model Tests

**Files:**
- Create: `core_matrix/test/models/*_test.rb`

**Steps:**
1. Write failing model tests from the backend inventory first.
2. Run the failing tests to confirm they fail for the right reason.
3. Adjust model code minimally until tests pass.
4. Audit both for missing scenarios and Rails/model mismatches before moving on.

### Task 7: Phase 4 First Service Layer

**Files:**
- Create: `core_matrix/app/services/conversations/create_root.rb`
- Create: `core_matrix/app/services/conversations/create_branch.rb`
- Create: `core_matrix/app/services/turns/start_user_turn.rb`
- Create: `core_matrix/app/services/turns/queue_follow_up.rb`
- Create: `core_matrix/app/services/turns/steer_current_input.rb`
- Create: `core_matrix/app/services/workflows/mutator.rb`
- Create: `core_matrix/app/services/workflows/scheduler.rb`
- Create: `core_matrix/app/services/subagents/spawn.rb`
- Create: `core_matrix/app/services/processes/start.rb`
- Create: `core_matrix/test/services/**/*.rb`

**Steps:**
1. Write service tests first.
2. Implement the minimal service behavior to make each test pass.
3. Keep services in the application layer and keep models free of orchestration.
4. Audit both for missing service boundaries and document conflicts before continuing.

### Task 8: Phase 5 Secondary Backend Features And Final Audit

**Files:**
- Create or modify: remaining query objects, support services, and tests required by the source documents

**Steps:**
1. Fill any remaining backend-only gaps explicitly listed in the source documents.
2. Treat the backend blueprint service-test inventory plus the conversation tree query objects as the completion bar for this phase; do not expand to every longer-term bootstrap placeholder.
3. Run the full backend verification set.
4. Perform both audits over the entire backend slice.
5. Stop before any follow-up UI/runtime work.
