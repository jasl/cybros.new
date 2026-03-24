# Core Matrix Task 07.1: Build Conversation Structure

Part of `Core Matrix Kernel Phase 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-3-conversation-and-runtime.md`

Load this file as the detailed execution unit for Task 07.1. Treat Task 07 and the phase file as ordering indexes, not as the full task body.

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090019_create_conversations.rb`
- Create: `core_matrix/db/migrate/20260324090020_create_conversation_closures.rb`
- Create: `core_matrix/app/models/conversation.rb`
- Create: `core_matrix/app/models/conversation_closure.rb`
- Create: `core_matrix/app/services/conversations/create_root.rb`
- Create: `core_matrix/app/services/conversations/create_automation_root.rb`
- Create: `core_matrix/app/services/conversations/create_branch.rb`
- Create: `core_matrix/app/services/conversations/create_thread.rb`
- Create: `core_matrix/app/services/conversations/create_checkpoint.rb`
- Create: `core_matrix/app/services/conversations/archive.rb`
- Create: `core_matrix/app/services/conversations/unarchive.rb`
- Create: `core_matrix/test/models/conversation_test.rb`
- Create: `core_matrix/test/models/conversation_closure_test.rb`
- Create: `core_matrix/test/services/conversations/create_root_test.rb`
- Create: `core_matrix/test/services/conversations/create_automation_root_test.rb`
- Create: `core_matrix/test/services/conversations/create_branch_test.rb`
- Create: `core_matrix/test/services/conversations/create_thread_test.rb`
- Create: `core_matrix/test/services/conversations/create_checkpoint_test.rb`
- Create: `core_matrix/test/services/conversations/archive_test.rb`
- Create: `core_matrix/test/services/conversations/unarchive_test.rb`
- Create: `core_matrix/test/integration/conversation_structure_flow_test.rb`

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- conversation belongs to workspace, not directly to agent
- closure-table integrity
- conversation kind rules for `root`, `branch`, `thread`, and `checkpoint`
- conversation lifecycle state rules for `active` and `archived`
- conversation purpose rules for `interactive` and `automation`
- historical-anchor requirements for branch and checkpoint creation
- branch, thread, and checkpoint creation rejecting automation-purpose conversations
- automation conversations being root-only and read-only in v1

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/conversation_test.rb test/models/conversation_closure_test.rb test/services/conversations/create_root_test.rb test/services/conversations/create_automation_root_test.rb test/services/conversations/create_branch_test.rb test/services/conversations/create_thread_test.rb test/services/conversations/create_checkpoint_test.rb test/services/conversations/archive_test.rb test/services/conversations/unarchive_test.rb test/integration/conversation_structure_flow_test.rb
```

Expected:

- missing table and model failures

**Step 3: Write migrations, models, and services**

Rules:

- no direct `conversation.agent_id` shortcut
- conversation rows must carry kind, purpose, lifecycle state, parent lineage, and optional historical anchor
- `interactive` and `automation` purpose must remain separate from kind and lifecycle
- v1 automation conversations are root-only and reject branch, thread, and checkpoint creation
- branch and checkpoint creation must preserve lineage without transcript copying
- thread creation must keep separate timeline identity and must not imply transcript cloning
- archive and unarchive must change lifecycle state without mutating transcript history

**Step 4: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/conversation_test.rb test/models/conversation_closure_test.rb test/services/conversations/create_root_test.rb test/services/conversations/create_automation_root_test.rb test/services/conversations/create_branch_test.rb test/services/conversations/create_thread_test.rb test/services/conversations/create_checkpoint_test.rb test/services/conversations/archive_test.rb test/services/conversations/unarchive_test.rb test/integration/conversation_structure_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models/conversation.rb core_matrix/app/models/conversation_closure.rb core_matrix/app/services/conversations core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add conversation structure and lineage"
```

## Stop Point

Stop after conversation roots, lineage, archive lifecycle, and automation-root semantics pass their tests.

Do not implement these items in this subtask:

- `Turn` or `Message` tables
- interactive selector persistence
- conversation override persistence
- rollback, retry, rerun, or variant-selection behavior
