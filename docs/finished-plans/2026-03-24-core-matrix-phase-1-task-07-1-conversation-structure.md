# Core Matrix Task 07.1: Build Conversation Structure

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-milestone-3-conversation-and-runtime.md`

Load this file as the detailed execution unit for Task 07.1. Treat Task Group 07 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

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

Do not implement these items in this task:

- `Turn` or `Message` tables
- interactive selector persistence
- conversation override persistence
- rollback, retry, rerun, or variant-selection behavior

## Completion Record

- status:
  completed on `2026-03-24`
- actual landed scope:
  - added `Conversation` and `ConversationClosure` tables and models
  - added services for root, automation-root, branch, thread, checkpoint,
    archive, and unarchive flows
  - added `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
  - added targeted model, service, and integration coverage for workspace
    ownership, parent-workspace integrity, kind/purpose/lifecycle rules,
    closure lineage, and automation root-only semantics
- plan alignment notes:
  - conversation ownership stayed rooted in workspace and did not introduce a
    direct agent foreign key shortcut
  - branch, thread, and checkpoint flows preserved lineage only and did not
    pre-implement transcript cloning, turn rows, selector state, or variant
    behavior
  - automation conversations landed as root-only conversation history in v1
- verification evidence:
  - `cd core_matrix && bin/rails test test/models/conversation_test.rb test/models/conversation_closure_test.rb test/services/conversations/create_root_test.rb test/services/conversations/create_automation_root_test.rb test/services/conversations/create_branch_test.rb test/services/conversations/create_thread_test.rb test/services/conversations/create_checkpoint_test.rb test/services/conversations/archive_test.rb test/services/conversations/unarchive_test.rb test/integration/conversation_structure_flow_test.rb`
    passed with `16 runs, 72 assertions, 0 failures, 0 errors`
- checklist notes:
  - no manual checklist delta was retained for this task because the landed
    behavior is an internal structural substrate covered by automated tests
- retained findings:
  - conversation kind, purpose, and lifecycle are clearer and safer when they
    remain separate state axes instead of one overloaded status field
  - closure-table lineage gives branch, thread, and checkpoint flows explicit
    ancestry without forcing transcript duplication
  - reference sanity check from
    `references/original/references/openclaw` and
    `references/original/references/dify`:
    neither reference was treated as authoritative for lineage or automation
    semantics in this task, so the local design doc remained the source of
    truth
- carry-forward notes:
  - Task 07.2 should attach turns and turn-origin metadata onto these
    conversations without weakening the workspace-rooted ownership model
  - later transcript and variant work should treat conversation lineage as
    already-established structure rather than re-encoding it through transcript
    copies
