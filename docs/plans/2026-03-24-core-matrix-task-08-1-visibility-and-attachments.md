# Core Matrix Task 08.1: Add Visibility And Attachments

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-milestone-3-conversation-and-runtime.md`

Load this file as the detailed execution unit for Task 08.1. Treat Task Group 08 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090024_create_conversation_message_visibilities.rb`
- Create: `core_matrix/db/migrate/20260324090025_create_message_attachments.rb`
- Create: `core_matrix/app/models/conversation_message_visibility.rb`
- Create: `core_matrix/app/models/message_attachment.rb`
- Create: `core_matrix/app/services/messages/update_visibility.rb`
- Create: `core_matrix/app/services/attachments/materialize_refs.rb`
- Create: `core_matrix/test/models/conversation_message_visibility_test.rb`
- Create: `core_matrix/test/models/message_attachment_test.rb`
- Create: `core_matrix/test/services/messages/update_visibility_test.rb`
- Create: `core_matrix/test/services/attachments/materialize_refs_test.rb`
- Create: `core_matrix/test/integration/transcript_visibility_attachment_flow_test.rb`

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- soft delete and context exclusion through overlay rows
- attachment ancestry and origin pointers
- attachment visibility inheriting from the parent message instead of a separate attachment overlay model
- Active Storage attachment presence for file-bearing attachment rows
- confirming hidden or excluded message attachments do not appear in checkpoint or branch-derived transcript support projections
- excluding a message from context without deleting the immutable message row

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/conversation_message_visibility_test.rb test/models/message_attachment_test.rb test/services/messages/update_visibility_test.rb test/services/attachments/materialize_refs_test.rb test/integration/transcript_visibility_attachment_flow_test.rb
```

Expected:

- missing table and model failures

**Step 3: Write migrations, models, and services**

Rules:

- keep transcript rows immutable
- use overlay rows for mutable visibility
- use `has_one_attached` on `MessageAttachment`
- keep attachment visibility and context inclusion derived from the parent message in v1
- hidden transcript content must stay out of branch and checkpoint replay surfaces

**Step 4: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/conversation_message_visibility_test.rb test/models/message_attachment_test.rb test/services/messages/update_visibility_test.rb test/services/attachments/materialize_refs_test.rb test/integration/transcript_visibility_attachment_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models/conversation_message_visibility.rb core_matrix/app/models/message_attachment.rb core_matrix/app/services/messages core_matrix/app/services/attachments core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add transcript visibility and attachments"
```

## Stop Point

Stop after visibility overlays and attachment materialization pass their tests.

Do not implement these items in this task:

- conversation imports
- summary segments
- rollback or compaction-boundary preservation rules

## Completion Record

- status:
  completed on `2026-03-25`
- actual landed scope:
  - added `ConversationMessageVisibility` with hidden and context-exclusion
    overlay states
  - added `MessageAttachment` with `has_one_attached :file` and ancestry
    pointers through `origin_attachment` and `origin_message`
  - added `Messages::UpdateVisibility` and `Attachments::MaterializeRefs`
  - extended `Conversation` with minimal transcript and context support
    projections for root, thread, branch, and checkpoint lineage
  - added `core_matrix/docs/behavior/transcript-visibility-and-attachments.md`
  - added targeted model, service, and integration coverage for overlays,
    ancestry, file presence, and descendant support projection behavior
- plan alignment notes:
  - transcript rows remained immutable; visibility changes landed as overlay
    rows instead of message mutation
  - attachment reuse created new logical rows with preserved source ancestry
  - attachment support projection stayed derived from parent message visibility
    and context inclusion, without a separate attachment overlay model
  - branch and checkpoint support projections were kept intentionally minimal so
    Task 09 can own full context assembly
- verification evidence:
  - `cd core_matrix && bin/rails test test/models/conversation_message_visibility_test.rb test/models/message_attachment_test.rb test/services/messages/update_visibility_test.rb test/services/attachments/materialize_refs_test.rb test/integration/transcript_visibility_attachment_flow_test.rb`
    passed with `9 runs, 61 assertions, 0 failures, 0 errors`
- checklist notes:
  - no manual checklist delta was retained for this task because the landed
    behavior is kernel transcript-support infrastructure covered by automated
    tests
- retained findings:
  - conversation-specific overlays need to validate against the conversation's
    projected transcript path, not only the source message's native
    conversation
  - descendant attachment support can stay correct without a dedicated
    attachment overlay model when support projections derive from
    context-eligible parent messages
  - branch and checkpoint transcript support can stay orthogonal to Task 09
    context assembly by exposing only minimal projection helpers in
    `Conversation`
- carry-forward notes:
  - Task 08.2 should treat these projection helpers and attachment ancestry
    pointers as the substrate for imports and summary segments, not replace them
  - Task 09 context assembly should derive execution snapshots from
    `context_projection_messages` and `context_projection_attachments` rather
    than rebuilding separate visibility rules
